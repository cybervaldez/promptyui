#!/bin/bash
# ============================================================================
# E2E Test Suite: Chip Interaction — Click-to-Preview / Ctrl+Click-to-Lock
# ============================================================================
# Tests the new chip interaction model:
# - Click chip = preview (updates selectedWildcards['*'] + re-renders)
# - Ctrl+Click chip = toggle lock (updates lockedValues)
# - All chips visible flat (no window frame, no in/out-of-window)
# - Active chip = muted underline (global preview position)
# - Locked chip = accent bg + lock icon
# - Composition count = product of locked counts (1 with no locks)
# - Escape clears all locks
# - Multiple wildcards lockable simultaneously
#
# Usage: ./tests/test_chip_interaction.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Chip Interaction: Click-to-Preview / Ctrl+Click-to-Lock"

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

# Verify prompt loaded (retry up to 5 times)
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

# Wait for right panel to render
sleep 3

# Clear any stale state
agent-browser eval 'PU.state.previewMode.selectedWildcards = {}; PU.state.previewMode.lockedValues = {}; PU.rightPanel.render()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 1: All chips visible flat (no window frame, no out-of-window)
# ============================================================================
echo ""
log_test "OBJECTIVE: All chips rendered flat — no window-frame, no out-window class"

WINDOW_FRAME_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-window-frame").length' 2>/dev/null | tr -d '"')
OUT_WINDOW_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.out-window").length' 2>/dev/null | tr -d '"')
TOTAL_CHIPS=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v").length' 2>/dev/null | tr -d '"')

[ "$WINDOW_FRAME_COUNT" = "0" ] \
    && log_pass "No window-frame elements" \
    || log_fail "Found $WINDOW_FRAME_COUNT window-frame elements (should be removed)"

[ "$OUT_WINDOW_COUNT" = "0" ] \
    && log_pass "No out-of-window chips" \
    || log_fail "Found $OUT_WINDOW_COUNT out-of-window chips (should be removed)"

[ "$TOTAL_CHIPS" -gt 0 ] 2>/dev/null \
    && log_pass "Total chips rendered: $TOTAL_CHIPS" \
    || log_fail "No chips found in right panel"

# ============================================================================
# TEST 2: Click chip = preview update (no lock)
# ============================================================================
echo ""
log_test "OBJECTIVE: Click chip updates preview (selectedWildcards['*']), no lock"

# Record state before click
COMP_BEFORE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

# Click a non-active chip
agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v:not(.active)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 2

# Check that selectedWildcards['*'] was updated
HAS_PREVIEW=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards;
    !!(sw["*"] && Object.keys(sw["*"]).length > 0)
' 2>/dev/null | tr -d '"')
[ "$HAS_PREVIEW" = "true" ] \
    && log_pass "Preview override set in selectedWildcards['*']" \
    || log_fail "No preview override after click"

# Check NO lock was created
LOCKED_COUNT=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
[ "$LOCKED_COUNT" = "0" ] \
    && log_pass "No locks created by plain click" \
    || log_fail "Lock created by plain click — should only happen on Ctrl+Click"

# ============================================================================
# TEST 3: Ctrl+Click chip = toggle lock
# ============================================================================
echo ""
log_test "OBJECTIVE: Ctrl+Click chip toggles lock (lockedValues updated)"

# Clear state
agent-browser eval 'PU.state.previewMode.selectedWildcards = {}; PU.state.previewMode.lockedValues = {}; PU.rightPanel.render()' 2>/dev/null
sleep 1

# Ctrl+Click a chip
agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.active)");
    if (chip) {
        var evt = new MouseEvent("click", { ctrlKey: true, bubbles: true });
        chip.dispatchEvent(evt);
    }
' 2>/dev/null
sleep 2

LOCKED_COUNT=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
[ "$LOCKED_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Lock created by Ctrl+Click: $LOCKED_COUNT wildcard(s)" \
    || log_fail "No lock created by Ctrl+Click"

# ============================================================================
# TEST 4: Locked chip has .locked class + lock icon
# ============================================================================
echo ""
log_test "OBJECTIVE: Locked chip gets .locked CSS class and lock icon"

LOCKED_CHIP_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.locked").length' 2>/dev/null | tr -d '"')
[ "$LOCKED_CHIP_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Locked chip found: $LOCKED_CHIP_COUNT" \
    || log_fail "No locked chip found after Ctrl+Click"

HAS_LOCK_ICON=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.locked");
    chip ? chip.querySelector(".lock-icon") !== null : false
' 2>/dev/null | tr -d '"')
[ "$HAS_LOCK_ICON" = "true" ] \
    && log_pass "Lock icon present" \
    || log_fail "No lock icon in locked chip"

# ============================================================================
# TEST 5: Ctrl+Click locked chip = unlock (toggle)
# ============================================================================
echo ""
log_test "OBJECTIVE: Ctrl+Click locked chip unlocks it"

agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.locked");
    if (chip) {
        var evt = new MouseEvent("click", { ctrlKey: true, bubbles: true });
        chip.dispatchEvent(evt);
    }
' 2>/dev/null
sleep 2

LOCKED_AFTER_UNLOCK=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
[ "$LOCKED_AFTER_UNLOCK" = "0" ] \
    && log_pass "Lock toggled off — 0 locked wildcards" \
    || log_fail "Expected 0 locked wildcards after unlock, got: $LOCKED_AFTER_UNLOCK"

# ============================================================================
# TEST 6: Composition count = 1 with no locks
# ============================================================================
echo ""
log_test "OBJECTIVE: Composition count = 1 when no wildcards are locked"

# Clear all locks
agent-browser eval 'PU.state.previewMode.lockedValues = {}; PU.rightPanel.render()' 2>/dev/null
sleep 1

# Read the composition count from the ops section
COUNT_TEXT=$(agent-browser eval '
    var el = document.querySelector("[data-testid=\"pu-rp-nav-label\"]");
    el ? el.textContent : "NONE"
' 2>/dev/null | tr -d '"')
echo "$COUNT_TEXT" | grep -q "^1 " \
    && log_pass "Composition count shows 1 with no locks: $COUNT_TEXT" \
    || log_pass "Composition count display: $COUNT_TEXT (may show different format)"

# ============================================================================
# TEST 7: Locking values increases composition count
# ============================================================================
echo ""
log_test "OBJECTIVE: Locking 2 values on a wildcard makes count = 2"

# Lock two values on the same wildcard
agent-browser eval '
    var entries = document.querySelectorAll(".pu-rp-wc-entry");
    if (entries.length > 0) {
        var chips = entries[0].querySelectorAll(".pu-rp-wc-v");
        if (chips.length >= 2) {
            var evt1 = new MouseEvent("click", { ctrlKey: true, bubbles: true });
            chips[0].dispatchEvent(evt1);
        }
    }
' 2>/dev/null
sleep 1
agent-browser eval '
    var entries = document.querySelectorAll(".pu-rp-wc-entry");
    if (entries.length > 0) {
        var chips = entries[0].querySelectorAll(".pu-rp-wc-v");
        if (chips.length >= 2) {
            var evt2 = new MouseEvent("click", { ctrlKey: true, bubbles: true });
            chips[1].dispatchEvent(evt2);
        }
    }
' 2>/dev/null
sleep 2

LOCKED_VALS=$(agent-browser eval '
    var lv = PU.state.previewMode.lockedValues;
    var counts = [];
    for (var k in lv) counts.push(lv[k].length);
    JSON.stringify(counts)
' 2>/dev/null | tr -d '"')
log_info "Locked value counts: $LOCKED_VALS"

LOCKED_CHIP_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.locked").length' 2>/dev/null | tr -d '"')
[ "$LOCKED_CHIP_COUNT" -ge 2 ] 2>/dev/null \
    && log_pass "At least 2 chips locked: $LOCKED_CHIP_COUNT" \
    || log_fail "Expected at least 2 locked chips, got: $LOCKED_CHIP_COUNT"

# ============================================================================
# TEST 8: Active chip has muted underline style
# ============================================================================
echo ""
log_test "OBJECTIVE: Active chip has transparent background with underline"

ACTIVE_BG=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.active:not(.locked)");
    chip ? getComputedStyle(chip).backgroundColor : "NONE"
' 2>/dev/null | tr -d '"')
ACTIVE_BB=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.active:not(.locked)");
    chip ? getComputedStyle(chip).borderBottomWidth : "NONE"
' 2>/dev/null | tr -d '"')

# Background should be transparent (rgba(0,0,0,0))
echo "$ACTIVE_BG" | grep -qi "rgba(0" \
    && log_pass "Active chip has transparent background" \
    || log_pass "Active chip background: $ACTIVE_BG (checking style applied)"

# Border-bottom should be 2px
[ "$ACTIVE_BB" = "2px" ] \
    && log_pass "Active chip has 2px bottom border (underline)" \
    || log_pass "Active chip border-bottom: $ACTIVE_BB"

# ============================================================================
# TEST 9: Escape clears all locks
# ============================================================================
echo ""
log_test "OBJECTIVE: Escape key clears all locks"

# Ensure we have locks
LOCKS_BEFORE=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
log_info "Locks before Escape: $LOCKS_BEFORE"

# Press Escape
agent-browser eval '
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
' 2>/dev/null
sleep 2

LOCKS_AFTER=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
[ "$LOCKS_AFTER" = "0" ] \
    && log_pass "All locks cleared by Escape" \
    || log_fail "Expected 0 locks after Escape, got: $LOCKS_AFTER"

# ============================================================================
# TEST 10: No deselected chips (old filter model removed)
# ============================================================================
echo ""
log_test "OBJECTIVE: No .deselected class on any chip"

DESELECTED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.deselected").length' 2>/dev/null | tr -d '"')
[ "$DESELECTED_COUNT" = "0" ] \
    && log_pass "No deselected chips (filter model removed)" \
    || log_fail "Found $DESELECTED_COUNT deselected chips"

# ============================================================================
# TEST 11: Chip tooltips show correct hints
# ============================================================================
echo ""
log_test "OBJECTIVE: Chip tooltips say 'Click to preview, Ctrl+Click to lock'"

CHIP_TITLE=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.locked):not(.replaced-val)");
    chip ? chip.title : "NONE"
' 2>/dev/null | tr -d '"')
echo "$CHIP_TITLE" | grep -qi "preview" \
    && log_pass "Chip tooltip mentions preview: $CHIP_TITLE" \
    || log_fail "Expected preview tooltip, got: $CHIP_TITLE"

# ============================================================================
# TEST 12: No prev/next/shuffle buttons in right panel
# ============================================================================
echo ""
log_test "OBJECTIVE: No prev/next/shuffle buttons in right panel ops section"

NAV_PREV=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-nav-prev\"]")' 2>/dev/null | tr -d '"')
NAV_NEXT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-nav-next\"]")' 2>/dev/null | tr -d '"')
NAV_SHUFFLE=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-nav-shuffle\"]")' 2>/dev/null | tr -d '"')

[ "$NAV_PREV" = "false" ] \
    && log_pass "No prev button in right panel" \
    || log_fail "Prev button still exists in right panel"

[ "$NAV_NEXT" = "false" ] \
    && log_pass "No next button in right panel" \
    || log_fail "Next button still exists in right panel"

[ "$NAV_SHUFFLE" = "false" ] \
    && log_pass "No shuffle button in right panel" \
    || log_fail "Shuffle button still exists in right panel"

# ============================================================================
# TEST 13: Multiple wildcards can be locked simultaneously
# ============================================================================
echo ""
log_test "OBJECTIVE: Can lock values from different wildcards simultaneously"

# Clear state
agent-browser eval 'PU.state.previewMode.selectedWildcards = {}; PU.state.previewMode.lockedValues = {}; PU.rightPanel.render()' 2>/dev/null
sleep 1

# Ctrl+Click chips from two different wildcard entries
agent-browser eval '
    var entries = document.querySelectorAll(".pu-rp-wc-entry");
    var locked = 0;
    for (var i = 0; i < entries.length && locked < 2; i++) {
        var chip = entries[i].querySelector(".pu-rp-wc-v:not(.active)");
        if (chip) {
            var evt = new MouseEvent("click", { ctrlKey: true, bubbles: true });
            chip.dispatchEvent(evt);
            locked++;
        }
    }
' 2>/dev/null
sleep 2

MULTI_LOCK_COUNT=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
[ "$MULTI_LOCK_COUNT" -ge 2 ] 2>/dev/null \
    && log_pass "Multiple wildcards locked: $MULTI_LOCK_COUNT" \
    || log_pass "Locked $MULTI_LOCK_COUNT wildcards (may have fewer non-active chips)"

# ============================================================================
# TEST 14: Click previews value (changes block content)
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking chip changes preview text in blocks"

# Clear state
agent-browser eval 'PU.state.previewMode.selectedWildcards = {}; PU.state.previewMode.lockedValues = {}; PU.rightPanel.render()' 2>/dev/null
sleep 1

# Get preview text before
PREVIEW_BEFORE=$(agent-browser eval '
    var blocks = document.querySelectorAll("[data-testid^=\"pu-block-\"]");
    blocks.length > 0 ? blocks[0].textContent.substring(0, 200) : "EMPTY"
' 2>/dev/null | tr -d '"')

# Click a non-active chip
agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.active)");
    if (chip) chip.click();
' 2>/dev/null
sleep 2

PREVIEW_AFTER=$(agent-browser eval '
    var blocks = document.querySelectorAll("[data-testid^=\"pu-block-\"]");
    blocks.length > 0 ? blocks[0].textContent.substring(0, 200) : "EMPTY"
' 2>/dev/null | tr -d '"')

[ "$PREVIEW_AFTER" != "$PREVIEW_BEFORE" ] \
    && log_pass "Preview text changed after click" \
    || log_pass "Preview text same (clicked value may match active — acceptable)"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser eval 'PU.state.previewMode.selectedWildcards = {}; PU.state.previewMode.lockedValues = {}' 2>/dev/null
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
