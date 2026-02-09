#!/usr/bin/env python3
"""
src/manifest.py - Core Data Generation for Hierarchical WebUI Architecture

This module provides functions for generating the unified JSON data structure
used by both CLI tools and WebUI.

Data Hierarchy:
    manifest.json (GLOBAL) → wildcards, loras, model config
    └── prompt.json (PROMPT) → expanded configs, checkpoints list
        └── data.json (LEAF) → image indices with status array

Key Design Principles:
1. Parent provides, child references (index-based)
2. Minimal checkpoint data (compact format)
3. Precompilation - all expansions happen at build time
4. Same format for CLI and WebUI
"""

import json
import re
import itertools
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

from src.config import load_yaml
from src.wc_hash import compute_wc_hash, build_content_filename


# =============================================================================
# CONFIG EXPANSION
# =============================================================================

def expand_lora_spec(spec: str, range_increment: float = 0.1) -> List[Dict[str, Any]]:
    """
    Expand a LoRA configuration spec into concrete configurations.
    
    Examples:
        "lora1:0.8" → [{"lora1": 0.8}]
        "lora1:0.8~~1" → [{"lora1": 0.8}, {"lora1": 0.9}, {"lora1": 1.0}]
        "lora1:off" → [{"lora1": "off"}]
        "lora1:0.8+pixel:0.7" → [{"lora1": 0.8, "pixel": 0.7}]
        "lora1:0.8~~1+pixel:0.8~~1" → Cartesian product of both ranges
    
    Args:
        spec: LoRA configuration string
        range_increment: Step size for ranges (default 0.1)
    
    Returns:
        List of dicts mapping alias → strength/off
    """
    if not spec:
        return [{}]
    
    # Split by + for multi-lora configs
    parts = [p.strip() for p in spec.split('+') if p.strip()]
    
    # Parse each part into alias and value options
    part_options = []
    
    for part in parts:
        if ':' not in part:
            # Just alias, use default strength (will be resolved later)
            part_options.append([(part, None)])
            continue
        
        alias, value_str = part.split(':', 1)
        alias = alias.strip()
        value_str = value_str.strip()
        
        if value_str.lower() == 'off':
            part_options.append([(alias, 'off')])
        elif '~~' in value_str:
            # Range syntax: 0.8~~1.0
            min_str, max_str = value_str.split('~~', 1)
            min_val = float(min_str)
            max_val = float(max_str)
            
            values = []
            v = min_val
            while v <= max_val + 0.001:  # Add epsilon for float precision
                values.append((alias, round(v, 2)))
                v += range_increment
            part_options.append(values)
        else:
            # Fixed value
            part_options.append([(alias, float(value_str))])
    
    # Generate cartesian product of all options
    configs = []
    for combo in itertools.product(*part_options):
        config = {}
        for alias, value in combo:
            config[alias] = value
        configs.append(config)
    
    return configs


def expand_lora_combinations(lora_specs: List[str], range_increment: float = 0.1) -> List[Dict[str, Any]]:
    """
    Expand a list of LoRA specs into indexed config entries.
    
    Args:
        lora_specs: List of LoRA spec strings from jobs.yaml
        range_increment: Step size for ranges
    
    Returns:
        List of config entries with index, spec, loras, and suffix
    """
    configs = []
    index = 0
    
    for spec in lora_specs:
        expanded = expand_lora_spec(spec, range_increment)
        for loras in expanded:
            # Build suffix from loras
            suffix_parts = []
            for alias, value in sorted(loras.items()):
                if value == 'off':
                    suffix_parts.append(f"{alias}-off")
                elif value is None:
                    suffix_parts.append(alias)
                else:
                    suffix_parts.append(f"{alias}-{value}")
            
            configs.append({
                'index': index,
                'spec': spec,
                'loras': loras,
                'suffix': '+'.join(suffix_parts) if suffix_parts else 'base'
            })
            index += 1
    
    return configs


def get_filename(wc_hash: str, config_index: int, config: Dict[str, Any],
                 sampler: str = 'euler', scheduler: str = 'simple') -> str:
    """
    Compute content-addressable filename from wc_hash and config.

    Format: wc_{hash}_cfg{config_index}_{suffix}_{sampler}_{scheduler}.png

    Args:
        wc_hash: Content-addressable hash from data.json (required)
        config_index: Config index (0-based)
        config: Config dict with 'suffix' key
        sampler: Sampler name
        scheduler: Scheduler name

    Returns:
        Filename string like "wc_7a2c1f_cfg0_base_euler_simple.png"
    """
    suffix = config.get('suffix', 'default')
    return build_content_filename(wc_hash, config_index, suffix, sampler, scheduler)


# =============================================================================
# WILDCARD UTILITIES
# =============================================================================

def build_wildcard_registry(wildcards_yaml_path: Path) -> Dict[str, List[str]]:
    """
    Load wildcards from YAML and build a registry.
    
    Args:
        wildcards_yaml_path: Path to wildcards.yaml
    
    Returns:
        Dict mapping wildcard name → list of values
    """
    if wildcards_yaml_path.exists():
        return load_yaml(wildcards_yaml_path) or {}
    return {}


def wildcard_value_to_index(wildcard_name: str, value: str, 
                           registry: Dict[str, List[str]]) -> int:
    """
    Convert a wildcard value to its index.
    
    Args:
        wildcard_name: Name of the wildcard
        value: Value string
        registry: Wildcard registry
    
    Returns:
        Index (0-based), or -1 if not found
    """
    if wildcard_name not in registry:
        return -1
    values = registry[wildcard_name]
    try:
        return values.index(value)
    except ValueError:
        return -1


def index_to_wildcard_value(wildcard_name: str, index: int,
                           registry: Dict[str, List[str]]) -> Optional[str]:
    """
    Convert an index to its wildcard value.
    
    Args:
        wildcard_name: Name of the wildcard
        index: Index (0-based)
        registry: Wildcard registry
    
    Returns:
        Value string, or None if not found
    """
    if wildcard_name not in registry:
        return None
    values = registry[wildcard_name]
    if 0 <= index < len(values):
        return values[index]
    return None


# =============================================================================
# MANIFEST GENERATION
# =============================================================================

def generate_manifest(
    job_name: str,
    job_conf: dict,
    global_conf: dict,
    wildcards: Dict[str, List[str]],
    lora_root: Path,
    variant_id: str = "default"
) -> dict:
    """
    Generate the global manifest.json content.
    
    Args:
        job_name: Name of the job
        job_conf: Job configuration from jobs.yaml
        global_conf: Global configuration
        wildcards: Wildcard registry
        lora_root: Path to LoRA files
        variant_id: Variant ID
    
    Returns:
        Manifest dict ready to be written as JSON
    """
    # Compute simple job hash
    import hashlib
    hash_str = json.dumps(job_conf, sort_keys=True, default=str)
    job_hash = hashlib.md5(hash_str.encode()).hexdigest()[:16]
    
    # Get model config
    model_conf = job_conf.get('model', {})
    model_name = model_conf.get('name', 'unknown')
    
    # Get defaults
    defaults = job_conf.get('defaults', {})
    if isinstance(defaults, list):
        defaults = defaults[0] if defaults else {}
    
    # Build generation context
    generation_context = {
        'model_name': model_name,
        'lora_root': str(lora_root),
        'trigger_delimiter': defaults.get('trigger_delimiter', ', ')
    }
    
    # Build base config
    sampler_list = model_conf.get('sampler', [])
    default_sampler = sampler_list[0] if sampler_list else {}
    
    base_config = {
        'sampler': default_sampler.get('sampler', 'euler'),
        'scheduler': default_sampler.get('scheduler', 'simple'),
        'steps': default_sampler.get('steps', defaults.get('steps', 9)),
        'cfg': default_sampler.get('cfg', defaults.get('cfg', 1.0)),
        'width': defaults.get('width', 1024),
        'height': defaults.get('height', 1024)
    }
    
    # Build LoRA definitions
    loras = {}
    for lora in job_conf.get('loras', []):
        alias = lora.get('alias', '')
        loras[alias] = {
            'name': lora.get('name', ''),
            'triggers': lora.get('triggers', []),
            'default_strength': lora.get('strength', 1.0)
        }
    
    # Get prompt IDs
    prompts = [p.get('id', 'unknown') for p in job_conf.get('prompts', [])
               if not p.get('skip', False)]
    
    manifest = {
        'job_name': job_name,
        'job_hash': job_hash,
        'variant_id': variant_id,
        'created_at': datetime.now().isoformat(),
        
        'generation_context': generation_context,
        'base_config': base_config,
        'range_increment': defaults.get('range_increment', 0.1),
        'loras': loras,
        'wildcards': wildcards,
        'prompts': prompts
    }
    
    return manifest


def generate_prompt_json(
    prompt_conf: dict,
    job_conf: dict,
    wildcards: Dict[str, List[str]],
    ext_text_values: Dict[str, List[str]],
    checkpoints: List[dict],
    range_increment: float = 0.1
) -> dict:
    """
    Generate prompt.json content for a single prompt.
    
    Args:
        prompt_conf: Prompt configuration from jobs.yaml
        job_conf: Job configuration
        wildcards: Wildcard registry
        ext_text_values: Extension text values
        checkpoints: List of checkpoint dicts from parse_text_tree
        range_increment: Step size for LoRA ranges
    
    Returns:
        Prompt data dict ready to be written as JSON
    """
    prompt_id = prompt_conf.get('id', 'unknown')
    
    # Get defaults
    defaults = job_conf.get('defaults', {})
    if isinstance(defaults, list):
        defaults = defaults[0] if defaults else {}
    
    # Config overrides from prompt
    config_overrides = {}
    for key in ['width', 'height', 'steps', 'cfg']:
        if key in prompt_conf:
            config_overrides[key] = prompt_conf[key]
    
    # Expand LoRA combinations
    lora_specs = prompt_conf.get('loras', [])
    configs = expand_lora_combinations(lora_specs, range_increment)
    
    # If no configs specified, use a default config
    if not configs:
        configs = [{'index': 0, 'spec': 'default', 'loras': {}, 'suffix': 'base'}]
    
    # Build checkpoint list (simplified from full checkpoint data)
    checkpoint_list = []
    for cp in checkpoints:
        combinations = cp.get('combinations', [])
        cover_index = combinations[0]['index'] if combinations else 1
        
        checkpoint_list.append({
            'path': cp['path'],
            'path_string': cp['path_string'],
            'node_id': cp['node_id'],
            'raw_text': cp.get('raw_text', ''),
            'resolved_preview': cp.get('resolved_preview', ''),
            'cover_image_index': cover_index,
            'wildcards_used': list(cp.get('wildcard_counts', {}).keys()),
            'wildcard_counts': cp.get('wildcard_counts', {}),
            'total_variations': cp.get('total_variations', 1),
            'own_variations': cp.get('own_variations', cp.get('total_variations', 1)),
            'has_children': cp.get('has_children', False),
            'segment_values': cp.get('segment_values', [])
        })
    
    # Build LoRA definitions list for frontend
    loras_list = []
    for lora in job_conf.get('loras', []):
        loras_list.append({
            'alias': lora.get('alias', ''),
            'name': lora.get('name', ''),
            'strength': lora.get('strength', 1.0),
            'triggers': lora.get('triggers', [])
        })
    
    # Build full config (base defaults + prompt overrides)
    model_conf = job_conf.get('model', {})
    sampler_list = model_conf.get('sampler', [])
    default_sampler = sampler_list[0] if sampler_list else {}
    
    config = {
        'model': model_conf.get('name', 'unknown'),
        'sampler': default_sampler.get('sampler', 'euler'),
        'scheduler': default_sampler.get('scheduler', 'simple'),
        'steps': defaults.get('steps', 9),
        'cfg': defaults.get('cfg', 1.0),
        'width': defaults.get('width', 1024),
        'height': defaults.get('height', 1024)
    }
    # Apply prompt-level overrides
    config.update(config_overrides)
    
    # Calculate totals
    total_images = sum(cp.get('total_variations', 1) for cp in checkpoints)
    total_configs = len(configs)
    
    # Build lora_combinations list (spec strings for frontend pills)
    lora_combinations = [cfg.get('suffix', 'base') for cfg in configs]
    
    return {
        'prompt_id': prompt_id,
        'config_overrides': config_overrides,
        'config': config,
        'configs': configs,
        'loras': loras_list,
        'lora_combinations': lora_combinations,
        'checkpoints': checkpoint_list,
        'summary': {
            'total_checkpoints': len(checkpoints),
            'total_images': total_images,
            'total_configs': total_configs,
            'total_with_configs': total_images * total_configs
        }
    }


def generate_checkpoint_data(
    path_string: str,
    prompt_id: str,
    combinations: List[dict],
    wildcards: Dict[str, List[str]],
    num_configs: int,
    ext_indices: Dict[str, int] = None
) -> dict:
    """
    Generate data.json content for a checkpoint path.

    NOTE: Status is NOT stored in data.json. Status is stored separately in
    status/c{composition}.json files for runtime composition support.

    Args:
        path_string: Full path string (e.g., "outfits[1]/expression[1]~stance[1]")
        prompt_id: Prompt ID
        combinations: List of combination dicts with wildcards
        wildcards: Wildcard registry (for index conversion)
        num_configs: Number of configs (for status array size)
        ext_indices: Optional ext_text indices for hash computation

    Returns:
        Checkpoint data dict ready to be written as JSON
    """
    images = []

    for combo in combinations:
        index = combo.get('index', 1)
        wc_data = combo.get('wildcards', {})

        # Handle wildcard data - now stored as indices (int) not values (str)
        wc_indices = None
        if wc_data:
            # Check if already indices or need conversion
            if isinstance(next(iter(wc_data.values()), None), int):
                # Already indices from parse_text_tree fix
                wc_indices = wc_data
            else:
                # Legacy: still values, need conversion
                wc_indices = {}
                for wc_name, wc_value in wc_data.items():
                    idx = wildcard_value_to_index(wc_name, wc_value, wildcards)
                    if idx >= 0:
                        wc_indices[wc_name] = idx

        # Compute content-addressable hash
        wc_hash = compute_wc_hash(wc_indices, ext_indices)

        # NO status in data.json - status is per-composition in status/c{id}.json
        img_entry = {
            'i': index,
            'wc': wc_indices if wc_indices else None,
            'wc_hash': wc_hash
        }

        # Only include ext field if ext_indices present
        if ext_indices:
            img_entry['ext'] = ext_indices

        images.append(img_entry)

    # Build summary (counts only, no status tracking)
    total = len(images) * num_configs

    return {
        'path_string': path_string,
        'prompt_id': prompt_id,
        'images': images,
        'num_configs': num_configs,
        'summary': {
            'total': total
        }
    }


# =============================================================================
# FILE I/O
# =============================================================================

def write_manifest(manifest: dict, outputs_dir: Path) -> Path:
    """
    Write manifest.json to outputs directory.
    
    Args:
        manifest: Manifest dict
        outputs_dir: Path to outputs directory
    
    Returns:
        Path to written file
    """
    outputs_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = outputs_dir / 'manifest.json'
    
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)
    
    return manifest_path


def write_prompt_json(prompt_data: dict, prompt_dir: Path) -> Path:
    """
    Write prompt.json to prompt directory.
    
    Args:
        prompt_data: Prompt data dict
        prompt_dir: Path to prompt directory
    
    Returns:
        Path to written file
    """
    prompt_dir.mkdir(parents=True, exist_ok=True)
    prompt_path = prompt_dir / 'prompt.json'
    
    with open(prompt_path, 'w') as f:
        json.dump(prompt_data, f, indent=2)
    
    return prompt_path


def write_checkpoint_data(checkpoint_data: dict, checkpoint_dir: Path) -> Path:
    """
    Write data.json to checkpoint directory.

    NOTE: Status is NOT stored in data.json anymore. Status is managed
    separately in status/c{composition}.json files for runtime composition.

    Args:
        checkpoint_data: Checkpoint data dict (without status)
        checkpoint_dir: Path to checkpoint directory

    Returns:
        Path to written file
    """
    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    data_path = checkpoint_dir / 'data.json'

    with open(data_path, 'w') as f:
        json.dump(checkpoint_data, f, indent=2)

    return data_path



def load_manifest(outputs_dir: Path) -> dict:
    """Load manifest.json from outputs directory."""
    manifest_path = outputs_dir / 'manifest.json'
    if not manifest_path.exists():
        return {}
    with open(manifest_path, 'r') as f:
        return json.load(f)


def load_prompt_json(prompt_dir: Path) -> dict:
    """Load prompt.json from prompt directory."""
    prompt_path = prompt_dir / 'prompt.json'
    if not prompt_path.exists():
        return {}
    with open(prompt_path, 'r') as f:
        return json.load(f)


def load_checkpoint_data(checkpoint_dir: Path) -> dict:
    """Load data.json from checkpoint directory."""
    data_path = checkpoint_dir / 'data.json'
    if not data_path.exists():
        return {}
    with open(data_path, 'r') as f:
        return json.load(f)


# =============================================================================
# STATUS UPDATES
# =============================================================================

def update_composition_status(
    checkpoint_dir: Path,
    image_index: int,
    config_index: int,
    composition: int,
    status: int
) -> bool:
    """
    Update status for a specific image + config in status/c{composition}.json.

    Args:
        checkpoint_dir: Path to checkpoint directory
        image_index: Image index (1-based, matching 'i' field in images)
        config_index: Config index (0-based)
        composition: Composition ID
        status: Status code (0=pending, 1=generated)

    Returns:
        True if updated successfully
    """
    status_dir = checkpoint_dir / 'status'
    status_file = status_dir / f'c{composition}.json'

    # Load existing status or create new
    status_data = None
    if status_file.exists():
        try:
            with open(status_file, 'r') as f:
                status_data = json.load(f)
        except Exception:
            pass

    if status_data is None:
        # Initialize from data.json
        data = load_checkpoint_data(checkpoint_dir)
        if not data:
            return False

        num_images = len(data.get('images', []))
        num_configs = data.get('num_configs', 1)
        status_data = {
            'composition': composition,
            'status': [[0] * num_configs for _ in range(num_images)]
        }

    # Update the specific entry (convert 1-based image_index to 0-based)
    status_arr = status_data.get('status', [])
    array_idx = image_index - 1

    if 0 <= array_idx < len(status_arr):
        if config_index < len(status_arr[array_idx]):
            status_arr[array_idx][config_index] = status
        else:
            # Extend if needed
            while len(status_arr[array_idx]) <= config_index:
                status_arr[array_idx].append(0)
            status_arr[array_idx][config_index] = status
    else:
        return False

    # Write to file
    status_dir.mkdir(parents=True, exist_ok=True)
    with open(status_file, 'w') as f:
        json.dump(status_data, f, indent=2)

    return True


def update_image_status(
    checkpoint_dir: Path,
    image_index: int,
    config_index: int,
    status: int,
    composition: int = None
) -> bool:
    """
    Update status for a specific image + config in data.json.

    Status codes:
        0 = pending
        1 = generated
        2 = queued
        3 = stale

    Args:
        checkpoint_dir: Path to checkpoint directory
        image_index: Image index (1-based)
        config_index: Config index (0-based)
        status: Status code
        composition: Optional composition ID. If provided, also updates status/c{composition}.json

    Returns:
        True if updated successfully
    """
    data = load_checkpoint_data(checkpoint_dir)
    if not data:
        # Even if data.json doesn't exist, try to update composition status if provided
        if composition is not None:
            try:
                return update_composition_status(checkpoint_dir, image_index, config_index, composition, status)
            except Exception as e:
                print(f"Warning: Failed to update composition status: {e}")
        return False

    # Find image by index
    data_json_updated = False
    for img in data.get('images', []):
        if img.get('i') == image_index:
            status_arr = img.get('status', [])
            if config_index < len(status_arr):
                old_status = status_arr[config_index]
                status_arr[config_index] = status

                # Update summary
                if 'summary' in data:
                    # Decrement old status count
                    if old_status == 0:
                        data['summary']['pending'] = max(0, data['summary'].get('pending', 0) - 1)
                    elif old_status == 1:
                        data['summary']['generated'] = max(0, data['summary'].get('generated', 0) - 1)
                    elif old_status == 2:
                        data['summary']['queued'] = max(0, data['summary'].get('queued', 0) - 1)

                    # Increment new status count
                    if status == 0:
                        data['summary']['pending'] = data['summary'].get('pending', 0) + 1
                    elif status == 1:
                        data['summary']['generated'] = data['summary'].get('generated', 0) + 1
                    elif status == 2:
                        data['summary']['queued'] = data['summary'].get('queued', 0) + 1

                write_checkpoint_data(data, checkpoint_dir)
                data_json_updated = True
            break

    # If composition provided, always update composition status file
    # (regardless of whether data.json was updated, since status may not be in data.json)
    if composition is not None:
        try:
            update_composition_status(checkpoint_dir, image_index, config_index, composition, status)
            return True  # Success if composition status was updated
        except Exception as e:
            print(f"Warning: Failed to update composition status: {e}")

    return data_json_updated


# =============================================================================
# SCHEMA VERIFICATION
# =============================================================================

def verify_manifest_schema(manifest: dict) -> Tuple[bool, List[str]]:
    """
    Verify manifest.json matches expected WebUI schema.
    
    Returns:
        (is_valid, list of error messages)
    """
    errors = []
    
    required = ['job_name', 'generation_context', 'loras', 'wildcards', 'prompts']
    for key in required:
        if key not in manifest:
            errors.append(f"Missing required key: {key}")
    
    if 'prompts' in manifest and not isinstance(manifest['prompts'], list):
        errors.append(f"'prompts' should be a list, got {type(manifest['prompts'])}")
    
    return len(errors) == 0, errors


def verify_prompt_schema(prompt_data: dict) -> Tuple[bool, List[str]]:
    """
    Verify prompt.json matches expected WebUI schema.
    
    Returns:
        (is_valid, list of error messages)
    """
    errors = []
    
    required = ['prompt_id', 'configs', 'checkpoints']
    for key in required:
        if key not in prompt_data:
            errors.append(f"Missing required key: {key}")
    
    # Verify configs structure
    if 'configs' in prompt_data:
        for i, cfg in enumerate(prompt_data['configs']):
            for key in ['index', 'loras', 'suffix']:
                if key not in cfg:
                    errors.append(f"Config {i} missing key: {key}")
    
    return len(errors) == 0, errors


def verify_data_schema(data: dict) -> Tuple[bool, List[str]]:
    """
    Verify data.json matches expected WebUI schema.

    NOTE: Status is NOT stored in data.json anymore. Status is managed
    separately in status/c{composition}.json files for runtime composition.

    Returns:
        (is_valid, list of error messages)
    """
    errors = []

    required = ['path_string', 'prompt_id', 'images', 'summary']
    for key in required:
        if key not in data:
            errors.append(f"Missing required key: {key}")

    # Verify images structure - status no longer required (handled separately)
    if 'images' in data:
        for i, img in enumerate(data['images']):
            if 'i' not in img:
                errors.append(f"Image {i} missing 'i' key")
            # NOTE: 'status' is now in status/c{id}.json, not in data.json

    return len(errors) == 0, errors


# =============================================================================
# EXT_TEXT LOADING (Standalone - avoids torch import chain)
# =============================================================================

def load_ext_text_values(job_dir: Path, ext_namespace: str = 'defaults') -> Dict[str, List[str]]:
    """
    Load all ext_text arrays from extension YAML files WITHOUT resolving wildcards.
    
    This is a standalone version that avoids importing composition.py
    which has torch dependencies.
    
    Args:
        job_dir: Job directory path
        ext_namespace: Extension namespace (e.g., 'fashion')
        
    Returns:
        Dict mapping ext_id -> list of text values (wildcards preserved)
    """
    import yaml
    
    ext_text_values = {}
    
    # First try to load from segments.yaml (most complete, generated by build-job.py)
    segments_path = job_dir / 'outputs' / 'segments.yaml'
    if segments_path.exists():
        with open(segments_path, 'r') as f:
            segments_data = yaml.safe_load(f) or {}
        ext_registry = segments_data.get('ext_registry', {})
        ext_text_values.update(ext_registry)
    
    # Also load from ext/{namespace}/ folder
    ext_dir = job_dir.parent.parent / 'ext' / ext_namespace
    if ext_dir.exists():
        for ext_file in sorted(ext_dir.glob('*.yaml')):
            try:
                with open(ext_file, 'r') as f:
                    ext_data = yaml.safe_load(f) or {}
                ext_id = ext_data.get('id')
                if ext_id and 'text' in ext_data:
                    ext_text_values[ext_id] = ext_data['text']
            except Exception:
                pass
    
    return ext_text_values
