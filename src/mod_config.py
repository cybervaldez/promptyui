#!/usr/bin/env python3
"""
Mod Configuration Management

Provides loading, merging, and saving of mod configs with global/job inheritance.

Config Priority (highest to lowest):
1. Job-level config: /jobs/[job]/mods/[mod_id]/config.json
2. Global config: /mods/[mod_id]/config.json
3. Hardcoded defaults in mod script
"""

import json
from pathlib import Path
from typing import Dict, Any, Optional, List

PROJECT_ROOT = Path(__file__).parent.parent


def load_json(path: Path) -> Optional[dict]:
    """Load JSON file, return None if not exists or invalid."""
    if not path.exists():
        return None
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"   ⚠️ Failed to load {path}: {e}")
        return None


def save_json(path: Path, data: dict) -> bool:
    """Save JSON file, create directories if needed."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
        return True
    except IOError as e:
        print(f"   ⚠️ Failed to save {path}: {e}")
        return False


def deep_merge(base: dict, override: dict) -> dict:
    """
    Deep merge override into base.
    
    - Keys in override replace keys in base
    - Nested dicts are recursively merged
    - 'ui' key is always taken from base (global) to ensure UI schema consistency
    """
    result = base.copy()
    for key, value in override.items():
        if key == 'ui':
            # Never override UI schema from job config
            continue
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def get_global_config_path(mod_id: str) -> Path:
    """Get path to global mod config."""
    return PROJECT_ROOT / 'mods' / mod_id / 'config.json'


def get_job_config_path(mod_id: str, job_name: str) -> Path:
    """Get path to job-level mod config."""
    return PROJECT_ROOT / 'jobs' / job_name / 'mods' / mod_id / 'config.json'


def load_mod_config(mod_id: str, job_name: str) -> dict:
    """
    Load merged config for a mod.
    
    Args:
        mod_id: Mod identifier (e.g., 'test_config')
        job_name: Job name (e.g., 'pixel-fantasy')
    
    Returns:
        Merged config dict (job overrides global)
    """
    global_config = load_json(get_global_config_path(mod_id)) or {}
    job_config = load_json(get_job_config_path(mod_id, job_name)) or {}
    
    return deep_merge(global_config, job_config)


def save_job_config(mod_id: str, job_name: str, config: dict) -> bool:
    """
    Save job-level config override.
    
    Args:
        mod_id: Mod identifier
        job_name: Job name
        config: Config values to save (without 'ui' key)
    
    Returns:
        True if successful
    """
    # Don't save UI schema to job config
    config_to_save = {k: v for k, v in config.items() if k != 'ui' and k != '$schema'}
    return save_json(get_job_config_path(mod_id, job_name), config_to_save)


def delete_job_config(mod_id: str, job_name: str) -> bool:
    """Delete job-level config override (revert to global)."""
    path = get_job_config_path(mod_id, job_name)
    if path.exists():
        try:
            path.unlink()
            return True
        except IOError:
            return False
    return True


def has_job_override(mod_id: str, job_name: str) -> bool:
    """Check if job has a config override for this mod."""
    return get_job_config_path(mod_id, job_name).exists()


def get_mods_with_config() -> List[str]:
    """Get list of mod IDs that have global config files."""
    mods_dir = PROJECT_ROOT / 'mods'
    result = []
    
    if not mods_dir.exists():
        return result
    
    for item in mods_dir.iterdir():
        if item.is_dir() and (item / 'config.json').exists():
            result.append(item.name)
    
    return sorted(result)


def load_all_mod_configs(job_name: str, enabled_mods: List[str] = None) -> Dict[str, dict]:
    """
    Load configs for all mods (or specified subset).
    
    Args:
        job_name: Job name for job-level overrides
        enabled_mods: Optional list of mod IDs to load (loads all if None)
    
    Returns:
        Dict mapping mod_id -> merged config
    """
    mods_with_config = get_mods_with_config()
    
    if enabled_mods:
        # Only load configs for enabled mods that have config files
        mod_ids = [m for m in enabled_mods if m in mods_with_config]
    else:
        mod_ids = mods_with_config
    
    return {
        mod_id: load_mod_config(mod_id, job_name)
        for mod_id in mod_ids
    }
