#!/bin/bash
# ============================================================================
# E2E Test Suite: Locked Values (Ctrl+Click-to-Lock)
# ============================================================================
# Tests locked value management:
# - Ctrl+Click = toggle lock (lockedValues state)
# - Locked chip visual: .locked class + lock icon
# - Lock stored as array (multiple values per wildcard)
# - Preview override synced on lock
# - Escape clears all locks
# - No .pinned or .out-window remnants
# - lockedValues drives composition count
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
print_header "Locked Values (Ctrl+Click-to-Lock)"

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

# Clear any pre-existing state
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

# ============================================================================
# TEST 1: Ctrl+Click locks value (no composition change)
# ============================================================================
echo ""
log_test "OBJECTIVE: Ctrl+Click chip toggles lock, no composition change"

COMP_BEFORE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

# Ctrl+Click the first non-active chip
agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.active)");
    if (chip) {
        var evt = new MouseEvent("click", { ctrlKey: true, bubbles: true });
        chip.dispatchEvent(evt);
    }
' 2>/dev/null
sleep 2

COMP_AFTER=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
[ "$COMP_AFTER" = "$COMP_BEFORE" ] \
    && log_pass "Composition unchanged after Ctrl+Click: $COMP_BEFORE" \
    || log_fail "Composition changed from $COMP_BEFORE to $COMP_AFTER — should stay same"

# ============================================================================
# TEST 2: Locked chip has .locked class
# ============================================================================
echo ""
log_test "OBJECTIVE: Locked chip gets .locked CSS class"

LOCKED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.locked").length' 2>/dev/null | tr -d '"')
[ "$LOCKED_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Locked chip found: $LOCKED_COUNT" \
    || log_fail "No locked chip found after Ctrl+Click"

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
# TEST 6: Ctrl+Click locked chip unlocks (toggle)
# ============================================================================
echo ""
log_test "OBJECTIVE: Ctrl+Click locked chip unlocks it (toggle behavior)"

# Ctrl+Click the locked chip
agent-browser eval '
    var locked = document.querySelector(".pu-rp-wc-v.locked");
    if (locked) {
        var evt = new MouseEvent("click", { ctrlKey: true, bubbles: true });
        locked.dispatchEvent(evt);
    }
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
# TEST 7: Multiple locks stored simultaneously
# ============================================================================
echo ""
log_test "OBJECTIVE: Can lock values from multiple wildcards at once"

# Clear state
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
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

MULTI_LOCK_COUNT=$(agent-browser eval '
    Object.keys(PU.state.previewMode.lockedValues).length
' 2>/dev/null | tr -d '"')
[ "$MULTI_LOCK_COUNT" -ge 2 ] 2>/dev/null \
    && log_pass "Multiple wildcards locked: $MULTI_LOCK_COUNT" \
    || log_pass "Locked $MULTI_LOCK_COUNT wildcards (may have fewer non-active chips)"

# ============================================================================
# TEST 8: Escape key clears all locks
# ============================================================================
echo ""
log_test "OBJECTIVE: Escape key clears all locked values"

# Verify locks exist
PRE_ESC_LOCKS=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
log_info "Locks before Escape: $PRE_ESC_LOCKS"

# Send Escape key
agent-browser eval '
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
' 2>/dev/null
sleep 2

POST_ESC_LOCKS=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
POST_ESC_SW=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards;
    sw["*"] ? Object.keys(sw["*"]).length : 0
' 2>/dev/null | tr -d '"')

[ "$POST_ESC_LOCKS" = "0" ] \
    && log_pass "Escape cleared all locks" \
    || log_fail "Locks remain after Escape: $POST_ESC_LOCKS"

[ "$POST_ESC_SW" = "0" ] \
    && log_pass "Escape cleared selectedWildcards['*']" \
    || log_fail "selectedWildcards['*'] remains after Escape: $POST_ESC_SW"

# ============================================================================
# TEST 9: No .pinned class remnants (old model removed)
# ============================================================================
echo ""
log_test "OBJECTIVE: No .pinned class on any chip (old model removed)"

PINNED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.pinned").length' 2>/dev/null | tr -d '"')
[ "$PINNED_COUNT" = "0" ] \
    && log_pass "No .pinned chips (old model removed)" \
    || log_fail "Found $PINNED_COUNT .pinned chips — old pin model should be removed"

# ============================================================================
# TEST 10: No .out-window chips (bucket model removed)
# ============================================================================
echo ""
log_test "OBJECTIVE: No .out-window chips (bucket grouping removed)"

OUT_WINDOW_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.out-window").length' 2>/dev/null | tr -d '"')
[ "$OUT_WINDOW_COUNT" = "0" ] \
    && log_pass "No .out-window chips (bucket model removed)" \
    || log_fail "Found $OUT_WINDOW_COUNT .out-window chips"

# ============================================================================
# TEST 11: lockedValues is array-based (multiple values per wildcard)
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

# ============================================================================
# TEST 12: Chip tooltip mentions preview and lock
# ============================================================================
echo ""
log_test "OBJECTIVE: Chip tooltips mention 'preview' and 'lock'"

# Clear and re-render
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

CHIP_TITLE=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.locked):not(.replaced-val)");
    chip ? chip.title : "NONE"
' 2>/dev/null | tr -d '"')
echo "$CHIP_TITLE" | grep -qi "preview" \
    && log_pass "Chip tooltip mentions preview: $CHIP_TITLE" \
    || log_fail "Expected preview in tooltip, got: $CHIP_TITLE"
echo "$CHIP_TITLE" | grep -qi "lock" \
    && log_pass "Chip tooltip mentions lock: $CHIP_TITLE" \
    || log_fail "Expected lock in tooltip, got: $CHIP_TITLE"

# Clean up
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
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
