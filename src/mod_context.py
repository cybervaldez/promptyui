"""
mod_context.py - Shared Context Building Module

Single source of truth for execution context building.
Used by:
- mod-cli.py
- workflow-cli.py
- src/cli/main.py (generation pipeline)

This module consolidates the duplicated context building logic that was previously
spread across multiple files (~100+ lines duplicated).
"""

import json
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple


def build_execution_context(
    job_dir: Path,
    composition: int,
    prompt_id: str,
    path_string: str,
    address_index: int = 1,
    config_index: int = 0,
    variant: str = None  # Deprecated: kept for API compatibility
) -> Optional[Dict[str, Any]]:
    """
    Build a complete execution context for mod/workflow execution.

    This is the single source of truth for building context objects used by
    mods and workflows. It handles:
    - Loading manifest data
    - Loading checkpoint data
    - Building output paths
    - Resolving LoRA configurations
    - Building the full context dictionary

    Args:
        job_dir: Path to job directory (e.g., jobs/pixel-fantasy)
        composition: Composition number
        prompt_id: Prompt identifier
        path_string: Checkpoint path (e.g., 'mood[1]~pose[1]')
        address_index: Image address index (1-based)
        config_index: Config index (0-based)
        variant: Deprecated - variant level removed from outputs structure

    Returns:
        Dict containing:
            - job_name: Job directory name
            - composition: Composition number
            - job_dir: Absolute path to job directory
            - prompt_id: Prompt identifier
            - path: List of path segments
            - path_string: Original path string
            - address_index: Image address (1-based)
            - config_index: Config index (0-based)
            - config: LoRA config dictionary for this config_index
            - resolved_prompt: Resolved prompt text
            - output_dir: Path to output directory
            - output_path: Full path to output image
            - image_path: Same as output_path

        Or None if context cannot be built (missing data)
    """
    job_dir = Path(job_dir)

    if not job_dir.exists():
        return None

    # Build data directory path (variant level removed)
    comp_dir = f'c{composition}'
    data_dir = job_dir / 'outputs' / comp_dir / prompt_id
    for part in path_string.split('/'):
        if part:
            data_dir = data_dir / part

    # Load manifest
    manifest = load_manifest(job_dir)

    # Load LoRA configs
    lora_combos = manifest.get('lora_combinations', {})
    config_list = lora_combos.get('configs', [])
    config = config_list[config_index] if config_index < len(config_list) else {}

    # Get base config for filename pattern
    base_config = manifest.get('base_config', {})
    sampler = base_config.get('sampler', 'euler')
    scheduler = base_config.get('scheduler', 'simple')

    # Load data.json for resolved prompt and wc_hash
    data = load_checkpoint_data(data_dir)
    resolved_prompt = data.get('resolved_prompt', '') if data else ''

    # Get wildcards and wc_hash for this image (wc_hash is required)
    wildcards = {}
    wc_hash = None
    if data:
        images = data.get('images', [])
        for img in images:
            if img.get('i') == address_index:
                wildcards = img.get('wc', {})
                wc_hash = img.get('wc_hash')
                break

    # Find existing image or determine output path
    # Check both old (wc_hash) and new (composition) filename formats
    existing_path = find_existing_image(
        data_dir, wc_hash, config_index, config, sampler, scheduler, composition
    )

    if existing_path:
        output_path = existing_path
    elif composition is not None:
        # Use new format for new files when composition is available
        filename = get_filename(wc_hash, config_index, config, sampler, scheduler, composition)
        output_path = data_dir / filename
    elif wc_hash:
        # Fall back to old format if wc_hash available but no composition
        filename = get_filename(wc_hash, config_index, config, sampler, scheduler)
        output_path = data_dir / filename
    else:
        raise ValueError(f"Neither wc_hash nor composition available for address_index={address_index} in {data_dir}")

    return {
        'job_name': job_dir.name,
        'composition': composition,
        'job_dir': str(job_dir),
        'prompt_id': prompt_id,
        'path': path_string.split('/'),
        'path_string': path_string,
        'address_index': address_index,
        'config_index': config_index,
        'config': config,
        'resolved_prompt': resolved_prompt,
        'output_dir': str(data_dir),
        'output_path': str(output_path),
        'image_path': str(output_path),
        'wildcards': wildcards,
        'wc_hash': wc_hash,
        'base_config': base_config,
        'manifest': manifest,
    }


def get_filename(
    wc_hash: str,
    config_index: int,
    config: Dict[str, Any],
    sampler: str = 'euler',
    scheduler: str = 'simple',
    composition: int = None
) -> str:
    """
    Build content-addressable filename for an image.

    Uses wc_hash-based format to enable file sharing between compositions
    that map to the same wildcard combination (due to wrap-around).

    Format: wc_{hash}_cfg{config_index}_{suffix}_{sampler}_{scheduler}.png

    Args:
        wc_hash: Content-addressable hash from data.json (required)
        config_index: Config index (0-based)
        config: Config dictionary with 'suffix' key
        sampler: Sampler name
        scheduler: Scheduler name
        composition: Deprecated - kept for API compatibility, ignored

    Returns:
        Filename like 'wc_7a2c1f_cfg0_base_euler_simple.png'
    """
    suffix = config.get('suffix', 'base')
    return f'wc_{wc_hash}_cfg{config_index}_{suffix}_{sampler}_{scheduler}.png'


def find_existing_image(
    data_dir: Path,
    wc_hash: str,
    config_index: int,
    config: Dict[str, Any],
    sampler: str = 'euler',
    scheduler: str = 'simple',
    composition: int = None
) -> Optional[Path]:
    """
    Find existing image file using content-addressable wc_hash.

    Uses wc_hash-based filename to enable file sharing between compositions.

    Args:
        data_dir: Directory to search in
        wc_hash: Content-addressable hash (required)
        config_index: Config index (0-based)
        config: Config dictionary
        sampler: Sampler name
        scheduler: Scheduler name
        composition: Deprecated - kept for API compatibility, ignored

    Returns:
        Path to existing file, or None if not found
    """
    suffix = config.get('suffix', 'base')

    # Content-addressable format (current)
    if wc_hash:
        filename = f'wc_{wc_hash}_cfg{config_index}_{suffix}_{sampler}_{scheduler}.png'
        path = data_dir / filename
        if path.exists():
            return path

    return None


def load_manifest(job_dir: Path) -> Dict[str, Any]:
    """
    Load manifest.json from job outputs.

    Args:
        job_dir: Path to job directory

    Returns:
        Manifest dictionary or empty dict if not found
    """
    manifest_path = job_dir / 'outputs' / 'manifest.json'
    if not manifest_path.exists():
        return {}

    try:
        with open(manifest_path, 'r') as f:
            return json.load(f)
    except Exception:
        return {}


def load_checkpoint_data(data_dir: Path) -> Optional[Dict[str, Any]]:
    """
    Load data.json from checkpoint directory.

    Args:
        data_dir: Path to checkpoint directory

    Returns:
        Data dictionary or None if not found
    """
    data_path = data_dir / 'data.json'
    if not data_path.exists():
        return None

    try:
        with open(data_path, 'r') as f:
            return json.load(f)
    except Exception:
        return None


def load_prompt_data(
    job_dir: Path,
    composition: int,
    prompt_id: str,
    variant: str = None  # Deprecated: kept for API compatibility
) -> Optional[Dict[str, Any]]:
    """
    Load prompt.json for a prompt.

    Args:
        job_dir: Path to job directory
        composition: Composition number
        prompt_id: Prompt identifier
        variant: Deprecated - variant level removed from outputs structure

    Returns:
        Prompt data dictionary or None if not found
    """
    comp_dir = f'c{composition}'
    prompt_path = job_dir / 'outputs' / comp_dir / prompt_id / 'prompt.json'

    if not prompt_path.exists():
        return None

    try:
        with open(prompt_path, 'r') as f:
            return json.load(f)
    except Exception:
        return None


def get_image_path(
    job_dir: Path,
    composition: int,
    prompt_id: str,
    path_string: str,
    address_index: int,
    config_index: int,
    variant: str = None  # Deprecated: kept for API compatibility
) -> Optional[Path]:
    """
    Get the full path to a generated image.

    Args:
        job_dir: Path to job directory
        composition: Composition number
        prompt_id: Prompt identifier
        path_string: Checkpoint path
        address_index: Image address (1-based)
        config_index: Config index (0-based)
        variant: Deprecated - variant level removed from outputs structure

    Returns:
        Path to image file or None if cannot be determined
    """
    # Load manifest for filename pattern
    manifest = load_manifest(job_dir)
    lora_combos = manifest.get('lora_combinations', {})
    config_list = lora_combos.get('configs', [])
    config = config_list[config_index] if config_index < len(config_list) else {}

    base_config = manifest.get('base_config', {})
    sampler = base_config.get('sampler', 'euler')
    scheduler = base_config.get('scheduler', 'simple')

    filename = get_filename(address_index, config_index, config, sampler, scheduler)

    # Build path (variant level removed)
    comp_dir = f'c{composition}'
    data_dir = job_dir / 'outputs' / comp_dir / prompt_id
    for part in path_string.split('/'):
        if part:
            data_dir = data_dir / part

    return data_dir / filename


def get_checkpoint_images(
    job_dir: Path,
    composition: int,
    prompt_id: str,
    path_string: str,
    variant: str = None  # Deprecated: kept for API compatibility
) -> List[Dict[str, Any]]:
    """
    Get list of all images in a checkpoint with their status.

    Args:
        job_dir: Path to job directory
        composition: Composition number
        prompt_id: Prompt identifier
        path_string: Checkpoint path
        variant: Deprecated - variant level removed from outputs structure

    Returns:
        List of image dictionaries with address_index, config_indices, and status
    """
    comp_dir = f'c{composition}'
    data_dir = job_dir / 'outputs' / comp_dir / prompt_id
    for part in path_string.split('/'):
        if part:
            data_dir = data_dir / part

    data = load_checkpoint_data(data_dir)
    if not data:
        return []

    images = data.get('images', [])

    # Enhance with full paths
    manifest = load_manifest(job_dir)
    lora_combos = manifest.get('lora_combinations', {})
    config_list = lora_combos.get('configs', [])
    base_config = manifest.get('base_config', {})
    sampler = base_config.get('sampler', 'euler')
    scheduler = base_config.get('scheduler', 'simple')

    result = []
    for img in images:
        address_index = img.get('i', 1)
        status = img.get('status', [])
        wildcards = img.get('wc', {})

        configs = []
        for cfg_idx, cfg_status in enumerate(status):
            config = config_list[cfg_idx] if cfg_idx < len(config_list) else {}
            filename = get_filename(address_index, cfg_idx, config, sampler, scheduler)

            configs.append({
                'config_index': cfg_idx,
                'status': cfg_status,
                'filename': filename,
                'path': str(data_dir / filename)
            })

        result.append({
            'address_index': address_index,
            'wildcards': wildcards,
            'configs': configs,
            'generated_count': sum(1 for c in configs if c['status'] == 1),
            'total_count': len(configs)
        })

    return result


def get_stats(
    job_dir: Path,
    composition: int,
    prompt_id: Optional[str] = None,
    path_string: Optional[str] = None,
    variant: str = None  # Deprecated: kept for API compatibility
) -> Dict[str, Any]:
    """
    Get generation statistics.

    Args:
        job_dir: Path to job directory
        composition: Composition number
        prompt_id: Optional prompt ID to filter by
        path_string: Optional path to filter by
        variant: Deprecated - variant level removed from outputs structure

    Returns:
        Dict with generated count, total count, and per-config breakdown
    """
    comp_dir = f'c{composition}'
    base_dir = job_dir / 'outputs' / comp_dir

    if not base_dir.exists():
        return {'generated': 0, 'total': 0, 'per_config': []}

    generated = 0
    total = 0
    per_config = {}

    for data_file in base_dir.rglob('data.json'):
        try:
            with open(data_file, 'r') as f:
                data = json.load(f)

            data_prompt_id = data.get('prompt_id', '')
            data_path = data.get('path_string', '')

            # Filter if specified
            if prompt_id and data_prompt_id != prompt_id:
                continue
            if path_string and data_path != path_string:
                continue

            for img in data.get('images', []):
                statuses = img.get('status', [])
                total += len(statuses)
                generated += sum(1 for s in statuses if s == 1)

                for cfg_idx, status in enumerate(statuses):
                    if cfg_idx not in per_config:
                        per_config[cfg_idx] = {'generated': 0, 'total': 0}
                    per_config[cfg_idx]['total'] += 1
                    if status == 1:
                        per_config[cfg_idx]['generated'] += 1

        except Exception:
            continue

    return {
        'generated': generated,
        'total': total,
        'per_config': [
            {'config_idx': k, **v}
            for k, v in sorted(per_config.items())
        ]
    }
