"""
src/variant.py - Variant Structure Generation

Generates the variant.json file containing the "skeleton" or "structure" of a job:
- Generation context (model, lora_root, trigger_delimiter)  
- Configuration arrays (sampler, lora, cfg, steps, etc.)
- Segments (prompts, ext_registry, wildcards, composition, configs)
- LoRA information (triggers, paths)

This structure is SHARED across all seeds of a variant.
Seed-specific data (images array, status) goes in data.json.

USAGE:
------
    from src.variant import build_variant_structure, write_variant_json

    structure = build_variant_structure(job_conf, global_conf, lora_root, ...)
    write_variant_json(structure, output_path)
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional

from src.config import compute_job_hash
from src.jobs import build_jobs
from src.segments import SegmentRegistry, build_composition


def build_variant_structure(
    job_conf: dict,
    global_conf: dict,
    lora_root: Path,
    variant_id: str = "default",
    job_name: str = "",
    job_dir: Optional[Path] = None,
    default_params: Optional[dict] = None,
    wildcards_max: int = 0,
    ext_text_max: int = 1,
    default_ext: str = "defaults",
    samplers_config: Optional[list] = None,
    range_increment: float = 0.1,
    prompts_delimiter: str = " ",
    trigger_delimiter: str = ", ",
    ext_text_delimiter: str = ", ",
    composition_id: int = None
) -> dict:
    """
    Build the complete variant structure (skeleton/makeup).
    
    This contains everything EXCEPT seed-specific data (images array, status).
    Designed to be shared across multiple seeds.
    
    Args:
        job_conf: Job configuration from jobs.yaml
        global_conf: Global configuration with loaded extensions
        lora_root: Path to LoRA files
        variant_id: Variant identifier (default: "default")
        job_name: Name of the job
        job_dir: Path to job directory (for hash computation)
        default_params: Default generation parameters {width, height, steps, cfg}
        wildcards_max: Wildcard expansion limit (caps ALL wildcards post-merge)
        ext_text_max: Extension text consumption limit
        default_ext: Default extension folder
        samplers_config: Sampler configuration list
        range_increment: Range increment for parameter sweeps
        prompts_delimiter: Delimiter for prompt joining
        trigger_delimiter: Delimiter for LoRA triggers
        ext_text_delimiter: Delimiter for extension texts
        composition_id: Composition ID for seeding random wildcard selection (default: None uses 42)

    Returns:
        Complete variant structure dictionary
    """
    if default_params is None:
        default_params = {'width': 1024, 'height': 1024, 'steps': 9, 'cfg': 1.0}
    
    # Compute job config hash
    job_config_hash = compute_job_hash(job_conf, global_conf, job_dir, variant_id)
    
    # Build jobs to extract structure
    jobs = build_jobs(
        job_conf,
        lora_root,
        range_increment,
        prompts_delimiter,
        global_conf,
        wildcards_max=wildcards_max,
        ext_text_max=ext_text_max,
        default_ext=default_ext,
        samplers_config=samplers_config,
        default_params=default_params,
        input_images=None,
        composition_id=composition_id
    )
    
    # =========================================================================
    # BUILD SEGMENT LOOKUP TABLES
    # =========================================================================
    
    prompt_lookup = {}   # prompt_id -> index
    prompts_list = []    # index -> prompt_id
    
    text_lookup = {}     # text_key -> index
    texts_list = []      # index -> text_key
    
    config_lookup = {}   # config_key -> index
    configs_list = []    # index -> config_key
    
    ext_indices_map = {}       # t -> ext_indices dict
    wildcard_values_map = {}   # t -> wildcard_usage dict
    
    def get_segment_idx(lookup, lst, value):
        """Get or create index for a segment value."""
        if value not in lookup:
            lookup[value] = len(lst)
            lst.append(value)
        return lookup[value]
    
    unique_pt = set()  # Track unique prompt+text combos for stacked view count
    
    for job in jobs:
        prompt_entry = job['prompt']
        prompt_id = prompt_entry.get('id', 'unknown')
        prompt_text = prompt_entry.get('text', '')
        
        # P = prompt index
        p_idx = get_segment_idx(prompt_lookup, prompts_list, prompt_id)
        
        # Build text variation key from ext_indices
        ext_indices = prompt_entry.get('_ext_indices')
        if ext_indices:
            text_key = "_".join(f"ext_{k}[{v}]" for k, v in sorted(ext_indices.items()))
        else:
            text_var_idx = prompt_entry.get('_text_variation_index', 0)
            text_key = f"text[{text_var_idx}]" if text_var_idx else ""
        
        # Extract wildcard usage
        wildcard_usage = prompt_entry.get('_wildcard_usage', {})
        
        # Build wc_parts for text_key
        wc_parts = []
        for wc_name in sorted(wildcard_usage.keys()):
            wc_data = wildcard_usage[wc_name]
            if isinstance(wc_data, dict):
                wc_idx = wc_data.get('index', 1)
            else:
                wc_idx = wc_data
            wc_parts.append(f"{wc_name}[{wc_idx}]")
        
        if wc_parts:
            text_key = text_key + "_" + "_".join(wc_parts) if text_key else "_".join(wc_parts)
        
        t_idx = get_segment_idx(text_lookup, texts_list, text_key) if text_key else 0
        
        # Store reconstruction data for this text segment
        if t_idx not in ext_indices_map:
            ext_indices_map[t_idx] = prompt_entry.get('_ext_indices', {})
            wildcard_values_map[t_idx] = wildcard_usage
        
        # Build config key (lora + sampler + cfg + steps)
        lora_suffix = job.get('filename_suffix', 'base')
        sampler_name = job.get('sampler')
        scheduler_type = job.get('scheduler')
        params = job.get('params', default_params)
        
        config_key = f"{lora_suffix}_{sampler_name}_{scheduler_type}_cfg[{params.get('cfg', 1.0)}]_s[{params.get('steps', 9)}]"
        c_idx = get_segment_idx(config_lookup, configs_list, config_key)
        
        unique_pt.add((p_idx, t_idx))
    
    # =========================================================================
    # BUILD SEGMENT REGISTRY AND COMPOSITION
    # =========================================================================
    
    segment_registry = SegmentRegistry.from_global_conf(global_conf)
    
    # Build composition array
    max_t = len(texts_list)
    composition = []
    
    for t in range(max_t):
        ext_indices = ext_indices_map.get(t, {})
        wc_usage = wildcard_values_map.get(t, {})
        comp = build_composition(ext_indices, wc_usage)
        composition.append(comp)
    
    # =========================================================================
    # EXTRACT CONFIG VALUES
    # =========================================================================
    
    config_values = {
        'sampler': set(),
        'scheduler': set(),
        'lora': set(),
        'cfg': set(),
        'steps': set(),
        'width': set(),
        'height': set(),
        'shift': set(),
    }
    
    for job in jobs:
        if job.get('sampler'):
            config_values['sampler'].add(job['sampler'])
        if job.get('scheduler'):
            config_values['scheduler'].add(job['scheduler'])
        for lora in job.get('loras', []):
            config_values['lora'].add(lora.get('alias', ''))
        
        params = job.get('params', {})
        config_values['cfg'].add(params.get('cfg', default_params['cfg']))
        config_values['steps'].add(params.get('steps', default_params['steps']))
        config_values['width'].add(params.get('width', default_params['width']))
        config_values['height'].add(params.get('height', default_params['height']))
        
        sampler_params = job.get('sampler_params', {})
        if 'shift' in sampler_params:
            config_values['shift'].add(sampler_params['shift'])
    
    # =========================================================================
    # EXTRACT LORA DATA
    # =========================================================================
    
    loras_dict = {}
    lora_paths_dict = {}
    
    for lora_entry in job_conf.get('loras', []):
        alias = lora_entry.get('alias')
        triggers = lora_entry.get('triggers', [])
        if not isinstance(triggers, list):
            single_trigger = lora_entry.get('trigger', '')
            triggers = [single_trigger] if single_trigger else []
        
        if alias:
            loras_dict[alias] = [t for t in triggers if t]
            lora_name = lora_entry.get('name', '')
            if lora_name:
                lora_paths_dict[alias] = str(lora_root / lora_name)
    
    # =========================================================================
    # EXTRACT WILDCARDS FROM EXTENSIONS
    # =========================================================================
    
    wildcards_dict = {}
    for ext in global_conf.get('ext', []):
        if 'wildcards' in ext:
            for wc in ext['wildcards']:
                wc_name = wc.get('name')
                wc_options = wc.get('text', [])
                if wc_name and wc_options:
                    if wc_name in wildcards_dict:
                        existing = set(wildcards_dict[wc_name])
                        wildcards_dict[wc_name] = list(existing | set(wc_options))
                    else:
                        wildcards_dict[wc_name] = wc_options
    
    # =========================================================================
    # EXTRACT WILDCARDS FROM INLINE PROMPT DEFINITIONS
    # =========================================================================
    
    for prompt_entry in job_conf.get('prompts', []):
        inline_wildcards = prompt_entry.get('wildcards', [])
        for wc in inline_wildcards:
            wc_name = wc.get('name')
            wc_options = wc.get('text', [])
            if wc_name and wc_options:
                if wc_name in wildcards_dict:
                    existing = set(wildcards_dict[wc_name])
                    wildcards_dict[wc_name] = list(existing | set(wc_options))
                else:
                    wildcards_dict[wc_name] = wc_options
    
    # =========================================================================
    # BUILD FILENAME PATTERN
    # =========================================================================
    
    filename_pattern = "{prompt_id}_t{t}_c{c}.png"
    if jobs:
        sample_job = jobs[0]
        pattern_parts = ["{index:04d}", "{prompt_id}", "{lora_suffix}"]
        if sample_job.get('sampler'):
            pattern_parts.append("{sampler}_{scheduler}")
        filename_pattern = "_".join(pattern_parts) + ".png"
    
    # =========================================================================
    # BUILD FINAL STRUCTURE
    # =========================================================================
    
    structure = {
        'variant_id': variant_id,
        'job_name': job_name,
        'job_config_hash': job_config_hash,
        'created_at': datetime.now().isoformat(),
        'generation_context': {
            'model_name': job_conf.get('model', {}).get('name', 'unknown'),
            'lora_root': str(lora_root),
            'trigger_delimiter': trigger_delimiter,
        },
        'config': {k: sorted(list(v)) for k, v in config_values.items() if v},
        'loras': loras_dict,
        'wildcards': wildcards_dict,
        'segments': {
            'prompts': prompts_list,
            'ext_registry': segment_registry.ext_registry,
            'wildcards': segment_registry.wildcards,
            'composition': composition,
            'configs': configs_list,
            'ext_text_delimiter': ext_text_delimiter,
            'resolution': {
                'width': default_params['width'],
                'height': default_params['height']
            },
        },
        'lora_paths': lora_paths_dict,
        'filename_pattern': filename_pattern,
        'total_images': len(jobs),
        'stacked_count': len(unique_pt),
    }
    
    return structure


def write_variant_json(structure: dict, output_path: Path) -> Path:
    """
    Write variant structure to JSON file.
    
    Args:
        structure: Variant structure dictionary
        output_path: Path to write JSON file
        
    Returns:
        Path to written file
    """
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w') as f:
        json.dump(structure, f, indent=2, default=str)
    
    return output_path


def load_variant(variant_path: Path) -> dict:
    """
    Load and validate a variant.json file.
    
    Args:
        variant_path: Path to variant.json
        
    Returns:
        Variant structure dictionary
        
    Raises:
        FileNotFoundError: If variant.json doesn't exist
        ValueError: If variant.json is invalid
    """
    if not variant_path.exists():
        raise FileNotFoundError(f"Variant file not found: {variant_path}")
    
    with open(variant_path, 'r') as f:
        structure = json.load(f)
    
    # Validate required keys
    required_keys = ['variant_id', 'job_config_hash', 'segments', 'total_images']
    for key in required_keys:
        if key not in structure:
            raise ValueError(f"Variant file missing required key: {key}")
    
    return structure


def get_variant_path(job_dir: Path, variant_id: str = "default") -> Path:
    """
    Get the path to a variant YAML directory.
    
    Args:
        job_dir: Job directory path
        variant_id: Variant identifier
        
    Returns:
        Path to variant directory (outputs/{variant_id}/)
    """
    return job_dir / "outputs" / variant_id


# =============================================================================
# SPLIT YAML FORMAT
# =============================================================================

COMPOSITION_BATCH_SIZE = 500  # Items per composition batch file


def write_variant_yaml(structure: dict, output_dir: Path) -> Path:
    """
    Write variant structure to split YAML files.
    
    Creates:
        outputs/{variant_id}/
        ├── variant.yaml      # Core config
        ├── wildcards.yaml    # Wildcard registry
        ├── segments.yaml     # Ext registry, prompts, configs
        └── composition/      # Batched composition data
            ├── c00000.yaml
            ├── c00500.yaml
            └── ...
    
    Args:
        structure: Variant structure dictionary
        output_dir: Directory to write YAML files (outputs/{variant_id}/)
        
    Returns:
        Path to output directory
    """
    import yaml
    
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Extract segments for splitting
    segments = structure.get('segments', {})
    composition = segments.get('composition', [])
    
    # 1. Write variant.yaml (core config, small)
    variant_data = {
        'variant_id': structure.get('variant_id'),
        'job_name': structure.get('job_name'),
        'job_config_hash': structure.get('job_config_hash'),
        'created_at': structure.get('created_at'),
        'total_images': structure.get('total_images'),
        'stacked_count': structure.get('stacked_count'),
        'filename_pattern': structure.get('filename_pattern'),
        'generation_context': structure.get('generation_context', {}),
        'config': structure.get('config', {}),
        'loras': structure.get('loras', {}),
        'lora_paths': structure.get('lora_paths', {}),
    }
    
    with open(output_dir / 'variant.yaml', 'w') as f:
        yaml.dump(variant_data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    # 2. Write wildcards.yaml
    wildcards_data = structure.get('wildcards', {})
    with open(output_dir / 'wildcards.yaml', 'w') as f:
        yaml.dump(wildcards_data, f, default_flow_style=False, allow_unicode=True)
    
    # 3. Write segments.yaml (without composition - that's split separately)
    segments_data = {
        'prompts': segments.get('prompts', []),
        'ext_registry': segments.get('ext_registry', {}),
        'wildcards': segments.get('wildcards', {}),
        'configs': segments.get('configs', []),
        'ext_text_delimiter': segments.get('ext_text_delimiter', ', '),
        'resolution': segments.get('resolution', {'width': 1024, 'height': 1024}),
    }
    
    # Add composition index
    num_batches = (len(composition) + COMPOSITION_BATCH_SIZE - 1) // COMPOSITION_BATCH_SIZE
    if num_batches > 0:
        segments_data['composition_files'] = [
            f"c{i * COMPOSITION_BATCH_SIZE:05d}.yaml" 
            for i in range(num_batches)
        ]
    segments_data['composition_count'] = len(composition)
    
    with open(output_dir / 'segments.yaml', 'w') as f:
        yaml.dump(segments_data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    # 4. Write composition batches
    comp_dir = output_dir / 'composition'
    comp_dir.mkdir(parents=True, exist_ok=True)
    
    for batch_idx in range(num_batches):
        start = batch_idx * COMPOSITION_BATCH_SIZE
        end = min(start + COMPOSITION_BATCH_SIZE, len(composition))
        
        batch_data = {
            'range': [start, end - 1],
            'items': composition[start:end]
        }
        
        batch_file = comp_dir / f"c{start:05d}.yaml"
        with open(batch_file, 'w') as f:
            yaml.dump(batch_data, f, default_flow_style=False, allow_unicode=True)
    
    return output_dir



def load_variant_yaml(variant_dir: Path, load_composition: bool = True) -> dict:
    """
    Load job structure from index.yaml (consolidated file).
    
    Args:
        variant_dir: Path to outputs directory (now contains index.yaml instead of variant.yaml)
        load_composition: Whether to load full composition (memory intensive)
        
    Returns:
        Complete job structure dictionary
    """
    import yaml
    
    variant_dir = Path(variant_dir)
    
    # Load consolidated index.yaml (replaces former variant.yaml)
    index_path = variant_dir / 'index.yaml'
    wildcards_path = variant_dir / 'wildcards.yaml'
    segments_path = variant_dir / 'segments.yaml'
    
    if not index_path.exists():
        raise FileNotFoundError(f"Index file not found: {index_path}")
    
    with open(index_path, 'r') as f:
        structure = yaml.safe_load(f) or {}
    
    # Load wildcards
    if wildcards_path.exists():
        with open(wildcards_path, 'r') as f:
            structure['wildcards'] = yaml.safe_load(f) or {}
    
    # Load segments
    if segments_path.exists():
        with open(segments_path, 'r') as f:
            segments = yaml.safe_load(f) or {}
            structure['segments'] = segments
    
    # Load composition if requested
    if load_composition:
        composition = []
        comp_files = structure.get('segments', {}).get('composition_files', [])
        comp_dir = variant_dir / 'composition'
        
        for comp_file in comp_files:
            comp_path = comp_dir / comp_file
            if comp_path.exists():
                with open(comp_path, 'r') as f:
                    batch = yaml.safe_load(f) or {}
                    composition.extend(batch.get('items', []))
        
        if 'segments' in structure:
            structure['segments']['composition'] = composition
    
    return structure


def load_composition_entry(variant_dir: Path, t_idx: int) -> dict:
    """
    Load a single composition entry by t index (lazy loading).
    
    Args:
        variant_dir: Path to variant directory
        t_idx: Text variation index
        
    Returns:
        Composition entry dict {ext: [...], wc: {...}}
    """
    import yaml
    
    batch_idx = t_idx // COMPOSITION_BATCH_SIZE
    local_idx = t_idx % COMPOSITION_BATCH_SIZE
    
    comp_file = variant_dir / 'composition' / f"c{batch_idx * COMPOSITION_BATCH_SIZE:05d}.yaml"
    
    if not comp_file.exists():
        return {'ext': [], 'wc': {}}
    
    with open(comp_file, 'r') as f:
        batch = yaml.safe_load(f) or {}
    
    items = batch.get('items', [])
    if local_idx < len(items):
        return items[local_idx]
    
    return {'ext': [], 'wc': {}}


def get_variant_yaml_path(job_dir: Path, variant_id: str = "default") -> Path:
    """
    Get the path to the variant YAML directory.
    
    Since consolidation, all variants share the same structure in outputs/.
    The variant_id parameter is kept for backwards compatibility but ignored.
    
    Args:
        job_dir: Job directory path
        variant_id: (Deprecated) Variant identifier - now ignored
        
    Returns:
        Path to outputs directory
    """
    return job_dir / "outputs"

