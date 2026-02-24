"""
src/wildcard_operations.py - Wildcard Operations Module (Build Hook)

Single source of truth for wildcard operation calculations.
Operations are a type of build hook — independent value-replacement
mappings applied to prompts within a bucket window.

KEY CONCEPT: Each operation is independent and does NOT stack with others.
Base prompt → Operation A produces Result A
Base prompt → Operation B produces Result B
They never combine - you view/generate one at a time.

USAGE:
------
    from src.wildcard_operations import (
        WildcardOperation,
        load_operation,
        list_operations,
        compute_affected_indices,
        apply_to_prompt,
        get_affected_checkpoints
    )

    # Load an operation
    op = load_operation(job_dir, "futuristic")

    # Apply to prompt text
    transformed = apply_to_prompt(
        "sunny day, standing pose",
        op,
        base_wildcards
    )

    # Get affected indices
    affected = compute_affected_indices(op, base_wildcards)

    # Get affected checkpoints
    checkpoints = get_affected_checkpoints(op, all_checkpoints, base_wildcards)
"""

import json
import yaml
from pathlib import Path
from typing import Dict, List, Set, Any, Optional, Tuple
from dataclasses import dataclass, field


@dataclass
class WildcardOperation:
    """Represents a single wildcard operation set.

    Each operation defines independent text transformations that can be
    applied to a base prompt. Operations do not stack with each other.

    Note: To remove text, use replace with an empty "to" value.
    """
    name: str
    wildcards: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    # wildcards format: {
    #     "mood": {
    #         "replace": [{"from": "sunny day", "to": "sunset"}]
    #     }
    # }

    @classmethod
    def from_yaml(cls, name: str, yaml_data: dict) -> 'WildcardOperation':
        """Create operation from YAML config.

        YAML format:
            wildcards:
              - name: "mood"
                replace:
                  - text: "sunny day"
                    with: "sunset"

        Note: To remove text, use replace with an empty "with" value.
        """
        wildcards = {}

        for wc_op in (yaml_data or {}).get("wildcards", []):
            wc_name = wc_op.get("name")
            if not wc_name:
                continue

            wildcards[wc_name] = {
                "replace": []
            }

            # Parse replacements
            for rep in wc_op.get("replace", []):
                from_text = rep.get("text") or rep.get("from")
                to_text = rep.get("with") or rep.get("to")
                if from_text is not None and to_text is not None:
                    wildcards[wc_name]["replace"].append({
                        "from": from_text,
                        "to": to_text
                    })

        return cls(name=name, wildcards=wildcards)

    def to_yaml(self) -> dict:
        """Convert operation to YAML-serializable dict."""
        wildcards_list = []

        for wc_name, ops in self.wildcards.items():
            wc_entry = {"name": wc_name}

            if ops.get("replace"):
                wc_entry["replace"] = [
                    {"text": r["from"], "with": r["to"]}
                    for r in ops["replace"]
                ]

            wildcards_list.append(wc_entry)

        return {"wildcards": wildcards_list}

    def is_empty(self) -> bool:
        """Check if operation has no actual operations defined."""
        for ops in self.wildcards.values():
            if ops.get("replace"):
                return False
        return True


def load_operation(job_dir: Path, operation_name: str) -> Optional[WildcardOperation]:
    """Load an operation from YAML file.

    Args:
        job_dir: Job directory path
        operation_name: Name of the operation (without .yaml extension)

    Returns:
        WildcardOperation instance, or None if not found
    """
    operations_dir = Path(job_dir) / "operations"
    operation_path = operations_dir / f"{operation_name}.yaml"

    if not operation_path.exists():
        return None

    try:
        with open(operation_path, 'r') as f:
            yaml_data = yaml.safe_load(f) or {}
        return WildcardOperation.from_yaml(operation_name, yaml_data)
    except Exception:
        return None


def save_operation(job_dir: Path, operation: WildcardOperation) -> Path:
    """Save an operation to YAML file.

    Args:
        job_dir: Job directory path
        operation: WildcardOperation instance

    Returns:
        Path to written file
    """
    operations_dir = Path(job_dir) / "operations"
    operations_dir.mkdir(exist_ok=True)

    operation_path = operations_dir / f"{operation.name}.yaml"

    yaml_data = operation.to_yaml()

    with open(operation_path, 'w') as f:
        yaml.dump(yaml_data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

    return operation_path


def list_operations(job_dir: Path) -> List[str]:
    """List all available operations for a job.

    Args:
        job_dir: Job directory path

    Returns:
        List of operation names (without .yaml extension)
    """
    operations = []

    # Check operations/ directory
    operations_dir = Path(job_dir) / "operations"
    if operations_dir.exists():
        for f in operations_dir.glob("*.yaml"):
            operations.append(f.stem)

    return sorted(operations)


def compute_affected_indices(
    operation: WildcardOperation,
    base_wildcards: Dict[str, List[str]]
) -> Dict[str, Set[int]]:
    """Compute which wildcard indices are affected by the operation.

    This is THE SINGLE SOURCE OF TRUTH for affected calculations.

    Args:
        operation: WildcardOperation instance
        base_wildcards: Dict mapping wildcard_name -> list of values

    Returns:
        Dict mapping wildcard_name -> set of affected indices
        Example: {"mood": {0, 2}, "pose": {1}}
    """
    affected = {}

    for wc_name, ops in operation.wildcards.items():
        if wc_name not in base_wildcards:
            continue

        wc_values = base_wildcards[wc_name]
        indices = set()

        # Handle replacements (including empty replacements for removal)
        for rep in ops.get("replace", []):
            from_text = rep.get("from")
            if from_text and from_text in wc_values:
                idx = wc_values.index(from_text)
                indices.add(idx)

        if indices:
            affected[wc_name] = indices

    return affected


def image_is_affected(
    image_wc: Dict[str, int],
    affected_indices: Dict[str, Set[int]]
) -> bool:
    """Check if an image's wildcard combination is affected by operation.

    An image is affected if ANY of its wildcard values match an affected index.

    Args:
        image_wc: Image's wildcard values (e.g., {"mood": 0, "pose": 1})
        affected_indices: From compute_affected_indices()

    Returns:
        True if image is affected by operation
    """
    if not image_wc:
        return False

    for wc_name, idx in image_wc.items():
        if wc_name in affected_indices:
            if idx in affected_indices[wc_name]:
                return True

    return False


def count_affected_images(
    checkpoints: List[dict],
    affected_indices: Dict[str, Set[int]]
) -> Tuple[int, int]:
    """Count affected images and checkpoints.

    Args:
        checkpoints: List of checkpoint dicts with 'combinations'
        affected_indices: From compute_affected_indices()

    Returns:
        Tuple of (affected_images, affected_checkpoints)
    """
    affected_images = 0
    affected_checkpoints = 0

    for cp in checkpoints:
        cp_affected = False
        for combo in cp.get('combinations', []):
            wc = combo.get('wildcards')
            if wc and image_is_affected(wc, affected_indices):
                affected_images += 1
                cp_affected = True
        if cp_affected:
            affected_checkpoints += 1

    return affected_images, affected_checkpoints


def apply_to_prompt(
    prompt: str,
    operation: WildcardOperation,
    base_wildcards: Dict[str, List[str]],
    selected_values: Optional[Dict[str, int]] = None
) -> str:
    """Apply operation transformations to a prompt string.

    This performs text replacement based on the operation's rules.

    Args:
        prompt: Original prompt text
        operation: WildcardOperation instance
        base_wildcards: Dict mapping wildcard_name -> list of values
        selected_values: Optional dict of wildcard_name -> selected index
                        If provided, only applies operations for selected values

    Returns:
        Transformed prompt text
    """
    result = prompt

    for wc_name, ops in operation.wildcards.items():
        if wc_name not in base_wildcards:
            continue

        wc_values = base_wildcards[wc_name]

        # Handle replacements (including empty replacements for removal)
        for rep in ops.get("replace", []):
            from_text = rep.get("from")
            to_text = rep.get("to")

            if not from_text or to_text is None:
                continue

            # If selected_values is provided, only apply if this value is selected
            if selected_values is not None:
                selected_idx = selected_values.get(wc_name)
                if selected_idx is not None:
                    if from_text in wc_values:
                        from_idx = wc_values.index(from_text)
                        if selected_idx != from_idx:
                            continue  # Skip - not the selected value

            # Apply the replacement
            result = result.replace(from_text, to_text)

    # Clean up double spaces/commas from empty replacements
    while "  " in result:
        result = result.replace("  ", " ")
    result = result.replace(" ,", ",").replace(", ,", ",")
    result = result.strip()

    return result


def get_affected_checkpoints(
    operation: WildcardOperation,
    checkpoints: List[dict],
    base_wildcards: Dict[str, List[str]]
) -> List[str]:
    """Get list of checkpoint paths that contain affected images.

    Useful for sparse builds - only build these paths.

    Args:
        operation: WildcardOperation instance
        checkpoints: List of checkpoint dicts
        base_wildcards: Dict of wildcard_name -> list of values

    Returns:
        List of path_string values for affected checkpoints
    """
    affected_indices = compute_affected_indices(operation, base_wildcards)
    affected_paths = []

    for cp in checkpoints:
        for combo in cp.get('combinations', []):
            wc = combo.get('wildcards')
            if wc and image_is_affected(wc, affected_indices):
                path = cp.get('path_string')
                if path and path not in affected_paths:
                    affected_paths.append(path)
                break  # Only need one affected image per checkpoint

    return affected_paths


def get_affected_images_for_checkpoint(
    checkpoint: dict,
    operation: WildcardOperation,
    base_wildcards: Dict[str, List[str]]
) -> List[dict]:
    """Filter checkpoint combinations to only affected images.

    Used for sparse data creation - only include images affected by the operation.

    Args:
        checkpoint: Single checkpoint dict with 'combinations'
        operation: WildcardOperation instance
        base_wildcards: Dict of wildcard_name -> list of values

    Returns:
        List of affected combination dicts
    """
    affected_indices = compute_affected_indices(operation, base_wildcards)
    affected = []

    for combo in checkpoint.get('combinations', []):
        wc = combo.get('wildcards')
        if wc and image_is_affected(wc, affected_indices):
            affected.append(combo)

    return affected


def generate_operation_summary(
    operation: WildcardOperation,
    base_wildcards: Dict[str, List[str]],
    checkpoints: List[dict]
) -> dict:
    """Generate comprehensive summary of operation's effects.

    Args:
        operation: WildcardOperation instance
        base_wildcards: Dict of wildcard_name -> list of values
        checkpoints: List of checkpoint dicts from parsing

    Returns:
        Summary dict with affected counts and operations
    """
    # Calculate total base images
    total_images = sum(
        len(cp.get('combinations', [])) for cp in checkpoints
    )

    # Get affected indices and counts
    affected_indices = compute_affected_indices(operation, base_wildcards)
    affected_images, affected_checkpoints_count = count_affected_images(
        checkpoints, affected_indices
    )

    # Parse affected wildcards summary
    affected_wildcards = {}
    for wc_name, ops in operation.wildcards.items():
        replaced = len(ops.get("replace", []))
        if replaced > 0:
            affected_wildcards[wc_name] = {
                "replaced": replaced
            }

    # Build operations list (detailed)
    operations = []
    for wc_name, ops in operation.wildcards.items():
        wc_values = base_wildcards.get(wc_name, [])

        for rep in ops.get("replace", []):
            from_text = rep.get("from")
            to_text = rep.get("to")
            idx = wc_values.index(from_text) if from_text in wc_values else -1
            operations.append({
                "type": "replace",
                "wildcard": wc_name,
                "index": idx,
                "from": from_text,
                "to": to_text
            })

    return {
        "operation_name": operation.name,
        "type": "sparse" if not operation.is_empty() else "base",
        "affected_wildcards": affected_wildcards,
        "total_base_images": total_images,
        "affected_images": affected_images,
        "affected_checkpoints": affected_checkpoints_count,
        "operations": operations
    }


def format_summary_for_display(summary: dict) -> str:
    """Format summary for CLI display.

    Args:
        summary: Summary dict from generate_operation_summary()

    Returns:
        Formatted multi-line string for terminal output
    """
    lines = []

    if summary["type"] == "base":
        lines.append(f"   Total: {summary['total_base_images']} images across {summary['affected_checkpoints']} checkpoints")
        return "\n".join(lines)

    # Affected wildcards
    if summary["affected_wildcards"]:
        lines.append("   Operations:")
        for wc_name, counts in summary["affected_wildcards"].items():
            replaced = counts.get("replaced", 0)
            if replaced:
                lines.append(f"     - {wc_name}: {replaced} replaced")

        # Show specific operations
        for op in summary.get("operations", []):
            if op["type"] == "replace":
                to_display = f"\"{op['to']}\"" if op['to'] else "(removed)"
                lines.append(f"       \"{op['from']}\" -> {to_display}")

    # Affected counts
    total = summary["total_base_images"]
    affected = summary["affected_images"]
    pct = (affected / total * 100) if total > 0 else 0
    lines.append(f"   Affected: {affected} images ({pct:.1f}% of base) across {summary['affected_checkpoints']} checkpoints")

    return "\n".join(lines)


def validate_operation(
    operation: WildcardOperation,
    base_wildcards: Dict[str, List[str]]
) -> Tuple[bool, List[str]]:
    """Validate an operation against base wildcards.

    Checks:
    - Referenced wildcards exist
    - Replaced/removed values exist in base

    Args:
        operation: WildcardOperation instance
        base_wildcards: Dict of wildcard_name -> list of values

    Returns:
        Tuple of (is_valid, list of warning messages)
    """
    warnings = []

    for wc_name, ops in operation.wildcards.items():
        if wc_name not in base_wildcards:
            warnings.append(f"Unknown wildcard: '{wc_name}'")
            continue

        wc_values = base_wildcards[wc_name]

        # Check replacements
        for rep in ops.get("replace", []):
            from_text = rep.get("from")
            if from_text and from_text not in wc_values:
                warnings.append(f"Replace source '{from_text}' not found in wildcard '{wc_name}'")

    return len(warnings) == 0, warnings


# =============================================================================
# MANIFEST INTEGRATION
# =============================================================================

def load_base_wildcards(job_dir: Path) -> Dict[str, List[str]]:
    """Load base wildcards from job manifest.

    Args:
        job_dir: Job directory path

    Returns:
        Dict of wildcard_name -> list of values
    """
    manifest_path = Path(job_dir) / "outputs" / "manifest.json"

    if not manifest_path.exists():
        return {}

    try:
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
        return manifest.get("wildcards", {})
    except Exception:
        return {}


def load_checkpoints(job_dir: Path, composition: int, prompt_id: str = None) -> List[dict]:
    """Load checkpoint data from prompt.json files.

    Args:
        job_dir: Job directory path
        composition: Composition ID
        prompt_id: Optional specific prompt ID to load

    Returns:
        List of checkpoint dicts with combinations
    """
    comp_dir = Path(job_dir) / "outputs" / f"c{composition}"

    if not comp_dir.exists():
        return []

    checkpoints = []

    # If specific prompt_id, only load that
    if prompt_id:
        prompt_dirs = [comp_dir / prompt_id]
    else:
        prompt_dirs = [d for d in comp_dir.iterdir() if d.is_dir()]

    for prompt_dir in prompt_dirs:
        if not prompt_dir.exists():
            continue

        prompt_json = prompt_dir / "prompt.json"
        if prompt_json.exists():
            try:
                with open(prompt_json, 'r') as f:
                    prompt_data = json.load(f)
                checkpoints.extend(prompt_data.get("checkpoints", []))
            except Exception:
                pass

        # Also load from data.json files in subdirectories
        for data_path in prompt_dir.rglob("data.json"):
            if data_path.parent == prompt_dir:
                continue  # Skip root level
            try:
                with open(data_path, 'r') as f:
                    data = json.load(f)

                # Build checkpoint structure from data.json
                path_string = data.get("path_string", data_path.parent.name)
                images = data.get("images", [])

                combinations = []
                for img in images:
                    combinations.append({
                        "index": img.get("i", 1),
                        "wildcards": img.get("wc", {})
                    })

                if combinations:
                    checkpoints.append({
                        "path_string": path_string,
                        "combinations": combinations
                    })
            except Exception:
                pass

    return checkpoints
