"""
Move-to-Theme API Handler

Moves a content block from a prompt (jobs.yaml) to an ext/ theme file.
The content block becomes an ext_text reference. Selected local wildcards
are COPIED to the new theme (not moved) — local copies stay in jobs.yaml.
The build engine's union merge deduplicates same-name wildcards safely.

POST /api/pu/move-to-theme

Per-block only: no parent or child inclusion. Blocks with after: children
are rejected.
"""

import re
import copy
import yaml
import shutil
from pathlib import Path
from datetime import datetime


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def _find_wildcards_in_text(text):
    """Extract wildcard names from a content string."""
    return set(re.findall(r'__([a-zA-Z0-9_-]+)__', text))


def _collect_text_from_blocks(blocks, exclude_index):
    """Collect all content text from blocks, excluding one by index."""
    texts = []
    for i, block in enumerate(blocks):
        if i == exclude_index:
            continue
        if isinstance(block, dict):
            if 'content' in block:
                texts.append(block['content'])
            # Also scan after: children for shared wildcard detection
            if 'after' in block:
                texts.extend(_collect_after_text(block['after']))
    return ' '.join(texts)


def _collect_after_text(after_blocks):
    """Recursively collect text from after: children."""
    texts = []
    if isinstance(after_blocks, list):
        for block in after_blocks:
            if isinstance(block, dict):
                if 'content' in block:
                    texts.append(block['content'])
                if 'after' in block:
                    texts.extend(_collect_after_text(block['after']))
    return texts


def _count_ext_text_values(blocks, project_root, prompt_data, job_defaults):
    """Count total ext_text values across all blocks (summed dimension)."""
    total = 0
    ext_folder = prompt_data.get('ext') or job_defaults.get('ext', 'defaults')

    for block in blocks:
        if isinstance(block, dict) and 'ext_text' in block:
            ext_ref = block['ext_text']
            ext_max = block.get('ext_text_max')

            # Try to load the ext file to count values
            ext_file = project_root / "ext" / (ext_ref + ".yaml")
            if not ext_file.exists():
                # Try with ext folder prefix
                ext_file = project_root / "ext" / ext_folder / (ext_ref + ".yaml")

            if ext_file.exists():
                try:
                    with open(ext_file, 'r') as f:
                        data = yaml.safe_load(f)
                    text_count = len(data.get('text', []))
                    if ext_max and ext_max > 0:
                        text_count = min(text_count, ext_max)
                    total += text_count
                except Exception:
                    total += 1  # Assume at least 1 on error
            else:
                total += 1
    return total


def handle_move_to_theme(handler, params):
    """
    POST /api/pu/move-to-theme

    Move a content block from jobs.yaml to an ext/ theme file.
    Wildcards are COPIED to the theme (not moved) — local copies stay
    in jobs.yaml. The build engine's union merge deduplicates, so
    keeping both local and theme copies is safe.

    Request:
    {
        "job_id": "hiring-templates",
        "prompt_id": "job-posting",
        "block_index": 0,
        "theme_path": "hiring/job-postings",
        "fork": false,
        "wildcard_names": ["role"]
    }

    Response (success):
    {
        "success": true,
        "theme_file": "ext/hiring/job-postings.yaml",
        "ext_text_ref": "hiring/job-postings",
        "moved_text": "Write a job posting for a __role__ position",
        "copied_wildcards": ["role"],
        "kept_wildcards": ["tone", "role"],
        "new_composition": 0,
        "composition_changed": false,
        "warnings": []
    }
    """
    project_root = get_project_root()
    warnings = []

    # --- 1. VALIDATE required fields ---
    job_id = params.get('job_id')
    if not job_id:
        handler.send_json({"error": "job_id required"}, 400)
        return

    prompt_id = params.get('prompt_id')
    if not prompt_id:
        handler.send_json({"error": "prompt_id required"}, 400)
        return

    block_index = params.get('block_index')
    if block_index is None:
        handler.send_json({"error": "block_index required"}, 400)
        return

    theme_path = params.get('theme_path')
    if not theme_path:
        handler.send_json({"error": "theme_path required"}, 400)
        return

    fork = params.get('fork', False)

    # Sanitize theme_path
    if not re.match(r'^[a-zA-Z0-9_\-/]+$', theme_path):
        handler.send_json({"error": "Invalid path characters"}, 400)
        return

    # --- 2. LOAD job ---
    jobs_yaml_path = project_root / "jobs" / job_id / "jobs.yaml"
    if not jobs_yaml_path.exists():
        handler.send_json({"error": f"Job '{job_id}' not found"}, 404)
        return

    try:
        with open(jobs_yaml_path, 'r') as f:
            job_data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        handler.send_json({"error": f"Failed to parse jobs.yaml: {e}"}, 500)
        return

    if not job_data or 'prompts' not in job_data:
        handler.send_json({"error": "Job has no prompts"}, 400)
        return

    # --- 3. FIND prompt ---
    prompt = None
    for p in job_data['prompts']:
        if isinstance(p, dict) and p.get('id') == prompt_id:
            prompt = p
            break

    if prompt is None:
        handler.send_json({"error": f"Prompt '{prompt_id}' not found in job"}, 404)
        return

    blocks = prompt.get('text', [])
    if not isinstance(blocks, list):
        handler.send_json({"error": "Prompt has no text blocks"}, 400)
        return

    # --- 4. VALIDATE block ---
    if block_index < 0 or block_index >= len(blocks):
        handler.send_json({
            "error": f"Block index {block_index} out of range (0-{len(blocks) - 1})"
        }, 404)
        return

    block = blocks[block_index]
    if not isinstance(block, dict):
        handler.send_json({"error": f"Block at index {block_index} is not a dict"}, 400)
        return

    if 'ext_text' in block:
        handler.send_json({
            "error": f"Block at index {block_index} is already an ext_text reference"
        }, 400)
        return

    if 'after' in block:
        handler.send_json({
            "error": f"Block at index {block_index} has nested children. Move children first."
        }, 400)
        return

    if 'content' not in block:
        handler.send_json({
            "error": f"Block at index {block_index} has no content"
        }, 400)
        return

    content = block['content']

    # --- 5. DETERMINE wildcards to bundle ---
    text_wildcards = _find_wildcards_in_text(content)
    requested_names = params.get('wildcard_names')

    if requested_names is None:
        # Auto-detect: only wildcards that appear in the moved text
        requested_names = list(text_wildcards)

    # Check for shared wildcards (used in other blocks too)
    other_text = _collect_text_from_blocks(blocks, block_index)
    other_wildcards = _find_wildcards_in_text(other_text)

    bundled_names = []
    for name in requested_names:
        if name in other_wildcards:
            warnings.append(
                f"'{name}' also used in other blocks, keeping local copy"
            )
        else:
            bundled_names.append(name)

    # Separate wildcards into copied (to theme) and the rest.
    # All wildcards STAY local — copied ones get a copy in the theme.
    # The build engine's union merge deduplicates same-name wildcards.
    prompt_wildcards = prompt.get('wildcards', [])
    copied_wc_data = []

    for wc in prompt_wildcards:
        if isinstance(wc, dict) and wc.get('name') in bundled_names:
            copied_wc_data.append(copy.deepcopy(wc))

    # --- 6. BUILD theme data ---
    theme_id = theme_path.split('/')[-1]
    theme_data = {'id': theme_id, 'text': [content]}
    if copied_wc_data:
        theme_data['wildcards'] = copied_wc_data

    # --- 7. COMPUTE file path ---
    if fork:
        ext_text_ref = f"{job_id}/{theme_path}"
        full_path = f"ext/{job_id}/{theme_path}"
    else:
        ext_text_ref = theme_path
        full_path = f"ext/{theme_path}"

    theme_file = project_root / (full_path + ".yaml")

    if theme_file.exists():
        handler.send_json({
            "error": f"Theme already exists: {full_path}.yaml"
        }, 409)
        return

    # --- 8. COUNT existing ext_text values (for composition math) ---
    job_defaults = job_data.get('defaults', {})
    ext_text_before = _count_ext_text_values(
        blocks, project_root, prompt, job_defaults
    )

    # --- 9. BACKUP jobs.yaml ---
    backup_name = f"jobs.yaml.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    backup_path = jobs_yaml_path.parent / backup_name
    shutil.copy2(jobs_yaml_path, backup_path)

    # --- 10. WRITE THEME FIRST (safe direction) ---
    try:
        theme_file.parent.mkdir(parents=True, exist_ok=True)
        with open(theme_file, 'w') as f:
            yaml.dump(
                theme_data, f,
                default_flow_style=False,
                allow_unicode=True,
                sort_keys=False
            )
    except Exception as e:
        handler.send_json({
            "error": f"Failed to create theme file: {e}"
        }, 500)
        return

    # --- 11. UPDATE PROMPT (with rollback) ---
    try:
        # Replace content block with ext_text reference
        blocks[block_index] = {
            'ext_text': ext_text_ref,
            'ext_text_max': 1
        }

        # Wildcards stay local (copy semantics, not move)
        # No change to prompt['wildcards'] needed

        # Write updated jobs.yaml
        from .export import job_to_yaml
        yaml_content = job_to_yaml(job_data)
        with open(jobs_yaml_path, 'w') as f:
            f.write(yaml_content)

    except Exception as e:
        # ROLLBACK: delete the theme file we just created
        try:
            theme_file.unlink()
            # Remove empty parent dirs
            parent = theme_file.parent
            while parent != project_root / "ext":
                if not any(parent.iterdir()):
                    parent.rmdir()
                    parent = parent.parent
                else:
                    break
        except Exception:
            pass

        # Restore jobs.yaml from backup
        try:
            shutil.copy2(backup_path, jobs_yaml_path)
        except Exception:
            pass

        handler.send_json({
            "error": f"Failed to update job file, theme creation rolled back"
        }, 500)
        return

    # --- 12. COMPUTE new composition ---
    # New ext_text count: previous + 1 (the moved text)
    ext_text_after = ext_text_before + 1
    composition_changed = ext_text_before > 0

    if composition_changed:
        # The moved text is appended to the summed ext_text dimension
        # Its index is ext_text_before (the old count = new last index)
        moved_ext_index = ext_text_before

        # Compute wildcard product for the new composition
        # (wildcards are unchanged in the merged pool)
        all_wc_counts = []
        for wc in prompt_wildcards:
            if isinstance(wc, dict) and 'text' in wc:
                all_wc_counts.append(len(wc['text']))

        # Sort by name for odometer order (alphabetical)
        wc_names_values = []
        for wc in prompt_wildcards:
            if isinstance(wc, dict):
                wc_names_values.append((wc['name'], len(wc.get('text', []))))
        wc_names_values.sort(key=lambda x: x[0])

        # Compute stride for ext_text dimension
        wc_product = 1
        for _, count in wc_names_values:
            wc_product *= count

        new_composition = moved_ext_index * wc_product
    else:
        new_composition = 0

    # --- 13. RESPOND ---
    handler.send_json({
        "success": True,
        "theme_file": full_path + ".yaml",
        "ext_text_ref": ext_text_ref,
        "moved_text": content,
        "copied_wildcards": bundled_names,
        "kept_wildcards": [wc['name'] for wc in prompt_wildcards if isinstance(wc, dict)],
        "new_composition": new_composition,
        "composition_changed": composition_changed,
        "backup": str(backup_path.relative_to(project_root)),
        "warnings": warnings
    })
