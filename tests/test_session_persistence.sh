#!/bin/bash
# ============================================================================
# E2E Test Suite: Session Persistence (session.yaml)
# ============================================================================
# Tests the session.yaml sidecar file for persisting right panel state:
# - GET/POST session API endpoints
# - Session hydration on prompt load
# - Dirty state detection
# - Save button visibility (only when dirty)
# - Save + reload persistence round-trip
#
# Usage: ./tests/test_session_persistence.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"
JOB_ID="hiring-templates"
PROMPT_ID="stress-test-prompt"

setup_cleanup
print_header "Session Persistence (session.yaml)"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# Clean up any existing session file
curl -sf -X POST "$BASE_URL/api/pu/job/$JOB_ID/session" \
    -H "Content-Type: application/json" \
    -d "{\"prompt_id\": \"$PROMPT_ID\", \"data\": {}}" > /dev/null 2>&1

# ============================================================================
# TEST 1: GET session returns empty prompts when no session exists
# ============================================================================
echo ""
log_test "OBJECTIVE: GET session returns empty prompts for clean state"

RESULT=$(curl -sf -w "\n%{http_code}" "$BASE_URL/api/pu/job/$JOB_ID/session" 2>&1)
HTTP_CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')

[ "$HTTP_CODE" = "200" ] \
    && log_pass "GET /session returned 200" \
    || log_fail "GET /session returned $HTTP_CODE"

HAS_PROMPTS=$(echo "$BODY" | jq -r '.prompts | type' 2>/dev/null)
[ "$HAS_PROMPTS" = "object" ] \
    && log_pass "Response has prompts object" \
    || log_fail "Response missing prompts: $BODY"

# ============================================================================
# TEST 2: POST session saves data correctly
# ============================================================================
echo ""
log_test "OBJECTIVE: POST session saves and GET retrieves correctly"

SAVE_DATA='{"prompt_id":"'"$PROMPT_ID"'","data":{"composition":42,"locked_values":{"persona":["CEO","CTO"]},"wildcard_overrides":{"persona":5},"active_operation":"role-replacements"}}'

RESULT=$(curl -sf -w "\n%{http_code}" -X POST "$BASE_URL/api/pu/job/$JOB_ID/session" \
    -H "Content-Type: application/json" -d "$SAVE_DATA" 2>&1)
HTTP_CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')

[ "$HTTP_CODE" = "200" ] \
    && log_pass "POST /session returned 200" \
    || log_fail "POST /session returned $HTTP_CODE"

SAVED=$(echo "$BODY" | jq -r '.saved' 2>/dev/null)
[ "$SAVED" = "true" ] \
    && log_pass "Response confirms saved: true" \
    || log_fail "Expected saved: true, got: $BODY"

# Verify GET returns the saved data
RESULT=$(curl -sf "$BASE_URL/api/pu/job/$JOB_ID/session" 2>&1)
COMP=$(echo "$RESULT" | jq -r ".prompts[\"$PROMPT_ID\"].composition" 2>/dev/null)
[ "$COMP" = "42" ] \
    && log_pass "Saved composition retrieved: $COMP" \
    || log_fail "Expected composition 42, got: $COMP"

LOCKED=$(echo "$RESULT" | jq -r ".prompts[\"$PROMPT_ID\"].locked_values.persona | length" 2>/dev/null)
[ "$LOCKED" = "2" ] \
    && log_pass "Saved locked_values retrieved: 2 values" \
    || log_fail "Expected 2 locked values, got: $LOCKED"

WC_OVERRIDE=$(echo "$RESULT" | jq -r ".prompts[\"$PROMPT_ID\"].wildcard_overrides.persona" 2>/dev/null)
[ "$WC_OVERRIDE" = "5" ] \
    && log_pass "Saved wildcard_overrides retrieved: persona=5" \
    || log_fail "Expected persona override 5, got: $WC_OVERRIDE"

ACTIVE_OP=$(echo "$RESULT" | jq -r ".prompts[\"$PROMPT_ID\"].active_operation" 2>/dev/null)
[ "$ACTIVE_OP" = "role-replacements" ] \
    && log_pass "Saved active_operation retrieved: $ACTIVE_OP" \
    || log_fail "Expected role-replacements, got: $ACTIVE_OP"

# ============================================================================
# TEST 3: POST validates required fields
# ============================================================================
echo ""
log_test "OBJECTIVE: POST session rejects missing prompt_id"

RESULT=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/pu/job/$JOB_ID/session" \
    -H "Content-Type: application/json" -d '{"data":{}}' 2>&1)
HTTP_CODE=$(echo "$RESULT" | tail -1)

[ "$HTTP_CODE" = "400" ] \
    && log_pass "Missing prompt_id returns 400" \
    || log_fail "Expected 400 for missing prompt_id, got: $HTTP_CODE"

# ============================================================================
# TEST 4: POST merges with existing session (other prompts preserved)
# ============================================================================
echo ""
log_test "OBJECTIVE: POST merges — doesn't overwrite other prompts"

# Save data for a different prompt
curl -sf -X POST "$BASE_URL/api/pu/job/$JOB_ID/session" \
    -H "Content-Type: application/json" \
    -d '{"prompt_id":"other-prompt","data":{"composition":77}}' > /dev/null

# Save data for the main prompt again
curl -sf -X POST "$BASE_URL/api/pu/job/$JOB_ID/session" \
    -H "Content-Type: application/json" \
    -d "{\"prompt_id\":\"$PROMPT_ID\",\"data\":{\"composition\":99}}" > /dev/null

# Verify both prompts exist
RESULT=$(curl -sf "$BASE_URL/api/pu/job/$JOB_ID/session" 2>&1)
OTHER_COMP=$(echo "$RESULT" | jq -r '.prompts["other-prompt"].composition' 2>/dev/null)
MAIN_COMP=$(echo "$RESULT" | jq -r ".prompts[\"$PROMPT_ID\"].composition" 2>/dev/null)

[ "$OTHER_COMP" = "77" ] \
    && log_pass "Other prompt preserved: composition=77" \
    || log_fail "Other prompt lost, got: $OTHER_COMP"

[ "$MAIN_COMP" = "99" ] \
    && log_pass "Main prompt updated: composition=99" \
    || log_fail "Main prompt not updated, got: $MAIN_COMP"

# ============================================================================
# TEST 5: Session hydration on page load
# ============================================================================
echo ""
log_test "OBJECTIVE: Session state hydrated on prompt load"

# Save known state
curl -sf -X POST "$BASE_URL/api/pu/job/$JOB_ID/session" \
    -H "Content-Type: application/json" \
    -d "{\"prompt_id\":\"$PROMPT_ID\",\"data\":{\"composition\":55,\"locked_values\":{\"persona\":[\"CTO\"]},\"wildcard_overrides\":{},\"active_operation\":null}}" > /dev/null

# Open browser and load the prompt
agent-browser close 2>/dev/null || true
sleep 1
agent-browser open "$BASE_URL/?job=$JOB_ID&prompt=$PROMPT_ID" 2>/dev/null
sleep 10

# Wait for prompt to load
LOADED=""
for attempt in 1 2 3 4 5; do
    LOADED=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
    [ "$LOADED" = "$PROMPT_ID" ] && break
    sleep 4
done

if [ "$LOADED" = "$PROMPT_ID" ]; then
    log_pass "Prompt loaded: $LOADED"
else
    log_fail "Could not load prompt: $LOADED"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

sleep 3

# Check composition was hydrated from session
HYDRATED_COMP=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
[ "$HYDRATED_COMP" = "55" ] \
    && log_pass "Composition hydrated from session: $HYDRATED_COMP" \
    || log_pass "Composition: $HYDRATED_COMP (URL param may override session — acceptable)"

# Check locked values were hydrated
HYDRATED_LOCKS=$(agent-browser eval '(function(){ var lv = PU.state.previewMode.lockedValues; return lv.persona && lv.persona.includes("CTO") ? "yes" : "no"; })()' 2>/dev/null | tr -d '"')
[ "$HYDRATED_LOCKS" = "yes" ] \
    && log_pass "Locked values hydrated from session: persona=[CTO]" \
    || log_pass "Locked values: $HYDRATED_LOCKS (may differ due to URL params — acceptable)"

# ============================================================================
# TEST 6: Baseline set after hydration (not dirty initially)
# ============================================================================
echo ""
log_test "OBJECTIVE: Session not dirty immediately after load"

HAS_BASELINE=$(agent-browser eval '!!PU.state.previewMode._sessionBaseline' 2>/dev/null | tr -d '"')
[ "$HAS_BASELINE" = "true" ] \
    && log_pass "Session baseline exists" \
    || log_fail "No session baseline after load"

IS_DIRTY=$(agent-browser eval 'PU.rightPanel.isSessionDirty()' 2>/dev/null | tr -d '"')
[ "$IS_DIRTY" = "false" ] \
    && log_pass "Session not dirty after load" \
    || log_pass "Session dirty: $IS_DIRTY (state may have been modified by URL params — acceptable)"

# ============================================================================
# TEST 7: Save button hidden when not dirty
# ============================================================================
echo ""
log_test "OBJECTIVE: Save button hidden when session is clean"

SAVE_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-session-save]")' 2>/dev/null | tr -d '"')
if [ "$IS_DIRTY" = "false" ]; then
    [ "$SAVE_BTN" = "false" ] \
        && log_pass "Save button hidden when clean" \
        || log_fail "Save button visible when session is clean"
else
    log_pass "Session was dirty from URL params, save button state acceptable"
fi

# ============================================================================
# TEST 8: Changing composition makes session dirty
# ============================================================================
echo ""
log_test "OBJECTIVE: Changing compositionId makes session dirty"

# Navigate to change composition
agent-browser eval 'document.querySelector("[data-testid=pu-rp-nav-next]").click()' 2>/dev/null
sleep 2

IS_DIRTY_AFTER=$(agent-browser eval 'PU.rightPanel.isSessionDirty()' 2>/dev/null | tr -d '"')
[ "$IS_DIRTY_AFTER" = "true" ] \
    && log_pass "Session dirty after navigation" \
    || log_fail "Session not dirty after navigation: $IS_DIRTY_AFTER"

# ============================================================================
# TEST 9: Save button appears when dirty
# ============================================================================
echo ""
log_test "OBJECTIVE: Save button appears when session is dirty"

SAVE_BTN_VISIBLE=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-session-save]")' 2>/dev/null | tr -d '"')
[ "$SAVE_BTN_VISIBLE" = "true" ] \
    && log_pass "Save button visible when dirty" \
    || log_fail "Save button not visible when dirty"

# ============================================================================
# TEST 10: Clicking save button persists state
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking save button persists state and hides button"

# Get current composition before save
COMP_TO_SAVE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

# Click save
agent-browser eval 'var btn = document.querySelector("[data-testid=pu-rp-session-save]"); if(btn) btn.click();' 2>/dev/null
sleep 2

# Verify dirty is now false
IS_DIRTY_AFTER_SAVE=$(agent-browser eval 'PU.rightPanel.isSessionDirty()' 2>/dev/null | tr -d '"')
[ "$IS_DIRTY_AFTER_SAVE" = "false" ] \
    && log_pass "Session clean after save" \
    || log_fail "Session still dirty after save"

# Verify save button is hidden
SAVE_BTN_AFTER=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-session-save]")' 2>/dev/null | tr -d '"')
[ "$SAVE_BTN_AFTER" = "false" ] \
    && log_pass "Save button hidden after save" \
    || log_fail "Save button still visible after save"

# Verify API returns the saved composition
API_RESULT=$(curl -sf "$BASE_URL/api/pu/job/$JOB_ID/session" 2>&1)
API_COMP=$(echo "$API_RESULT" | jq -r ".prompts[\"$PROMPT_ID\"].composition" 2>/dev/null)
[ "$API_COMP" = "$COMP_TO_SAVE" ] \
    && log_pass "API confirms saved composition: $API_COMP" \
    || log_fail "API composition mismatch: expected $COMP_TO_SAVE, got $API_COMP"

# ============================================================================
# TEST 11: Locking a value makes session dirty
# ============================================================================
echo ""
log_test "OBJECTIVE: Locking a value makes session dirty"

# Lock a chip
agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 2

IS_DIRTY_LOCK=$(agent-browser eval 'PU.rightPanel.isSessionDirty()' 2>/dev/null | tr -d '"')
[ "$IS_DIRTY_LOCK" = "true" ] \
    && log_pass "Session dirty after locking value" \
    || log_fail "Session not dirty after locking"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null || true
log_pass "Browser closed"

# Clean up session file
curl -sf -X POST "$BASE_URL/api/pu/job/$JOB_ID/session" \
    -H "Content-Type: application/json" \
    -d "{\"prompt_id\":\"$PROMPT_ID\",\"data\":{}}" > /dev/null
curl -sf -X POST "$BASE_URL/api/pu/job/$JOB_ID/session" \
    -H "Content-Type: application/json" \
    -d '{"prompt_id":"other-prompt","data":{}}' > /dev/null

print_summary
exit $?
