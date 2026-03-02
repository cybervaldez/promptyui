"""
Session API Handlers

Endpoints for reading and writing session.yaml — UI navigation state
persisted as a sidecar file alongside jobs.yaml.

GET  /api/pu/job/{job_id}/session    - Read session state
POST /api/pu/job/{job_id}/session    - Write session state
"""

import yaml
from pathlib import Path


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def handle_session_get(handler, job_id):
    """
    GET /api/pu/job/{job_id}/session

    Read session.yaml for a job. Returns empty prompts dict if file doesn't exist.

    Response: { "prompts": { "prompt-id": { "composition": 99, ... } } }
    """
    project_root = get_project_root()
    session_file = project_root / "jobs" / job_id / "session.yaml"

    if not session_file.exists():
        handler.send_json({"prompts": {}})
        return

    try:
        with open(session_file, 'r', encoding='utf-8') as f:
            raw = yaml.safe_load(f)

        if not raw or not isinstance(raw, dict):
            handler.send_json({"prompts": {}})
            return

        prompts = raw.get('prompts', {})
        if not isinstance(prompts, dict):
            prompts = {}

        handler.send_json({"prompts": prompts})

    except yaml.YAMLError as e:
        error_msg = str(e)
        if hasattr(e, 'problem_mark') and e.problem_mark:
            line = e.problem_mark.line + 1
            error_msg = f"YAML parse error at line {line}: {e.problem}"
        handler.send_json({"error": error_msg}, 400)
    except Exception as e:
        handler.send_json({"error": str(e)}, 500)


def handle_session_save(handler, job_id, params):
    """
    POST /api/pu/job/{job_id}/session

    Save session state for a specific prompt. Merges with existing session data.

    Request body: { "prompt_id": "stress-test-prompt", "data": { "composition": 99, ... } }
    Response: { "saved": true }
    """
    prompt_id = params.get('prompt_id')
    data = params.get('data')

    if not prompt_id:
        handler.send_json({"error": "prompt_id is required"}, 400)
        return
    if not isinstance(data, dict):
        handler.send_json({"error": "data must be an object"}, 400)
        return

    project_root = get_project_root()
    job_dir = project_root / "jobs" / job_id

    if not job_dir.exists():
        handler.send_json({"error": f"Job '{job_id}' not found"}, 404)
        return

    session_file = job_dir / "session.yaml"

    try:
        # Load existing session (merge)
        existing = {}
        if session_file.exists():
            with open(session_file, 'r', encoding='utf-8') as f:
                raw = yaml.safe_load(f)
            if isinstance(raw, dict):
                existing = raw

        if 'prompts' not in existing or not isinstance(existing['prompts'], dict):
            existing['prompts'] = {}

        # Sanitize the data — only allow known fields
        clean_data = {}
        if 'composition' in data and isinstance(data['composition'], (int, float)):
            clean_data['composition'] = int(data['composition'])
        if 'locked_values' in data and isinstance(data['locked_values'], dict):
            clean_data['locked_values'] = data['locked_values']
        if 'active_operation' in data:
            if data['active_operation'] is None or isinstance(data['active_operation'], str):
                clean_data['active_operation'] = data['active_operation']
        if 'shortlist' in data and isinstance(data['shortlist'], list):
            clean_shortlist = []
            for item in data['shortlist']:
                if isinstance(item, dict) and 'text' in item and 'sources' in item:
                    clean_item = {
                        'text': str(item['text']),
                        'sources': []
                    }
                    if isinstance(item['sources'], list):
                        for src in item['sources']:
                            if isinstance(src, dict) and 'block' in src:
                                clean_item['sources'].append({
                                    'block': str(src['block']),
                                    'combo': str(src.get('combo', ''))
                                })
                    clean_shortlist.append(clean_item)
            clean_data['shortlist'] = clean_shortlist

        existing['prompts'][prompt_id] = clean_data

        # Write
        with open(session_file, 'w', encoding='utf-8') as f:
            yaml.dump(existing, f, default_flow_style=False, allow_unicode=True)

        handler.send_json({"saved": True})

    except Exception as e:
        handler.send_json({"error": str(e)}, 500)
