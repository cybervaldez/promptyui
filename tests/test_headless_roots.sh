#!/bin/bash
# ============================================================================
# E2E Test Suite: Headless Compact Roots with Identity Bar
# ============================================================================
# Tests that root blocks render without headers (compact inline path hints,
# animated path dividers), and that the identity bar shows save state.
#
# Usage: ./tests/test_headless_roots.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Headless Compact Roots with Identity Bar"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load test-fixtures in compact mode ─────────────────────────
log_info "Loading test-fixtures / ext-sourcing-strategy (compact)..."
agent-browser close 2>/dev/null || true
sleep 1
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=ext-sourcing-strategy" 2>/dev/null
sleep 10

# Verify prompt loaded
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

# Ensure compact mode
agent-browser eval 'PU.state.previewMode.visualizer = "compact"; PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId)' 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: Root block has no .pu-block-header element
# ============================================================================
echo ""
log_test "OBJECTIVE: Root block has no .pu-block-header element"

HEADER_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-block-header").length
' 2>/dev/null | tr -d '"')

[ "$HEADER_COUNT" = "0" ] \
    && log_pass "No .pu-block-header elements found (roots are headerless)" \
    || log_fail "Expected 0 .pu-block-header elements, got: $HEADER_COUNT"

# ============================================================================
# TEST 2: Root block in compact mode has inline path hint with source
# ============================================================================
echo ""
log_test "OBJECTIVE: Root block in compact has inline path hint with source"

ROOT_PATH_HINT=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    el ? el.textContent.trim() : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

if [ "$ROOT_PATH_HINT" != "NOT_FOUND" ] && [ -n "$ROOT_PATH_HINT" ]; then
    log_pass "Root block has inline path hint: $ROOT_PATH_HINT"
else
    log_fail "Root block missing inline path hint: $ROOT_PATH_HINT"
fi

# Check source suffix present
ROOT_HAS_SOURCE=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    el ? el.hasAttribute("data-has-source") : false
' 2>/dev/null)

[ "$ROOT_HAS_SOURCE" = "true" ] \
    && log_pass "Root path hint has data-has-source attribute" \
    || log_fail "Root path hint missing data-has-source"

# ============================================================================
# TEST 3: Root block path hint is clickable (opens source dropdown)
# ============================================================================
echo ""
log_test "OBJECTIVE: Root block path hint is clickable (opens source dropdown)"

agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    if (el) el.click();
' 2>/dev/null
sleep 1

DROPDOWN_EXISTS=$(agent-browser eval '!!document.querySelector("#pu-source-dropdown")' 2>/dev/null)
[ "$DROPDOWN_EXISTS" = "true" ] \
    && log_pass "Source dropdown opened from root path hint" \
    || log_fail "Source dropdown did not open from root path hint"

# Close dropdown
agent-browser eval 'PU.overlay.dismissAll()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 4: No + Child / + Theme buttons visible in header area
# ============================================================================
echo ""
log_test "OBJECTIVE: No header action buttons visible"

HEADER_ACTIONS=$(agent-browser eval '
    document.querySelectorAll(".pu-header-actions").length
' 2>/dev/null | tr -d '"')

[ "$HEADER_ACTIONS" = "0" ] \
    && log_pass "No .pu-header-actions elements (header buttons removed)" \
    || log_fail "Expected 0 .pu-header-actions, got: $HEADER_ACTIONS"

# ============================================================================
# TEST 5: Context menu (nest action) still has Add Child and Insert Theme
# ============================================================================
echo ""
log_test "OBJECTIVE: Nest action buttons still available for root blocks"

NEST_BTN=$(agent-browser eval '
    var btn = document.querySelector("[data-testid=pu-nest-btn-0]");
    btn ? btn.textContent.trim() : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

NEST_THEME=$(agent-browser eval '
    var btn = document.querySelector("[data-testid=pu-nest-theme-btn-0]");
    btn ? btn.textContent.trim() : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

if echo "$NEST_BTN" | grep -qi "child"; then
    log_pass "Nest action has Add Child button: $NEST_BTN"
else
    log_fail "Expected nest Add Child button, got: $NEST_BTN"
fi

if echo "$NEST_THEME" | grep -qi "theme"; then
    log_pass "Nest action has Insert Theme button: $NEST_THEME"
else
    log_fail "Expected nest Insert Theme button, got: $NEST_THEME"
fi

# ============================================================================
# TEST 6: Save badge hidden on fresh load (no modifications)
# ============================================================================
echo ""
log_test "OBJECTIVE: Save badge hidden on fresh load"

SAVE_STATE_DISPLAY=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-prompt-save-state]");
    el ? el.style.display : "MISSING"
' 2>/dev/null | tr -d '"')

[ "$SAVE_STATE_DISPLAY" = "none" ] \
    && log_pass "Save state hidden on fresh load" \
    || log_fail "Expected save state display=none, got: $SAVE_STATE_DISPLAY"

# ============================================================================
# TEST 7: Edit block content -> (modified) badge appears
# ============================================================================
echo ""
log_test "OBJECTIVE: Edit block content triggers (modified) badge"

# Trigger a modification via getModifiedPrompt + updateHeaderSaveState
agent-browser eval '
    PU.editor.getModifiedPrompt();
    PU.editor.updateHeaderSaveState();
' 2>/dev/null
sleep 1

SAVE_STATE_VISIBLE=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-prompt-save-state]");
    el ? el.style.display : "MISSING"
' 2>/dev/null | tr -d '"')

BADGE_TEXT=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-save-badge]");
    el ? el.textContent.trim() : "MISSING"
' 2>/dev/null | tr -d '"')

[ "$SAVE_STATE_VISIBLE" = "inline-flex" ] \
    && log_pass "Save state visible after modification" \
    || log_fail "Expected save state display=inline-flex, got: $SAVE_STATE_VISIBLE"

if echo "$BADGE_TEXT" | grep -q "modified"; then
    log_pass "Badge shows (modified): $BADGE_TEXT"
else
    log_fail "Expected (modified) badge, got: $BADGE_TEXT"
fi

# ============================================================================
# TEST 8: Click Save -> badge shows (saved) then hides
# ============================================================================
echo ""
log_test "OBJECTIVE: Click Save -> badge shows (saved) then hides"

agent-browser eval '
    var btn = document.querySelector("[data-testid=pu-save-btn]");
    if (btn) btn.click();
' 2>/dev/null
sleep 2

SAVED_TEXT=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-save-badge]");
    el ? el.textContent.trim() : "MISSING"
' 2>/dev/null | tr -d '"')

if echo "$SAVED_TEXT" | grep -qi "saved"; then
    log_pass "Badge shows saved state: $SAVED_TEXT"
else
    log_fail "Expected (saved) badge, got: $SAVED_TEXT"
fi

# Wait for auto-hide
sleep 3

SAVE_STATE_AFTER=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-prompt-save-state]");
    el ? el.style.display : "MISSING"
' 2>/dev/null | tr -d '"')

[ "$SAVE_STATE_AFTER" = "none" ] \
    && log_pass "Save state hidden after save completes" \
    || log_fail "Expected save state to hide after save, got: $SAVE_STATE_AFTER"

# ============================================================================
# TEST 9: Cmd+S keyboard shortcut triggers save
# ============================================================================
echo ""
log_test "OBJECTIVE: Cmd+S keyboard shortcut triggers save"

# Create a modification first
agent-browser eval '
    PU.editor.getModifiedPrompt();
    PU.editor.updateHeaderSaveState();
' 2>/dev/null
sleep 1

# Simulate Cmd+S via dispatching keydown event
agent-browser eval '
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "s", metaKey: true, bubbles: true }));
' 2>/dev/null
sleep 2

SAVE_TRIGGERED=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-save-badge]");
    el ? el.textContent.trim() : "MISSING"
' 2>/dev/null | tr -d '"')

if echo "$SAVE_TRIGGERED" | grep -qi "saved"; then
    log_pass "Cmd+S triggered save: $SAVE_TRIGGERED"
else
    log_fail "Cmd+S did not trigger save, badge: $SAVE_TRIGGERED"
fi

# ============================================================================
# TEST 10: Root blocks in animated mode have path divider (no arrow)
# ============================================================================
echo ""
log_test "OBJECTIVE: Root blocks in animated mode have path divider without child arrow"

# Switch to typewriter mode
agent-browser eval 'PU.state.previewMode.visualizer = "typewriter"; PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId)' 2>/dev/null
sleep 3

ROOT_DIVIDER=$(agent-browser eval '
    var d = document.querySelector(".pu-root-divider");
    d ? "FOUND" : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

[ "$ROOT_DIVIDER" = "FOUND" ] \
    && log_pass "Root block has .pu-root-divider in animated mode" \
    || log_fail "Expected .pu-root-divider in animated mode, got: $ROOT_DIVIDER"

# Verify no child arrow in root divider
ROOT_ARROW=$(agent-browser eval '
    var d = document.querySelector(".pu-root-divider .pu-child-arrow");
    d ? "HAS_ARROW" : "NO_ARROW"
' 2>/dev/null | tr -d '"')

[ "$ROOT_ARROW" = "NO_ARROW" ] \
    && log_pass "Root divider has no child arrow" \
    || log_fail "Root divider should not have child arrow"

# ── Cleanup ────────────────────────────────────────────────────────────
agent-browser close 2>/dev/null || true

print_summary
