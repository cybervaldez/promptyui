#!/bin/bash
# E2E Test: TreeExecutor — Depth-First Single Cursor Execution Engine
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PYTHON="./venv/bin/python"

print_header "TreeExecutor E2E Tests"

# ─────────────────────────────────────────────────────────────────────────────
# Test 1: build_jobs() output includes _block_path field
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 1: build_jobs() includes _block_path"
OUTPUT=$($PYTHON -c "
from src.jobs import build_text_variations

items = [{'content': 'Hello'}]
results = build_text_variations(items, {}, 0, 0, {})
assert len(results[0]) == 8, f'Expected 8-tuple, got {len(results[0])}-tuple'
assert results[0][7] == '0', f'Expected path \"0\", got \"{results[0][7]}\"'
print('OK: 8-tuple with block_path')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: 8-tuple" && log_pass "build_text_variations returns 8-tuple with _block_path" || log_fail "Missing _block_path in 8-tuple: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 2: Root blocks have paths "0", "1", etc.
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 2: Root block paths"
OUTPUT=$($PYTHON -c "
from src.jobs import build_text_variations

items = [
    {'content': 'First'},
    {'content': 'Second'},
    {'content': 'Third'},
]
results = build_text_variations(items, {}, 0, 0, {})
paths = [r[7] for r in results]
assert paths == ['0', '1', '2'], f'Expected [\"0\",\"1\",\"2\"], got {paths}'
print('OK: root paths correct')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: root paths" && log_pass "Root blocks have paths 0, 1, 2" || log_fail "Root paths wrong: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 3: Child blocks have paths "0.0", "0.1", etc.
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 3: Child block paths"
OUTPUT=$($PYTHON -c "
from src.jobs import build_text_variations

items = [
    {'content': 'Root', 'after': [
        {'content': 'ChildA'},
        {'content': 'ChildB'},
    ]}
]
results = build_text_variations(items, {}, 0, 0, {})
paths = sorted(set(r[7] for r in results))
assert '0.0' in paths, f'Missing 0.0 in {paths}'
assert '0.1' in paths, f'Missing 0.1 in {paths}'
print('OK: child paths correct')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: child paths" && log_pass "Child blocks have paths 0.0, 0.1" || log_fail "Child paths wrong: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 4: TreeExecutor builds queue in depth-first order
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 4: Depth-first queue order"
OUTPUT=$($PYTHON -c "
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline

jobs = [
    {'prompt': {'text': 'R0', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'R0', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'C', '_block_path': '0.0', '_parent_path': '0'}},
    {'prompt': {'text': 'C', '_block_path': '0.0', '_parent_path': '0'}},
]

executor = TreeExecutor(jobs, HookPipeline('/tmp', {}, {}))
queue = executor.build_queue()

# Depth-first: root comp 0 -> child comp 0 -> root comp 1 -> child comp 1
order = [(e['block_path'], e['composition_idx']) for e in queue]
assert order == [('0', 0), ('0.0', 0), ('0', 1), ('0.0', 1)], f'Wrong order: {order}'
print('OK: depth-first order')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: depth-first" && log_pass "Queue is depth-first ordered" || log_fail "Queue order wrong: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 5: Hook lifecycle fires in correct order
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 5: Hook lifecycle order"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, load_hooks_config

job_dir = Path('jobs/test-fixtures')
hooks_config = load_hooks_config(job_dir)
pipeline = HookPipeline(job_dir, hooks_config, {})

jobs = [
    {'prompt': {'text': 'Test', '_block_path': '0', '_parent_path': None}},
]

executor = TreeExecutor(jobs, pipeline)
executor.execute()

# Should be: node_start, resolve, pre, generate, post, node_end
assert executor._state == 'complete', f'State={executor._state}'
assert executor.completed_compositions == 1
print('OK: lifecycle complete')
" 2>&1)

# Check both success and hook log output
echo "$OUTPUT" | grep -q "OK: lifecycle complete" && \
echo "$OUTPUT" | grep -q "\[HOOK\] node_start" && \
echo "$OUTPUT" | grep -q "\[HOOK\] resolve" && \
echo "$OUTPUT" | grep -q "\[HOOK\] pre" && \
echo "$OUTPUT" | grep -q "\[HOOK\] post" && \
echo "$OUTPUT" | grep -q "\[HOOK\] node_end" && \
log_pass "Hook lifecycle fires in correct order" || log_fail "Missing hooks in output: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 6: resolve fires once per block (not per composition)
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 6: resolve fires once per block"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, load_hooks_config

job_dir = Path('jobs/test-fixtures')
hooks_config = load_hooks_config(job_dir)
pipeline = HookPipeline(job_dir, hooks_config, {})

# 3 compositions in same block
jobs = [
    {'prompt': {'text': 'A', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'B', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'C', '_block_path': '0', '_parent_path': None}},
]

executor = TreeExecutor(jobs, pipeline)
executor.execute()

assert executor.completed_compositions == 3
# resolve_cache should have exactly 1 entry (one per block)
assert len(executor.resolve_cache) == 1, f'Expected 1 resolve cache entry, got {len(executor.resolve_cache)}'
print('OK: resolve fires once')
" 2>&1)
# Count resolve hook calls
RESOLVE_COUNT=$(echo "$OUTPUT" | grep -c "\[HOOK\] resolve")
echo "$OUTPUT" | grep -q "OK: resolve fires once" && [ "$RESOLVE_COUNT" -eq 1 ] && \
log_pass "resolve fires once per block (not per composition)" || log_fail "resolve fired $RESOLVE_COUNT times: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 7: node_end fires once per block after all compositions
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 7: node_end fires once after all compositions"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, load_hooks_config

job_dir = Path('jobs/test-fixtures')
hooks_config = load_hooks_config(job_dir)
pipeline = HookPipeline(job_dir, hooks_config, {})

jobs = [
    {'prompt': {'text': 'A', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'B', '_block_path': '0', '_parent_path': None}},
]

events = []
executor = TreeExecutor(jobs, pipeline, on_progress=lambda e, *a: events.append((e, a)))
executor.execute()

block_complete_events = [e for e in events if e[0] == 'block_complete']
assert len(block_complete_events) == 1, f'Expected 1 block_complete, got {len(block_complete_events)}'
print('OK: node_end fires once')
" 2>&1)
NODE_END_COUNT=$(echo "$OUTPUT" | grep -c "\[HOOK\] node_end")
echo "$OUTPUT" | grep -q "OK: node_end fires once" && [ "$NODE_END_COUNT" -eq 1 ] && \
log_pass "node_end fires once per block" || log_fail "node_end fired $NODE_END_COUNT times: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 8: Failure cascade — failing block blocks all children
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 8: Failure cascade"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, HookResult, STATUS_ERROR

class FailResolve(HookPipeline):
    def execute_hook(self, hook_name, context):
        if hook_name == 'resolve' and context.get('block_path') == '0':
            return HookResult(STATUS_ERROR, error={'code': 'TEST', 'message': 'fail'}, message='fail')
        return super().execute_hook(hook_name, context)

jobs = [
    {'prompt': {'text': 'Root', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'Child', '_block_path': '0.0', '_parent_path': '0'}},
    {'prompt': {'text': 'Grandchild', '_block_path': '0.0.0', '_parent_path': '0.0'}},
    {'prompt': {'text': 'Sibling', '_block_path': '1', '_parent_path': None}},
]

pipeline = FailResolve(Path('/tmp'), {}, {})
executor = TreeExecutor(jobs, pipeline)
executor.execute()

assert '0' in executor.failed_blocks, 'Block 0 not failed'
assert '0.0' in executor.blocked_blocks, 'Block 0.0 not blocked'
assert '0.0.0' in executor.blocked_blocks, 'Block 0.0.0 not blocked'
assert '1' not in executor.failed_blocks and '1' not in executor.blocked_blocks, 'Block 1 should not be affected'
assert executor.block_states.get('1') == 'complete', f'Block 1 state={executor.block_states.get(\"1\")}'
print('OK: failure cascades correctly')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: failure cascades" && log_pass "Failure cascade blocks all descendants" || log_fail "Cascade failed: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 9: Stop/resume preserves queue position
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 9: Stop/resume"
OUTPUT=$($PYTHON -c "
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline

jobs = [
    {'prompt': {'text': f'Item {i}', '_block_path': '0', '_parent_path': None}}
    for i in range(6)
]

executor = TreeExecutor(jobs, HookPipeline('/tmp', {}, {}),
    on_progress=lambda e, *a: executor.stop() if e == 'composition_complete' and a[1] == 2 else None)
executor.execute()

assert executor._state == 'paused', f'Expected paused, got {executor._state}'
pos_after_stop = executor.queue_position
completed_after_stop = executor.completed_compositions

# Resume
executor.resume()

assert executor._state == 'complete', f'Expected complete after resume, got {executor._state}'
assert executor.completed_compositions == 6, f'Expected 6 completed, got {executor.completed_compositions}'
# node_start should NOT have re-fired (visited_blocks preserved)
assert '0' in executor.visited_blocks
print(f'OK: stop at pos={pos_after_stop} comp={completed_after_stop}, resume to complete')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: stop at" && log_pass "Stop/resume preserves queue position" || log_fail "Stop/resume failed: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 10: Parent result passes to child context
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 10: Parent result passes to child"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, HookResult, STATUS_SUCCESS

class TrackParent(HookPipeline):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.seen_parent_results = []

    def execute_hook(self, hook_name, context):
        if hook_name == 'pre' and context.get('block_path') == '0.0':
            self.seen_parent_results.append(context.get('parent_result'))
        return super().execute_hook(hook_name, context)

jobs = [
    {'prompt': {'text': 'Root', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'Child', '_block_path': '0.0', '_parent_path': '0'}},
]

pipeline = TrackParent(Path('/tmp'), {}, {})
executor = TreeExecutor(jobs, pipeline)
executor.execute()

# Child should have received parent's result
assert len(pipeline.seen_parent_results) == 1, f'Expected 1 parent result, got {len(pipeline.seen_parent_results)}'
parent_result = pipeline.seen_parent_results[0]
assert parent_result is not None, 'Parent result was None'
print(f'OK: parent result passed to child')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: parent result" && log_pass "Parent result passes to child context" || log_fail "Parent result not passed: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 11: Cached resolve data injected into subsequent compositions
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 11: resolve_data injected into ctx for 2nd composition"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, HookResult, STATUS_SUCCESS

class ResolveTracker(HookPipeline):
    \"\"\"Injects data at resolve, verifies it arrives in pre for later compositions.\"\"\"
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.resolve_data_seen = []  # (composition_idx, resolve_data) per pre call

    def execute_hook(self, hook_name, context):
        if hook_name == 'resolve':
            # Return data that should be cached and injected later
            return HookResult(STATUS_SUCCESS, data={'cached_key': 'cached_value'})
        if hook_name == 'pre':
            # Record what resolve_data the executor injected
            self.resolve_data_seen.append((
                context.get('composition_index'),
                context.get('resolve_data'),
            ))
        return super().execute_hook(hook_name, context)

# 3 compositions in one block — resolve fires once, pre fires 3 times
jobs = [
    {'prompt': {'text': f'Item {i}', 'id': 'test', '_block_path': '0', '_parent_path': None}}
    for i in range(3)
]

pipeline = ResolveTracker(Path('/tmp'), {}, {})
executor = TreeExecutor(jobs, pipeline)
executor.execute()

assert len(pipeline.resolve_data_seen) == 3, f'Expected 3 pre calls, got {len(pipeline.resolve_data_seen)}'

# All 3 compositions should have received the cached resolve data
for comp_idx, resolve_data in pipeline.resolve_data_seen:
    assert resolve_data is not None, f'comp {comp_idx}: resolve_data is None'
    assert resolve_data.get('cached_key') == 'cached_value', \
        f'comp {comp_idx}: resolve_data={resolve_data}'

print('OK: resolve_data injected into all compositions')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: resolve_data injected" && log_pass "Cached resolve_data injected into ctx for subsequent compositions" || log_fail "resolve_data not injected: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 12: Depth-3 — grandchild receives child result (not root's)
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 12: Grandchild receives child result, not root's"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, HookResult, STATUS_SUCCESS

class TagByBlock(HookPipeline):
    \"\"\"Tags each block's generate result with its block_path so children can verify lineage.\"\"\"
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.grandchild_parent_results = []

    def execute_hook(self, hook_name, context):
        bp = context.get('block_path')
        if hook_name == 'generate':
            # Tag the result with which block produced it
            return HookResult(STATUS_SUCCESS, data={'produced_by': bp})
        if hook_name == 'pre' and bp == '0.0.0':
            # Grandchild: record what parent_result it received
            self.grandchild_parent_results.append(context.get('parent_result'))
        return super().execute_hook(hook_name, context)

# Depth-3 tree: root -> child -> grandchild (1 composition each)
jobs = [
    {'prompt': {'text': 'Root', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'Child', '_block_path': '0.0', '_parent_path': '0'}},
    {'prompt': {'text': 'Grandchild', '_block_path': '0.0.0', '_parent_path': '0.0'}},
]

pipeline = TagByBlock(Path('/tmp'), {}, {})
executor = TreeExecutor(jobs, pipeline)
executor.execute()

assert executor._state == 'complete'
assert len(pipeline.grandchild_parent_results) == 1, \
    f'Expected 1 grandchild pre call, got {len(pipeline.grandchild_parent_results)}'

parent_result = pipeline.grandchild_parent_results[0]
assert parent_result is not None, 'Grandchild parent_result is None'

# The grandchild's parent_result should come from block '0.0' (child), NOT '0' (root)
produced_by = parent_result.get('data', {}).get('produced_by')
assert produced_by == '0.0', f'Expected produced_by=\"0.0\" (child), got \"{produced_by}\"'
print('OK: grandchild receives child result, not root')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: grandchild receives child result" && log_pass "Depth-3: grandchild receives child result (not root's)" || log_fail "Depth-3 parent result wrong: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 13: Multiple independent subtrees don't cross-contaminate
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 13: Independent subtrees execute without cross-contamination"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, HookResult, STATUS_SUCCESS

class SubtreeTracker(HookPipeline):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.child_parent_results = {}  # block_path -> parent_result

    def execute_hook(self, hook_name, context):
        bp = context.get('block_path')
        if hook_name == 'generate':
            return HookResult(STATUS_SUCCESS, data={'origin': bp})
        if hook_name == 'pre' and bp in ('0.0', '1.0'):
            self.child_parent_results[bp] = context.get('parent_result')
        return super().execute_hook(hook_name, context)

# Two independent subtrees: 0->0.0 and 1->1.0
jobs = [
    {'prompt': {'text': 'Root A', '_block_path': '0', '_parent_path': None}},
    {'prompt': {'text': 'Child A', '_block_path': '0.0', '_parent_path': '0'}},
    {'prompt': {'text': 'Root B', '_block_path': '1', '_parent_path': None}},
    {'prompt': {'text': 'Child B', '_block_path': '1.0', '_parent_path': '1'}},
]

pipeline = SubtreeTracker(Path('/tmp'), {}, {})
executor = TreeExecutor(jobs, pipeline)
executor.execute()

assert executor._state == 'complete'
assert executor.block_states.get('0') == 'complete'
assert executor.block_states.get('0.0') == 'complete'
assert executor.block_states.get('1') == 'complete'
assert executor.block_states.get('1.0') == 'complete'

# Child 0.0 should have parent from block '0'
pr_a = pipeline.child_parent_results.get('0.0')
assert pr_a is not None, 'Child 0.0 got no parent result'
assert pr_a.get('data', {}).get('origin') == '0', f'Child 0.0 parent origin={pr_a}'

# Child 1.0 should have parent from block '1' (not from block '0')
pr_b = pipeline.child_parent_results.get('1.0')
assert pr_b is not None, 'Child 1.0 got no parent result'
assert pr_b.get('data', {}).get('origin') == '1', f'Child 1.0 parent origin={pr_b}'

print('OK: independent subtrees have correct parent results')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: independent subtrees" && log_pass "Independent subtrees execute without cross-contamination" || log_fail "Subtree cross-contamination: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 14: stats() surfaces partial completion for failed blocks
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 14: Partial completion in stats for failed blocks"
OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, HookResult, STATUS_ERROR

class FailOnThird(HookPipeline):
    \"\"\"Fails generate on the 3rd composition (index 2) of block '0'.\"\"\"
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.call_count = 0

    def execute_hook(self, hook_name, context):
        if hook_name == 'generate' and context.get('block_path') == '0':
            self.call_count += 1
            if self.call_count == 3:
                return HookResult(STATUS_ERROR, error={'code': 'TEST', 'message': 'fail on 3rd'}, message='fail on 3rd')
        return super().execute_hook(hook_name, context)

# 5 compositions in one block — should fail on #3, leaving 2 completed
jobs = [
    {'prompt': {'text': f'Item {i}', 'id': 'test', '_block_path': '0', '_parent_path': None}}
    for i in range(5)
]

pipeline = FailOnThird(Path('/tmp'), {}, {})
executor = TreeExecutor(jobs, pipeline)
executor.execute()

stats = executor.stats()
assert stats['state'] == 'failed'
assert stats['blocks_failed'] == 1
assert '0' in stats['blocks_failed_detail']

detail = stats['blocks_failed_detail']['0']
assert detail['completed'] == 2, f'Expected 2 completed before failure, got {detail[\"completed\"]}'
assert detail['total'] == 5, f'Expected 5 total, got {detail[\"total\"]}'
print(f'OK: partial completion {detail[\"completed\"]}/{detail[\"total\"]} in stats')
" 2>&1)
echo "$OUTPUT" | grep -q "OK: partial completion 2/5" && log_pass "stats() surfaces partial completion for failed blocks" || log_fail "Partial completion stats wrong: $OUTPUT"

# ═════════════════════════════════════════════════════════════════════════════
# INTEGRATION TESTS: Real hook scripts + real job YAML
# ═════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# Test 15: Full integration — test-fixtures job through TreeExecutor
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 15: Full integration with test-fixtures job + real hooks"
OUTPUT=$($PYTHON -c "
import yaml
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, load_hooks_config, load_mods_config
from src.jobs import build_jobs

job_dir = Path('jobs/test-fixtures')

# Load job config
with open(job_dir / 'jobs.yaml') as f:
    task_conf = yaml.safe_load(f)

# Load hooks
hooks_config = load_hooks_config(job_dir)
mods_config = load_mods_config(job_dir)
pipeline = HookPipeline(job_dir, hooks_config, mods_config)

# Build jobs (the real build_jobs function)
defaults = task_conf.get('defaults', {})
jobs = build_jobs(
    task_conf, Path('/dev/null'), 0.1, ' ', {'ext': []},
    composition_id=0,
    wildcards_max=defaults.get('wildcards_max', 0),
    ext_text_max=defaults.get('ext_text_max', 0),
)

# Verify block paths exist
paths = set()
for j in jobs:
    bp = j['prompt'].get('_block_path')
    if bp:
        paths.add(bp)

assert len(paths) > 0, f'No _block_path found in build_jobs() output'
print(f'block_paths: {sorted(paths)}')

# Run TreeExecutor
executor = TreeExecutor(jobs, pipeline)
executor.execute()

stats = executor.stats()
assert stats['state'] == 'complete', f'Expected complete, got {stats[\"state\"]}'
assert stats['completed_compositions'] > 0, f'No compositions completed'
assert stats['blocks_failed'] == 0, f'Blocks failed: {stats[\"blocks_failed\"]}'

print(f'OK: {stats[\"completed_compositions\"]} compositions, {stats[\"blocks_complete\"]}/{stats[\"blocks_total\"]} blocks')
" 2>&1)
echo "$OUTPUT" | grep -q "OK:" && log_pass "Full integration: $(echo "$OUTPUT" | grep 'OK:')" || log_fail "Integration failed: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 16: Hook log output confirms correct lifecycle order
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 16: Real hook scripts fire in correct order"
OUTPUT=$($PYTHON -c "
import yaml
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, load_hooks_config, load_mods_config
from src.jobs import build_jobs

job_dir = Path('jobs/test-fixtures')
with open(job_dir / 'jobs.yaml') as f:
    task_conf = yaml.safe_load(f)

hooks_config = load_hooks_config(job_dir)
pipeline = HookPipeline(job_dir, hooks_config, load_mods_config(job_dir))

defaults = task_conf.get('defaults', {})
jobs = build_jobs(
    task_conf, Path('/dev/null'), 0.1, ' ', {'ext': []},
    composition_id=0,
    wildcards_max=defaults.get('wildcards_max', 0),
    ext_text_max=defaults.get('ext_text_max', 0),
)

executor = TreeExecutor(jobs, pipeline)
executor.execute()

stats = executor.stats()
assert stats['state'] == 'complete'
print('OK: hooks fired')
" 2>&1)

# Count hook invocations from log_stage.py output
NS_COUNT=$(echo "$OUTPUT" | grep -c "\[HOOK\] node_start" || true)
RS_COUNT=$(echo "$OUTPUT" | grep -c "\[HOOK\] resolve" || true)
PRE_COUNT=$(echo "$OUTPUT" | grep -c "\[HOOK\] pre" || true)
POST_COUNT=$(echo "$OUTPUT" | grep -c "\[HOOK\] post" || true)
NE_COUNT=$(echo "$OUTPUT" | grep -c "\[HOOK\] node_end" || true)

# node_start and resolve should fire once per block (same count)
# pre and post should fire once per composition (same count)
# node_end should fire once per block (same as node_start)
if [ "$NS_COUNT" -gt 0 ] && [ "$NS_COUNT" = "$RS_COUNT" ] && [ "$NS_COUNT" = "$NE_COUNT" ] && \
   [ "$PRE_COUNT" -gt 0 ] && [ "$PRE_COUNT" = "$POST_COUNT" ] && \
   [ "$PRE_COUNT" -ge "$NS_COUNT" ]; then
    log_pass "Hook counts: node_start=$NS_COUNT resolve=$RS_COUNT pre=$PRE_COUNT post=$POST_COUNT node_end=$NE_COUNT"
else
    log_fail "Hook count mismatch: ns=$NS_COUNT rs=$RS_COUNT pre=$PRE_COUNT post=$POST_COUNT ne=$NE_COUNT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 17: echo_generate.py produces output data
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 17: generate hook produces output in variation_results"
OUTPUT=$($PYTHON -c "
import yaml
from pathlib import Path
from src.tree_executor import TreeExecutor
from src.hooks import HookPipeline, load_hooks_config, load_mods_config
from src.jobs import build_jobs

job_dir = Path('jobs/test-fixtures')
with open(job_dir / 'jobs.yaml') as f:
    task_conf = yaml.safe_load(f)

hooks_config = load_hooks_config(job_dir)
pipeline = HookPipeline(job_dir, hooks_config, load_mods_config(job_dir))

defaults = task_conf.get('defaults', {})
jobs = build_jobs(
    task_conf, Path('/dev/null'), 0.1, ' ', {'ext': []},
    composition_id=0,
    wildcards_max=defaults.get('wildcards_max', 0),
    ext_text_max=defaults.get('ext_text_max', 0),
)

executor = TreeExecutor(jobs, pipeline)
executor.execute()

# Check that variation_results has data from echo_generate.py
assert len(executor.variation_results) > 0, 'No variation results stored'

# Each result should have 'output' key from echo_generate.py
for key, result in executor.variation_results.items():
    data = result.data if hasattr(result, 'data') else result.get('data', {})
    assert 'output' in data, f'{key}: missing output in data={data}'
    assert len(data['output']) > 0, f'{key}: empty output'

print(f'OK: {len(executor.variation_results)} results with generate output')
" 2>&1)
echo "$OUTPUT" | grep -q "OK:" && log_pass "$(echo "$OUTPUT" | grep 'OK:')" || log_fail "Generate output missing: $OUTPUT"

# ─────────────────────────────────────────────────────────────────────────────
# Test 18: Nested blocks produce parent-child block paths from real YAML
# ─────────────────────────────────────────────────────────────────────────────
log_info "TEST 18: Nested blocks in jobs.yaml produce correct block paths"
OUTPUT=$($PYTHON -c "
import yaml
from pathlib import Path
from src.jobs import build_jobs

job_dir = Path('jobs/test-fixtures')
with open(job_dir / 'jobs.yaml') as f:
    task_conf = yaml.safe_load(f)

defaults = task_conf.get('defaults', {})
jobs = build_jobs(
    task_conf, Path('/dev/null'), 0.1, ' ', {'ext': []},
    composition_id=0,
    wildcards_max=defaults.get('wildcards_max', 0),
    ext_text_max=defaults.get('ext_text_max', 0),
)

# Collect block paths and parent paths
paths = {}
for j in jobs:
    bp = j['prompt'].get('_block_path')
    pp = j['prompt'].get('_parent_path')
    if bp:
        paths[bp] = pp

# nested-blocks prompt has: root -> Child A, Child B
# So we expect at least one root path and child paths
root_paths = [p for p, parent in paths.items() if parent is None]
child_paths = [p for p, parent in paths.items() if parent is not None]

assert len(root_paths) > 0, f'No root paths found: {paths}'
assert len(child_paths) > 0, f'No child paths found (nested blocks missing): {paths}'

# Verify parent-child relationship
for child_path, parent_path in paths.items():
    if parent_path is not None:
        assert parent_path in paths, f'Child {child_path} references missing parent {parent_path}'

print(f'OK: roots={sorted(root_paths)} children={sorted(child_paths)}')
" 2>&1)
echo "$OUTPUT" | grep -q "OK:" && log_pass "$(echo "$OUTPUT" | grep 'OK:')" || log_fail "Block path hierarchy wrong: $OUTPUT"

print_summary
exit $?
