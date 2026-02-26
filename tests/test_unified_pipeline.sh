#!/bin/bash
# ============================================================================
# E2E Test Suite: Unified Pipeline Architecture
# ============================================================================
# Tests the EventStream-based architecture:
# - CLI and WebUI produce identical event types for same job
# - Hooks declared in jobs.yaml work via both paths
# - File lock acquired during execution and released after
# - 3-layer hook resolution (defaults.hooks + prompt.hooks)
# - Null sentinel removes default hooks
# - pipeline_runner.create_run shared bootstrap
#
# Usage: ./tests/test_unified_pipeline.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"
PYTHON="./venv/bin/python"

setup_cleanup

print_header "Unified Pipeline Architecture"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server; then
    log_pass "Server is running"
else
    log_fail "Server not running"
    exit 1
fi

# ============================================================================
# TEST 1: CLI and WebUI produce identical event types
# ============================================================================
echo ""
log_info "TEST 1: CLI and WebUI produce identical event types for nested-blocks"

# Run CLI and capture event types
CLI_OUTPUT=$($PYTHON -c "
from src.pipeline_runner import create_run
from src.event_stream import EventStream
from pathlib import Path
job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='nested-blocks')
events = []
stream = EventStream(pipeline, tree_jobs, meta, output_path=str(job_dir))
stream.on_event = lambda e: events.append(e['type'])
stream.run()
for t in sorted(set(events)):
    print(t)
" 2>/dev/null)
CLI_TYPES=$(echo "$CLI_OUTPUT" | sort)

# Run WebUI SSE and capture event types
SSE_RAW=$(curl -sf -N --max-time 15 \
    "$BASE_URL/api/pu/job/test-fixtures/pipeline/run?prompt_id=nested-blocks" 2>/dev/null)
SSE_TYPES=$(echo "$SSE_RAW" | grep "^event:" | sed 's/event: //' | sort -u)

# Both should have init, block_start, composition_complete, artifact, block_complete, run_complete
echo "$CLI_TYPES" | grep -q "init" \
    && log_pass "CLI produces init event" \
    || log_fail "CLI missing init event"

echo "$CLI_TYPES" | grep -q "run_complete" \
    && log_pass "CLI produces run_complete event" \
    || log_fail "CLI missing run_complete event"

echo "$SSE_TYPES" | grep -q "init" \
    && log_pass "WebUI SSE produces init event" \
    || log_fail "WebUI SSE missing init event"

echo "$SSE_TYPES" | grep -q "run_complete" \
    && log_pass "WebUI SSE produces run_complete event" \
    || log_fail "WebUI SSE missing run_complete event"

# Both should have artifact events
echo "$CLI_TYPES" | grep -q "artifact" \
    && log_pass "CLI produces artifact events" \
    || log_fail "CLI missing artifact events"

echo "$SSE_TYPES" | grep -q "artifact" \
    && log_pass "WebUI SSE produces artifact events" \
    || log_fail "WebUI SSE missing artifact events"

# WebUI should additionally have stage events (with_stage_timing=True)
echo "$SSE_TYPES" | grep -q "stage" \
    && log_pass "WebUI SSE produces stage timing events" \
    || log_fail "WebUI SSE missing stage timing events"

# ============================================================================
# TEST 2: Hooks declared in jobs.yaml (inline) work via CLI
# ============================================================================
echo ""
log_info "TEST 2: Hooks declared inline in jobs.yaml work via CLI"

OUTPUT=$($PYTHON -c "
from src.cli.main import main
import sys
sys.argv = ['main', 'test-fixtures', '--tree', '-p', 'nested-blocks', '-c', '0']
main()
" 2>&1)

echo "$OUTPUT" | grep -q '\[ART\]' \
    && log_pass "CLI hooks from jobs.yaml produced artifacts" \
    || log_fail "CLI hooks from jobs.yaml did not produce artifacts"

echo "$OUTPUT" | grep -q 'echo_generate' \
    && log_pass "echo_generate hook ran (from defaults.hooks.generate)" \
    || log_fail "echo_generate hook did not run"

# ============================================================================
# TEST 3: File lock acquired during execution and released after
# ============================================================================
echo ""
log_info "TEST 3: File lock lifecycle"

LOCK_PATH="jobs/test-fixtures/_artifacts/.lock"

# Clean any stale lock
rm -f "$LOCK_PATH"

# Run and check lock is released after
$PYTHON -c "
from src.pipeline_runner import create_run
from src.event_stream import EventStream
from pathlib import Path
job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='nested-blocks')
stream = EventStream(pipeline, tree_jobs, meta, output_path=str(job_dir))
stream.on_event = lambda e: None
stream.run()
" 2>/dev/null

[ ! -f "$LOCK_PATH" ] \
    && log_pass "Lock file released after execution" \
    || log_fail "Lock file still exists after execution"

# Test lock is created during execution
$PYTHON -c "
import time
from src.pipeline_runner import create_run
from src.event_stream import EventStream
from pathlib import Path

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='nested-blocks')

lock_seen = [False]
lock_path = job_dir / '_artifacts' / '.lock'

def check_lock(event):
    if event['type'] == 'block_start' and lock_path.exists():
        lock_seen[0] = True

stream = EventStream(pipeline, tree_jobs, meta, output_path=str(job_dir))
stream.on_event = check_lock
stream.run()
print('LOCK_DURING=' + str(lock_seen[0]))
" 2>/dev/null | grep -q "LOCK_DURING=True" \
    && log_pass "Lock file present during execution" \
    || log_fail "Lock file not observed during execution"

# ============================================================================
# TEST 4: 3-layer hook resolution (defaults.hooks + prompt.hooks)
# ============================================================================
echo ""
log_info "TEST 4: 3-layer hook resolution"

RESOLVE_OUTPUT=$($PYTHON -c "
from src.pipeline_runner import resolve_hooks

# Test: prompt adds post scripts to defaults
defaults = {'generate': [{'script': 'a.py'}], 'pre': [{'script': 'b.py'}]}
prompt = {'post': [{'script': 'c.py'}]}
merged = resolve_hooks(defaults, prompt)

# Should have all 3 stages
assert 'generate' in merged, 'generate missing'
assert 'pre' in merged, 'pre missing'
assert 'post' in merged, 'post missing'
assert len(merged['generate']) == 1
assert len(merged['post']) == 1
print('MERGE_OK')

# Test: prompt appends to existing stage
defaults2 = {'pre': [{'script': 'a.py'}]}
prompt2 = {'pre': [{'script': 'b.py'}]}
merged2 = resolve_hooks(defaults2, prompt2)
assert len(merged2['pre']) == 2, f'Expected 2 pre scripts, got {len(merged2[\"pre\"])}'
print('APPEND_OK')

# Test: null sentinel removes stage
defaults3 = {'pre': [{'script': 'a.py'}], 'generate': [{'script': 'b.py'}]}
prompt3 = {'pre': None}
merged3 = resolve_hooks(defaults3, prompt3)
assert 'pre' not in merged3, 'pre should be removed by null sentinel'
assert 'generate' in merged3
print('NULL_SENTINEL_OK')
" 2>&1)

echo "$RESOLVE_OUTPUT" | grep -q "MERGE_OK" \
    && log_pass "defaults + prompt hooks merge correctly" \
    || log_fail "Hook merge failed"

echo "$RESOLVE_OUTPUT" | grep -q "APPEND_OK" \
    && log_pass "Prompt hooks append to defaults (same stage)" \
    || log_fail "Hook append failed"

echo "$RESOLVE_OUTPUT" | grep -q "NULL_SENTINEL_OK" \
    && log_pass "Null sentinel removes default stage" \
    || log_fail "Null sentinel failed"

# ============================================================================
# TEST 5: create_run shared bootstrap
# ============================================================================
echo ""
log_info "TEST 5: pipeline_runner.create_run shared bootstrap"

BOOTSTRAP_OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.pipeline_runner import create_run

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'

# Test basic creation
pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='nested-blocks')
assert meta['job_id'] == 'test-fixtures'
assert meta['prompt_id'] == 'nested-blocks'
assert len(meta['block_paths']) == 2
assert meta['total_jobs'] == 4
print('CREATE_RUN_OK')

# Test FileNotFoundError
try:
    create_run(Path('/nonexistent/path'))
    print('ERROR_MISSING')
except FileNotFoundError:
    print('FILENOTFOUND_OK')

# Test ValueError for bad prompt_id
try:
    create_run(job_dir, prompt_id='nonexistent-prompt')
    print('ERROR_MISSING')
except ValueError:
    print('VALUEERROR_OK')
" 2>&1)

echo "$BOOTSTRAP_OUTPUT" | grep -q "CREATE_RUN_OK" \
    && log_pass "create_run returns pipeline, tree_jobs, run_meta" \
    || log_fail "create_run failed"

echo "$BOOTSTRAP_OUTPUT" | grep -q "FILENOTFOUND_OK" \
    && log_pass "create_run raises FileNotFoundError for missing jobs.yaml" \
    || log_fail "Missing FileNotFoundError"

echo "$BOOTSTRAP_OUTPUT" | grep -q "VALUEERROR_OK" \
    && log_pass "create_run raises ValueError for bad prompt_id" \
    || log_fail "Missing ValueError"

# ============================================================================
# TEST 6: Dead mods code removed — HookPipeline works without mods_config
# ============================================================================
echo ""
log_info "TEST 6: HookPipeline works without mods_config parameter"

MODS_OUTPUT=$($PYTHON -c "
from pathlib import Path
from src.hooks import HookPipeline, load_hooks_config

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
hooks_config = load_hooks_config(job_dir)

# Should accept only 2 args (job_dir, hooks_config) - no mods_config
pipeline = HookPipeline(job_dir, hooks_config)
result = pipeline.execute_hook('node_start', {'block_path': '0'})
assert result.status == 'success'
print('NO_MODS_OK')

# load_mods_config should return empty dict (deprecated stub)
from src.hooks import load_mods_config
mods = load_mods_config(job_dir)
assert mods == {}
print('DEPRECATED_STUB_OK')
" 2>&1)

echo "$MODS_OUTPUT" | grep -q "NO_MODS_OK" \
    && log_pass "HookPipeline works without mods_config" \
    || log_fail "HookPipeline failed without mods_config"

echo "$MODS_OUTPUT" | grep -q "DEPRECATED_STUB_OK" \
    && log_pass "load_mods_config returns empty dict (deprecated)" \
    || log_fail "load_mods_config not returning empty dict"

# ============================================================================
# TEST 7: EventStream emits all canonical event types
# ============================================================================
echo ""
log_info "TEST 7: EventStream canonical event catalog"

EVENT_OUTPUT=$($PYTHON -c "
from src.pipeline_runner import create_run
from src.event_stream import EventStream
from pathlib import Path

# Test with cross-block pipeline (has artifacts, dependencies, consumed events)
job_dir = Path.cwd() / 'jobs' / 'test-fixtures'
pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='cross-block-pipeline')

event_types = set()
stream = EventStream(pipeline, tree_jobs, meta, output_path=str(job_dir), with_stage_timing=True)
stream.on_event = lambda e: event_types.add(e['type'])
stream.run()

for t in sorted(event_types):
    print(t)
" 2>/dev/null)

echo "$EVENT_OUTPUT" | grep -q "init" \
    && log_pass "EventStream emits: init" \
    || log_fail "Missing: init"
echo "$EVENT_OUTPUT" | grep -q "block_start" \
    && log_pass "EventStream emits: block_start" \
    || log_fail "Missing: block_start"
echo "$EVENT_OUTPUT" | grep -q "stage" \
    && log_pass "EventStream emits: stage (timing)" \
    || log_fail "Missing: stage"
echo "$EVENT_OUTPUT" | grep -q "composition_complete" \
    && log_pass "EventStream emits: composition_complete" \
    || log_fail "Missing: composition_complete"
echo "$EVENT_OUTPUT" | grep -q "artifact" \
    && log_pass "EventStream emits: artifact" \
    || log_fail "Missing: artifact"
echo "$EVENT_OUTPUT" | grep -q "artifact_consumed" \
    && log_pass "EventStream emits: artifact_consumed" \
    || log_fail "Missing: artifact_consumed"
echo "$EVENT_OUTPUT" | grep -q "block_complete" \
    && log_pass "EventStream emits: block_complete" \
    || log_fail "Missing: block_complete"
echo "$EVENT_OUTPUT" | grep -q "run_complete" \
    && log_pass "EventStream emits: run_complete" \
    || log_fail "Missing: run_complete"

# ============================================================================
# TEST 8: email-writer — text_writer hook produces content artifacts in JSONL
# ============================================================================
echo ""
log_info "TEST 8: email-writer prompt with text_writer hook"

EMAIL_OUTPUT=$($PYTHON -c "
from src.pipeline_runner import create_run
from src.event_stream import EventStream
from pathlib import Path
import json

job_dir = Path.cwd() / 'jobs' / 'test-fixtures'

# Clean previous artifacts
import shutil
artifacts_dir = job_dir / '_artifacts'
if artifacts_dir.exists():
    shutil.rmtree(artifacts_dir)

pipeline, tree_jobs, meta = create_run(job_dir, composition_id=0, prompt_id='email-writer')

events = []
stream = EventStream(pipeline, tree_jobs, meta, output_path=str(job_dir))
stream.on_event = lambda e: events.append(e)
stats = stream.run()

# Check artifacts
art_events = [e for e in events if e['type'] == 'artifact']
print(f'ARTIFACT_COUNT={len(art_events)}')

# Check JSONL file exists and has content field
jsonl_path = job_dir / '_artifacts' / 'text_writer' / '0.0.jsonl'
if jsonl_path.exists():
    first_line = json.loads(jsonl_path.read_text().strip().split(chr(10))[0])
    if 'content' in first_line and len(first_line['content']) > 50:
        print('CONTENT_OK')
    if 'friendly' in first_line['content']:
        print('ANNOTATIONS_OK')
else:
    print('JSONL_MISSING')

# Check mod_id is text_writer (not echo_generate)
if art_events and art_events[0]['data']['artifact']['mod_id'] == 'text_writer':
    print('MOD_ID_OK')

print(f'STATS_TOTAL={stats.get(\"artifacts_total\", 0)}')
" 2>/dev/null)

echo "$EMAIL_OUTPUT" | grep -q "ARTIFACT_COUNT=4" \
    && log_pass "email-writer produced 4 artifacts" \
    || log_fail "email-writer artifact count: $(echo "$EMAIL_OUTPUT" | grep ARTIFACT_COUNT)"

echo "$EMAIL_OUTPUT" | grep -q "CONTENT_OK" \
    && log_pass "JSONL has full content (not just preview)" \
    || log_fail "JSONL missing content field or too short"

echo "$EMAIL_OUTPUT" | grep -q "ANNOTATIONS_OK" \
    && log_pass "Annotations flowed into generated content" \
    || log_fail "Annotations not found in content"

echo "$EMAIL_OUTPUT" | grep -q "MOD_ID_OK" \
    && log_pass "mod_id is text_writer (prompt hooks override defaults)" \
    || log_fail "mod_id is wrong (prompt hooks didn't override)"

echo "$EMAIL_OUTPUT" | grep -q "STATS_TOTAL=4" \
    && log_pass "run stats show 4 artifacts total" \
    || log_fail "run stats unexpected: $(echo "$EMAIL_OUTPUT" | grep STATS_TOTAL)"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

rm -f "$LOCK_PATH"
agent-browser close 2>/dev/null
log_pass "Cleanup complete"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
