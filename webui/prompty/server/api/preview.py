"""
Preview API Handlers

Endpoints for previewing resolved prompt variations.

POST /api/pu/preview - Preview resolved text variations for a prompt block
"""

import re
import yaml
from pathlib import Path
from itertools import product


def composition_to_indices(composition: int, ext_text_count: int, wildcard_counts: dict) -> tuple:
    """Convert composition ID to (ext_text_idx, {wc_name: idx}) using odometer logic.

    Odometer logic: ext_text outermost (slowest), wildcards alphabetical (fastest).

    Order: ext_text OUTERMOST (slowest), wildcards ALPHABETICAL (last = fastest)

    Example: ext_text=3, wildcards={'mood': 2, 'pose': 4}, Total=24
      comp 0 → ext=0, mood=0, pose=0
      comp 1 → ext=0, mood=0, pose=1
      comp 4 → ext=0, mood=1, pose=0
      comp 8 → ext=1, mood=0, pose=0
      comp 24 → wraps to comp 0

    Args:
        composition: The composition ID
        ext_text_count: Number of ext_text values (or 1 if none)
        wildcard_counts: Dict of {wildcard_name: count}

    Returns:
        Tuple of (ext_text_idx, {wildcard_name: idx})
    """
    ext_text_count = max(1, ext_text_count or 1)
    sorted_wc = sorted(wildcard_counts.keys())
    dimensions = [ext_text_count] + [max(1, wildcard_counts.get(n, 1)) for n in sorted_wc]

    total = 1
    for d in dimensions:
        total *= d

    idx = composition % total if total > 0 else 0

    indices = []
    for dim in reversed(dimensions):
        indices.append(idx % dim)
        idx //= dim
    indices.reverse()

    return indices[0], {n: indices[i + 1] for i, n in enumerate(sorted_wc)}


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def resolve_wildcards_in_text(text, wildcard_lookup, max_per_wildcard=0):
    """
    Resolve wildcards in text and return all variations.

    Args:
        text: String containing __wildcard__ patterns
        wildcard_lookup: Dict mapping wildcard names to value lists
        max_per_wildcard: Max values per wildcard (0 = all)

    Returns:
        List of (resolved_text, wildcard_values_dict) tuples
    """
    # Find all wildcards in text
    wildcard_names = re.findall(r'__([a-zA-Z0-9_-]+)__', text)
    unique_wildcards = sorted(list(set(wildcard_names)))

    if not unique_wildcards:
        return [(text, {})]

    # Build value lists for each wildcard
    value_lists = []
    for wc_name in unique_wildcards:
        if wc_name not in wildcard_lookup:
            # Keep unresolved
            value_lists.append([(f'__{wc_name}__', wc_name, -1)])
        else:
            values = wildcard_lookup[wc_name]
            if max_per_wildcard > 0 and len(values) > max_per_wildcard:
                values = values[:max_per_wildcard]
            value_lists.append([(v, wc_name, i) for i, v in enumerate(values)])

    # Generate all combinations
    results = []
    for combo in product(*value_lists):
        resolved = text
        wc_values = {}

        for value, wc_name, idx in combo:
            resolved = resolved.replace(f'__{wc_name}__', value, 1)
            if idx >= 0:
                wc_values[wc_name] = value

        results.append((resolved, wc_values))

    return results


def build_variations_recursive(items, ext_texts, wildcards, ext_text_max=0, wildcards_max=0, path_prefix=""):
    """
    Recursively build text variations from nested content/after structure.

    Returns list of dicts:
    {
        "text": "resolved text",
        "path": "0.0.1",
        "wildcard_values": {"pose": "standing"},
        "ext_indices": {"boss_fight": 1},
        "annotations": {"output_format": "markdown"}
    }
    """
    if not items:
        return [{"text": "", "path": path_prefix, "wildcard_values": {}, "ext_indices": {}, "annotations": {}}]

    all_results = []

    for item_idx, item in enumerate(items):
        item_path = f"{path_prefix}.{item_idx}" if path_prefix else str(item_idx)
        item_annotations = item.get('annotations', {}) or {}
        base_variations = []

        if 'content' in item:
            # Content block - resolve wildcards
            content = item['content']
            resolved = resolve_wildcards_in_text(content, wildcards, wildcards_max)

            for resolved_text, wc_values in resolved:
                base_variations.append({
                    "text": resolved_text,
                    "path": item_path,
                    "wildcard_values": wc_values,
                    "ext_indices": {},
                    "annotations": dict(item_annotations)
                })

        elif 'ext_text' in item:
            # ext_text block - load from extension
            ext_name = item['ext_text']
            ext_values = ext_texts.get(ext_name, [])

            if not ext_values:
                base_variations.append({
                    "text": f"[ext_text:{ext_name} not found]",
                    "path": item_path,
                    "wildcard_values": {},
                    "ext_indices": {},
                    "annotations": dict(item_annotations)
                })
            else:
                # Apply ext_text_max
                if ext_text_max > 0 and len(ext_values) > ext_text_max:
                    ext_values = ext_values[:ext_text_max]

                for ext_idx, ext_value in enumerate(ext_values):
                    # Resolve wildcards in ext_text value
                    resolved = resolve_wildcards_in_text(ext_value, wildcards, wildcards_max)

                    for resolved_text, wc_values in resolved:
                        base_variations.append({
                            "text": resolved_text,
                            "path": f"{item_path}.{ext_idx}",
                            "wildcard_values": wc_values,
                            "ext_indices": {ext_name: ext_idx + 1},
                            "annotations": dict(item_annotations)
                        })

        # Process 'after' children
        if 'after' in item and base_variations:
            after_variations = build_variations_recursive(
                item['after'], ext_texts, wildcards,
                ext_text_max, wildcards_max,
                path_prefix=item_path
            )

            # Combine base with after (concatenate text)
            combined = []
            for base in base_variations:
                for after in after_variations:
                    # Concatenate text with smart spacing
                    base_text = base["text"]
                    after_text = after["text"]

                    if base_text and after_text:
                        if not base_text.rstrip().endswith((',', ' ', '\n')) and \
                           not after_text.lstrip().startswith((',', ' ', '\n')):
                            combined_text = base_text + " " + after_text
                        else:
                            combined_text = base_text + after_text
                    else:
                        combined_text = base_text + after_text

                    # Merge annotations: parent first, child wins
                    merged_annotations = {**base["annotations"], **after["annotations"]}

                    combined.append({
                        "text": combined_text,
                        "path": after["path"],
                        "wildcard_values": {**base["wildcard_values"], **after["wildcard_values"]},
                        "ext_indices": {**base["ext_indices"], **after["ext_indices"]},
                        "annotations": merged_annotations
                    })

            base_variations = combined

        all_results.extend(base_variations)

    return all_results


def handle_preview(handler, params):
    """
    POST /api/pu/preview

    Preview resolved variations for a prompt block.

    Request:
    {
        "job_id": "pixel-fantasy",
        "prompt_id": "pixel-wildcards",
        "path": "0",                    # Optional: specific block path
        "text": "pixel sprite, __pose__",  # Optional: override text
        "wildcards": [{"name": "pose", "text": ["a", "b"]}],
        "include_nested": true,
        "limit": 10
    }

    Response:
    {
        "variations": [
            {
                "text": "pixel sprite, standing",
                "path": "0",
                "wildcard_values": {"pose": "standing"}
            }
        ],
        "total_count": 25,
        "breakdown": {
            "this_level": 5,
            "nested_paths": 5,
            "total": 25
        }
    }
    """
    project_root = get_project_root()

    job_id = params.get('job_id')
    prompt_id = params.get('prompt_id')
    text_items = params.get('text')  # Can be string or list of items
    wildcards_input = params.get('wildcards', [])
    include_nested = params.get('include_nested', True)
    limit = params.get('limit', 50)
    ext_text_max = params.get('ext_text_max', 0)
    ext_wildcards_max = params.get('wildcards_max', params.get('ext_wildcards_max', 0))

    # Build wildcard lookup
    wildcards = {}
    for wc in wildcards_input:
        if isinstance(wc, dict) and 'name' in wc:
            values = wc.get('text', [])
            if isinstance(values, str):
                values = [values]
            wildcards[wc['name']] = values

    # If job_id provided, load job data for defaults and ext_texts
    ext_texts = {}
    if job_id:
        jobs_yaml = project_root / "jobs" / job_id / "jobs.yaml"
        if jobs_yaml.exists():
            try:
                with open(jobs_yaml, 'r') as f:
                    job_data = yaml.safe_load(f)

                defaults = job_data.get('defaults', {})
                ext_folder = defaults.get('ext', 'defaults')

                # If prompt_id specified, find that prompt's config
                if prompt_id and not text_items:
                    for p in job_data.get('prompts', []):
                        if p.get('id') == prompt_id:
                            text_items = p.get('text', [])
                            # Merge prompt wildcards
                            for wc in p.get('wildcards', []):
                                if 'name' in wc:
                                    values = wc.get('text', [])
                                    if isinstance(values, str):
                                        values = [values]
                                    if wc['name'] not in wildcards:
                                        wildcards[wc['name']] = values
                                    else:
                                        # Merge values
                                        wildcards[wc['name']] = list(set(wildcards[wc['name']] + values))
                            # Get prompt-level ext settings
                            if 'ext_text_max' in p:
                                ext_text_max = p['ext_text_max']
                            if 'wildcards_max' in p:
                                ext_wildcards_max = p['wildcards_max']
                            elif 'ext_wildcards_max' in p:
                                ext_wildcards_max = p['ext_wildcards_max']
                            break

                # Load ext_texts from extension folder
                ext_dir = project_root / "ext" / ext_folder
                if ext_dir.exists():
                    for ext_file in ext_dir.glob("*.yaml"):
                        try:
                            with open(ext_file, 'r') as f:
                                ext_data = yaml.safe_load(f)
                            if ext_data:
                                ext_id = ext_data.get('id', ext_file.stem)
                                # Collect text values
                                text_values = []
                                for key, value in ext_data.items():
                                    if key == 'text' or re.match(r'^text\d+$', key):
                                        if isinstance(value, list):
                                            text_values.extend(value)
                                        elif isinstance(value, str):
                                            text_values.append(value)
                                if text_values:
                                    ext_texts[ext_id] = text_values
                                # Also load wildcards from extension
                                for wc in ext_data.get('wildcards', []):
                                    if 'name' in wc:
                                        values = wc.get('text', [])
                                        if isinstance(values, str):
                                            values = [values]
                                        if wc['name'] not in wildcards:
                                            wildcards[wc['name']] = values
                        except:
                            pass

            except Exception as e:
                pass

    # Handle text input
    if not text_items:
        handler.send_json({
            "error": "No text items provided"
        }, 400)
        return

    # Convert string to content block
    if isinstance(text_items, str):
        text_items = [{"content": text_items}]
    elif isinstance(text_items, list) and text_items and isinstance(text_items[0], str):
        # Legacy format: list of strings
        text_items = [{"content": t} for t in text_items]

    # Build variations
    variations = build_variations_recursive(
        text_items, ext_texts, wildcards,
        ext_text_max, ext_wildcards_max
    )

    # Calculate breakdown
    total = len(variations)

    # Count unique base paths (this level)
    base_paths = set()
    for v in variations:
        path_parts = v["path"].split(".")
        if path_parts:
            base_paths.add(path_parts[0])

    breakdown = {
        "this_level": len(base_paths),
        "nested_paths": total // max(len(base_paths), 1) if base_paths else total,
        "total": total
    }

    # Apply limit
    limited_variations = variations[:limit]

    handler.send_json({
        "variations": limited_variations,
        "total_count": total,
        "breakdown": breakdown,
        "wildcards_used": list(wildcards.keys())
    })
