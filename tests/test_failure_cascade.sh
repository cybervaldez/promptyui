#!/bin/bash
# ============================================================================
# E2E Test Suite: Failure Cascade via depends_on
# ============================================================================
# Tests that when a dependency block fails, dependent blocks are blocked.
#
# Uses the "fail-cascade-pipeline" prompt in test-fixtures which has:
#   Block 0: "This block will fail" (_force_fail: true annotation)
#   Block 1: "This block depends on the failing block" (_depends_on: ["0"])
#
# Expected behavior:
#   - Block 0 attempts execution, generate hook returns error
#   - Block 0 state -> failed, emits block_failed
#   - Block 1 state -> blocked (cascade from block 0 failure)
#   - Block 1 emits block_blocked, never executes
#   - run_complete stats: blocks_failed=1, blocks_blocked=1
#
# Usage: ./tests/test_failure_cascade.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"
JOB_ID="test-fixtures"
PROMPT_ID="fail-cascade-pipeline"
SSE_URL="$BASE_URL/api/pu/job/$JOB_ID/pipeline/run?prompt_id=$PROMPT_ID"

setup_cleanup

print_header "Failure Cascade via depends_on"

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

# Clean previous artifacts
rm -rf "$(cd "$SCRIPT_DIR/.." && pwd)/jobs/$JOB_ID/_artifacts"

# ============================================================================
# TEST 1: SSE stream — block_failed event for block 0
# ============================================================================
echo ""
log_info "TEST 1: Block 0 emits block_failed event"

# Capture SSE output
SSE_OUTPUT=$(curl -sf --max-time 15 "$SSE_URL" 2>&1)

# Find block_failed event using jq
BLOCK_FAILED=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    if [ "$TYPE" = "block_failed" ]; then
        echo "$DATA" | jq -r '.block_path' 2>/dev/null
        break
    fi
done)

[ "$BLOCK_FAILED" = "0" ] \
    && log_pass "block_failed emitted for block 0" \
    || log_fail "block_failed not emitted for block 0 (got: '$BLOCK_FAILED')"

# ============================================================================
# TEST 2: SSE stream — block_blocked event for block 1
# ============================================================================
echo ""
log_info "TEST 2: Block 1 emits block_blocked event (cascade from block 0)"

BLOCK_BLOCKED=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    if [ "$TYPE" = "block_blocked" ]; then
        echo "$DATA" | jq -r '.block_path' 2>/dev/null
        break
    fi
done)

[ "$BLOCK_BLOCKED" = "1" ] \
    && log_pass "block_blocked emitted for block 1 (cascade)" \
    || log_fail "block_blocked not emitted for block 1 (got: '$BLOCK_BLOCKED')"

# ============================================================================
# TEST 3: Block 1 never started (no block_start for block 1)
# ============================================================================
echo ""
log_info "TEST 3: Block 1 never executed (no block_start event)"

BLOCK1_STARTED=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    BP=$(echo "$DATA" | jq -r '.block_path // empty' 2>/dev/null)
    if [ "$TYPE" = "block_start" ] && [ "$BP" = "1" ]; then
        echo "yes"
        break
    fi
done)

[ -z "$BLOCK1_STARTED" ] \
    && log_pass "Block 1 was never started (correctly skipped)" \
    || log_fail "Block 1 was started despite dependency failure"

# ============================================================================
# TEST 4: run_complete stats show failure and blocked counts
# ============================================================================
echo ""
log_info "TEST 4: run_complete stats reflect failure cascade"

RUN_COMPLETE_DATA=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    if [ "$TYPE" = "run_complete" ]; then
        echo "$DATA"
        break
    fi
done)

[ -n "$RUN_COMPLETE_DATA" ] \
    && log_pass "run_complete event received" \
    || log_fail "run_complete event not found"

STATS_FAILED=$(echo "$RUN_COMPLETE_DATA" | jq -r '.stats.blocks_failed // empty' 2>/dev/null)
STATS_BLOCKED=$(echo "$RUN_COMPLETE_DATA" | jq -r '.stats.blocks_blocked // empty' 2>/dev/null)
STATS_COMPLETE=$(echo "$RUN_COMPLETE_DATA" | jq -r '.stats.blocks_complete // empty' 2>/dev/null)
STATS_STATE=$(echo "$RUN_COMPLETE_DATA" | jq -r '.stats.state // empty' 2>/dev/null)

[ "$STATS_FAILED" = "1" ] \
    && log_pass "stats.blocks_failed: 1" \
    || log_fail "stats.blocks_failed unexpected: '$STATS_FAILED'"

[ "$STATS_BLOCKED" = "1" ] \
    && log_pass "stats.blocks_blocked: 1" \
    || log_fail "stats.blocks_blocked unexpected: '$STATS_BLOCKED'"

[ "$STATS_COMPLETE" = "0" ] \
    && log_pass "stats.blocks_complete: 0 (no block succeeded)" \
    || log_fail "stats.blocks_complete unexpected: '$STATS_COMPLETE'"

[ "$STATS_STATE" = "failed" ] \
    && log_pass "stats.state: failed" \
    || log_fail "stats.state unexpected: '$STATS_STATE'"

# ============================================================================
# TEST 5: No artifacts produced (block 0 failed, block 1 blocked)
# ============================================================================
echo ""
log_info "TEST 5: No artifacts produced when pipeline fails"

STATS_ARTIFACTS=$(echo "$RUN_COMPLETE_DATA" | jq -r '.stats.artifacts_total // 0' 2>/dev/null)
[ "$STATS_ARTIFACTS" = "0" ] \
    && log_pass "stats.artifacts_total: 0 (no artifacts from failed pipeline)" \
    || log_fail "stats.artifacts_total unexpected: '$STATS_ARTIFACTS'"

# ============================================================================
# TEST 6: Execution order — block 0 attempted before block 1
# ============================================================================
echo ""
log_info "TEST 6: Execution order — block 0 started before block 1 was blocked"

# Collect event types in order
EVENT_ORDER=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    BP=$(echo "$DATA" | jq -r '.block_path // empty' 2>/dev/null)
    if [ "$TYPE" = "block_start" ] || [ "$TYPE" = "block_failed" ] || [ "$TYPE" = "block_blocked" ]; then
        echo "${TYPE}:${BP}"
    fi
done | tr '\n' ',')

# block_start:0 must appear before block_blocked:1
echo "$EVENT_ORDER" | grep -q 'block_start:0.*block_blocked:1' \
    && log_pass "Correct order: block 0 started before block 1 blocked: $EVENT_ORDER" \
    || log_fail "Unexpected event order: $EVENT_ORDER"

# block_failed:0 must appear before block_blocked:1
echo "$EVENT_ORDER" | grep -q 'block_failed:0.*block_blocked:1' \
    && log_pass "Correct order: block 0 failed before block 1 blocked" \
    || log_fail "block_failed:0 did not precede block_blocked:1"

# ============================================================================
# TEST 7: No manifest written (no artifacts to manifest)
# ============================================================================
echo ""
log_info "TEST 7: No manifest written for fully failed pipeline"

ARTIFACT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)/jobs/$JOB_ID/_artifacts"

# The artifacts API should return empty or no-artifacts response
api_call GET "$BASE_URL/api/pu/job/$JOB_ID/artifacts"
# After a failed run, manifest might not exist at all or have empty blocks
MANIFEST_BLOCKS=$(echo "$BODY" | jq '.blocks | length // 0' 2>/dev/null)
[ "$MANIFEST_BLOCKS" = "0" ] || [ -z "$MANIFEST_BLOCKS" ] \
    && log_pass "No artifact blocks in manifest after failed pipeline" \
    || log_fail "Unexpected manifest blocks: $MANIFEST_BLOCKS"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null
log_pass "Cleanup complete"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
