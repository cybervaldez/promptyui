"""
Export API Handlers

Endpoints for exporting and validating job configurations.

POST /api/pu/export - Export job to jobs.yaml
POST /api/pu/validate - Validate job configuration
"""

import yaml
import re
from pathlib import Path
from datetime import datetime


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


class IndentedDumper(yaml.SafeDumper):
    """Custom YAML dumper with better formatting."""
    pass


def str_representer(dumper, data):
    """Handle multi-line strings with literal block style."""
    if '\n' in data:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)


IndentedDumper.add_representer(str, str_representer)


def job_to_yaml(job_data):
    """
    Convert job data to YAML string with nice formatting.
    """
    # Remove internal fields
    clean_data = {}
    for key, value in job_data.items():
        if not key.startswith('_') and key not in ['job_id', 'valid']:
            clean_data[key] = value

    # Order keys nicely
    ordered_keys = ['defaults', 'model', 'loras', 'prompts']
    ordered_data = {}

    for key in ordered_keys:
        if key in clean_data:
            ordered_data[key] = clean_data[key]

    # Add remaining keys
    for key in clean_data:
        if key not in ordered_keys:
            ordered_data[key] = clean_data[key]

    return yaml.dump(
        ordered_data,
        Dumper=IndentedDumper,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
        width=120
    )


def validate_job(job_data, ext_dir):
    """
    Validate job configuration.

    Returns:
        (is_valid, warnings, errors)
    """
    warnings = []
    errors = []

    # Check required sections
    if 'prompts' not in job_data:
        errors.append("Missing 'prompts' section")
    elif not job_data['prompts']:
        warnings.append("No prompts defined")

    # Check prompts have IDs
    prompts = job_data.get('prompts', [])
    seen_ids = set()
    for i, p in enumerate(prompts):
        if not isinstance(p, dict):
            errors.append(f"Prompt at index {i} is not a dict")
            continue

        pid = p.get('id')
        if not pid:
            errors.append(f"Prompt at index {i} missing 'id'")
        elif pid in seen_ids:
            errors.append(f"Duplicate prompt id: '{pid}'")
        else:
            seen_ids.add(pid)

        # Check for text content
        text = p.get('text')
        if not text:
            warnings.append(f"Prompt '{pid or i}' has no text content")

        # Validate wildcard references
        if text:
            wildcards_defined = {wc.get('name') for wc in p.get('wildcards', []) if isinstance(wc, dict)}

            def find_wildcards_in_items(items):
                found = set()
                if isinstance(items, str):
                    found.update(re.findall(r'__([a-zA-Z0-9_-]+)__', items))
                elif isinstance(items, list):
                    for item in items:
                        if isinstance(item, dict):
                            if 'content' in item:
                                found.update(re.findall(r'__([a-zA-Z0-9_-]+)__', item['content']))
                            if 'after' in item:
                                found.update(find_wildcards_in_items(item['after']))
                        elif isinstance(item, str):
                            found.update(re.findall(r'__([a-zA-Z0-9_-]+)__', item))
                return found

            used_wildcards = find_wildcards_in_items(text)
            undefined = used_wildcards - wildcards_defined

            # Check if undefined wildcards might come from extensions
            # This is a soft warning since ext_text can provide wildcards
            if undefined:
                warnings.append(f"Prompt '{pid}': Wildcards may be undefined (or from ext): {', '.join(undefined)}")

        # Validate ext_text references
        def find_ext_text_refs(items):
            refs = set()
            if isinstance(items, list):
                for item in items:
                    if isinstance(item, dict):
                        if 'ext_text' in item:
                            refs.add(item['ext_text'])
                        if 'after' in item:
                            refs.update(find_ext_text_refs(item['after']))
            return refs

        ext_refs = find_ext_text_refs(text) if isinstance(text, list) else set()

        if ext_refs and ext_dir:
            ext_folder = p.get('ext') or job_data.get('defaults', {}).get('ext', 'defaults')
            ext_path = ext_dir / ext_folder

            for ref in ext_refs:
                ref_file = ext_path / f"{ref}.yaml"
                if not ref_file.exists():
                    warnings.append(f"Prompt '{pid}': ext_text '{ref}' not found in ext/{ext_folder}/")

    # Check LoRA definitions
    loras = job_data.get('loras', [])
    lora_aliases = set()
    for l in loras:
        if isinstance(l, dict):
            alias = l.get('alias')
            if alias:
                lora_aliases.add(alias)

    # Check LoRA references in prompts
    for p in prompts:
        if not isinstance(p, dict):
            continue

        prompt_loras = p.get('loras', [])
        for lora_str in prompt_loras:
            if isinstance(lora_str, str):
                # Parse LoRA string (e.g., "pixel_aziib:0.8+real1:0.5")
                parts = lora_str.replace('+', ' ').split()
                for part in parts:
                    alias = part.split(':')[0]
                    if alias not in lora_aliases and alias != 'off':
                        warnings.append(f"Prompt '{p.get('id')}': LoRA alias '{alias}' not defined in loras section")

    is_valid = len(errors) == 0
    return is_valid, warnings, errors


def handle_validate(handler, params):
    """
    POST /api/pu/validate

    Validate job configuration.

    Request:
    {
        "job_id": "pixel-fantasy"
    }
    or
    {
        "job_data": {...}  # Full job data to validate
    }

    Response:
    {
        "valid": true,
        "warnings": [],
        "errors": []
    }
    """
    project_root = get_project_root()
    ext_dir = project_root / "ext"

    job_id = params.get('job_id')
    job_data = params.get('job_data')

    if job_id and not job_data:
        # Load from file
        jobs_yaml = project_root / "jobs" / job_id / "jobs.yaml"
        if not jobs_yaml.exists():
            handler.send_json({
                "valid": False,
                "warnings": [],
                "errors": [f"Job '{job_id}' not found"]
            })
            return

        try:
            with open(jobs_yaml, 'r') as f:
                job_data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            handler.send_json({
                "valid": False,
                "warnings": [],
                "errors": [f"YAML parse error: {e}"]
            })
            return

    if not job_data:
        handler.send_json({
            "valid": False,
            "warnings": [],
            "errors": ["No job data provided"]
        })
        return

    is_valid, warnings, errors = validate_job(job_data, ext_dir)

    handler.send_json({
        "valid": is_valid,
        "warnings": warnings,
        "errors": errors
    })


def handle_export(handler, params):
    """
    POST /api/pu/export

    Export job to jobs.yaml.

    Request:
    {
        "job_id": "pixel-fantasy",
        "job_data": {...},  # Optional: modified job data
        "dry_run": true,    # Optional: just return YAML without saving
        "save_to_file": true  # Optional: save to jobs/{job_id}/jobs.yaml
    }

    Response:
    {
        "success": true,
        "yaml": "...",
        "path": "jobs/pixel-fantasy/jobs.yaml"
    }
    """
    project_root = get_project_root()

    job_id = params.get('job_id')
    job_data = params.get('job_data')
    dry_run = params.get('dry_run', False)
    save_to_file = params.get('save_to_file', False)

    if not job_id:
        handler.send_json({
            "success": False,
            "error": "job_id required"
        }, 400)
        return

    # Load existing if no job_data provided
    if not job_data:
        jobs_yaml = project_root / "jobs" / job_id / "jobs.yaml"
        if jobs_yaml.exists():
            try:
                with open(jobs_yaml, 'r') as f:
                    job_data = yaml.safe_load(f)
            except Exception as e:
                handler.send_json({
                    "success": False,
                    "error": f"Failed to load job: {e}"
                }, 500)
                return
        else:
            handler.send_json({
                "success": False,
                "error": f"Job '{job_id}' not found"
            }, 404)
            return

    # Generate YAML
    yaml_content = job_to_yaml(job_data)

    response = {
        "success": True,
        "yaml": yaml_content
    }

    # Save to file if requested and not dry run
    if save_to_file and not dry_run:
        jobs_dir = project_root / "jobs" / job_id
        jobs_dir.mkdir(parents=True, exist_ok=True)

        jobs_yaml = jobs_dir / "jobs.yaml"

        # Create backup if file exists
        if jobs_yaml.exists():
            backup_name = f"jobs.yaml.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            backup_path = jobs_dir / backup_name
            jobs_yaml.rename(backup_path)
            response["backup"] = str(backup_path.relative_to(project_root))

        # Write new file
        with open(jobs_yaml, 'w') as f:
            f.write(yaml_content)

        response["path"] = str(jobs_yaml.relative_to(project_root))

    handler.send_json(response)
