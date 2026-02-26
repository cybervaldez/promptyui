"""
Artifacts API — serve artifact manifest and files.

GET /api/pu/job/{job_id}/artifacts                    → manifest.json contents
GET /api/pu/job/{job_id}/artifacts/{mod_id}/{filename} → artifact file or JSONL line

JSONL support:
  For .jsonl files, pass ?line=N to extract a single line (0-indexed).
  Without ?line, the entire JSONL file is served as application/x-ndjson.
"""

import json
from pathlib import Path


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def handle_artifacts_list(handler, job_id):
    """Return manifest.json contents for a job's artifacts."""
    project_root = get_project_root()
    manifest_path = project_root / "jobs" / job_id / "_artifacts" / "manifest.json"

    if not manifest_path.exists():
        handler.send_json({'artifacts': {}, 'message': 'No artifacts found'})
        return

    try:
        manifest = json.loads(manifest_path.read_text())
        handler.send_json(manifest)
    except Exception as e:
        handler.send_json({'error': str(e)}, 500)


def handle_artifact_file(handler, job_id, mod_id, filename):
    """Serve an artifact file — supports JSONL line extraction via ?line=N."""
    import urllib.parse

    project_root = get_project_root()
    artifact_path = project_root / "jobs" / job_id / "_artifacts" / mod_id / filename

    if not artifact_path.exists():
        handler.send_json({'error': 'Artifact not found'}, 404)
        return

    # Parse query params for JSONL line extraction
    parsed = urllib.parse.urlparse(handler.path)
    params = dict(urllib.parse.parse_qsl(parsed.query))
    line_num = params.get('line')

    # JSONL line extraction
    if artifact_path.suffix == '.jsonl' and line_num is not None:
        try:
            line_idx = int(line_num)
            lines = artifact_path.read_text().strip().split('\n')
            if 0 <= line_idx < len(lines):
                data = lines[line_idx].encode('utf-8')
                handler.send_response(200)
                handler.send_header('Content-Type', 'application/json')
                handler.send_header('Content-Length', len(data))
                handler.send_header('Access-Control-Allow-Origin', '*')
                handler.end_headers()
                handler.wfile.write(data)
            else:
                handler.send_json({'error': f'Line {line_idx} out of range (0-{len(lines)-1})'}, 404)
        except ValueError:
            handler.send_json({'error': f'Invalid line number: {line_num}'}, 400)
        except Exception as e:
            handler.send_json({'error': str(e)}, 500)
        return

    # Determine content type
    suffix = artifact_path.suffix.lower()
    content_types = {
        '.json': 'application/json',
        '.jsonl': 'application/x-ndjson',
        '.txt': 'text/plain',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.gif': 'image/gif',
        '.svg': 'image/svg+xml',
        '.csv': 'text/csv',
    }
    content_type = content_types.get(suffix, 'application/octet-stream')

    try:
        data = artifact_path.read_bytes()
        handler.send_response(200)
        handler.send_header('Content-Type', content_type)
        handler.send_header('Content-Length', len(data))
        handler.send_header('Access-Control-Allow-Origin', '*')
        handler.end_headers()
        handler.wfile.write(data)
    except (BrokenPipeError, ConnectionResetError):
        pass
    except Exception as e:
        handler.send_json({'error': str(e)}, 500)
