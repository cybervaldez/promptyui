#!/bin/bash
# ============================================================================
# E2E Test Suite: Right Panel Phase 2 + Phase 3 (Operations)
# ============================================================================
# Tests operation selection, replaced-val chips, unmatched warnings,
# right-click replacement popover, and variant label on export.
#
# Uses hiring-templates job which has operations/role-replacements.yaml
#
# Usage: ./tests/test_right_panel_operations.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Right Panel Operations (Phase 2 + Phase 3)"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ============================================================================
# TEST 1: Operations API - List operations for hiring-templates
# ============================================================================
echo ""
log_test "OBJECTIVE: API returns operations list for hiring-templates"

api_call GET "$BASE_URL/api/pu/job/hiring-templates/operations"
[ "$HTTP_CODE" = "200" ] \
    && log_pass "GET /operations returned 200" \
    || log_fail "GET /operations returned $HTTP_CODE"

OPS_LIST=$(json_get "$BODY" '.operations' '[]')
echo "$OPS_LIST" | grep -q "role-replacements" \
    && log_pass "Found role-replacements in operations list" \
    || log_fail "role-replacements not in operations list: $OPS_LIST"

# ============================================================================
# TEST 2: Operations API - Load single operation
# ============================================================================
echo ""
log_test "OBJECTIVE: API returns normalized operation data"

api_call GET "$BASE_URL/api/pu/job/hiring-templates/operation/role-replacements"
[ "$HTTP_CODE" = "200" ] \
    && log_pass "GET /operation/role-replacements returned 200" \
    || log_fail "GET /operation/role-replacements returned $HTTP_CODE"

# Check normalized format has mappings
HAS_MAPPINGS=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if 'mappings' in d and 'role' in d['mappings'] else 'false')" 2>/dev/null)
[ "$HAS_MAPPINGS" = "true" ] \
    && log_pass "Operation has normalized mappings with 'role' wildcard" \
    || log_fail "Expected mappings with 'role' key: $BODY"

# ============================================================================
# TEST 3: Operations API - 404 for missing operation
# ============================================================================
echo ""
log_test "OBJECTIVE: API returns 404 for non-existent operation"

api_call GET "$BASE_URL/api/pu/job/hiring-templates/operation/does-not-exist"
[ "$HTTP_CODE" = "404" ] \
    && log_pass "GET non-existent operation returned 404" \
    || log_fail "Expected 404, got $HTTP_CODE"

# ── Browser setup: Load hiring-templates with stress-test-prompt ──────
echo ""
log_info "Loading hiring-templates / stress-test-prompt..."
agent-browser close 2>/dev/null || true
sleep 1
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt" 2>/dev/null
sleep 10

# Verify prompt loaded (retry up to 5 times with longer waits)
PROMPT_NAME=""
for attempt in 1 2 3 4 5; do
    PROMPT_NAME=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
    [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ] && break
    sleep 4
done
if [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ]; then
    log_pass "Prompt loaded: $PROMPT_NAME"
else
    log_fail "Could not load prompt (activePromptId: $PROMPT_NAME)"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

sleep 3

# ============================================================================
# TEST 4: Operations loaded into state
# ============================================================================
echo ""
log_test "OBJECTIVE: Operations loaded into buildComposition state"

OPS_IN_STATE=$(agent-browser eval 'JSON.stringify(PU.state.buildComposition.operations)' 2>/dev/null | tr -d '"')
echo "$OPS_IN_STATE" | grep -q "role-replacements" \
    && log_pass "role-replacements loaded in state: $OPS_IN_STATE" \
    || log_fail "role-replacements not in state: $OPS_IN_STATE"

# ============================================================================
# TEST 5: Operation selector visible in top bar
# ============================================================================
echo ""
log_test "OBJECTIVE: Operation selector appears in top bar when operations exist"

OP_SELECTOR=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-rp-op-selector]");
    el ? el.textContent.trim() : "MISSING"
' 2>/dev/null | tr -d '"')
# Should show "None" initially (no operation selected)
echo "$OP_SELECTOR" | grep -qi "none" \
    && log_pass "Operation selector shows 'None': $OP_SELECTOR" \
    || log_pass "Operation selector shows: $OP_SELECTOR"

# ============================================================================
# TEST 6: Click selector opens dropdown
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking operation selector opens dropdown"

agent-browser eval 'document.querySelector("[data-testid=pu-rp-op-selector]").click()' 2>/dev/null
sleep 1

DROPDOWN_VISIBLE=$(agent-browser eval '
    var dd = document.querySelector("[data-testid=pu-rp-op-dropdown]");
    dd ? (dd.style.display !== "none" ? "visible" : "hidden") : "MISSING"
' 2>/dev/null | tr -d '"')
[ "$DROPDOWN_VISIBLE" = "visible" ] \
    && log_pass "Operation dropdown is visible" \
    || log_fail "Dropdown should be visible, got: $DROPDOWN_VISIBLE"

# Check dropdown has items
DROPDOWN_ITEMS=$(agent-browser eval 'document.querySelectorAll(".pu-rp-op-dropdown-item").length' 2>/dev/null | tr -d '"')
[ "$DROPDOWN_ITEMS" -gt 1 ] 2>/dev/null \
    && log_pass "Dropdown has items: $DROPDOWN_ITEMS (incl. None)" \
    || log_fail "Expected dropdown items > 1, got: $DROPDOWN_ITEMS"

# Close it
agent-browser eval 'PU.rightPanel.hideOpDropdown()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 7: Select operation and verify state + chips
# ============================================================================
echo ""
log_test "OBJECTIVE: Selecting an operation loads its data and shows replaced-val chips"

agent-browser eval 'PU.rightPanel.selectOperation("role-replacements")' 2>/dev/null
sleep 3

# Check state
ACTIVE_OP=$(agent-browser eval 'PU.state.buildComposition.activeOperation' 2>/dev/null | tr -d '"')
[ "$ACTIVE_OP" = "role-replacements" ] \
    && log_pass "Active operation set: $ACTIVE_OP" \
    || log_fail "Expected activeOperation = role-replacements, got: $ACTIVE_OP"

# Check operation data loaded
HAS_OP_DATA=$(agent-browser eval '
    var d = PU.state.buildComposition.activeOperationData;
    !!(d && d.mappings && Object.keys(d.mappings).length > 0)
' 2>/dev/null | tr -d '"')
[ "$HAS_OP_DATA" = "true" ] \
    && log_pass "Operation data loaded with mappings" \
    || log_fail "Operation data missing or empty"

# ============================================================================
# TEST 8: Replaced-val chips rendered
# ============================================================================
echo ""
log_test "OBJECTIVE: Replaced-val chips appear with purple styling and asterisks"

REPLACED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.replaced-val").length' 2>/dev/null | tr -d '"')
[ "$REPLACED_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Replaced-val chips found: $REPLACED_COUNT" \
    || log_fail "No replaced-val chips found"

# Check asterisk inside replaced chip
ASTERISK_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.replaced-val .asterisk").length' 2>/dev/null | tr -d '"')
[ "$ASTERISK_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Asterisks inside replaced chips: $ASTERISK_COUNT" \
    || log_fail "No asterisks found in replaced chips"

# Check title tooltip shows original value
FIRST_TITLE=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.replaced-val");
    chip ? chip.title : "NONE"
' 2>/dev/null | tr -d '"')
echo "$FIRST_TITLE" | grep -q "replaces" \
    && log_pass "Replaced chip has title tooltip: $FIRST_TITLE" \
    || log_fail "Expected title with 'replaces', got: $FIRST_TITLE"

# ============================================================================
# TEST 9: Override mark on wildcard name
# ============================================================================
echo ""
log_test "OBJECTIVE: Wildcard names with operation mappings show green * mark"

OVERRIDE_MARK=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-override-mark")' 2>/dev/null | tr -d '"')
[ "$OVERRIDE_MARK" = "true" ] \
    && log_pass "Override mark found on wildcard name" \
    || log_fail "No override mark found"

# ============================================================================
# TEST 10: Top bar shows operation name instead of "None"
# ============================================================================
echo ""
log_test "OBJECTIVE: Top bar shows active operation name"

OP_LABEL=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-rp-op-selector]");
    el ? el.textContent.trim() : "MISSING"
' 2>/dev/null | tr -d '"')
echo "$OP_LABEL" | grep -q "role-replacements" \
    && log_pass "Top bar shows operation name: $OP_LABEL" \
    || log_fail "Expected 'role-replacements' in selector, got: $OP_LABEL"

# ============================================================================
# TEST 11: Export button shows variant label
# ============================================================================
echo ""
log_test "OBJECTIVE: Export button shows variant label when operation active"

EXPORT_HTML=$(agent-browser eval '
    var btn = document.querySelector("[data-testid=pu-rp-export-btn]");
    btn ? btn.innerHTML : "MISSING"
' 2>/dev/null | tr -d '"')
echo "$EXPORT_HTML" | grep -q "variant-label" \
    && log_pass "Export button has variant label" \
    || log_fail "Export button missing variant label: $EXPORT_HTML"

echo "$EXPORT_HTML" | grep -q "role-replacements" \
    && log_pass "Variant label shows operation name" \
    || log_fail "Variant label should show 'role-replacements': $EXPORT_HTML"

# ============================================================================
# TEST 12: Right-click chip shows replacement popover
# ============================================================================
echo ""
log_test "OBJECTIVE: Right-click on a chip opens replacement popover"

# Find a chip and trigger contextmenu
agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v[data-wc-name]");
    if (chip) {
        var ev = new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: 100, clientY: 200 });
        chip.dispatchEvent(ev);
    }
' 2>/dev/null
sleep 1

POPOVER_VISIBLE=$(agent-browser eval '
    var p = document.querySelector("[data-testid=pu-rp-replace-popover]");
    p ? (p.style.display !== "none" ? "visible" : "hidden") : "MISSING"
' 2>/dev/null | tr -d '"')
[ "$POPOVER_VISIBLE" = "visible" ] \
    && log_pass "Replacement popover is visible" \
    || log_fail "Popover should be visible, got: $POPOVER_VISIBLE"

# Check popover has input
INPUT_EXISTS=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-replace-input]")' 2>/dev/null | tr -d '"')
[ "$INPUT_EXISTS" = "true" ] \
    && log_pass "Popover has input field" \
    || log_fail "Popover missing input field"

# Check popover has original value header
ORIGINAL_EXISTS=$(agent-browser eval '!!document.querySelector(".pu-rp-replace-popover-original")' 2>/dev/null | tr -d '"')
[ "$ORIGINAL_EXISTS" = "true" ] \
    && log_pass "Popover shows original value" \
    || log_fail "Popover missing original value"

# Check context-target highlight on right-clicked chip
CONTEXT_TARGET=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-v.context-target")' 2>/dev/null | tr -d '"')
[ "$CONTEXT_TARGET" = "true" ] \
    && log_pass "Context-target highlight on right-clicked chip" \
    || log_fail "No context-target highlight"

# Close popover
agent-browser eval 'PU.rightPanel.hideReplacePopover()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 13: Right-click on replaced chip shows edit mode with Remove
# ============================================================================
echo ""
log_test "OBJECTIVE: Right-click on replaced chip shows edit mode with Remove link"

agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.replaced-val");
    if (chip) {
        var ev = new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: 100, clientY: 200 });
        chip.dispatchEvent(ev);
    }
' 2>/dev/null
sleep 1

REMOVE_EXISTS=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-replace-remove]")' 2>/dev/null | tr -d '"')
[ "$REMOVE_EXISTS" = "true" ] \
    && log_pass "Edit mode has Remove link" \
    || log_fail "Edit mode missing Remove link"

# Check input has current replacement value
INPUT_VALUE=$(agent-browser eval '
    var input = document.querySelector("[data-testid=pu-rp-replace-input]");
    input ? input.value : "EMPTY"
' 2>/dev/null | tr -d '"')
[ -n "$INPUT_VALUE" ] && [ "$INPUT_VALUE" != "EMPTY" ] \
    && log_pass "Input pre-filled with current replacement: $INPUT_VALUE" \
    || log_fail "Input should be pre-filled, got: $INPUT_VALUE"

# Close popover
agent-browser eval 'PU.rightPanel.hideReplacePopover()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 14: Deselect operation (back to None)
# ============================================================================
echo ""
log_test "OBJECTIVE: Deselecting operation removes replaced-val chips"

agent-browser eval 'PU.rightPanel.selectOperation("__none__")' 2>/dev/null
sleep 2

ACTIVE_OP_AFTER=$(agent-browser eval 'PU.state.buildComposition.activeOperation' 2>/dev/null | tr -d '"')
[ "$ACTIVE_OP_AFTER" = "null" ] || [ -z "$ACTIVE_OP_AFTER" ] \
    && log_pass "Operation deselected" \
    || log_fail "Expected null activeOperation, got: $ACTIVE_OP_AFTER"

REPLACED_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.replaced-val").length' 2>/dev/null | tr -d '"')
[ "$REPLACED_AFTER" = "0" ] \
    && log_pass "No replaced-val chips after deselection" \
    || log_fail "Still $REPLACED_AFTER replaced-val chips after deselection"

# Check export button no longer has variant label
EXPORT_AFTER=$(agent-browser eval '
    var btn = document.querySelector("[data-testid=pu-rp-export-btn]");
    btn ? btn.innerHTML : "MISSING"
' 2>/dev/null | tr -d '"')
echo "$EXPORT_AFTER" | grep -q "variant-label" \
    && log_fail "Export still has variant label after deselection" \
    || log_pass "Export button variant label removed"

# ============================================================================
# TEST 15: Right-click without active operation does NOT show popover
# ============================================================================
echo ""
log_test "OBJECTIVE: Right-click without active operation doesn't show popover"

agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v[data-wc-name]");
    if (chip) {
        var ev = new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: 100, clientY: 200 });
        chip.dispatchEvent(ev);
    }
' 2>/dev/null
sleep 0.5

POPOVER_AFTER=$(agent-browser eval '
    var p = document.querySelector("[data-testid=pu-rp-replace-popover]");
    p ? p.style.display : "MISSING"
' 2>/dev/null | tr -d '"')
[ "$POPOVER_AFTER" = "none" ] \
    && log_pass "Popover hidden when no operation active" \
    || log_fail "Popover should be hidden, got: $POPOVER_AFTER"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
