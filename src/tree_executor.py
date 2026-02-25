"""
src/tree_executor.py - Depth-First Single Cursor Execution Engine

Ports the execution model from webui/prompty/previews/preview-build-flow-diagram.html
to production Python.

ARCHITECTURE:
  build_jobs() output        TreeExecutor              HookPipeline
  (flat list + _block_path)  (depth-first queue)       (execute_hook)
                                  |
                             build_queue()
                                  |
                             execute()  <-- stop/resume
                                  |
                            per block (once):
                               node_start -> resolve [cached]
                            per composition:
                               pre -> generate -> post
                            per block (once):
                               node_end

BLOCK STATES:
  idle     - Not yet visited
  dormant  - Queued but not reached
  running  - Cursor is here
  partial  - Was visited, cursor moved, more compositions pending
  paused   - Stopped mid-execution
  complete - All compositions finished
  failed   - A composition failed
  blocked  - Parent block failed

HOOK CONTEXT (Strategy D — namespace separation):
  Each hook receives an enriched context dict:
    Identity:     block_path, parent_path, is_leaf, block_depth
    Composition:  composition_index, composition_total, wildcards, wildcard_indices
    Operations:   operation, operation_mappings
    Annotations:  annotations, annotation_sources  (user intent — "what to DO")
    Meta:         meta, ext_text_source             (theme facts — "what it IS")
    Inheritance:  parent_result, parent_annotations
    Content:      resolved_text, prompt_id, job

  `meta` and `annotations` are SEPARATE namespaces. Theme metadata (from ext_text
  values) is never overridden by block annotations. Hooks receive both independently.
  See docs/composition-model.md "Theme Metadata (meta)".
"""

from typing import List, Dict, Optional, Callable, Any

from src.hooks import HookPipeline, HookResult, STATUS_SUCCESS, STATUS_ERROR


class TreeExecutor:
    """
    Depth-first single cursor executor for the hook-based pipeline.

    One composition at a time, depth-first block order.
    """

    # Block states (matching preview CSS data-run-state values)
    IDLE = 'idle'
    DORMANT = 'dormant'
    RUNNING = 'running'
    PARTIAL = 'partial'
    PAUSED = 'paused'
    COMPLETE = 'complete'
    FAILED = 'failed'
    BLOCKED = 'blocked'

    def __init__(self, jobs: list, pipeline: HookPipeline, on_progress: Callable = None):
        """
        Args:
            jobs: Complete, unfiltered output from build_jobs(). Each prompt dict
                  should have _block_path (e.g. "0", "0.0") and _parent_path.
                  The queue builder assumes uniform Cartesian distribution of child
                  compositions across parents — partial or filtered job lists will
                  produce incorrect queue ordering.
            pipeline: HookPipeline instance for executing hooks
            on_progress: optional callback(event_type, *args) for progress reporting
        """
        self.pipeline = pipeline
        self.on_progress = on_progress

        # Build block tree from flat jobs list
        self.blocks = self._build_block_tree(jobs)

        # Execution state
        self.queue = []             # Flat depth-first queue of entries
        self.queue_position = 0     # Current cursor position (preserved across stop/resume)
        self._state = self.IDLE     # Overall execution state

        # Block-level tracking
        self.visited_blocks = set()       # Blocks that have had node_start + resolve
        self.failed_blocks = set()        # Blocks that failed
        self.blocked_blocks = set()       # Blocks blocked by parent failure
        self.block_states = {}            # block_path -> state string
        self.block_completed = {}         # block_path -> count of completed compositions
        self.resolve_cache = {}           # block_path -> cached resolve HookResult

        # Composition-level tracking
        self.variation_results = {}       # "block_path:idx" -> HookResult (for parent->child passing)
        self.completed_compositions = 0   # Global counter
        self.stop_requested = False       # Stop flag

    def _build_block_tree(self, jobs: list) -> dict:
        """Group flat job list by _block_path into block definitions."""
        blocks = {}
        for job in jobs:
            prompt = job['prompt']
            path = prompt.get('_block_path')
            if path is None:
                # Jobs from old format (no nested text) won't have _block_path
                path = '0'
            if path not in blocks:
                blocks[path] = {
                    'path': path,
                    'parent_path': prompt.get('_parent_path'),
                    'compositions': 0,
                    'jobs': [],
                }
            blocks[path]['compositions'] += 1
            blocks[path]['jobs'].append(job)
        return blocks

    def build_queue(self) -> list:
        """
        Build flat execution queue in depth-first order.

        Each entry: { block_path, composition_idx, parent_key }
        parent_key: "block_path:composition_idx" or None for roots

        Mirrors preview-build-flow-diagram.html:buildDepthFirstQueue()
        """
        queue = []

        def enqueue_subtree(block_path, idx, parent_key):
            queue.append({
                'block_path': block_path,
                'composition_idx': idx,
                'parent_key': parent_key,
            })
            children = [b for b in self.blocks.values()
                        if b['parent_path'] == block_path]
            for child in sorted(children, key=lambda c: c['path']):
                parent_block = self.blocks[block_path]
                if parent_block['compositions'] > 0:
                    child_comps_per_parent = child['compositions'] // parent_block['compositions']
                else:
                    child_comps_per_parent = 0
                start_idx = idx * child_comps_per_parent
                for c in range(child_comps_per_parent):
                    child_idx = start_idx + c
                    if child_idx < child['compositions']:
                        enqueue_subtree(child['path'], child_idx, f"{block_path}:{idx}")

        # Roots: blocks with no parent, or whose parent doesn't exist in blocks.
        # The latter happens when build_text_variations() merges parent text into
        # children via Cartesian product — the parent block has no standalone jobs.
        roots = sorted([b for b in self.blocks.values()
                        if b['parent_path'] is None or b['parent_path'] not in self.blocks],
                       key=lambda b: b['path'])
        for root in roots:
            for i in range(root['compositions']):
                enqueue_subtree(root['path'], i, None)

        self.queue = queue
        return queue

    def execute(self):
        """
        Execute the queue. Single cursor, one composition at a time.

        Hook lifecycle per block:
            Block-level (once):  execute_hook('node_start') -> execute_hook('resolve') [cached]
            Per-composition:     execute_hook('pre') -> execute_hook('generate') -> execute_hook('post')
            Block-level (once):  execute_hook('node_end')
        """
        if not self.queue:
            self.build_queue()

        self._state = self.RUNNING

        while self.queue_position < len(self.queue) and not self.stop_requested:
            entry = self.queue[self.queue_position]
            block_path = entry['block_path']
            idx = entry['composition_idx']
            parent_key = entry['parent_key']

            # Skip failed/blocked blocks
            if block_path in self.failed_blocks or block_path in self.blocked_blocks:
                self.queue_position += 1
                continue

            # Skip if parent block failed
            if parent_key and parent_key.split(':')[0] in self.failed_blocks:
                self.blocked_blocks.add(block_path)
                self.block_states[block_path] = self.BLOCKED
                self._emit('block_blocked', block_path)
                self.queue_position += 1
                continue

            # Build hook context
            parent_result = self.variation_results.get(parent_key) if parent_key else None
            block = self.blocks[block_path]
            job = block['jobs'][idx] if idx < len(block['jobs']) else block['jobs'][0]
            prompt = job['prompt']

            ctx = {
                'block_path': block_path,
                'composition_index': idx,
                'composition_total': block['compositions'],
                'parent_result': parent_result.to_dict() if isinstance(parent_result, HookResult) else parent_result,
                'resolved_text': prompt.get('text'),
                'prompt_id': prompt.get('id'),
                'annotations': prompt.get('_annotations'),
                'job': job,
            }

            # Block-level hooks (fire once per block)
            if block_path not in self.visited_blocks:
                self.visited_blocks.add(block_path)
                self.block_states[block_path] = self.RUNNING
                self._emit('block_start', block_path)

                result = self.pipeline.execute_hook('node_start', ctx)
                if self.stop_requested:
                    break
                if result.modify_context:
                    ctx.update(result.modify_context)

                result = self.pipeline.execute_hook('resolve', ctx)
                if self.stop_requested:
                    break
                if not result.success:
                    self._handle_failure(block_path, idx, result)
                    self.queue_position += 1
                    continue
                self.resolve_cache[block_path] = result

            # Inject cached resolve data
            cached = self.resolve_cache.get(block_path)
            if cached and isinstance(cached, HookResult):
                ctx['resolve_data'] = cached.data
            elif cached and isinstance(cached, dict):
                ctx['resolve_data'] = cached

            # Per-composition hooks
            composition_failed = False
            composition_data = {}  # Accumulate data across all stages
            for stage in ('pre', 'generate', 'post'):
                result = self.pipeline.execute_hook(stage, ctx)
                if self.stop_requested:
                    break
                if not result.success:
                    self._handle_failure(block_path, idx, result)
                    composition_failed = True
                    break
                # Accumulate data from each stage
                if result.data:
                    composition_data.update(result.data)
                # Apply context modifications from each stage
                if result.modify_context:
                    ctx.update(result.modify_context)

            if self.stop_requested:
                break

            if not composition_failed:
                # All three stages succeeded — store combined result
                self.block_completed[block_path] = self.block_completed.get(block_path, 0) + 1
                self.completed_compositions += 1
                combined_result = HookResult(STATUS_SUCCESS, data=composition_data)
                self.variation_results[f"{block_path}:{idx}"] = combined_result
                self._emit('composition_complete', block_path, idx)

                # Block complete -> node_end
                if self.block_completed[block_path] == block['compositions']:
                    self.pipeline.execute_hook('node_end', ctx)
                    self.block_states[block_path] = self.COMPLETE
                    self._emit('block_complete', block_path)

            self.queue_position += 1

        # Finalize state
        if self.stop_requested:
            self._state = self.PAUSED
        elif self.failed_blocks:
            self._state = self.FAILED
        else:
            self._state = self.COMPLETE

    def stop(self):
        """Request stop at next composition boundary."""
        self.stop_requested = True

    def resume(self):
        """Resume from current queue_position."""
        self.stop_requested = False
        self.execute()

    def _handle_failure(self, block_path: str, idx: int, result: HookResult):
        """Mark block as failed, cascade to all descendants."""
        self.failed_blocks.add(block_path)
        self.block_states[block_path] = self.FAILED
        self.variation_results[f"{block_path}:{idx}"] = result
        self._emit('block_failed', block_path, getattr(result, 'message', None))

        # Cascade: block all children recursively
        def cascade(parent_path):
            children = [b for b in self.blocks.values() if b['parent_path'] == parent_path]
            for child in children:
                self.blocked_blocks.add(child['path'])
                self.block_states[child['path']] = self.BLOCKED
                self._emit('block_blocked', child['path'])
                cascade(child['path'])
        cascade(block_path)

    def _emit(self, event_type: str, *args):
        """Emit progress event to callback."""
        if self.on_progress:
            self.on_progress(event_type, *args)

    def stats(self) -> dict:
        """Return execution statistics."""
        # Build partial completion detail for failed blocks
        failed_detail = {}
        for bp in self.failed_blocks:
            block = self.blocks.get(bp)
            if block:
                failed_detail[bp] = {
                    'completed': self.block_completed.get(bp, 0),
                    'total': block['compositions'],
                }

        return {
            'state': self._state,
            'total_compositions': len(self.queue),
            'completed_compositions': self.completed_compositions,
            'queue_position': self.queue_position,
            'blocks_total': len(self.blocks),
            'blocks_complete': sum(1 for s in self.block_states.values() if s == self.COMPLETE),
            'blocks_failed': len(self.failed_blocks),
            'blocks_failed_detail': failed_detail,
            'blocks_blocked': len(self.blocked_blocks),
        }
