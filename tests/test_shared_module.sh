#!/bin/bash
# ============================================================================
# E2E Test Suite: Shared Module (PU.shared)
# ============================================================================
# Tests that PU.shared exists with all expected functions and that
# existing functionality (pipeline modal, build composition) still works
# after extracting shared functions.
#
# Usage: ./tests/test_shared_module.sh [--port 8085]
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

print_header "Shared Module (PU.shared)"

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

# Open page with a job that has wildcards
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks&composition=99" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: PU.shared module exists
# ============================================================================
echo ""
log_info "TEST 1: PU.shared module exists"

HAS_SHARED=$(agent-browser eval 'typeof PU.shared === "object"' 2>/dev/null)
[ "$HAS_SHARED" = "true" ] \
    && log_pass "PU.shared exists" \
    || log_fail "PU.shared missing"

# ============================================================================
# TEST 2: All expected functions exist on PU.shared
# ============================================================================
echo ""
log_info "TEST 2: PU.shared function inventory"

FUNCS="getCompositionParams computeLockedTotal isExtWildcard getExtWildcardPath buildThemeSourceMap buildBlockTree renderDimPills formatBytes formatDuration"
for fn in $FUNCS; do
    HAS=$(agent-browser eval "typeof PU.shared.${fn} === 'function'" 2>/dev/null)
    [ "$HAS" = "true" ] \
        && log_pass "PU.shared.${fn} exists" \
        || log_fail "PU.shared.${fn} missing"
done

# ============================================================================
# TEST 3: Old duplicate functions removed
# ============================================================================
echo ""
log_info "TEST 3: Old duplicates removed"

OLD_PIPELINE_FUNCS="_buildBlockTree _renderDimPills _isExtWildcard"
for fn in $OLD_PIPELINE_FUNCS; do
    GONE=$(agent-browser eval "typeof PU.pipeline.${fn}" 2>/dev/null | tr -d '"')
    [ "$GONE" = "undefined" ] \
        && log_pass "PU.pipeline.${fn} removed" \
        || log_fail "PU.pipeline.${fn} still exists (type: $GONE)"
done

OLD_RP_FUNCS="_isExtWildcard _getExtWildcardPath _buildThemeSourceMap _computeLockedTotal"
for fn in $OLD_RP_FUNCS; do
    GONE=$(agent-browser eval "typeof PU.rightPanel.${fn}" 2>/dev/null | tr -d '"')
    [ "$GONE" = "undefined" ] \
        && log_pass "PU.rightPanel.${fn} removed" \
        || log_fail "PU.rightPanel.${fn} still exists (type: $GONE)"
done

OLD_BC_FUNCS="_getCompositionParams _formatBytes"
for fn in $OLD_BC_FUNCS; do
    GONE=$(agent-browser eval "typeof PU.buildComposition.${fn}" 2>/dev/null | tr -d '"')
    [ "$GONE" = "undefined" ] \
        && log_pass "PU.buildComposition.${fn} removed" \
        || log_fail "PU.buildComposition.${fn} still exists (type: $GONE)"
done

# ============================================================================
# TEST 4: getCompositionParams returns correct structure
# ============================================================================
echo ""
log_info "TEST 4: getCompositionParams returns correct shape"

PARAMS_KEYS=$(agent-browser eval 'Object.keys(PU.shared.getCompositionParams()).sort().join(",")' 2>/dev/null | tr -d '"')
EXPECTED="extTextCount,extTextMax,lookup,total,wcMax,wcNames,wildcardCounts"
[ "$PARAMS_KEYS" = "$EXPECTED" ] \
    && log_pass "Keys match: $PARAMS_KEYS" \
    || log_fail "Keys: '$PARAMS_KEYS' (expected '$EXPECTED')"

TOTAL=$(agent-browser eval 'PU.shared.getCompositionParams().total' 2>/dev/null | tr -d '"')
[ "$TOTAL" -gt 0 ] 2>/dev/null \
    && log_pass "Total compositions: $TOTAL" \
    || log_fail "Total: $TOTAL (expected > 0)"

# ============================================================================
# TEST 5: formatBytes works
# ============================================================================
echo ""
log_info "TEST 5: formatBytes"

FMT_B=$(agent-browser eval 'PU.shared.formatBytes(512)' 2>/dev/null | tr -d '"')
[ "$FMT_B" = "512 B" ] \
    && log_pass "512 B: $FMT_B" \
    || log_fail "512 B: '$FMT_B'"

FMT_KB=$(agent-browser eval 'PU.shared.formatBytes(2048)' 2>/dev/null | tr -d '"')
[ "$FMT_KB" = "2.0 KB" ] \
    && log_pass "2 KB: $FMT_KB" \
    || log_fail "2 KB: '$FMT_KB'"

FMT_MB=$(agent-browser eval 'PU.shared.formatBytes(5242880)' 2>/dev/null | tr -d '"')
[ "$FMT_MB" = "5.0 MB" ] \
    && log_pass "5 MB: $FMT_MB" \
    || log_fail "5 MB: '$FMT_MB'"

# ============================================================================
# TEST 6: formatDuration works
# ============================================================================
echo ""
log_info "TEST 6: formatDuration"

FMT_MS=$(agent-browser eval 'PU.shared.formatDuration(450)' 2>/dev/null | tr -d '"')
[ "$FMT_MS" = "450ms" ] \
    && log_pass "450ms: $FMT_MS" \
    || log_fail "450ms: '$FMT_MS'"

FMT_S=$(agent-browser eval 'PU.shared.formatDuration(2500)' 2>/dev/null | tr -d '"')
[ "$FMT_S" = "2.5s" ] \
    && log_pass "2.5s: $FMT_S" \
    || log_fail "2.5s: '$FMT_S'"

# ============================================================================
# TEST 7: buildBlockTree returns block structure
# ============================================================================
echo ""
log_info "TEST 7: buildBlockTree"

BLOCK_COUNT=$(agent-browser eval '
    var prompt = PU.helpers.getActivePrompt();
    var blocks = PU.shared.buildBlockTree(prompt ? prompt.text : []);
    blocks.length
' 2>/dev/null | tr -d '"')
[ "$BLOCK_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Block count: $BLOCK_COUNT" \
    || log_fail "Block count: $BLOCK_COUNT (expected > 0)"

HAS_PATH=$(agent-browser eval '
    var prompt = PU.helpers.getActivePrompt();
    var blocks = PU.shared.buildBlockTree(prompt ? prompt.text : []);
    blocks.length > 0 && typeof blocks[0].path === "string"
' 2>/dev/null)
[ "$HAS_PATH" = "true" ] \
    && log_pass "Block has path field" \
    || log_fail "Block missing path field"

# ============================================================================
# TEST 8: computeLockedTotal works
# ============================================================================
echo ""
log_info "TEST 8: computeLockedTotal"

LOCKED_TOTAL=$(agent-browser eval 'PU.shared.computeLockedTotal({tone: 3, role: 2}, 1, {tone: ["formal", "casual"], role: ["dev"]})' 2>/dev/null | tr -d '"')
[ "$LOCKED_TOTAL" = "2" ] \
    && log_pass "Locked total (2 tones x 1 role): $LOCKED_TOTAL" \
    || log_fail "Locked total: '$LOCKED_TOTAL' (expected 2)"

NO_LOCKS=$(agent-browser eval 'PU.shared.computeLockedTotal({tone: 3, role: 2}, 1, {})' 2>/dev/null | tr -d '"')
[ "$NO_LOCKS" = "1" ] \
    && log_pass "No locks (1x1): $NO_LOCKS" \
    || log_fail "No locks: '$NO_LOCKS' (expected 1)"

# ============================================================================
# TEST 9: Pipeline modal still works (regression)
# ============================================================================
echo ""
log_info "TEST 9: Pipeline modal regression"

agent-browser eval 'PU.pipeline.open()' 2>/dev/null
sleep 1

HAS_TREE=$(agent-browser eval '!!document.querySelector("[data-testid=pu-pipeline-tree]")' 2>/dev/null)
[ "$HAS_TREE" = "true" ] \
    && log_pass "Pipeline tree renders" \
    || log_fail "Pipeline tree missing"

HAS_PILLS=$(agent-browser eval 'document.querySelectorAll(".pu-pipeline-pill").length' 2>/dev/null | tr -d '"')
[ "$HAS_PILLS" -gt 0 ] 2>/dev/null \
    && log_pass "Dimension pills rendered: $HAS_PILLS" \
    || log_fail "No dimension pills"

HAS_NODES=$(agent-browser eval 'document.querySelectorAll(".pu-pipeline-node").length' 2>/dev/null | tr -d '"')
[ "$HAS_NODES" -gt 0 ] 2>/dev/null \
    && log_pass "Block nodes rendered: $HAS_NODES" \
    || log_fail "No block nodes"

agent-browser eval 'PU.pipeline.close()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 10: Build composition panel still works (regression)
# ============================================================================
echo ""
log_info "TEST 10: Build composition regression"

agent-browser eval 'PU.buildComposition.open()' 2>/dev/null
sleep 1

HAS_TOTAL=$(agent-browser eval '!!document.querySelector("[data-testid=pu-build-total]")' 2>/dev/null)
[ "$HAS_TOTAL" = "true" ] \
    && log_pass "Build total renders" \
    || log_fail "Build total missing"

TOTAL_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-total]").textContent.trim()' 2>/dev/null | tr -d '"')
echo "$TOTAL_TEXT" | grep -qE '[0-9]+ compositions' \
    && log_pass "Total text: $TOTAL_TEXT" \
    || log_fail "Total text: '$TOTAL_TEXT'"

agent-browser eval 'PU.buildComposition.close()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 11: Pipeline execution still works (regression)
# ============================================================================
echo ""
log_info "TEST 11: Pipeline execution regression"

SSE_OUTPUT=$(curl -sf -m 15 "$BASE_URL/api/pu/job/test-fixtures/pipeline/run?prompt_id=nested-blocks" 2>&1)
echo "$SSE_OUTPUT" | grep -q '"type": "run_complete"' \
    && log_pass "SSE run_complete received" \
    || log_fail "SSE run_complete missing"

echo "$SSE_OUTPUT" | grep -q '"state": "complete"' \
    && log_pass "Final state: complete" \
    || log_fail "Final state not complete"

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
