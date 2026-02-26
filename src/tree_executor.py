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
  blocked  - Parent or dependency failed

CROSS-BLOCK DEPENDENCIES (depends_on):
  Prompts can declare depends_on: ["0.0", "0.1"] in YAML.
  The engine enforces ordering (topological sort in build_queue) and
  failure cascade (if any dependency fails, dependent blocks are blocked).
  Hooks receive upstream_artifacts and block_states for data flow.

HOOK CONTEXT (Strategy D — namespace separation):
  Each hook receives an enriched context dict:
    Identity:     block_path, parent_path, is_leaf, block_depth
    Composition:  composition_index, composition_total, wildcards, wildcard_indices
    Operations:   operation, operation_mappings
    Annotations:  annotations, annotation_sources  (user intent — "what to DO")
    Meta:         meta, ext_text_source             (theme facts — "what it IS")
    Inheritance:  parent_result, parent_annotations
    Content:      resolved_text, prompt_id, job
    Cross-block:  upstream_artifacts, block_states, block_completed

  `meta` and `annotations` are SEPARATE namespaces. Theme metadata (from ext_text
  values) is never overridden by block annotations. Hooks receive both independently.
  See docs/composition-model.md "Theme Metadata (meta)".

  `upstream_artifacts` is a read-only copy of artifacts from completed blocks.
  Each artifact dict may include `disk_path` (relative path to JSONL or binary file)
  and `disk_line` (line offset in JSONL, text artifacts only) when flushed to disk.
  Text artifacts are consolidated into JSONL files to prevent file explosion at scale.
  Hooks can attach arbitrary keys to artifact dicts — the engine never strips them.
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

    def __init__(self, jobs: list, pipeline: HookPipeline, on_progress: Callable = None,
                 output_path: str = None):
        """
        Args:
            jobs: Complete, unfiltered output from build_jobs(). Each prompt dict
                  should have _block_path (e.g. "0", "0.0") and _parent_path.
                  The queue builder assumes uniform Cartesian distribution of child
                  compositions across parents — partial or filtered job lists will
                  produce incorrect queue ordering.
            pipeline: HookPipeline instance for executing hooks
            on_progress: optional callback(event_type, *args) for progress reporting
            output_path: job directory for per-block artifact flushing (optional)
        """
        self.pipeline = pipeline
        self.on_progress = on_progress
        self.output_path = output_path

        # Build block tree from flat jobs list
        self.blocks = self._build_block_tree(jobs)

        # Execution state
        self.queue = []             # Flat depth-first queue of entries
        self.queue_position = 0     # Current cursor position (preserved across stop/resume)
        self._state = self.IDLE     # Overall execution state

        # Block-level tracking
        self.visited_blocks = set()       # Blocks that have had node_start + resolve
        self.failed_blocks = set()        # Blocks that failed
        self.blocked_blocks = set()       # Blocks blocked by parent or dependency failure
        self.block_states = {}            # block_path -> state string
        self.block_completed = {}         # block_path -> count of completed compositions
        self.resolve_cache = {}           # block_path -> cached resolve HookResult

        # Composition-level tracking
        self.variation_results = {}       # "block_path:idx" -> HookResult (for parent->child passing)
        self.completed_compositions = 0   # Global counter
        self.stop_requested = False       # Stop flag
        self.block_artifacts = {}         # block_path -> [artifact_dict, ...]

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
                # Extract depends_on from:
                # 1. Prompt-level depends_on (multi-prompt pipelines)
                # 2. Annotation _depends_on (single-prompt, per-block dependency)
                depends_on = prompt.get('depends_on', [])
                annotations = prompt.get('_annotations', {}) or {}
                ann_depends = annotations.get('_depends_on', [])
                if isinstance(depends_on, str):
                    depends_on = [depends_on]
                if isinstance(ann_depends, str):
                    ann_depends = [ann_depends]
                # Merge both sources (annotation takes precedence for per-block config)
                all_deps = list(depends_on) + [d for d in ann_depends if d not in depends_on]
                blocks[path] = {
                    'path': path,
                    'parent_path': prompt.get('_parent_path'),
                    'depends_on': all_deps,
                    'compositions': 0,
                    'jobs': [],
                }
            blocks[path]['compositions'] += 1
            blocks[path]['jobs'].append(job)
        return blocks

    def build_queue(self) -> list:
        """
        Build flat execution queue in dependency-respecting depth-first order.

        Each entry: { block_path, composition_idx, parent_key }
        parent_key: "block_path:composition_idx" or None for roots

        Roots are topologically sorted so that blocks with depends_on are
        placed after their dependency targets. Within a dependency tier,
        the original lexicographic order is preserved.
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
        roots = [b for b in self.blocks.values()
                 if b['parent_path'] is None or b['parent_path'] not in self.blocks]

        # Topological sort roots to respect depends_on ordering.
        # Blocks with depends_on targets are placed after those targets.
        roots = self._topo_sort_roots(roots)

        for root in roots:
            for i in range(root['compositions']):
                enqueue_subtree(root['path'], i, None)

        self.queue = queue
        return queue

    def _topo_sort_roots(self, roots: list) -> list:
        """
        Topological sort of root blocks respecting depends_on.

        A block's depends_on may reference non-root blocks (children).
        We resolve this to the root-level: if block "1" depends on "0.0",
        it must come after whichever root subtree contains "0.0".

        Within the same dependency tier, lexicographic order is preserved.
        """
        # Build set of all block paths under each root subtree
        root_paths = {r['path'] for r in roots}
        root_by_path = {r['path']: r for r in roots}

        def find_root_for(dep_path):
            """Find which root subtree contains dep_path."""
            # Direct match — dep_path is itself a root
            if dep_path in root_paths:
                return dep_path
            # Walk up parent chain
            parts = dep_path.split('.')
            while parts:
                candidate = '.'.join(parts)
                if candidate in root_paths:
                    return candidate
                # Check if any root is a prefix (child of a merged parent)
                for rp in root_paths:
                    if rp.startswith(candidate + '.') or rp == candidate:
                        return rp
                parts.pop()
            # dep_path may be a prefix of root paths (e.g. depends_on "0" when roots are "0.0", "0.1")
            matching = [rp for rp in root_paths if rp.startswith(dep_path + '.') or rp == dep_path]
            return matching[0] if matching else None

        # Build adjacency: root_path -> set of root_paths it must come after
        deps = {r['path']: set() for r in roots}
        for root in roots:
            for dep in root.get('depends_on', []):
                target_root = find_root_for(dep)
                if target_root and target_root != root['path']:
                    deps[root['path']].add(target_root)

        # Kahn's algorithm for topological sort (stable — preserves lex order within tier)
        in_degree = {rp: len(d) for rp, d in deps.items()}
        # Start with nodes that have no dependencies, sorted lexicographically
        ready = sorted([rp for rp, deg in in_degree.items() if deg == 0])
        result = []

        while ready:
            node = ready.pop(0)
            result.append(root_by_path[node])
            # Decrease in-degree for nodes that depend on this one
            for rp, d in deps.items():
                if node in d:
                    d.discard(node)
                    in_degree[rp] -= 1
                    if in_degree[rp] == 0:
                        # Insert in sorted position to maintain lex order within tier
                        import bisect
                        bisect.insort(ready, rp)

        # If result is shorter than roots, there's a cycle — fall back to lex order
        if len(result) < len(roots):
            return sorted(roots, key=lambda b: b['path'])

        return result

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

            block = self.blocks[block_path]

            # Check depends_on — if any dependency failed, block this block
            if block.get('depends_on') and block_path not in self.visited_blocks:
                failed_deps = [d for d in block['depends_on'] if d in self.failed_blocks]
                if failed_deps:
                    self.blocked_blocks.add(block_path)
                    self.block_states[block_path] = self.BLOCKED
                    self._emit('block_blocked', block_path)
                    self.queue_position += 1
                    continue

            # Build hook context
            parent_result = self.variation_results.get(parent_key) if parent_key else None
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
                # Cross-block data flow (read-only copies)
                'upstream_artifacts': {bp: list(arts) for bp, arts in self.block_artifacts.items()},
                'block_states': dict(self.block_states),
                'block_completed': dict(self.block_completed),
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
                # Extract artifacts from hook return data
                artifacts = composition_data.pop('artifacts', [])
                if isinstance(artifacts, dict):
                    artifacts = [artifacts]
                for artifact in artifacts:
                    artifact.setdefault('composition_idx', idx)
                    artifact.setdefault('block_path', block_path)
                if artifacts:
                    self.block_artifacts.setdefault(block_path, []).extend(artifacts)
                    for artifact in artifacts:
                        self._emit('artifact', block_path, idx, artifact)

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

                    # Per-block artifact flush: write to disk immediately
                    if self.block_artifacts.get(block_path) and self.output_path:
                        self._flush_block_artifacts(block_path)

                    # Emit artifact_consumed for blocks that have depends_on
                    # (signals that this block's artifacts are now available to dependents)
                    if self.block_artifacts.get(block_path):
                        dependents = [b for b in self.blocks.values()
                                      if block_path in b.get('depends_on', [])]
                        for dep in dependents:
                            self._emit('artifact_consumed', dep['path'], block_path,
                                       len(self.block_artifacts[block_path]))

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
        """Mark block as failed, cascade to all descendants and dependents."""
        self.failed_blocks.add(block_path)
        self.block_states[block_path] = self.FAILED
        self.variation_results[f"{block_path}:{idx}"] = result
        error_msg = getattr(result, 'message', None)
        if error_msg is None and isinstance(getattr(result, 'error', None), dict):
            error_msg = result.error.get('message', 'Unknown error')
        self._emit('block_failed', block_path, error_msg)

        # Cascade: block all children and dependents recursively
        def cascade(failed_path):
            # Block children (parent→child relationship)
            children = [b for b in self.blocks.values() if b['parent_path'] == failed_path]
            # Block dependents (depends_on relationship)
            dependents = [b for b in self.blocks.values()
                          if failed_path in b.get('depends_on', [])]
            for block in children + dependents:
                if block['path'] not in self.blocked_blocks:
                    self.blocked_blocks.add(block['path'])
                    self.block_states[block['path']] = self.BLOCKED
                    self._emit('block_blocked', block['path'])
                    cascade(block['path'])
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
            'artifacts_total': sum(len(v) for v in self.block_artifacts.values()),
            'artifacts_by_block': {bp: len(arts) for bp, arts in self.block_artifacts.items()},
        }

    def _flush_block_artifacts(self, block_path: str):
        """
        Flush a completed block's artifacts to disk immediately.

        Text artifacts are consolidated into JSONL files (one per mod_id per block)
        to prevent file explosion at scale. Binary artifacts get individual files.

        Layout:
          _artifacts/{mod_id}/{block_path}.jsonl   — text artifacts (one line per composition)
          _artifacts/{mod_id}/{block_path}/{name}   — binary artifacts (content_bytes key)

        Each artifact dict gets:
          disk_path  — relative path to JSONL or binary file
          disk_line  — line offset in JSONL (text artifacts only)

        Called after each block completes (not just at the end of execution).
        """
        import json
        from pathlib import Path

        if not self.output_path:
            return

        artifacts_root = Path(self.output_path) / '_artifacts'
        artifacts = self.block_artifacts.get(block_path, [])
        if not artifacts:
            return

        # Group artifacts by mod_id
        by_mod = {}
        for artifact in artifacts:
            mod_id = artifact.get('mod_id', '_unknown')
            by_mod.setdefault(mod_id, []).append(artifact)

        for mod_id, mod_artifacts in by_mod.items():
            mod_dir = artifacts_root / mod_id
            mod_dir.mkdir(parents=True, exist_ok=True)

            # Separate text vs binary artifacts
            text_arts = []
            for artifact in mod_artifacts:
                if 'content_bytes' in artifact:
                    # Binary artifact — write individual file
                    filename = artifact.get('name', '')
                    if not filename:
                        continue
                    artifact_dir = mod_dir / block_path
                    artifact_dir.mkdir(parents=True, exist_ok=True)
                    artifact_path = artifact_dir / filename
                    artifact_path.write_bytes(artifact['content_bytes'])
                    artifact['disk_path'] = str(artifact_path.relative_to(Path(self.output_path)))
                else:
                    text_arts.append(artifact)

            # Consolidate text artifacts into JSONL (one file per mod per block)
            if text_arts:
                jsonl_path = mod_dir / f'{block_path}.jsonl'
                with open(jsonl_path, 'w') as f:
                    for i, artifact in enumerate(text_arts):
                        content = artifact.get('content') or artifact.get('preview', '')
                        line = {
                            'composition_idx': artifact.get('composition_idx', i),
                            'name': artifact.get('name', ''),
                            'content': str(content),
                        }
                        f.write(json.dumps(line) + '\n')

                        # Set locator fields
                        rel_path = str(jsonl_path.relative_to(Path(self.output_path)))
                        artifact['disk_path'] = rel_path
                        artifact['disk_line'] = i

        # Update running manifest after each block
        self._write_manifest()

    def _write_manifest(self):
        """Write/update _artifacts/manifest.json with current state."""
        import json
        import time
        from pathlib import Path

        if not self.block_artifacts or not self.output_path:
            return None

        manifest = {
            'version': 3,
            'format': 'jsonl',
            'run': {
                'timestamp': time.time(),
                'blocks_complete': sum(1 for s in self.block_states.values() if s == self.COMPLETE),
                'blocks_total': len(self.blocks),
            },
            'blocks': {}
        }
        for bp, arts in self.block_artifacts.items():
            block = self.blocks.get(bp, {})
            manifest['blocks'][bp] = {
                'artifacts': arts,
                'count': len(arts),
                'depends_on': block.get('depends_on', []),
                'composition_total': block.get('compositions', 0),
            }

        manifest_dir = Path(self.output_path) / '_artifacts'
        manifest_dir.mkdir(parents=True, exist_ok=True)
        manifest_file = manifest_dir / 'manifest.json'
        manifest_file.write_text(json.dumps(manifest, indent=2))
        return manifest_file

    def write_manifest(self, output_path):
        """Write _artifacts/manifest.json with all collected artifacts (legacy API)."""
        self.output_path = output_path
        return self._write_manifest()
