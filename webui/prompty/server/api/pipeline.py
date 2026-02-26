"""
Pipeline execution API — SSE streaming endpoint.

GET /api/pu/job/{job_id}/pipeline/run?prompt_id={prompt_id}
  Streams SSE events as TreeExecutor processes blocks via EventStream.

GET /api/pu/job/{job_id}/pipeline/stop
  Stops the running executor at the next composition boundary.

Events streamed (canonical, from EventStream):
  init               { job_id, prompt_id, total_jobs, block_paths }
  block_start        { block_path }
  stage              { block_path, stage, time_ms, success }
  composition_complete { block_path, composition_idx, completed, total }
  artifact           { block_path, composition_idx, artifact }
  artifact_consumed  { consuming_block, source_block, artifact_count }
  block_complete     { block_path, stage_times, artifacts_count }
  block_failed       { block_path, error }
  block_blocked      { block_path }
  run_complete       { stats }
  error              { message }
"""

import json
import threading
from pathlib import Path

# Active streams per job (single-user model — one executor at a time)
_active_streams = {}  # job_id -> EventStream
_stream_lock = threading.Lock()


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def handle_pipeline_run(handler, job_id, prompt_id):
    """
    GET /api/pu/job/{job_id}/pipeline/run?prompt_id={prompt_id}

    Runs EventStream for the specified job/prompt and bridges events to SSE.
    """
    import sys

    # Ensure project root is in sys.path for src.* imports
    project_root = get_project_root()
    root_str = str(project_root)
    if root_str not in sys.path:
        sys.path.insert(0, root_str)

    from src.pipeline_runner import create_run
    from src.event_stream import EventStream

    job_dir = project_root / "jobs" / job_id

    if not job_dir.exists():
        handler.send_response(404)
        handler.send_header('Content-Type', 'application/json')
        handler.end_headers()
        handler.wfile.write(json.dumps({'error': f'Job {job_id} not found'}).encode())
        return

    # Setup SSE headers
    handler.send_response(200)
    handler.send_header('Content-Type', 'text/event-stream')
    handler.send_header('Cache-Control', 'no-cache, no-store')
    handler.send_header('Access-Control-Allow-Origin', '*')
    handler.send_header('Connection', 'keep-alive')
    handler.end_headers()

    def send_sse(event):
        """Bridge EventStream event to SSE wire format."""
        try:
            event_type = event['type']
            payload = json.dumps({'type': event_type, **event['data']})
            handler.wfile.write(f"event: {event_type}\ndata: {payload}\n\n".encode('utf-8'))
            handler.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    try:
        pipeline, tree_jobs, meta = create_run(job_dir, prompt_id=prompt_id)
    except FileNotFoundError as e:
        send_sse({'type': 'error', 'data': {'message': str(e)}, 'ts': 0})
        return
    except ValueError as e:
        send_sse({'type': 'error', 'data': {'message': str(e)}, 'ts': 0})
        return

    try:
        stream = EventStream(pipeline, tree_jobs, meta,
                             output_path=str(job_dir), with_stage_timing=True)
        stream.on_event = send_sse

        with _stream_lock:
            _active_streams[job_id] = stream

        stream.run()

    except Exception as e:
        send_sse({'type': 'error', 'data': {'message': str(e)}, 'ts': 0})
    finally:
        with _stream_lock:
            _active_streams.pop(job_id, None)


def handle_pipeline_stop(handler, job_id):
    """
    GET /api/pu/job/{job_id}/pipeline/stop

    Stops the active EventStream for this job.
    """
    with _stream_lock:
        stream = _active_streams.get(job_id)

    if stream:
        stream.stop()
        handler.send_response(200)
        handler.send_header('Content-Type', 'application/json')
        handler.send_header('Access-Control-Allow-Origin', '*')
        handler.end_headers()
        handler.wfile.write(json.dumps({'status': 'stopping'}).encode())
    else:
        handler.send_response(404)
        handler.send_header('Content-Type', 'application/json')
        handler.send_header('Access-Control-Allow-Origin', '*')
        handler.end_headers()
        handler.wfile.write(json.dumps({'error': 'No active executor'}).encode())
