"""
EventStream — canonical event producer for pipeline execution.

Wraps TreeExecutor + lifecycle events (init, stage, run_complete, error).
Both CLI and WebUI are thin consumers of this stream:

    CLI:   stream.on_event = lambda e: print(TAG_MAP[e['type']](e['data']))
    WebUI: stream.on_event = lambda e: send_sse(e['type'], json.dumps(e['data']))

The EventStream normalizes all TreeExecutor callbacks into typed event dicts
and adds lifecycle events that TreeExecutor doesn't emit natively.

Event catalog:
    init               - Run metadata (job_id, prompt_id, block_paths, total_jobs)
    block_start        - Block entered (block_path)
    stage              - Hook stage completed with timing (block_path, stage, time_ms, success)
    composition_complete - One composition finished (block_path, idx, progress counters)
    artifact           - Artifact produced (block_path, idx, artifact dict)
    artifact_consumed  - Dependency's artifacts available (consuming_block, source_block, count)
    block_complete     - All compositions done (block_path, stage_times, artifacts_count)
    block_failed       - Block failed (block_path, error)
    block_blocked      - Block blocked by dependency failure (block_path)
    run_complete       - Execution finished (stats dict)
    error              - Exception during execution (message)
"""

import time
from pathlib import Path
from typing import Callable, Optional

from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline


class EventStream:
    """
    Canonical event producer. Both CLI and WebUI consume this.

    Usage:
        stream = EventStream(pipeline, tree_jobs, run_meta,
                             output_path=str(job_dir))
        stream.on_event = my_callback   # {type, data, ts}
        stats = stream.run()
    """

    def __init__(self, pipeline: HookPipeline, tree_jobs: list, run_meta: dict,
                 output_path: str = None, with_stage_timing: bool = False):
        """
        Args:
            pipeline: HookPipeline instance
            tree_jobs: Job list from build_jobs() (already filtered)
            run_meta: Dict with job_id, prompt_id, block_paths, total_jobs
            output_path: Job directory for per-block artifact flush
            with_stage_timing: Wrap pipeline.execute_hook for per-stage timing events
        """
        self.pipeline = pipeline
        self.run_meta = run_meta
        self.output_path = output_path
        self.on_event: Optional[Callable] = None

        # Stage timing state
        self._stage_times = {}   # block_path -> {stage: [ms, ms, ...]}

        # Optionally wrap pipeline for stage timing
        if with_stage_timing:
            self._wrap_pipeline_timing()

        self.executor = TreeExecutor(
            tree_jobs, pipeline,
            on_progress=self._handle_progress,
            output_path=output_path,
        )

        # File lock path
        self._lock_path = None
        if output_path:
            self._lock_path = Path(output_path) / '_artifacts' / '.lock'

    def run(self) -> dict:
        """
        Execute the pipeline and return final stats.

        Emits init → (block/composition/artifact events) → run_complete.
        Acquires file lock before execution, releases after.
        """
        try:
            self._acquire_lock()
            self._emit('init', self.run_meta)

            self.pipeline.execute_hook('job_start', {
                'job_name': self.run_meta.get('job_id', ''),
            })

            self.executor.execute()

            # Final manifest write
            if self.executor.block_artifacts and self.output_path:
                self.executor.write_manifest(self.output_path)

            stats = self.executor.stats()
            self.pipeline.execute_hook('job_end', {
                'job_name': self.run_meta.get('job_id', ''),
                'stats': stats,
            })

            self._emit('run_complete', {'stats': stats})
            return stats

        except Exception as e:
            self._emit('error', {'message': str(e)})
            raise
        finally:
            self._release_lock()

    def stop(self):
        """Request stop at next composition boundary."""
        self.executor.stop()

    def _handle_progress(self, event_type: str, *args):
        """Normalize TreeExecutor callbacks into typed event dicts."""
        if event_type == 'block_start':
            block_path = args[0]
            self._stage_times[block_path] = {}
            self._emit('block_start', {'block_path': block_path})

        elif event_type == 'composition_complete':
            block_path, idx = args[0], args[1]
            block = self.executor.blocks.get(block_path, {})
            self._emit('composition_complete', {
                'block_path': block_path,
                'composition_idx': idx,
                'completed': self.executor.block_completed.get(block_path, 0),
                'total': block.get('compositions', 0),
                'global_completed': self.executor.completed_compositions,
                'global_total': len(self.executor.queue),
            })

        elif event_type == 'block_complete':
            block_path = args[0]
            block_artifacts = self.executor.block_artifacts.get(block_path, [])
            self._emit('block_complete', {
                'block_path': block_path,
                'stage_times': self._stage_times.get(block_path, {}),
                'artifacts_count': len(block_artifacts),
            })

        elif event_type == 'block_failed':
            block_path = args[0]
            error_msg = args[1] if len(args) > 1 else 'Unknown error'
            self._emit('block_failed', {
                'block_path': block_path,
                'error': str(error_msg),
            })

        elif event_type == 'block_blocked':
            self._emit('block_blocked', {'block_path': args[0]})

        elif event_type == 'artifact':
            block_path, idx, artifact = args[0], args[1], args[2]
            self._emit('artifact', {
                'block_path': block_path,
                'composition_idx': idx,
                'artifact': {
                    'name': artifact.get('name', ''),
                    'type': artifact.get('type', 'text'),
                    'mod_id': artifact.get('mod_id', ''),
                    'preview': artifact.get('preview', ''),
                    'disk_path': artifact.get('disk_path', ''),
                    'disk_line': artifact.get('disk_line'),
                },
            })

        elif event_type == 'artifact_consumed':
            consuming_block, source_block, count = args[0], args[1], args[2]
            self._emit('artifact_consumed', {
                'consuming_block': consuming_block,
                'source_block': source_block,
                'artifact_count': count,
            })

    def _emit(self, event_type: str, data: dict):
        """Emit a typed event to the consumer callback."""
        if self.on_event:
            self.on_event({
                'type': event_type,
                'data': data,
                'ts': time.time(),
            })

    def _wrap_pipeline_timing(self):
        """Wrap pipeline.execute_hook to emit stage timing events."""
        original = self.pipeline.execute_hook

        def timed_execute_hook(hook_name, context):
            block_path = context.get('block_path', '?')
            start = time.time()
            result = original(hook_name, context)
            elapsed_ms = round((time.time() - start) * 1000, 1)

            if block_path in self._stage_times:
                if hook_name not in self._stage_times[block_path]:
                    self._stage_times[block_path][hook_name] = []
                self._stage_times[block_path][hook_name].append(elapsed_ms)

            self._emit('stage', {
                'block_path': block_path,
                'stage': hook_name,
                'time_ms': elapsed_ms,
                'success': result.success,
            })
            return result

        self.pipeline.execute_hook = timed_execute_hook

    def _acquire_lock(self):
        """Create .lock file to signal execution in progress."""
        if self._lock_path:
            self._lock_path.parent.mkdir(parents=True, exist_ok=True)
            self._lock_path.write_text(str(time.time()))

    def _release_lock(self):
        """Remove .lock file after execution completes."""
        if self._lock_path and self._lock_path.exists():
            self._lock_path.unlink()
