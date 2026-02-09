"""
Jobs API Handlers

Endpoints for listing and retrieving job configurations.

GET /api/pu/jobs - List all jobs from jobs/ folder
GET /api/pu/job/{job_id} - Get single job's parsed jobs.yaml
"""

import yaml
from pathlib import Path


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def handle_jobs_list(handler, params):
    """
    GET /api/pu/jobs

    List all jobs from jobs/ folder with validation status.

    Response:
    {
        "jobs": {
            "pixel-fantasy": {
                "valid": true,
                "prompts": ["pixel-solo-variations", "pixel-wildcards", ...],
                "loras": ["pixel_aziib", "pixel_art", ...],
                "defaults": {...}
            },
            "broken-job": {
                "valid": false,
                "error": "YAML parse error at line 15"
            }
        }
    }
    """
    project_root = get_project_root()
    jobs_dir = project_root / "jobs"

    result = {"jobs": {}}

    if not jobs_dir.exists():
        handler.send_json(result)
        return

    # Scan all job directories
    for job_dir in sorted(jobs_dir.iterdir()):
        if not job_dir.is_dir():
            continue

        job_id = job_dir.name
        jobs_yaml = job_dir / "jobs.yaml"

        if not jobs_yaml.exists():
            result["jobs"][job_id] = {
                "valid": False,
                "error": "jobs.yaml not found"
            }
            continue

        try:
            with open(jobs_yaml, 'r') as f:
                job_data = yaml.safe_load(f)

            if not job_data:
                result["jobs"][job_id] = {
                    "valid": False,
                    "error": "jobs.yaml is empty"
                }
                continue

            # Extract summary information
            prompts = []
            for p in job_data.get('prompts', []):
                if isinstance(p, dict) and 'id' in p:
                    prompts.append(p['id'])

            loras = []
            for l in job_data.get('loras', []):
                if isinstance(l, dict) and 'alias' in l:
                    loras.append(l['alias'])

            defaults = job_data.get('defaults', {})

            result["jobs"][job_id] = {
                "valid": True,
                "prompts": prompts,
                "loras": loras,
                "defaults": defaults
            }

        except yaml.YAMLError as e:
            # Extract line number from YAML error if available
            error_msg = str(e)
            if hasattr(e, 'problem_mark') and e.problem_mark:
                line = e.problem_mark.line + 1
                error_msg = f"YAML parse error at line {line}: {e.problem}"
            result["jobs"][job_id] = {
                "valid": False,
                "error": error_msg
            }
        except Exception as e:
            result["jobs"][job_id] = {
                "valid": False,
                "error": str(e)
            }

    handler.send_json(result)


def handle_job_get(handler, job_id, params):
    """
    GET /api/pu/job/{job_id}

    Get full job configuration (parsed jobs.yaml).

    Response:
    {
        "valid": true,
        "defaults": {...},
        "prompts": [...],
        "loras": [...],
        "model": {...}
    }
    or
    {
        "valid": false,
        "error": "error message"
    }
    """
    project_root = get_project_root()
    jobs_yaml = project_root / "jobs" / job_id / "jobs.yaml"

    if not jobs_yaml.exists():
        handler.send_json({
            "valid": False,
            "error": f"Job '{job_id}' not found"
        }, 404)
        return

    try:
        with open(jobs_yaml, 'r') as f:
            job_data = yaml.safe_load(f)

        if not job_data:
            handler.send_json({
                "valid": False,
                "error": "jobs.yaml is empty"
            }, 400)
            return

        # Add job_id to response
        job_data["job_id"] = job_id
        job_data["valid"] = True

        handler.send_json(job_data)

    except yaml.YAMLError as e:
        error_msg = str(e)
        if hasattr(e, 'problem_mark') and e.problem_mark:
            line = e.problem_mark.line + 1
            error_msg = f"YAML parse error at line {line}: {e.problem}"
        handler.send_json({
            "valid": False,
            "error": error_msg
        }, 400)
    except Exception as e:
        handler.send_json({
            "valid": False,
            "error": str(e)
        }, 500)
