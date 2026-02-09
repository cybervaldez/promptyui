#!/usr/bin/env python3
"""
build-job.py - Generate Job Structure YAML

Generates the variant structure YAML from job/workflows configuration.
The structure contains all image permutations (prompts × wildcards × configs)
used by composition.py and bake.py.

Variant filtering is now handled by composition.py - this script builds ONE structure
for all variants to share.

USAGE:
    python build-job.py <job_name>                 # Generate outputs/
    python build-job.py <job_name> --list          # List available variants
    python build-job.py <job_name> --force         # Force rebuild

Output:
    Writes YAML to: jobs/<job_name>/outputs/<variant>/
"""

import os
import sys
import argparse
from pathlib import Path
from datetime import datetime

# Import from src/ package
from src.config import load_yaml, compute_job_hash
from src.extensions import process_addons, load_and_apply_operations
from src.variant import build_variant_structure, write_variant_yaml, load_variant_yaml


def main():
    """
    Main entry point for variant structure generation.
    """
    parser = argparse.ArgumentParser(description="Generate job structure for WebUI")
    parser.add_argument("job", type=str, help="Name of the job folder (e.g., 'andrea-fashion')")
    parser.add_argument("--list", action="store_true", help="List available variants")
    parser.add_argument("--force", action="store_true", help="Overwrite existing structure files")
    parser.add_argument("--composition", "-c", type=int, default=None,
                        help="Composition ID for seeding wildcard selection (default: 42 for backwards compat)")
    args = parser.parse_args()

    root_dir = Path.cwd()
    job_dir = root_dir / "jobs" / args.job
    job_config_path = job_dir / "jobs.yaml"
    
    if not job_config_path.exists():
        sys.exit(f"❌ Job config not found: {job_config_path}")
    
    # List mode
    if args.list:
        variants_dir = job_dir / "variants"
        print(f"\n📂 Job: {args.job}")
        print(f"   Variants directory: {variants_dir}")
        
        if variants_dir.exists():
            variants = list(variants_dir.glob("*.yaml"))
            if variants:
                print(f"   Available variants:")
                for v in variants:
                    print(f"     - {v.stem}")
            else:
                print(f"   No variant files found")
        else:
            print(f"   Variants directory doesn't exist")
        
        # Check existing built variants
        outputs_dir = job_dir / "outputs"
        if outputs_dir.exists():
            built = [d for d in outputs_dir.iterdir() if d.is_dir() and (d / 'variant.yaml').exists()]
            if built:
                print(f"\n   Built variant structures:")
                for b in built:
                    print(f"     - {b.name}/")
        return
    
    print(f"\n📂 Loading job: {args.job}")
    
    # Load configurations
    global_conf = load_yaml(root_dir / "config.yaml")
    job_conf = load_yaml(job_config_path)
    
    # =========================================================================
    # EXTENSION LOADING
    # =========================================================================
    
    job_defaults = job_conf.get('defaults', {})
    if isinstance(job_defaults, list):
        job_defaults = job_defaults[0] if job_defaults else {}
    default_ext = job_defaults.get('ext', 'defaults')
    ext_text_max = job_defaults.get('ext_text_max', 1)
    ext_wildcards_max = job_defaults.get('ext_wildcards_max', 0)
    
    # Auto-load extensions from /ext/{ext}/ folder
    ext_dir = root_dir / "ext" / default_ext
    if ext_dir.exists():
        loaded_extensions = []
        for ext_file in sorted(ext_dir.glob("*.yaml")):
            try:
                ext_data = load_yaml(ext_file)
                if ext_data and 'id' in ext_data:
                    ext_data['_ext'] = default_ext
                    loaded_extensions.append(ext_data)
                    print(f"   📦 Loaded extension: {ext_data['id']}")
            except Exception as e:
                print(f"   ⚠️  Failed to load {ext_file.name}: {e}")
        
        if loaded_extensions:
            if 'ext' not in global_conf:
                global_conf['ext'] = []
            global_conf['ext'] = loaded_extensions + global_conf.get('ext', [])
    
    # Process per-prompt ext overrides
    prompts_with_ext_override = [p for p in job_conf.get('prompts', []) if 'ext' in p]
    loaded_exts = {default_ext}
    
    for prompt in prompts_with_ext_override:
        prompt_ext = prompt['ext']
        if prompt_ext not in loaded_exts:
            prompt_ext_dir = root_dir / "ext" / prompt_ext
            if prompt_ext_dir.exists():
                for ext_file in sorted(prompt_ext_dir.glob("*.yaml")):
                    try:
                        ext_data = load_yaml(ext_file)
                        if ext_data and 'id' in ext_data:
                            ext_data['_ext'] = prompt_ext
                            already_loaded = any(
                                e.get('id') == ext_data['id'] and e.get('_ext') == prompt_ext
                                for e in global_conf.get('ext', [])
                            )
                            if not already_loaded:
                                global_conf['ext'].append(ext_data)
                    except Exception:
                        pass
                loaded_exts.add(prompt_ext)
    
    # Process addons
    process_addons(job_dir, global_conf)
    
    # Compute common parameters used by all variants
    # Sampler config
    samplers_config = None
    if 'model' in job_conf and 'sampler' in job_conf['model']:
        samplers_config = job_conf['model']['sampler']
    if samplers_config is None:
        samplers_config = job_defaults.get('sampler')
    
    # Other params
    range_increment = float(job_defaults.get('range_increment', 0.1))
    prompts_delimiter = job_defaults.get('prompts_delimiter', ' ')
    trigger_delimiter = job_defaults.get('trigger_delimiter', ', ')
    ext_text_delimiter = job_defaults.get('ext_text_delimiter', ', ')
    
    # Build single structure (variants are applied at composition time, not here)
    # No variant operations needed - composition.py handles variant filtering
    build_variant(job_dir, job_conf, global_conf, args, root_dir, job_defaults, ext_wildcards_max, ext_text_max, default_ext, samplers_config, range_increment, prompts_delimiter, trigger_delimiter, ext_text_delimiter)


def build_variant(job_dir, job_conf, global_conf, args, root_dir, job_defaults, ext_wildcards_max, ext_text_max, default_ext, samplers_config, range_increment, prompts_delimiter, trigger_delimiter, ext_text_delimiter):
    """Build job structure - single output, variants handled at composition time."""
    
    # =========================================================================
    # RESOLVE LORA PATH
    # =========================================================================
    
    model_lora_path = job_conf.get('model', {}).get('lora_path')
    if model_lora_path is None:
        lora_root = root_dir / "loras" / job_conf.get('model', {}).get('name', 'unknown')
    else:
        p = Path(model_lora_path)
        lora_root = p if p.is_absolute() else (job_dir / p).resolve()
    
    print(f"   📂 LoRA Root: {lora_root}")
    
    # =========================================================================
    # GET DEFAULT PARAMETERS
    # =========================================================================
    
    # Try to load model config for defaults
    models_yaml_path = root_dir / "models.yaml"
    model_defaults = {}
    if models_yaml_path.exists():
        try:
            from models import ModelRegistry
            model_registry = ModelRegistry(models_yaml_path)
            model_name = job_conf.get('model', {}).get('name', '')
            if model_name:
                model_config = model_registry.get(model_name)
                model_defaults = model_config.get_defaults()
        except Exception as e:
            print(f"   ⚠️  Warning: Could not load model defaults: {e}")
    
    def_width = job_defaults.get('width') or model_defaults.get('width', 1024)
    def_height = job_defaults.get('height') or model_defaults.get('height', 1024)
    def_steps = job_defaults.get('steps') or model_defaults.get('steps', 9)
    def_cfg = job_defaults.get('cfg') or model_defaults.get('cfg', 1.0)
    
    default_params = {
        'width': int(def_width),
        'height': int(def_height),
        'steps': int(def_steps),
        'cfg': float(def_cfg)
    }
    
    # Note: samplers_config, range_increment, prompts_delimiter, trigger_delimiter, ext_text_delimiter
    # are passed as parameters from main()
    
    # =========================================================================
    # BUILD VARIANT STRUCTURE
    # =========================================================================
    
    print(f"\n📋 Building job structure for: {args.job}")
    
    structure = build_variant_structure(
        job_conf=job_conf,
        global_conf=global_conf,
        lora_root=lora_root,
        variant_id='default',  # Always build base structure
        job_name=args.job,
        job_dir=job_dir,
        default_params=default_params,
        ext_wildcards_max=ext_wildcards_max,
        ext_text_max=ext_text_max,
        default_ext=default_ext,
        samplers_config=samplers_config,
        range_increment=range_increment,
        prompts_delimiter=prompts_delimiter,
        trigger_delimiter=trigger_delimiter,
        ext_text_delimiter=ext_text_delimiter,
        composition_id=args.composition
    )
    
    # =========================================================================
    # WRITE OUTPUT
    # =========================================================================
    
    
    output_dir = job_dir / "outputs"
    index_yaml_path = output_dir / "index.yaml"
    
    # Always update outputs/index.yaml
    update_outputs_index(job_dir, args.job, structure)
    
    # Always rebuild (fast operation)
    print(f"\n📋 Building job structure...")

    output_dir = write_variant_yaml(structure, output_dir)
    
    print(f"\n✅ Created: {output_dir}/")
    print(f"   📊 Total images: {structure['total_images']}")
    print(f"   📂 Stacked count: {structure['stacked_count']}")
    print(f"   🔗 Hash: {structure['job_config_hash'][:16]}...")
    
    # Show composition file count
    comp_dir = output_dir / 'composition'
    if comp_dir.exists():
        comp_files = list(comp_dir.glob('c*.yaml'))
        print(f"   📁 {len(comp_files)} composition batch files")


def update_outputs_index(job_dir: Path, job_name: str, structure: dict):
    """
    Create/update outputs/index.yaml with complete job structure for WebUI.
    
    Consolidates former variant.yaml content into single index.yaml file.
    """
    import yaml
    from datetime import datetime
    
    index_path = job_dir / 'outputs' / 'index.yaml'
    
    # Build prompts summary with counts
    prompts_summary = []
    for p in structure.get('prompts', []):
        prompts_summary.append({
            'id': p.get('id', 'unknown'),
            'count': p.get('_image_count', 0)
        })
    
    # Detect available variants from variants/ folder
    variants_dir = job_dir / 'variants'
    variants = [{'id': 'default', 'affected_wildcards': []}]
    if variants_dir.exists():
        for vf in sorted(variants_dir.glob('*.yaml')):
            variant_id = vf.stem
            if variant_id != 'default':
                # Parse affected wildcards from variant file
                try:
                    with open(vf, 'r') as f:
                        vdata = yaml.safe_load(f) or {}
                    affected = [wc.get('name') for wc in vdata.get('wildcards', []) 
                               if isinstance(wc, dict) and 'name' in wc]
                    variants.append({'id': variant_id, 'affected_wildcards': affected})
                except:
                    variants.append({'id': variant_id, 'affected_wildcards': []})
    
    # Load existing compositions (preserve if exist)
    compositions = []
    if index_path.exists():
        with open(index_path, 'r') as f:
            existing = yaml.safe_load(f) or {}
        compositions = existing.get('compositions', [])
    
    # Consolidated data (former variant.yaml + index.yaml)
    data = {
        # Job Metadata
        'job_name': job_name,
        'job_config_hash': structure.get('job_config_hash', ''),
        'total_images': structure.get('total_images', 0),
        'stacked_count': structure.get('stacked_count', 0),
        'created_at': structure.get('created_at', datetime.now().isoformat()),
        'updated_at': datetime.now().isoformat(),
        
        # Generation Config (from variant.yaml)
        'filename_pattern': structure.get('filename_pattern', ''),
        'generation_context': structure.get('generation_context', {}),
        
        # LoRAs (from variant.yaml)
        'loras': structure.get('loras', {}),
        'lora_paths': structure.get('lora_paths', {}),
        
        # Generation Params (from variant.yaml)
        'config': structure.get('config', {}),
        
        # WebUI Data
        'prompts': prompts_summary,
        'variants': variants,
        'compositions': compositions,
    }
    
    # Ensure output dir exists
    index_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(index_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)
    
    print(f"   📋 Updated: outputs/index.yaml")



if __name__ == "__main__":
    main()
