#!/bin/bash
# ============================================================================
# E2E Test Suite: Wildcard Focus Mode (Bulb Toggle, Multi-Focus OR)
# ============================================================================
# Tests the bulb icon toggle for multi-wildcard focus: matching blocks
# visible (OR union), non-matching blocks hidden, banner with counts.
#
# Usage: ./tests/test_wc_focus_mode.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Wildcard Focus Mode (Bulb Toggle, Multi-Focus OR)"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load hiring-templates / stress-test-prompt ──────────────────
log_info "Loading hiring-templates / stress-test-prompt..."
agent-browser close 2>/dev/null || true
sleep 1
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt" 2>/dev/null
sleep 10

PROMPT_NAME=""
for attempt in 1 2 3 4 5; do
    PROMPT_NAME=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
    [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ] && break
    sleep 4
done
if [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ]; then
    log_pass "Prompt loaded: $PROMPT_NAME"
else
    log_fail "Could not load prompt"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

sleep 3

# Clear state
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.state.previewMode.focusedWildcards = [];
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

# ============================================================================
# TEST 1: Bulb icon exists on wildcard entries (hidden by default)
# ============================================================================
echo ""
log_test "OBJECTIVE: Bulb icon exists on wildcard entries"

ICON_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-wc-focus-icon").length' 2>/dev/null | tr -d '"')
[ "$ICON_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Found $ICON_COUNT bulb icons" \
    || log_fail "No bulb icons found"

# ============================================================================
# TEST 2: Bulb icon is hidden by default (opacity 0)
# ============================================================================
echo ""
log_test "OBJECTIVE: Bulb icon is hidden by default"

DEFAULT_OPACITY=$(agent-browser eval '(function(){ var icon = document.querySelector(".pu-wc-focus-icon"); if (!icon) return "no-icon"; return window.getComputedStyle(icon).opacity; })()' 2>/dev/null | tr -d '"')
[ "$DEFAULT_OPACITY" = "0" ] \
    && log_pass "Bulb icon default opacity: 0 (hidden)" \
    || log_fail "Bulb icon opacity: $DEFAULT_OPACITY (expected 0)"

# ============================================================================
# TEST 3: Clicking bulb adds wildcard to focusedWildcards array
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking bulb icon activates focus mode"

# Find a wildcard name that has block mappings
TEST_WC=$(agent-browser eval '(function(){ var keys = Object.keys(PU.editor._wildcardToBlocks || {}); return keys.length > 0 ? keys[0] : "NONE"; })()' 2>/dev/null | tr -d '"')
log_info "Test wildcard 1: $TEST_WC"

agent-browser eval "
    var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]');
    if (icon) icon.click();
" 2>/dev/null
sleep 1

FOCUSED_LEN=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null | tr -d '"')
FOCUSED_FIRST=$(agent-browser eval 'PU.state.previewMode.focusedWildcards[0]' 2>/dev/null | tr -d '"')
[ "$FOCUSED_LEN" = "1" ] && [ "$FOCUSED_FIRST" = "$TEST_WC" ] \
    && log_pass "focusedWildcards contains: $FOCUSED_FIRST" \
    || log_fail "focusedWildcards length=$FOCUSED_LEN, first=$FOCUSED_FIRST (expected 1, $TEST_WC)"

# ============================================================================
# TEST 4: Focus banner appears with wildcard name and block count
# ============================================================================
echo ""
log_test "OBJECTIVE: Focus banner shows with wildcard name and counts"

BANNER_VISIBLE=$(agent-browser eval '(function(){ var b = document.querySelector("[data-testid=pu-focus-banner]"); if (!b) return "no-banner"; return b.style.display === "flex" ? "visible" : "hidden:" + b.style.display; })()' 2>/dev/null | tr -d '"')
[ "$BANNER_VISIBLE" = "visible" ] \
    && log_pass "Focus banner is visible" \
    || log_fail "Focus banner: $BANNER_VISIBLE"

BANNER_TEXT=$(agent-browser eval '(function(){ var b = document.querySelector("[data-testid=pu-focus-banner]"); return b ? b.textContent : "none"; })()' 2>/dev/null | tr -d '"')
echo "$BANNER_TEXT" | grep -q "$TEST_WC" \
    && log_pass "Banner contains wildcard name: $TEST_WC" \
    || log_fail "Banner text: $BANNER_TEXT (expected $TEST_WC)"

# Check banner has block count (N/M blocks pattern)
echo "$BANNER_TEXT" | grep -qE '[0-9]+/[0-9]+ blocks' \
    && log_pass "Banner shows block count" \
    || log_fail "Banner missing block count: $BANNER_TEXT"

# ============================================================================
# TEST 5: Blocks container has focus-active class
# ============================================================================
echo ""
log_test "OBJECTIVE: Blocks container has .pu-wc-focus-active"

HAS_FOCUS_CLASS=$(agent-browser eval '(function(){ var c = document.querySelector("[data-testid=pu-blocks-container]"); return c ? c.classList.contains("pu-wc-focus-active") : false; })()' 2>/dev/null | tr -d '"')
[ "$HAS_FOCUS_CLASS" = "true" ] \
    && log_pass "Container has .pu-wc-focus-active" \
    || log_fail "Container missing .pu-wc-focus-active"

# ============================================================================
# TEST 6: Matching blocks have .pu-highlight-match
# ============================================================================
echo ""
log_test "OBJECTIVE: Matching blocks visible with .pu-highlight-match"

MATCH_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-highlight-match").length' 2>/dev/null | tr -d '"')
[ "$MATCH_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Found $MATCH_COUNT matching blocks" \
    || log_fail "No matching blocks found"

# ============================================================================
# TEST 7: Non-matching blocks are hidden (display: none)
# ============================================================================
echo ""
log_test "OBJECTIVE: Non-matching blocks are hidden"

HIDDEN_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-focus-hidden").length' 2>/dev/null | tr -d '"')
[ "$HIDDEN_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Found $HIDDEN_COUNT hidden blocks" \
    || log_pass "No hidden blocks (all blocks may use this wildcard)"

HIDDEN_DISPLAY=$(agent-browser eval '(function(){ var h = document.querySelector(".pu-block.pu-focus-hidden"); if (!h) return "none-found"; return window.getComputedStyle(h).display; })()' 2>/dev/null | tr -d '"')
if [ "$HIDDEN_DISPLAY" = "none" ]; then
    log_pass "Hidden block display: none"
elif [ "$HIDDEN_DISPLAY" = "none-found" ]; then
    log_pass "No hidden blocks to check (acceptable)"
else
    log_fail "Hidden block display: $HIDDEN_DISPLAY (expected none)"
fi

# ============================================================================
# TEST 8: Bulb icon has .active class when focused
# ============================================================================
echo ""
log_test "OBJECTIVE: Focused bulb icon has .active class"

ICON_ACTIVE=$(agent-browser eval "(function(){ var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]'); return icon ? icon.classList.contains('active') : false; })()" 2>/dev/null | tr -d '"')
[ "$ICON_ACTIVE" = "true" ] \
    && log_pass "Bulb icon has .active class" \
    || log_fail "Bulb icon missing .active class"

# ============================================================================
# TEST 9: Multi-focus — clicking second bulb ADDS to set (OR)
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking second bulb adds to focus set (OR union)"

# Get a second wildcard
SECOND_WC=$(agent-browser eval '(function(){ var keys = Object.keys(PU.editor._wildcardToBlocks || {}); return keys.length > 1 ? keys[1] : "NONE"; })()' 2>/dev/null | tr -d '"')
log_info "Test wildcard 2: $SECOND_WC"

if [ "$SECOND_WC" != "NONE" ] && [ -n "$SECOND_WC" ]; then
    # Click second bulb (should ADD, not replace)
    agent-browser eval "
        var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$SECOND_WC\"]');
        if (icon) icon.click();
    " 2>/dev/null
    sleep 1

    FOCUSED_LEN=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null | tr -d '"')
    [ "$FOCUSED_LEN" = "2" ] \
        && log_pass "Two wildcards focused (OR union)" \
        || log_fail "Expected 2 focused, got $FOCUSED_LEN"

    # Both should be in the array
    HAS_FIRST=$(agent-browser eval "PU.state.previewMode.focusedWildcards.includes('$TEST_WC')" 2>/dev/null | tr -d '"')
    HAS_SECOND=$(agent-browser eval "PU.state.previewMode.focusedWildcards.includes('$SECOND_WC')" 2>/dev/null | tr -d '"')
    [ "$HAS_FIRST" = "true" ] && [ "$HAS_SECOND" = "true" ] \
        && log_pass "Both $TEST_WC and $SECOND_WC in focused set" \
        || log_fail "Missing wildcard in set: first=$HAS_FIRST, second=$HAS_SECOND"

    # Banner should show both names
    BANNER_TEXT=$(agent-browser eval '(function(){ var b = document.querySelector("[data-testid=pu-focus-banner]"); return b ? b.textContent : "none"; })()' 2>/dev/null | tr -d '"')
    echo "$BANNER_TEXT" | grep -q "$TEST_WC" && echo "$BANNER_TEXT" | grep -q "$SECOND_WC" \
        && log_pass "Banner shows both wildcard names" \
        || log_fail "Banner missing names: $BANNER_TEXT"

    # Both bulb icons should have .active
    ICON1_ACTIVE=$(agent-browser eval "(function(){ var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]'); return icon ? icon.classList.contains('active') : false; })()" 2>/dev/null | tr -d '"')
    ICON2_ACTIVE=$(agent-browser eval "(function(){ var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$SECOND_WC\"]'); return icon ? icon.classList.contains('active') : false; })()" 2>/dev/null | tr -d '"')
    [ "$ICON1_ACTIVE" = "true" ] && [ "$ICON2_ACTIVE" = "true" ] \
        && log_pass "Both bulb icons have .active class" \
        || log_fail "Icon active states: first=$ICON1_ACTIVE, second=$ICON2_ACTIVE"

    # OR union: match count should be >= single-focus match count
    MULTI_MATCH=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-highlight-match").length' 2>/dev/null | tr -d '"')
    [ "$MULTI_MATCH" -ge "$MATCH_COUNT" ] 2>/dev/null \
        && log_pass "Multi-focus match count ($MULTI_MATCH) >= single ($MATCH_COUNT)" \
        || log_fail "Multi-focus match count ($MULTI_MATCH) < single ($MATCH_COUNT)"
else
    log_skip "Only one wildcard in block map — skipping multi-focus tests"
fi

# ============================================================================
# TEST 10: Clicking active bulb removes it from set
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking active bulb removes from focus set"

if [ "$SECOND_WC" != "NONE" ] && [ -n "$SECOND_WC" ]; then
    # Remove first wildcard by clicking its bulb again
    agent-browser eval "
        var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]');
        if (icon) icon.click();
    " 2>/dev/null
    sleep 1

    FOCUSED_LEN=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null | tr -d '"')
    FOCUSED_REMAINING=$(agent-browser eval 'PU.state.previewMode.focusedWildcards[0]' 2>/dev/null | tr -d '"')
    [ "$FOCUSED_LEN" = "1" ] && [ "$FOCUSED_REMAINING" = "$SECOND_WC" ] \
        && log_pass "Removed $TEST_WC, $SECOND_WC remains" \
        || log_fail "Expected 1 remaining ($SECOND_WC), got $FOCUSED_LEN ($FOCUSED_REMAINING)"

    # Focus should still be active (one left)
    HAS_FOCUS=$(agent-browser eval '(function(){ var c = document.querySelector("[data-testid=pu-blocks-container]"); return c ? c.classList.contains("pu-wc-focus-active") : false; })()' 2>/dev/null | tr -d '"')
    [ "$HAS_FOCUS" = "true" ] \
        && log_pass "Focus still active with one remaining" \
        || log_fail "Focus lost after removing one wildcard"

    # Clear for next tests
    agent-browser eval 'PU.rightPanel.clearFocus()' 2>/dev/null
    sleep 0.5
else
    log_skip "Only one wildcard — skipping remove test"
fi

# ============================================================================
# TEST 11: Clicking bulb again on single focus clears all
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking single focused bulb clears all focus"

agent-browser eval "
    var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]');
    if (icon) icon.click();
" 2>/dev/null
sleep 1

# Now click same bulb again — should clear
agent-browser eval "
    var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]');
    if (icon) icon.click();
" 2>/dev/null
sleep 1

CLEARED_LEN=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null | tr -d '"')
[ "$CLEARED_LEN" = "0" ] \
    && log_pass "focusedWildcards cleared to empty array" \
    || log_fail "focusedWildcards length: $CLEARED_LEN (expected 0)"

NO_FOCUS_CLASS=$(agent-browser eval '(function(){ var c = document.querySelector("[data-testid=pu-blocks-container]"); return c ? c.classList.contains("pu-wc-focus-active") : true; })()' 2>/dev/null | tr -d '"')
[ "$NO_FOCUS_CLASS" = "false" ] \
    && log_pass "Container .pu-wc-focus-active removed" \
    || log_fail "Container still has .pu-wc-focus-active"

# ============================================================================
# TEST 12: Escape key clears all focus
# ============================================================================
echo ""
log_test "OBJECTIVE: Escape key clears all focus"

# Activate focus on first wildcard
agent-browser eval "
    var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]');
    if (icon) icon.click();
" 2>/dev/null
sleep 1

# Verify active
REFOCUSED_LEN=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null | tr -d '"')
[ "$REFOCUSED_LEN" -gt 0 ] 2>/dev/null && log_pass "Re-focused on $TEST_WC"

# Press Escape
agent-browser eval 'document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))' 2>/dev/null
sleep 1

ESC_CLEARED_LEN=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null | tr -d '"')
[ "$ESC_CLEARED_LEN" = "0" ] \
    && log_pass "Escape cleared all focus" \
    || log_fail "After Escape: focusedWildcards length=$ESC_CLEARED_LEN (expected 0)"

# ============================================================================
# TEST 13: Banner X button clears all focus
# ============================================================================
echo ""
log_test "OBJECTIVE: Banner close button clears all focus"

# Re-activate focus
agent-browser eval "
    var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]');
    if (icon) icon.click();
" 2>/dev/null
sleep 1

# Click banner close
agent-browser eval '
    var btn = document.querySelector("[data-testid=pu-focus-banner-close]");
    if (btn) btn.click();
' 2>/dev/null
sleep 1

BANNER_CLEARED_LEN=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null | tr -d '"')
[ "$BANNER_CLEARED_LEN" = "0" ] \
    && log_pass "Banner X cleared all focus" \
    || log_fail "After banner X: focusedWildcards length=$BANNER_CLEARED_LEN (expected 0)"

# ============================================================================
# TEST 14: Focus persists after clicking a chip (preview change)
# ============================================================================
echo ""
log_test "OBJECTIVE: Focus persists after chip click preview change"

# Activate focus
agent-browser eval "
    var icon = document.querySelector('.pu-wc-focus-icon[data-wc-name=\"$TEST_WC\"]');
    if (icon) icon.click();
" 2>/dev/null
sleep 1

# Click a chip to trigger preview change
agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.active):not(.locked)");
    if (chip) chip.click();
' 2>/dev/null
sleep 2

STILL_FOCUSED_LEN=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null | tr -d '"')
STILL_HAS=$(agent-browser eval "PU.state.previewMode.focusedWildcards.includes('$TEST_WC')" 2>/dev/null | tr -d '"')
[ "$STILL_FOCUSED_LEN" -gt 0 ] 2>/dev/null && [ "$STILL_HAS" = "true" ] \
    && log_pass "Focus persists after chip click" \
    || log_fail "Focus lost after chip click: length=$STILL_FOCUSED_LEN, has=$STILL_HAS"

STILL_ACTIVE=$(agent-browser eval '(function(){ var c = document.querySelector("[data-testid=pu-blocks-container]"); return c ? c.classList.contains("pu-wc-focus-active") : false; })()' 2>/dev/null | tr -d '"')
[ "$STILL_ACTIVE" = "true" ] \
    && log_pass "Focus-active class persists on container" \
    || log_fail "Focus-active class missing after chip click"

# Clean up
agent-browser eval 'PU.rightPanel.clearFocus()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 15: Bulb icon uses lightbulb character (not eye)
# ============================================================================
echo ""
log_test "OBJECTIVE: Bulb icon uses lightbulb character"

ICON_HTML=$(agent-browser eval '(function(){ var icon = document.querySelector(".pu-wc-focus-icon"); return icon ? icon.innerHTML.trim() : "none"; })()' 2>/dev/null | tr -d '"')
# 💡 is &#128161; which renders as the lightbulb emoji
echo "$ICON_HTML" | grep -qE '💡|128161' \
    && log_pass "Icon is lightbulb character" \
    || log_fail "Icon HTML: $ICON_HTML (expected lightbulb)"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
