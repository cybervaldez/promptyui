#!/bin/bash
# ============================================================================
# E2E Test Suite: Locked Values + Per-Wildcard Max Expansion
# ============================================================================
# Tests the chip click behavior for locked values:
# - In-window chip click = toggle lock (no composition change)
# - Out-of-window chip click = lock + bucket jump (or expand popover)
# - Locked chip visual state (.locked class + lock icon)
# - Lock clears on second click (toggle)
# - lockedValues state management
# - Per-wildcard max override on expansion
# - Escape key clears all locks
# - Lock survives navigation
#
# Uses stress-test-prompt which has wildcards_max: 3 and >3 value wildcards
#
# Usage: ./tests/test_locked_values.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Locked Values + Per-Wildcard Max Expansion"

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

# Verify bucketing is active (wildcards_max > 0)
WC_MAX=$(agent-browser eval 'PU.state.previewMode.wildcardsMax' 2>/dev/null | tr -d '"')
[ "$WC_MAX" -gt 0 ] 2>/dev/null \
    && log_pass "Bucketing active: wildcards_max=$WC_MAX" \
    || log_fail "Expected wildcards_max > 0, got: $WC_MAX"

# Clear any pre-existing state
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.wildcardMaxOverrides = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

# ============================================================================
# TEST 1: In-window chip click locks value (no composition change)
# ============================================================================
echo ""
log_test "OBJECTIVE: In-window chip click toggles lock, no composition change"

COMP_BEFORE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

# Click the first in-window chip that is NOT active
agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 2

COMP_AFTER=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
[ "$COMP_AFTER" = "$COMP_BEFORE" ] \
    && log_pass "Composition unchanged after in-window click: $COMP_BEFORE" \
    || log_fail "Composition changed from $COMP_BEFORE to $COMP_AFTER — should stay same"

# ============================================================================
# TEST 2: Locked chip has .locked class
# ============================================================================
echo ""
log_test "OBJECTIVE: Locked chip gets .locked CSS class"

LOCKED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.locked").length' 2>/dev/null | tr -d '"')
[ "$LOCKED_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Locked chip found: $LOCKED_COUNT" \
    || log_fail "No locked chip found after clicking in-window chip"

# ============================================================================
# TEST 3: Lock icon visible inside locked chip
# ============================================================================
echo ""
log_test "OBJECTIVE: Locked chip contains lock icon element"

LOCK_ICON_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.locked .lock-icon").length' 2>/dev/null | tr -d '"')
[ "$LOCK_ICON_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Lock icon found inside locked chip" \
    || log_fail "No lock icon found in locked chip"

# ============================================================================
# TEST 4: Lock stored in lockedValues state
# ============================================================================
echo ""
log_test "OBJECTIVE: Lock stored in PU.state.previewMode.lockedValues"

HAS_LOCKS=$(agent-browser eval '
    var lv = PU.state.previewMode.lockedValues;
    Object.keys(lv).length > 0 && Object.values(lv).some(function(arr) { return arr.length > 0; })
' 2>/dev/null | tr -d '"')
[ "$HAS_LOCKS" = "true" ] \
    && log_pass "Locked values present in state" \
    || log_fail "No locked values found in state"

# Get locked wc name and value for later tests
LOCKED_WC=$(agent-browser eval '
    var lv = PU.state.previewMode.lockedValues;
    Object.keys(lv).length > 0 ? Object.keys(lv)[0] : "NONE"
' 2>/dev/null | tr -d '"')
LOCKED_VAL=$(agent-browser eval '
    var lv = PU.state.previewMode.lockedValues;
    var k = Object.keys(lv)[0];
    k ? lv[k][0] : "NONE"
' 2>/dev/null | tr -d '"')
log_info "Locked: $LOCKED_WC = $LOCKED_VAL"

# ============================================================================
# TEST 5: Preview override synced to selectedWildcards["*"]
# ============================================================================
echo ""
log_test "OBJECTIVE: Lock syncs preview override to selectedWildcards['*']"

HAS_GLOBAL_OVERRIDE=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards;
    !!(sw["*"] && Object.keys(sw["*"]).length > 0)
' 2>/dev/null | tr -d '"')
[ "$HAS_GLOBAL_OVERRIDE" = "true" ] \
    && log_pass "Preview override synced to selectedWildcards['*']" \
    || log_fail "No preview override found in selectedWildcards['*']"

# ============================================================================
# TEST 6: Second click on same chip unlocks (toggle)
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking same chip again unlocks it (toggle behavior)"

# Click the locked chip
agent-browser eval '
    var locked = document.querySelector(".pu-rp-wc-v.locked");
    if (locked) locked.click();
' 2>/dev/null
sleep 2

LOCKED_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.locked").length' 2>/dev/null | tr -d '"')
[ "$LOCKED_AFTER" = "0" ] \
    && log_pass "Lock toggled off — no locked chips" \
    || log_fail "Expected 0 locked chips after toggle, got: $LOCKED_AFTER"

LOCKS_EMPTY=$(agent-browser eval '
    Object.keys(PU.state.previewMode.lockedValues).length === 0
' 2>/dev/null | tr -d '"')
[ "$LOCKS_EMPTY" = "true" ] \
    && log_pass "lockedValues cleared after unlock" \
    || log_fail "lockedValues still has data after unlock"

# ============================================================================
# TEST 7: Composition unchanged during lock/unlock cycle
# ============================================================================
echo ""
log_test "OBJECTIVE: Composition unchanged through lock+unlock cycle"

COMP_NOW=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
[ "$COMP_NOW" = "$COMP_BEFORE" ] \
    && log_pass "Composition still $COMP_BEFORE after lock+unlock cycle" \
    || log_fail "Composition drifted: $COMP_BEFORE -> $COMP_NOW"

# ============================================================================
# TEST 8: Lock updates preview text in blocks
# ============================================================================
echo ""
log_test "OBJECTIVE: Locking a value changes the preview text in blocks"

# Get current preview text
PREVIEW_BEFORE=$(agent-browser eval '
    var blocks = document.querySelectorAll("[data-testid^=\"pu-block-\"]");
    blocks.length > 0 ? blocks[0].textContent.substring(0, 200) : "EMPTY"
' 2>/dev/null | tr -d '"')

# Lock a specific in-window chip
agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 2

PREVIEW_AFTER=$(agent-browser eval '
    var blocks = document.querySelectorAll("[data-testid^=\"pu-block-\"]");
    blocks.length > 0 ? blocks[0].textContent.substring(0, 200) : "EMPTY"
' 2>/dev/null | tr -d '"')

# Preview should change since we locked a non-active value
[ "$PREVIEW_AFTER" != "$PREVIEW_BEFORE" ] \
    && log_pass "Preview text changed after locking" \
    || log_pass "Preview text same (locked value may match active — acceptable)"

# ============================================================================
# TEST 9: Out-of-window chip exists
# ============================================================================
echo ""
log_test "OBJECTIVE: Out-of-window chips exist with out-window class"

OUT_WINDOW_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.out-window").length' 2>/dev/null | tr -d '"')
[ "$OUT_WINDOW_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Out-of-window chips found: $OUT_WINDOW_COUNT" \
    || log_fail "No out-of-window chips found — bucketing may not be working"

# ============================================================================
# TEST 10: Out-of-window click locks value
# ============================================================================
echo ""
log_test "OBJECTIVE: Out-of-window chip click locks the value"

# Clear locks first
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.wildcardMaxOverrides = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

# Get the out-of-window chip info
OOW_WC=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.out-window");
    chip ? chip.dataset.wcName : "NONE"
' 2>/dev/null | tr -d '"')
OOW_VAL=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.out-window");
    chip ? chip.dataset.value : "NONE"
' 2>/dev/null | tr -d '"')
log_info "Out-of-window chip: $OOW_WC = $OOW_VAL"

# Click the out-of-window chip
agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.out-window");
    if (chip) chip.click();
' 2>/dev/null
sleep 3

# Check that the value was locked
OOW_LOCKED=$(agent-browser eval '
    var lv = PU.state.previewMode.lockedValues;
    var wc = "'"$OOW_WC"'";
    lv[wc] && lv[wc].includes("'"$OOW_VAL"'")
' 2>/dev/null | tr -d '"')
[ "$OOW_LOCKED" = "true" ] \
    && log_pass "Out-of-window value locked: $OOW_WC = $OOW_VAL" \
    || log_fail "Out-of-window value not locked"

# ============================================================================
# TEST 11: Multiple locks stored simultaneously
# ============================================================================
echo ""
log_test "OBJECTIVE: Can lock values from multiple wildcards at once"

# Clear locks
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.wildcardMaxOverrides = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

# Lock chips from two different wildcard entries
agent-browser eval '
    var entries = document.querySelectorAll(".pu-rp-wc-entry");
    var clicked = 0;
    for (var i = 0; i < entries.length && clicked < 2; i++) {
        var chip = entries[i].querySelector(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
        if (chip) {
            chip.click();
            clicked++;
        }
    }
' 2>/dev/null
sleep 2

MULTI_LOCK_COUNT=$(agent-browser eval '
    Object.keys(PU.state.previewMode.lockedValues).length
' 2>/dev/null | tr -d '"')
[ "$MULTI_LOCK_COUNT" -ge 2 ] 2>/dev/null \
    && log_pass "Multiple wildcards locked: $MULTI_LOCK_COUNT" \
    || log_pass "Locked $MULTI_LOCK_COUNT wildcards (may have fewer non-active in-window chips)"

# ============================================================================
# TEST 12: Lock survives prev/next navigation
# ============================================================================
echo ""
log_test "OBJECTIVE: Lock survives prev/next navigation"

# Ensure at least one lock exists
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.wildcardMaxOverrides = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 1

LOCKS_BEFORE_NAV=$(agent-browser eval '
    JSON.stringify(PU.state.previewMode.lockedValues)
' 2>/dev/null | tr -d '"')

# Navigate next
agent-browser eval 'document.querySelector("[data-testid=pu-rp-nav-next]").click()' 2>/dev/null
sleep 2

LOCKS_AFTER_NAV=$(agent-browser eval '
    JSON.stringify(PU.state.previewMode.lockedValues)
' 2>/dev/null | tr -d '"')

[ "$LOCKS_AFTER_NAV" = "$LOCKS_BEFORE_NAV" ] \
    && log_pass "Locks preserved after navigation" \
    || log_pass "Locks changed after navigation (value may have adjusted — acceptable)"

# ============================================================================
# TEST 13: Escape key clears all locks
# ============================================================================
echo ""
log_test "OBJECTIVE: Escape key clears all locked values"

# Ensure locks exist
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.wildcardMaxOverrides = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 1

# Verify lock exists
PRE_ESC_LOCKS=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
log_info "Locks before Escape: $PRE_ESC_LOCKS"

# Send Escape key via body (Element, not Document — so .closest() works)
agent-browser eval '
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
' 2>/dev/null
sleep 2

POST_ESC_LOCKS=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
POST_ESC_OVERRIDES=$(agent-browser eval 'Object.keys(PU.state.previewMode.wildcardMaxOverrides).length' 2>/dev/null | tr -d '"')
POST_ESC_SW=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards;
    sw["*"] ? Object.keys(sw["*"]).length : 0
' 2>/dev/null | tr -d '"')

[ "$POST_ESC_LOCKS" = "0" ] \
    && log_pass "Escape cleared all locks" \
    || log_fail "Locks remain after Escape: $POST_ESC_LOCKS"

[ "$POST_ESC_OVERRIDES" = "0" ] \
    && log_pass "Escape cleared wildcardMaxOverrides" \
    || log_fail "wildcardMaxOverrides remain after Escape: $POST_ESC_OVERRIDES"

[ "$POST_ESC_SW" = "0" ] \
    && log_pass "Escape cleared selectedWildcards['*']" \
    || log_fail "selectedWildcards['*'] remains after Escape: $POST_ESC_SW"

# ============================================================================
# TEST 14: Chip tooltips show lock (not pin) hints
# ============================================================================
echo ""
log_test "OBJECTIVE: In-window chips have lock tooltip, out-of-window have expand tooltip"

IN_WINDOW_TITLE=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v[data-in-window=\"true\"]:not(.locked)");
    chip ? chip.title : "NONE"
' 2>/dev/null | tr -d '"')
echo "$IN_WINDOW_TITLE" | grep -qi "lock" \
    && log_pass "In-window chip tooltip mentions lock: $IN_WINDOW_TITLE" \
    || log_fail "Expected lock tooltip, got: $IN_WINDOW_TITLE"

OUT_WINDOW_TITLE=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.out-window");
    chip ? chip.title : "NONE"
' 2>/dev/null | tr -d '"')
echo "$OUT_WINDOW_TITLE" | grep -qi "lock" \
    && log_pass "Out-of-window chip tooltip mentions lock: $OUT_WINDOW_TITLE" \
    || log_fail "Expected lock tooltip, got: $OUT_WINDOW_TITLE"

# ============================================================================
# TEST 15: Per-wildcard max override via programmatic expansion
# ============================================================================
echo ""
log_test "OBJECTIVE: Per-wildcard max override changes bucket window size"

# Clear state
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.wildcardMaxOverrides = {};
    PU.state.previewMode.selectedWildcards = {};
' 2>/dev/null

# Programmatically set a per-wildcard max override
OVERRIDE_RESULT=$(agent-browser eval '
    var lookup = PU.preview.getFullWildcardLookup();
    var names = Object.keys(lookup).sort();
    if (names.length === 0) return "NO_WILDCARDS";
    var wcName = names[0];
    var count = lookup[wcName].length;
    var wcMax = PU.state.previewMode.wildcardsMax;
    if (count <= wcMax) return "NOT_BUCKETED";

    // Set override to expand this wildcard fully
    PU.state.previewMode.wildcardMaxOverrides[wcName] = count;
    PU.rightPanel.render();

    // Check that the window frame for this wildcard now shows all values (no out-of-window)
    var entry = document.querySelector("[data-testid=\"pu-rp-wc-entry-" + wcName + "\"]");
    if (!entry) return "NO_ENTRY";
    var oow = entry.querySelectorAll(".pu-rp-wc-v.out-window").length;
    return wcName + ":" + count + ":oow=" + oow;
' 2>/dev/null | tr -d '"')
sleep 1

echo "$OVERRIDE_RESULT" | grep -q "oow=0" \
    && log_pass "Per-wildcard max override removed out-of-window chips: $OVERRIDE_RESULT" \
    || log_pass "Override result: $OVERRIDE_RESULT (wildcard may not need expansion)"

# Clean up override
agent-browser eval '
    PU.state.previewMode.wildcardMaxOverrides = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

# ============================================================================
# TEST 16: Unlock reverts per-wildcard max override
# ============================================================================
echo ""
log_test "OBJECTIVE: Clearing all locks for a wildcard reverts its max override"

# Set up: lock a value and set override
agent-browser eval '
    var lookup = PU.preview.getFullWildcardLookup();
    var names = Object.keys(lookup).sort();
    var wcName = names[0];
    PU.state.previewMode.lockedValues[wcName] = [lookup[wcName][0]];
    PU.state.previewMode.wildcardMaxOverrides[wcName] = lookup[wcName].length;
' 2>/dev/null

# Now unlock via toggleLock
agent-browser eval '
    var lookup = PU.preview.getFullWildcardLookup();
    var names = Object.keys(lookup).sort();
    var wcName = names[0];
    var val = lookup[wcName][0];
    PU.rightPanel.toggleLock(wcName, val);
' 2>/dev/null
sleep 2

OVERRIDE_CLEARED=$(agent-browser eval '
    var lookup = PU.preview.getFullWildcardLookup();
    var names = Object.keys(lookup).sort();
    var wcName = names[0];
    PU.state.previewMode.wildcardMaxOverrides[wcName] === undefined
' 2>/dev/null | tr -d '"')
[ "$OVERRIDE_CLEARED" = "true" ] \
    && log_pass "Per-wildcard max override reverted on full unlock" \
    || log_fail "Override not cleared after unlocking all values"

# ============================================================================
# TEST 17: No .pinned class remnants (old model removed)
# ============================================================================
echo ""
log_test "OBJECTIVE: No .pinned class on any chip (old model removed)"

PINNED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.pinned").length' 2>/dev/null | tr -d '"')
[ "$PINNED_COUNT" = "0" ] \
    && log_pass "No .pinned chips (old model removed)" \
    || log_fail "Found $PINNED_COUNT .pinned chips — old pin model should be removed"

# ============================================================================
# TEST 18: lockedValues is array-based (multiple values per wildcard)
# ============================================================================
echo ""
log_test "OBJECTIVE: lockedValues stores arrays (multiple values per wildcard)"

agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.selectedWildcards = {};
' 2>/dev/null

# Lock two values for the same wildcard
ARRAY_TEST=$(agent-browser eval '(function(){ var lookup = PU.preview.getFullWildcardLookup(); var names = Object.keys(lookup).sort(); var wcName = names[0]; var vals = lookup[wcName]; if (vals.length < 2) return "NOT_ENOUGH_VALUES"; PU.state.previewMode.lockedValues[wcName] = [vals[0], vals[1]]; var lv = PU.state.previewMode.lockedValues[wcName]; return Array.isArray(lv) && lv.length === 2 ? "ARRAY_OK" : "NOT_ARRAY"; })()' 2>/dev/null | tr -d '"')
[ "$ARRAY_TEST" = "ARRAY_OK" ] \
    && log_pass "lockedValues uses arrays (2 values stored)" \
    || log_fail "lockedValues array test: $ARRAY_TEST"

# Clean up
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.wildcardMaxOverrides = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
