"""
src/cli/utils.py - Data & Prompt Utilities

Pure functions with no side effects. Contains:
- Logging utilities (_log, _debug_log)
- Regex escaping
- Data loading (manifest, data.json, prompt.json)
- Wildcard resolution
- Prompt building and variant operations

Debug relevance: When prompts are built incorrectly
"""

import os
import json
import re
from pathlib import Path
from datetime import datetime


def _log(message: str) -> None:
    """Print with optional debug ID prefix for log correlation."""
    debug_id = os.environ.get('DEBUG_ID', '')
    prefix = f"[{debug_id}] " if debug_id else ""
    print(f"{prefix}{message}")


def _debug_log(source: str, event: str, message: str) -> None:
    """Write to debug log file with timestamp and source.

    Creates a single log file per debug ID at:
    jobs/{job}/tmp/debug/DBG-{id}.log

    Args:
        source: Origin of the log (CLI, WEBUI, etc.)
        event: Event type (START, BUILD, GEN, SSE, etc.)
        message: Log message
    """
    debug_id = os.environ.get('DEBUG_ID')
    if not debug_id:
        return

    # Get job directory from environment (set during CLI startup)
    job_dir = os.environ.get('JOB_DIR')
    if not job_dir:
        return

    job_dir = Path(job_dir)
    debug_dir = job_dir / 'tmp' / 'debug'
    debug_dir.mkdir(parents=True, exist_ok=True)

    # Single file per debug ID
    log_file = debug_dir / f"{debug_id}.log"
    timestamp = datetime.now().strftime('%H:%M:%S.%f')[:-3]

    with open(log_file, 'a') as f:
        f.write(f"[{timestamp}] [{source}:{event}] {message}\n")


def escape_regex(text: str) -> str:
    """Escape regex special characters."""
    escaped = text.replace('\\', '\\\\')
    for char in r'.*+?^${}()|[]':
        escaped = escaped.replace(char, '\\' + char)
    return escaped


def apply_variant_ops(prompt: str, variant_ops: list) -> str:
    """Apply variant operations to a prompt (same logic as run_job.py).

    Args:
        prompt: The base prompt text
        variant_ops: List of variant operation dicts with 'replace' and 'remove' keys

    Returns:
        Transformed prompt with replacements and removals applied
    """
    resolved_prompt = prompt

    for op in variant_ops:
        # Apply replacements
        for replace_op in op.get('replace', []):
            old_text = replace_op.get('text') or replace_op.get('from')
            new_text = replace_op.get('with') or replace_op.get('to')
            if old_text and new_text:
                escaped_old = escape_regex(old_text)
                resolved_prompt = re.sub(escaped_old, new_text, resolved_prompt)

        # Apply removals
        for remove_text in op.get('remove', []):
            if remove_text:
                escaped_remove = escape_regex(remove_text)
                resolved_prompt = re.sub(escaped_remove + r',?\s*', '', resolved_prompt)
                resolved_prompt = re.sub(r',\s*,', ', ', resolved_prompt)

    return resolved_prompt


def load_manifest(outputs_dir: Path) -> dict:
    """Load manifest.json from outputs directory.

    Args:
        outputs_dir: Path to the outputs directory

    Returns:
        Manifest dict or None if not found
    """
    manifest_path = outputs_dir / 'manifest.json'
    if manifest_path.exists():
        with open(manifest_path) as f:
            return json.load(f)
    return None


def load_data_json(checkpoint_dir: Path) -> dict:
    """Load data.json from checkpoint directory.

    Args:
        checkpoint_dir: Path to the checkpoint directory

    Returns:
        Data dict or None if not found
    """
    data_path = checkpoint_dir / 'data.json'
    if data_path.exists():
        with open(data_path) as f:
            return json.load(f)
    return None


def load_prompt_json(prompt_dir: Path) -> dict:
    """Load prompt.json from prompt directory.

    Args:
        prompt_dir: Path to the prompt directory

    Returns:
        Prompt dict or None if not found
    """
    prompt_path = prompt_dir / 'prompt.json'
    if prompt_path.exists():
        with open(prompt_path) as f:
            return json.load(f)
    return None


def resolve_wildcards(manifest: dict, wc_indices: dict) -> dict:
    """Resolve wildcard indices to actual values.

    Args:
        manifest: The manifest dict containing wildcards
        wc_indices: Dict mapping wildcard names to indices

    Returns:
        Dict mapping wildcard names to resolved values
    """
    if not wc_indices:
        return {}
    wildcards = manifest.get('wildcards', {})
    resolved = {}
    for wc_name, wc_idx in wc_indices.items():
        values = wildcards.get(wc_name, [])
        if isinstance(wc_idx, int) and wc_idx < len(values):
            resolved[wc_name] = values[wc_idx]
    return resolved


def build_base_prompt(prompt_data: dict, path_string: str, resolved_wildcards: dict = None) -> str:
    """Build base prompt from checkpoint hierarchy.

    Args:
        prompt_data: Prompt configuration data
        path_string: Path to checkpoint (e.g., 'mood[1]~pose[1]')
        resolved_wildcards: Dict of resolved wildcard values (e.g., {'mood': 'sunny day', 'pose': 'standing'})
                           If provided, placeholders in raw_text will be substituted.
                           If None, returns raw_text with placeholders OR resolved_preview.

    Returns:
        Base prompt string with wildcards either substituted or as placeholders.
    """
    checkpoints = prompt_data.get('checkpoints', [])
    path_parts = path_string.split('/') if path_string else []
    base_prompt_parts = []

    for i in range(len(path_parts)):
        partial_path = '/'.join(path_parts[:i+1])
        checkpoint = next((cp for cp in checkpoints if cp.get('path_string') == partial_path), None)
        if checkpoint:
            # Use raw_text if we have resolved_wildcards to substitute
            # This avoids duplicating wildcards that are already in resolved_preview
            if resolved_wildcards and checkpoint.get('raw_text'):
                text = checkpoint.get('raw_text', '').strip()
                # Substitute wildcard placeholders: __mood__ -> actual value
                for wc_name, wc_value in resolved_wildcards.items():
                    placeholder = f'__{wc_name}__'
                    text = text.replace(placeholder, wc_value)
            else:
                # No wildcards to substitute - use resolved_preview for display
                text = (checkpoint.get('resolved_preview') or checkpoint.get('raw_text', '')).strip()

            if text and text not in base_prompt_parts:
                base_prompt_parts.append(text)

    return ', '.join(base_prompt_parts)
