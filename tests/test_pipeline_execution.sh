#!/bin/bash
# ============================================================================
# E2E Test Suite: Pipeline Execution (Phase 2)
# ============================================================================
# Tests live pipeline execution via SSE endpoint and UI controls.
# Verifies: SSE streams events, Run button triggers execution,
# block states change, progress updates, completion state.
#
# Usage: ./tests/test_pipeline_execution.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

setup_cleanup

print_header "Pipeline Execution (Phase 2 - SSE)"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server; then
    log_pass "Server is running"
else
    log_fail "Server not running at $BASE_URL"
    exit 1
fi

# ============================================================================
# TEST 1: SSE endpoint returns event stream for test-fixtures
# ============================================================================
echo ""
log_info "TEST 1: SSE endpoint responds with event stream"

# Use curl with timeout to capture SSE events (test-fixtures runs fast)
SSE_OUTPUT=$(curl -sf -m 15 "$BASE_URL/api/pu/job/test-fixtures/pipeline/run?prompt_id=nested-blocks" 2>&1)
SSE_EXIT=$?

# Check we got output
if [ -n "$SSE_OUTPUT" ]; then
    log_pass "SSE endpoint returned data"
else
    log_fail "SSE endpoint returned no data (exit=$SSE_EXIT)"
fi

# ============================================================================
# TEST 2: SSE stream contains init event
# ============================================================================
echo ""
log_info "TEST 2: SSE stream contains init event"

echo "$SSE_OUTPUT" | grep -q '"type": "init"' \
    && log_pass "init event present" \
    || log_fail "init event missing"

# ============================================================================
# TEST 3: SSE stream contains block_start events
# ============================================================================
echo ""
log_info "TEST 3: block_start events"

BLOCK_STARTS=$(echo "$SSE_OUTPUT" | grep -c 'block_start')
[ "$BLOCK_STARTS" -gt 0 ] 2>/dev/null \
    && log_pass "block_start events: $BLOCK_STARTS" \
    || log_fail "No block_start events found"

# ============================================================================
# TEST 4: SSE stream contains composition_complete events
# ============================================================================
echo ""
log_info "TEST 4: composition_complete events"

COMP_COMPLETE=$(echo "$SSE_OUTPUT" | grep -c 'composition_complete')
[ "$COMP_COMPLETE" -gt 0 ] 2>/dev/null \
    && log_pass "composition_complete events: $COMP_COMPLETE" \
    || log_fail "No composition_complete events found"

# ============================================================================
# TEST 5: SSE stream contains block_complete events
# ============================================================================
echo ""
log_info "TEST 5: block_complete events"

BLOCK_COMPLETE=$(echo "$SSE_OUTPUT" | grep -c 'block_complete')
[ "$BLOCK_COMPLETE" -gt 0 ] 2>/dev/null \
    && log_pass "block_complete events: $BLOCK_COMPLETE" \
    || log_fail "No block_complete events found"

# ============================================================================
# TEST 6: SSE stream contains run_complete event with stats
# ============================================================================
echo ""
log_info "TEST 6: run_complete event with stats"

echo "$SSE_OUTPUT" | grep -q '"type": "run_complete"' \
    && log_pass "run_complete event present" \
    || log_fail "run_complete event missing"

echo "$SSE_OUTPUT" | grep -q '"state": "complete"' \
    && log_pass "Final state is complete" \
    || log_fail "Final state not complete"

# ============================================================================
# TEST 7: SSE stream contains stage timing events
# ============================================================================
echo ""
log_info "TEST 7: Stage timing events"

STAGE_EVENTS=$(echo "$SSE_OUTPUT" | grep -c '"type": "stage"')
[ "$STAGE_EVENTS" -gt 0 ] 2>/dev/null \
    && log_pass "stage events: $STAGE_EVENTS" \
    || log_fail "No stage events found"

# Check for expected stages
echo "$SSE_OUTPUT" | grep '"stage": "generate"' | head -1 | grep -q 'time_ms' \
    && log_pass "generate stage has timing" \
    || log_fail "generate stage timing missing"

# ============================================================================
# TEST 8: Pipeline stop endpoint returns 404 when no executor active
# ============================================================================
echo ""
log_info "TEST 8: Stop endpoint with no active executor"

STOP_RESULT=$(curl -sf -w "\n%{http_code}" "$BASE_URL/api/pu/job/test-fixtures/pipeline/stop" 2>&1)
STOP_CODE=$(echo "$STOP_RESULT" | tail -1)
[ "$STOP_CODE" = "404" ] \
    && log_pass "Stop returns 404 when no executor" \
    || log_fail "Stop returned: $STOP_CODE"

# ============================================================================
# TEST 9: UI - Pipeline modal has Run button and progress bar
# ============================================================================
echo ""
log_info "TEST 9: UI controls exist"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# Open pipeline modal
agent-browser eval 'PU.pipeline.open()' 2>/dev/null
sleep 1

HAS_ACTION_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=pu-pipeline-action-btn]")' 2>/dev/null)
[ "$HAS_ACTION_BTN" = "true" ] \
    && log_pass "Action button exists" \
    || log_fail "Action button missing"

HAS_PROGRESS=$(agent-browser eval '!!document.querySelector("[data-testid=pu-pipeline-progress]")' 2>/dev/null)
[ "$HAS_PROGRESS" = "true" ] \
    && log_pass "Progress bar exists" \
    || log_fail "Progress bar missing"

# Check initial button state is "Run"
BTN_STATE=$(agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-action-btn]").dataset.runState' 2>/dev/null | tr -d '"')
[ "$BTN_STATE" = "idle" ] \
    && log_pass "Button initial state: idle" \
    || log_fail "Button state: $BTN_STATE (expected idle)"

# ============================================================================
# TEST 10: UI - Run button triggers execution and completes
# ============================================================================
echo ""
log_info "TEST 10: Run triggers execution"

# Click Run
agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-action-btn]").click()' 2>/dev/null

# Wait for execution to complete (test-fixtures is fast)
sleep 5

# Check final state
RUN_STATE=$(agent-browser eval 'PU.state.pipeline.runState' 2>/dev/null | tr -d '"')
[ "$RUN_STATE" = "complete" ] \
    && log_pass "Run state: complete" \
    || log_fail "Run state: $RUN_STATE (expected complete)"

# Check button changed
BTN_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-action-btn]").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$BTN_TEXT" = "Done" ] \
    && log_pass "Button text: Done" \
    || log_fail "Button text: '$BTN_TEXT' (expected Done)"

# ============================================================================
# TEST 11: UI - Block nodes changed state after execution
# ============================================================================
echo ""
log_info "TEST 11: Block node states updated"

# Check at least one node is complete
COMPLETE_NODES=$(agent-browser eval 'document.querySelectorAll("[data-run-state=complete]").length' 2>/dev/null | tr -d '"')
[ "$COMPLETE_NODES" -gt 0 ] 2>/dev/null \
    && log_pass "Complete nodes: $COMPLETE_NODES" \
    || log_fail "No complete nodes found"

# ============================================================================
# TEST 12: UI - Progress bar shows completion
# ============================================================================
echo ""
log_info "TEST 12: Progress bar updated"

PROGRESS_LABEL=$(agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-progress-label]").textContent.trim()' 2>/dev/null | tr -d '"')
# Should show something like "4 / 4" or "6 / 6"
echo "$PROGRESS_LABEL" | grep -qE '[0-9]+ / [0-9]+' \
    && log_pass "Progress label: $PROGRESS_LABEL" \
    || log_fail "Progress label: '$PROGRESS_LABEL'"

FILL_WIDTH=$(agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-progress-fill]").style.width' 2>/dev/null | tr -d '"')
[ "$FILL_WIDTH" = "100%" ] \
    && log_pass "Progress bar full: $FILL_WIDTH" \
    || log_fail "Progress bar: $FILL_WIDTH (expected 100%)"

# ============================================================================
# TEST 13: UI - Node expansion shows stage detail
# ============================================================================
echo ""
log_info "TEST 13: Node expansion"

# Click a complete node to expand it
agent-browser eval 'var n = document.querySelector("[data-run-state=complete]"); if(n) n.click()' 2>/dev/null
sleep 0.5

HAS_DETAIL=$(agent-browser eval '!!document.querySelector(".pu-pipeline-node-detail")' 2>/dev/null)
[ "$HAS_DETAIL" = "true" ] \
    && log_pass "Detail panel expanded" \
    || log_fail "Detail panel not found"

# Check detail has stage breakdown
HAS_STAGES=$(agent-browser eval '!!document.querySelector(".pu-pipeline-detail-stages")' 2>/dev/null)
[ "$HAS_STAGES" = "true" ] \
    && log_pass "Stage breakdown visible" \
    || log_fail "Stage breakdown missing"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null
log_pass "Browser closed"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
