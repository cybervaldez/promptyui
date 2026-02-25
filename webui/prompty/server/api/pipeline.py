"""
Pipeline execution API — SSE streaming endpoint.

GET /api/pu/job/{job_id}/pipeline/run?prompt_id={prompt_id}
  Streams SSE events as TreeExecutor processes blocks.

GET /api/pu/job/{job_id}/pipeline/stop
  Stops the running executor at the next composition boundary.

Events streamed:
  block_start          { block_path }
  composition_complete { block_path, composition_idx, completed, total }
  block_complete       { block_path }
  block_failed         { block_path, error }
  block_blocked        { block_path }
  run_complete         { stats }
  error                { message }
"""

import json
import time
import threading
from pathlib import Path

# Active executor per job (single-user model — one executor at a time)
_active_executors = {}  # job_id -> TreeExecutor
_executor_lock = threading.Lock()


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def handle_pipeline_run(handler, job_id, prompt_id):
    """
    GET /api/pu/job/{job_id}/pipeline/run?prompt_id={prompt_id}

    Runs TreeExecutor for the specified job/prompt and streams SSE events.
    Uses test-fixtures hooks for now; production jobs can define their own.
    """
    import sys
    import yaml

    # Ensure project root is in sys.path for src.* imports
    project_root = get_project_root()
    root_str = str(project_root)
    if root_str not in sys.path:
        sys.path.insert(0, root_str)

    from src.jobs import build_jobs
    from src.hooks import HookPipeline, load_hooks_config, load_mods_config
    from src.tree_executor import TreeExecutor
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

    def send_event(event_type, data):
        """Write an SSE event to the response stream."""
        try:
            payload = json.dumps({'type': event_type, **data})
            handler.wfile.write(f"event: {event_type}\ndata: {payload}\n\n".encode('utf-8'))
            handler.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    try:
        # Load job config
        jobs_file = job_dir / "jobs.yaml"
        if not jobs_file.exists():
            send_event('error', {'message': f'jobs.yaml not found in {job_id}'})
            return

        with open(jobs_file) as f:
            task_conf = yaml.safe_load(f)

        # Load extensions (if any)
        from src.extensions import process_addons
        global_conf = {'ext': []}
        try:
            process_addons(job_dir, global_conf)
        except Exception:
            pass  # Extensions are optional

        # Load hooks and mods config
        hooks_config = load_hooks_config(job_dir)
        mods_config = load_mods_config(job_dir)
        pipeline = HookPipeline(job_dir, hooks_config, mods_config)

        # Build jobs with block paths
        defaults = task_conf.get('defaults', {})
        tree_jobs = build_jobs(
            task_conf, Path('/dev/null'), 0.1, ' ', global_conf,
            composition_id=defaults.get('composition', 0),
            wildcards_max=defaults.get('wildcards_max', 0),
            ext_text_max=defaults.get('ext_text_max', 0),
        )

        # Filter to requested prompt if specified
        if prompt_id:
            tree_jobs = [j for j in tree_jobs if j['prompt'].get('id') == prompt_id]

        if not tree_jobs:
            send_event('error', {'message': f'No jobs found for prompt {prompt_id}'})
            return

        # Send initial info
        paths = sorted(set(j['prompt'].get('_block_path', '0') for j in tree_jobs))
        send_event('init', {
            'job_id': job_id,
            'prompt_id': prompt_id,
            'total_jobs': len(tree_jobs),
            'block_paths': paths,
        })

        # Track per-stage timing
        stage_times = {}  # block_path -> {stage: [times]}
        current_stage_start = [None]  # mutable for closure

        # Progress callback — emits SSE events
        def on_progress(event_type, *args):
            if event_type == 'block_start':
                block_path = args[0]
                stage_times[block_path] = {}
                send_event('block_start', {'block_path': block_path})
            elif event_type == 'composition_complete':
                block_path, comp_idx = args[0], args[1]
                block = executor.blocks.get(block_path, {})
                send_event('composition_complete', {
                    'block_path': block_path,
                    'composition_idx': comp_idx,
                    'completed': executor.block_completed.get(block_path, 0),
                    'total': block.get('compositions', 0),
                    'global_completed': executor.completed_compositions,
                    'global_total': len(executor.queue),
                })
            elif event_type == 'block_complete':
                block_path = args[0]
                send_event('block_complete', {
                    'block_path': block_path,
                    'stage_times': stage_times.get(block_path, {}),
                })
            elif event_type == 'block_failed':
                block_path = args[0]
                error_msg = args[1] if len(args) > 1 else 'Unknown error'
                send_event('block_failed', {
                    'block_path': block_path,
                    'error': str(error_msg),
                })
            elif event_type == 'block_blocked':
                block_path = args[0]
                send_event('block_blocked', {'block_path': block_path})

        # Create and register executor
        executor = TreeExecutor(tree_jobs, pipeline, on_progress=on_progress)

        with _executor_lock:
            _active_executors[job_id] = executor

        # Wrap pipeline.execute_hook to capture per-stage timing
        original_execute_hook = pipeline.execute_hook

        def timed_execute_hook(hook_name, context):
            block_path = context.get('block_path', '?')
            start = time.time()
            result = original_execute_hook(hook_name, context)
            elapsed_ms = round((time.time() - start) * 1000, 1)

            if block_path in stage_times:
                if hook_name not in stage_times[block_path]:
                    stage_times[block_path][hook_name] = []
                stage_times[block_path][hook_name].append(elapsed_ms)

            # Send stage progress for running blocks
            send_event('stage', {
                'block_path': block_path,
                'stage': hook_name,
                'time_ms': elapsed_ms,
                'success': result.success,
            })
            return result

        pipeline.execute_hook = timed_execute_hook

        # Execute
        executor.execute()

        # Send final stats
        stats = executor.stats()
        send_event('run_complete', {'stats': stats})

    except Exception as e:
        send_event('error', {'message': str(e)})
    finally:
        with _executor_lock:
            _active_executors.pop(job_id, None)


def handle_pipeline_stop(handler, job_id):
    """
    GET /api/pu/job/{job_id}/pipeline/stop

    Stops the active executor for this job.
    """
    with _executor_lock:
        executor = _active_executors.get(job_id)

    if executor:
        executor.stop()
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
