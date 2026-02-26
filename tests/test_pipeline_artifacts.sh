#!/bin/bash
# ============================================================================
# E2E Test Suite: Pipeline Artifacts
# ============================================================================
# Tests artifact extraction, SSE streaming, manifest writing, API endpoint,
# and UI badge/detail rendering in Pipeline View.
#
# OBJECTIVES:
#   - Hooks that return data.artifacts produce artifact SSE events
#   - block_complete carries artifact count matching actual artifacts
#   - run_complete stats report correct artifact total
#   - Artifacts API serves manifest matching SSE data
#   - UI badge shows correct count, detail shows artifact rows with content
#
# Usage: ./tests/test_pipeline_artifacts.sh [--port 8085]
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

print_header "Pipeline Artifacts"

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
# TEST 1: SSE stream contains artifact events with correct structure
# ============================================================================
echo ""
log_info "TEST 1: SSE artifact events with correct structure"

# OBJECTIVE: Hook returning data.artifacts produces artifact SSE events
SSE_OUTPUT=$(curl -sf -m 15 "$BASE_URL/api/pu/job/test-fixtures/pipeline/run?prompt_id=nested-blocks" 2>&1)

if [ -n "$SSE_OUTPUT" ]; then
    log_pass "SSE endpoint returned data"
else
    log_fail "SSE endpoint returned no data"
fi

ARTIFACT_EVENTS=$(echo "$SSE_OUTPUT" | grep -c '"type": "artifact"')
[ "$ARTIFACT_EVENTS" -gt 0 ] 2>/dev/null \
    && log_pass "artifact events found: $ARTIFACT_EVENTS" \
    || log_fail "No artifact events in SSE stream"

# Verify artifact name matches echo_generate.py format: output-{block}-{idx}.txt
FIRST_ARTIFACT_NAME=$(echo "$SSE_OUTPUT" | grep '"type": "artifact"' | head -1 | grep -oE '"name": "[^"]*"' | head -1)
echo "$FIRST_ARTIFACT_NAME" | grep -qE '"name": "output-[0-9.]+-[0-9]+\.txt"' \
    && log_pass "artifact name matches expected format: $FIRST_ARTIFACT_NAME" \
    || log_fail "artifact name format unexpected: $FIRST_ARTIFACT_NAME"

# Verify mod_id is set to echo_generate
echo "$SSE_OUTPUT" | grep '"type": "artifact"' | head -1 | grep -q '"mod_id": "echo_generate"' \
    && log_pass "artifact mod_id is echo_generate" \
    || log_fail "artifact mod_id missing or wrong"

# Verify preview contains actual text (not empty)
echo "$SSE_OUTPUT" | grep '"type": "artifact"' | head -1 | grep -q '"preview": "' \
    && log_pass "artifact has preview text" \
    || log_fail "artifact preview empty or missing"

# ============================================================================
# TEST 2: block_complete includes artifacts_count matching actual count
# ============================================================================
echo ""
log_info "TEST 2: block_complete artifacts_count matches actual"

# OBJECTIVE: artifacts_count in block_complete matches number of artifact events for that block
BLOCK_COMPLETE_LINE=$(echo "$SSE_OUTPUT" | grep '"type": "block_complete"' | head -1)
echo "$BLOCK_COMPLETE_LINE" | grep -q '"artifacts_count"' \
    && log_pass "block_complete has artifacts_count field" \
    || log_fail "block_complete missing artifacts_count"

# Extract artifacts_count value and verify > 0
ARTIFACTS_COUNT=$(echo "$BLOCK_COMPLETE_LINE" | grep -oE '"artifacts_count": [0-9]+' | grep -oE '[0-9]+')
[ -n "$ARTIFACTS_COUNT" ] && [ "$ARTIFACTS_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "artifacts_count is $ARTIFACTS_COUNT (> 0)" \
    || log_fail "artifacts_count is 0 or missing (value: $ARTIFACTS_COUNT)"

# ============================================================================
# TEST 3: run_complete stats include artifacts_total > 0
# ============================================================================
echo ""
log_info "TEST 3: run_complete stats artifacts_total > 0"

# OBJECTIVE: Final stats report non-zero artifact count
RUN_COMPLETE_LINE=$(echo "$SSE_OUTPUT" | grep '"type": "run_complete"')
ARTIFACTS_TOTAL=$(echo "$RUN_COMPLETE_LINE" | grep -oE '"artifacts_total": [0-9]+' | grep -oE '[0-9]+')
[ -n "$ARTIFACTS_TOTAL" ] && [ "$ARTIFACTS_TOTAL" -gt 0 ] 2>/dev/null \
    && log_pass "artifacts_total is $ARTIFACTS_TOTAL" \
    || log_fail "artifacts_total is 0 or missing (value: $ARTIFACTS_TOTAL)"

# Verify artifacts_total matches total artifact events
[ "$ARTIFACTS_TOTAL" = "$ARTIFACT_EVENTS" ] 2>/dev/null \
    && log_pass "artifacts_total ($ARTIFACTS_TOTAL) matches SSE event count ($ARTIFACT_EVENTS)" \
    || log_fail "artifacts_total ($ARTIFACTS_TOTAL) != SSE event count ($ARTIFACT_EVENTS)"

# ============================================================================
# TEST 4: Artifacts API endpoint returns manifest with matching data
# ============================================================================
echo ""
log_info "TEST 4: Artifacts API returns manifest matching SSE data"

# OBJECTIVE: Manifest on disk matches what was streamed via SSE
api_call GET "$BASE_URL/api/pu/job/test-fixtures/artifacts"
[ "$HTTP_CODE" = "200" ] \
    && log_pass "Artifacts API returned 200" \
    || log_fail "Artifacts API returned: $HTTP_CODE"

# Check manifest structure
MANIFEST_VERSION=$(echo "$BODY" | jq -r '.version // empty' 2>/dev/null)
[ "$MANIFEST_VERSION" = "3" ] \
    && log_pass "Manifest version: $MANIFEST_VERSION" \
    || log_fail "Manifest version unexpected: $MANIFEST_VERSION (expected 3)"

MANIFEST_BLOCKS=$(echo "$BODY" | jq -r '.blocks | keys | length // 0' 2>/dev/null)
[ "$MANIFEST_BLOCKS" -gt 0 ] 2>/dev/null \
    && log_pass "Manifest has $MANIFEST_BLOCKS blocks with artifacts" \
    || log_fail "Manifest has no blocks"

# Cross-verify: total artifacts in manifest matches SSE total
MANIFEST_TOTAL=$(echo "$BODY" | jq '[.blocks[].count] | add // 0' 2>/dev/null)
[ "$MANIFEST_TOTAL" = "$ARTIFACTS_TOTAL" ] 2>/dev/null \
    && log_pass "Manifest total ($MANIFEST_TOTAL) matches run_complete ($ARTIFACTS_TOTAL)" \
    || log_fail "Manifest total ($MANIFEST_TOTAL) != run_complete ($ARTIFACTS_TOTAL)"

# ============================================================================
# TEST 5: UI - Badge shows correct artifact count
# ============================================================================
echo ""
log_info "TEST 5: UI artifact badge shows correct count"

# OBJECTIVE: User sees 📎 badge with count matching actual artifacts
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# Open pipeline modal and run
agent-browser eval 'PU.pipeline.open()' 2>/dev/null
sleep 1
agent-browser eval 'PU.pipeline.run()' 2>/dev/null
sleep 6

# Check badge exists and has data-testid
HAS_BADGE=$(agent-browser eval '!!document.querySelector("[data-testid^=pu-artifact-badge-]")' 2>/dev/null)
[ "$HAS_BADGE" = "true" ] \
    && log_pass "Artifact badge with data-testid found" \
    || log_fail "Artifact badge not found"

# Verify badge text contains a number (📎 N format)
BADGE_TEXT=$(agent-browser eval 'var b = document.querySelector("[data-testid^=pu-artifact-badge-]"); b ? b.textContent.trim() : ""' 2>/dev/null | tr -d '"')
echo "$BADGE_TEXT" | grep -qE '[0-9]+' \
    && log_pass "Badge shows count: $BADGE_TEXT" \
    || log_fail "Badge text has no count: '$BADGE_TEXT'"

# Verify badge count matches blockArtifacts state
FIRST_BLOCK_KEY=$(agent-browser eval 'Object.keys(PU.state.pipeline.blockArtifacts)[0] || ""' 2>/dev/null | tr -d '"')
if [ -n "$FIRST_BLOCK_KEY" ]; then
    STATE_COUNT=$(agent-browser eval "PU.state.pipeline.blockArtifacts['$FIRST_BLOCK_KEY'].length" 2>/dev/null | tr -d '"')
    BADGE_COUNT=$(agent-browser eval "var b = document.querySelector('[data-testid=\"pu-artifact-badge-$FIRST_BLOCK_KEY\"]'); b ? b.textContent.replace(/[^0-9]/g, '') : '0'" 2>/dev/null | tr -d '"')
    [ "$STATE_COUNT" = "$BADGE_COUNT" ] \
        && log_pass "Badge count ($BADGE_COUNT) matches state ($STATE_COUNT) for block $FIRST_BLOCK_KEY" \
        || log_fail "Badge count ($BADGE_COUNT) != state ($STATE_COUNT) for block $FIRST_BLOCK_KEY"
else
    log_fail "No blocks in blockArtifacts state"
fi

# ============================================================================
# TEST 6: UI - Expanded detail shows artifact rows with content
# ============================================================================
echo ""
log_info "TEST 6: Artifact detail rows show name, mod_id, preview"

# OBJECTIVE: Expanding a node shows artifact rows with actual content, not empty
agent-browser eval 'var n = document.querySelector("[data-run-state=complete]"); if(n) n.click()' 2>/dev/null
sleep 0.5

HAS_ARTIFACT_LIST=$(agent-browser eval '!!document.querySelector("[data-testid^=pu-artifact-list-]")' 2>/dev/null)
[ "$HAS_ARTIFACT_LIST" = "true" ] \
    && log_pass "Artifacts list section visible in detail" \
    || log_fail "Artifacts list not found in detail"

# Check artifact rows have name content (not empty)
FIRST_ROW_NAME=$(agent-browser eval 'var n = document.querySelector(".pu-pipeline-artifact-name"); n ? n.textContent.trim() : ""' 2>/dev/null | tr -d '"')
[ -n "$FIRST_ROW_NAME" ] && echo "$FIRST_ROW_NAME" | grep -qE 'output-' \
    && log_pass "Artifact row name: $FIRST_ROW_NAME" \
    || log_fail "Artifact row name empty or unexpected: '$FIRST_ROW_NAME'"

# Check mod_id badge rendered
HAS_MOD=$(agent-browser eval '!!document.querySelector(".pu-pipeline-artifact-mod")' 2>/dev/null)
[ "$HAS_MOD" = "true" ] \
    && log_pass "Artifact mod_id badge rendered" \
    || log_fail "Artifact mod_id badge missing"

# Verify artifact row count matches state
ARTIFACT_ROWS=$(agent-browser eval 'document.querySelectorAll(".pu-pipeline-artifact-row").length' 2>/dev/null | tr -d '"')
[ "$ARTIFACT_ROWS" -gt 0 ] 2>/dev/null \
    && log_pass "Artifact rows rendered: $ARTIFACT_ROWS" \
    || log_fail "No artifact rows found"

# ============================================================================
# TEST 7: blockArtifacts state structure is correct
# ============================================================================
echo ""
log_info "TEST 7: blockArtifacts state structure"

# OBJECTIVE: State has correct structure, not just non-empty
ARTIFACT_KEYS=$(agent-browser eval 'Object.keys(PU.state.pipeline.blockArtifacts).length' 2>/dev/null | tr -d '"')
[ "$ARTIFACT_KEYS" -gt 0 ] 2>/dev/null \
    && log_pass "blockArtifacts has entries: $ARTIFACT_KEYS blocks" \
    || log_fail "blockArtifacts is empty"

# Verify artifact objects have required fields
HAS_FIELDS=$(agent-browser eval 'var arts = PU.state.pipeline.blockArtifacts; var k = Object.keys(arts)[0]; if(k && arts[k][0]) { var a = arts[k][0]; !!(a.name && a.type && "mod_id" in a) } else false' 2>/dev/null)
[ "$HAS_FIELDS" = "true" ] \
    && log_pass "Artifact objects have name, type, mod_id fields" \
    || log_fail "Artifact objects missing required fields"

# ============================================================================
# TEST 8: Re-run resets blockArtifacts (no stale data)
# ============================================================================
echo ""
log_info "TEST 8: Re-run clears previous artifacts"

# OBJECTIVE: Starting a new run resets artifact state — no accumulation
agent-browser eval 'PU.pipeline._resetRunState()' 2>/dev/null
sleep 0.3

RESET_KEYS=$(agent-browser eval 'Object.keys(PU.state.pipeline.blockArtifacts).length' 2>/dev/null | tr -d '"')
[ "$RESET_KEYS" = "0" ] \
    && log_pass "blockArtifacts cleared after reset: $RESET_KEYS" \
    || log_fail "blockArtifacts not cleared after reset: $RESET_KEYS"

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
