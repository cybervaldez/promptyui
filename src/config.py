"""
src/config.py - Configuration Loading and Path Utilities

This module provides core utilities for YAML configuration loading, path resolution,
and job configuration hashing used throughout the Prompt Generator system.

FUNCTIONS:
----------
load_yaml(path):
    Load and parse a YAML file. Returns the parsed content as a dict/list.
    Used by: main.py, extensions.py, jobs.py

resolve_path(root, filename):
    Resolve a filename to an absolute path. If filename is already absolute,
    returns it as-is. Otherwise, joins it with root directory.
    Used by: jobs.py for LoRA path resolution

get_unique_filename(directory, filename):
    Handle file conflicts by backing up existing files. If target file exists,
    renames it to [name]_0001.bak (incrementing) and returns the original path.
    Used by: main.py for output file management

compute_job_hash(task_conf, global_conf, job_dir):
    Compute MD5 hash of job configuration for change detection between runs.
    Excludes volatile fields (batch_total, timestamps) to focus on what affects output.
    Used by: main.py to detect when job config changed and backup is needed

USAGE:
------
    from src.config import load_yaml, resolve_path, compute_job_hash
    
    config = load_yaml(Path("config.yaml"))
    lora_path = resolve_path(lora_root, "model.safetensors")
    job_hash = compute_job_hash(job_conf, global_conf, job_dir)

AI ASSISTANT NOTES:
-------------------
- load_yaml uses yaml.safe_load for security
- compute_job_hash is critical for the resume/continue feature
- Hash includes: prompts, loras, inputs, defaults, model config, extensions, operations
- Hash excludes: batch_total, total_batch_max (volatile runtime values)
"""

import os
import shutil
import yaml
import hashlib
from pathlib import Path


def load_yaml(path):
    """
    Load a YAML file and return its contents.
    
    Args:
        path: Path object or string to the YAML file
        
    Returns:
        Parsed YAML content (typically dict or list)
        
    Raises:
        FileNotFoundError: If the file doesn't exist
        yaml.YAMLError: If the file contains invalid YAML
        
    Example:
        config = load_yaml(Path("config.yaml"))
        job = load_yaml("jobs/andrea/jobs.yaml")
    """
    with open(path, "r") as f:
        return yaml.safe_load(f)


def save_yaml(path, data):
    """
    Save data to a YAML file.
    
    Args:
        path: Path object or string to the YAML file
        data: Data to save (typically dict or list)
        
    Example:
        save_yaml(Path("config.yaml"), {"key": "value"})
    """
    with open(path, "w") as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)



def resolve_path(root, filename):
    """
    Resolve a filename to an absolute path relative to root directory.
    
    If filename is already absolute, returns it unchanged.
    Otherwise, joins filename with root to create absolute path.
    
    Args:
        root: Base directory (Path or string)
        filename: Filename or relative path (Path or string)
        
    Returns:
        Path object with resolved absolute path
        
    Example:
        # Relative path gets joined with root
        resolve_path("/loras/flux", "model.safetensors")
        # -> /loras/flux/model.safetensors
        
        # Absolute path returned as-is
        resolve_path("/loras/flux", "/custom/path/model.safetensors")
        # -> /custom/path/model.safetensors
    """
    root = Path(root).expanduser().resolve()
    fpath = Path(filename).expanduser()
    if fpath.is_absolute():
        return fpath
    return root / filename


def get_unique_filename(directory, filename):
    """
    Returns the target filename path, backing up existing file if needed.
    
    If the target file exists, it's renamed to [name]_0001.bak
    (incrementing the counter if needed), then the original path is returned.
    
    Args:
        directory: Directory containing the file (Path object)
        filename: Target filename (string)
        
    Returns:
        Path object to the (now available) target filename
        
    Side Effects:
        - May rename existing file to .bak extension
        - Prints backup notification to console
        
    Example:
        # If output.json exists, it becomes output_0001.bak
        path = get_unique_filename(job_dir, "output.json")
        # path is now available for writing
    """
    candidate = directory / filename
    if not candidate.exists():
        return candidate
    
    # File exists, need to backup
    name, ext = os.path.splitext(filename)
    counter = 1
    
    # Find next available backup filename
    while True:
        backup_name = f"{name}_{counter:04d}.bak"
        backup_path = directory / backup_name
        if not backup_path.exists():
            # Rename existing file to backup
            shutil.move(str(candidate), str(backup_path))
            print(f"   📦 Backed up existing file to: {backup_name}")
            return candidate  # Return original name, now available
        counter += 1


def compute_job_hash(task_conf, global_conf, job_dir, variant_id="default"):
    """
    Compute MD5 hash of job configuration for change detection.
    
    This hash is used to detect when a job configuration has changed between runs,
    allowing the system to backup old results and start fresh instead of corrupting
    existing data by mixing incompatible configurations.
    
    Args:
        task_conf: Job configuration dict from jobs.yaml
        global_conf: Global configuration dict including processed extensions
        job_dir: Path to job directory (for loading variant file)
        variant_id: Variant identifier (default: "default")
        
    Returns:
        32-character hex string (MD5 hash)
        
    Hash Includes (affects generated images):
        - prompts: All prompt definitions, extends, wildcards, loras
        - loras: LoRA library definitions
        - inputs: Input image definitions
        - defaults: seed, delimiters, range_increment, ext settings
        - model: name, lora_path, sampler configuration
        - ext: Extension data (after addon processing)
        - variant: Content of variants/{variant_id}.yaml if exists
        - variant_id: The variant identifier itself
        
    Hash Excludes (volatile, doesn't affect output):
        - batch_total / total_batch_max
        - Per-sampler steps/cfg overrides (stored in JSON)
        - Timestamp fields
        
    Example:
        current_hash = compute_job_hash(job_conf, global_conf, job_dir, "default")
        if current_hash != previous_hash:
            print("Config changed, backing up old results")
    """
    # Create normalized config dict
    hash_config = {
        'prompts': task_conf.get('prompts', []),
        'loras': task_conf.get('loras', []),
        'inputs': task_conf.get('inputs', []),
    }
    
    # Include defaults but exclude volatile fields
    defaults = task_conf.get('defaults', {})
    hash_config['defaults'] = {
        k: v for k, v in defaults.items()
        if k not in ['batch_total', 'total_batch_max']
    }
    
    # Include model config
    model_config = task_conf.get('model', {})
    hash_config['model'] = {
        'name': model_config.get('name'),
        'lora_path': model_config.get('lora_path'),
        'sampler': model_config.get('sampler', []),
    }
    
    # Include extension data (after addon processing)
    hash_config['ext'] = global_conf.get('ext', [])
    
    # Include variant file if exists
    variant_file = job_dir / "variants" / f"{variant_id}.yaml"
    if variant_file.exists():
        try:
            hash_config['variant'] = load_yaml(variant_file)
        except Exception:
            pass  # If we can't load it, skip it
    
    # Include variant_id in hash (ensures different variants have different hashes)
    hash_config['variant_id'] = variant_id
    
    # Serialize to canonical YAML (deterministic ordering)
    yaml_str = yaml.dump(hash_config, sort_keys=True, default_flow_style=False)
    
    # Compute MD5 hash
    return hashlib.md5(yaml_str.encode('utf-8')).hexdigest()
