"""
Operations API Handlers (Build Hook: value replacement)

Operations are a type of build hook — named YAML files that remap
wildcard values within a bucket window. Each operation produces a
distinct variant family.

GET  /api/pu/job/{job_id}/operations         - List operation names
GET  /api/pu/job/{job_id}/operation/{name}    - Load operation content
POST /api/pu/job/{job_id}/operation/{name}    - Save operation content
"""

import yaml
from pathlib import Path


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def _normalize_operation(raw):
    """
    Normalize operation YAML into standard mappings format.

    Supports two input formats:
    1. wildcards[].replace[].text/with (existing files)
    2. mappings.{wcName}.{original}: replacement (docs format)

    Returns: { name: str, mappings: { wcName: { original: replacement } } }
    """
    result = {
        'name': raw.get('id') or raw.get('name') or '',
        'mappings': {}
    }

    # Format 1: wildcards[].replace[]
    if 'wildcards' in raw and isinstance(raw['wildcards'], list):
        for wc in raw['wildcards']:
            wc_name = wc.get('name')
            if not wc_name:
                continue
            replacements = {}
            for r in wc.get('replace', []):
                original = r.get('text')
                replacement = r.get('with')
                if original is not None and replacement is not None:
                    replacements[str(original)] = str(replacement)
            if replacements:
                result['mappings'][wc_name] = replacements

    # Format 2: mappings dict
    elif 'mappings' in raw and isinstance(raw['mappings'], dict):
        for wc_name, mapping in raw['mappings'].items():
            if isinstance(mapping, dict):
                result['mappings'][wc_name] = {
                    str(k): str(v) for k, v in mapping.items()
                }

    return result


def _denormalize_operation(name, mappings):
    """
    Convert normalized mappings back to YAML-writable format (wildcards[].replace[]).
    """
    wildcards = []
    for wc_name, replacement_map in sorted(mappings.items()):
        replace_list = []
        for original, replacement in sorted(replacement_map.items()):
            replace_list.append({'text': original, 'with': replacement})
        wildcards.append({'name': wc_name, 'replace': replace_list})

    return {'wildcards': wildcards}


def handle_operations_list(handler, job_id):
    """
    GET /api/pu/job/{job_id}/operations

    List operation filenames for a job.

    Response: { "operations": ["role-replacements", "english-to-japan"] }
    """
    project_root = get_project_root()
    ops_dir = project_root / "jobs" / job_id / "operations"

    operations = []
    if ops_dir.exists() and ops_dir.is_dir():
        for f in sorted(ops_dir.iterdir()):
            if f.suffix == '.yaml' and f.is_file():
                operations.append(f.stem)

    handler.send_json({"operations": operations})


def handle_operation_get(handler, job_id, op_name):
    """
    GET /api/pu/job/{job_id}/operation/{name}

    Load and parse an operation YAML file, returning normalized mappings.

    Response: { "name": "role-replacements", "mappings": { "role": { "A": "B" } } }
    """
    project_root = get_project_root()
    op_file = project_root / "jobs" / job_id / "operations" / f"{op_name}.yaml"

    if not op_file.exists():
        handler.send_json({"error": f"Operation '{op_name}' not found"}, 404)
        return

    try:
        with open(op_file, 'r', encoding='utf-8') as f:
            raw = yaml.safe_load(f)

        if not raw:
            handler.send_json({"name": op_name, "mappings": {}})
            return

        result = _normalize_operation(raw)
        if not result['name']:
            result['name'] = op_name
        handler.send_json(result)

    except yaml.YAMLError as e:
        error_msg = str(e)
        if hasattr(e, 'problem_mark') and e.problem_mark:
            line = e.problem_mark.line + 1
            error_msg = f"YAML parse error at line {line}: {e.problem}"
        handler.send_json({"error": error_msg}, 400)
    except Exception as e:
        handler.send_json({"error": str(e)}, 500)


def handle_operation_save(handler, job_id, op_name, params):
    """
    POST /api/pu/job/{job_id}/operation/{name}

    Save operation mappings to YAML file.

    Request body: { "mappings": { "role": { "A": "B" } } }
    Response: { "saved": true, "name": "role-replacements" }
    """
    project_root = get_project_root()
    ops_dir = project_root / "jobs" / job_id / "operations"

    if not ops_dir.exists():
        ops_dir.mkdir(parents=True, exist_ok=True)

    op_file = ops_dir / f"{op_name}.yaml"
    mappings = params.get('mappings', {})

    try:
        data = _denormalize_operation(op_name, mappings)

        with open(op_file, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True)

        handler.send_json({"saved": True, "name": op_name})

    except Exception as e:
        handler.send_json({"error": str(e)}, 500)
