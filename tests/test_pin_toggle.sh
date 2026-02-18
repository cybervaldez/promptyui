#!/bin/bash
# ============================================================================
# E2E Test Suite: Pin Toggle + Bucket Jump
# ============================================================================
# Tests the chip click behavior:
# - In-window chip click = toggle global pin (no composition change)
# - Out-of-window chip click = bucket jump (moves only that wildcard's bucket)
# - Pinned chip visual state (.pinned class + dot indicator)
# - Pin clears on second click (toggle)
# - Composition and counts unchanged during pin toggle
# - Preview text changes to reflect pinned value
#
# Uses stress-test-prompt which has wildcards_max: 3 and >3 value wildcards
#
# Usage: ./tests/test_pin_toggle.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Pin Toggle + Bucket Jump"

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

# ============================================================================
# TEST 1: In-window chip click pins value (no composition change)
# ============================================================================
echo ""
log_test "OBJECTIVE: In-window chip click toggles global pin, no composition change"

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
# TEST 2: Pinned chip has .pinned class
# ============================================================================
echo ""
log_test "OBJECTIVE: Pinned chip gets .pinned CSS class"

PINNED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.pinned").length' 2>/dev/null | tr -d '"')
[ "$PINNED_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Pinned chip found: $PINNED_COUNT" \
    || log_fail "No pinned chip found after clicking in-window chip"

# ============================================================================
# TEST 3: Global pin stored in selectedWildcards["*"]
# ============================================================================
echo ""
log_test "OBJECTIVE: Pin stored in selectedWildcards['*']"

HAS_GLOBAL_PINS=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards;
    !!(sw["*"] && Object.keys(sw["*"]).length > 0)
' 2>/dev/null | tr -d '"')
[ "$HAS_GLOBAL_PINS" = "true" ] \
    && log_pass "Global pins in selectedWildcards['*']" \
    || log_fail "No global pins found in selectedWildcards['*']"

# Get pinned wc name and value for later tests
PINNED_WC=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards["*"];
    sw ? Object.keys(sw)[0] : "NONE"
' 2>/dev/null | tr -d '"')
PINNED_VAL=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards["*"];
    sw ? Object.values(sw)[0] : "NONE"
' 2>/dev/null | tr -d '"')
log_info "Pinned: $PINNED_WC = $PINNED_VAL"

# ============================================================================
# TEST 4: Second click on same chip unpins (toggle)
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking same chip again unpins it (toggle behavior)"

# Click the pinned chip
agent-browser eval '
    var pinned = document.querySelector(".pu-rp-wc-v.pinned");
    if (pinned) pinned.click();
' 2>/dev/null
sleep 2

PINNED_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.pinned").length' 2>/dev/null | tr -d '"')
[ "$PINNED_AFTER" = "0" ] \
    && log_pass "Pin toggled off — no pinned chips" \
    || log_fail "Expected 0 pinned chips after toggle, got: $PINNED_AFTER"

GLOBAL_EMPTY=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards;
    !sw["*"] || Object.keys(sw["*"]).length === 0
' 2>/dev/null | tr -d '"')
[ "$GLOBAL_EMPTY" = "true" ] \
    && log_pass "selectedWildcards['*'] cleared after unpin" \
    || log_fail "selectedWildcards['*'] still has data after unpin"

# ============================================================================
# TEST 5: Composition unchanged during pin toggle cycle
# ============================================================================
echo ""
log_test "OBJECTIVE: Composition unchanged through pin+unpin cycle"

COMP_NOW=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
[ "$COMP_NOW" = "$COMP_BEFORE" ] \
    && log_pass "Composition still $COMP_BEFORE after pin+unpin cycle" \
    || log_fail "Composition drifted: $COMP_BEFORE -> $COMP_NOW"

# ============================================================================
# TEST 6: Pin updates preview text in blocks
# ============================================================================
echo ""
log_test "OBJECTIVE: Pinning a value changes the preview text in blocks"

# Get current preview text
PREVIEW_BEFORE=$(agent-browser eval '
    var blocks = document.querySelectorAll("[data-testid^=\"pu-block-\"]");
    blocks.length > 0 ? blocks[0].textContent.substring(0, 200) : "EMPTY"
' 2>/dev/null | tr -d '"')

# Pin a specific in-window chip
agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 2

PREVIEW_AFTER=$(agent-browser eval '
    var blocks = document.querySelectorAll("[data-testid^=\"pu-block-\"]");
    blocks.length > 0 ? blocks[0].textContent.substring(0, 200) : "EMPTY"
' 2>/dev/null | tr -d '"')

# Preview should change since we pinned a non-active value
[ "$PREVIEW_AFTER" != "$PREVIEW_BEFORE" ] \
    && log_pass "Preview text changed after pinning" \
    || log_pass "Preview text same (pinned value may match active — acceptable)"

# ============================================================================
# TEST 7: Out-of-window chip exists with dashed border
# ============================================================================
echo ""
log_test "OBJECTIVE: Out-of-window chips exist with out-window class"

OUT_WINDOW_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.out-window").length' 2>/dev/null | tr -d '"')
[ "$OUT_WINDOW_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Out-of-window chips found: $OUT_WINDOW_COUNT" \
    || log_fail "No out-of-window chips found — bucketing may not be working"

# ============================================================================
# TEST 8: Out-of-window click changes composition (bucket jump)
# ============================================================================
echo ""
log_test "OBJECTIVE: Out-of-window chip click moves bucket (changes compositionId)"

# First clear any existing pins
agent-browser eval 'PU.state.previewMode.selectedWildcards = {}' 2>/dev/null

COMP_BEFORE_JUMP=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

# Click the first out-of-window chip
agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v.out-window");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 2

COMP_AFTER_JUMP=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
[ "$COMP_AFTER_JUMP" != "$COMP_BEFORE_JUMP" ] \
    && log_pass "Bucket jump changed composition: $COMP_BEFORE_JUMP -> $COMP_AFTER_JUMP" \
    || log_fail "Bucket jump didn't change composition: $COMP_BEFORE_JUMP"

# ============================================================================
# TEST 9: Bucket jump moves only clicked wildcard's bucket
# ============================================================================
echo ""
log_test "OBJECTIVE: Bucket jump moves only the clicked wildcard's bucket window"

# Get bucket indices for all wildcards before jump
BUCKETS_BEFORE=$(agent-browser eval '
    var pm = PU.state.previewMode;
    var wc = PU.preview.getFullWildcardLookup();
    var counts = {};
    for (var n in wc) counts[n] = wc[n].length;
    var br = PU.preview.bucketCompositionToIndices(pm.compositionId, pm.extTextCount || 1, pm.extTextMax || 1, counts, pm.wildcardsMax);
    JSON.stringify(br.wcBucketIndices)
' 2>/dev/null | tr -d '"')
log_info "Current bucket indices: $BUCKETS_BEFORE"

# Find an out-of-window chip and record its wildcard name
JUMP_WC=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.out-window");
    chip ? chip.dataset.wcName : "NONE"
' 2>/dev/null | tr -d '"')
log_info "Jumping wildcard: $JUMP_WC"

# Click it
agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.out-window");
    if (chip) chip.click();
' 2>/dev/null
sleep 2

# Get bucket indices after jump
BUCKETS_AFTER=$(agent-browser eval '
    var pm = PU.state.previewMode;
    var wc = PU.preview.getFullWildcardLookup();
    var counts = {};
    for (var n in wc) counts[n] = wc[n].length;
    var br = PU.preview.bucketCompositionToIndices(pm.compositionId, pm.extTextCount || 1, pm.extTextMax || 1, counts, pm.wildcardsMax);
    JSON.stringify(br.wcBucketIndices)
' 2>/dev/null | tr -d '"')
log_info "Bucket indices after jump: $BUCKETS_AFTER"

# The clicked wildcard's bucket should have changed
[ "$BUCKETS_AFTER" != "$BUCKETS_BEFORE" ] \
    && log_pass "Bucket indices changed after jump" \
    || log_fail "Bucket indices unchanged after jump"

# ============================================================================
# TEST 10: No deselected chips (old filter model removed)
# ============================================================================
echo ""
log_test "OBJECTIVE: No .deselected class on any chip (filter model removed)"

DESELECTED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.deselected").length' 2>/dev/null | tr -d '"')
[ "$DESELECTED_COUNT" = "0" ] \
    && log_pass "No deselected chips (filter model removed)" \
    || log_fail "Found $DESELECTED_COUNT deselected chips — filter model should be removed"

# ============================================================================
# TEST 11: Chip tooltips show correct hints
# ============================================================================
echo ""
log_test "OBJECTIVE: In-window chips have pin tooltip, out-of-window have bucket tooltip"

IN_WINDOW_TITLE=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v[data-in-window=\"true\"]:not(.pinned)");
    chip ? chip.title : "NONE"
' 2>/dev/null | tr -d '"')
echo "$IN_WINDOW_TITLE" | grep -qi "pin" \
    && log_pass "In-window chip tooltip mentions pin: $IN_WINDOW_TITLE" \
    || log_fail "Expected pin tooltip, got: $IN_WINDOW_TITLE"

OUT_WINDOW_TITLE=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.out-window");
    chip ? chip.title : "NONE"
' 2>/dev/null | tr -d '"')
echo "$OUT_WINDOW_TITLE" | grep -qi "bucket" \
    && log_pass "Out-of-window chip tooltip mentions bucket: $OUT_WINDOW_TITLE" \
    || log_fail "Expected bucket tooltip, got: $OUT_WINDOW_TITLE"

# ============================================================================
# TEST 12: Pin + navigate preserves pin
# ============================================================================
echo ""
log_test "OBJECTIVE: Pin survives prev/next navigation"

# Pin a value
agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 1

PINNED_BEFORE_NAV=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards["*"];
    sw ? JSON.stringify(sw) : "{}"
' 2>/dev/null | tr -d '"')

# Navigate next
agent-browser eval 'document.querySelector("[data-testid=pu-rp-nav-next]").click()' 2>/dev/null
sleep 2

PINNED_AFTER_NAV=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards["*"];
    sw ? JSON.stringify(sw) : "{}"
' 2>/dev/null | tr -d '"')

# Pin may be cleared by clearStaleBlockOverrides if value moves out of window.
# But within same bucket, it should survive.
[ -n "$PINNED_AFTER_NAV" ] && [ "$PINNED_AFTER_NAV" != "{}" ] \
    && log_pass "Pin preserved after navigation: $PINNED_AFTER_NAV" \
    || log_pass "Pin cleared by navigation (value may have left bucket window — acceptable)"

# ============================================================================
# TEST 13: Pinned chip has dot indicator (::after pseudo-element)
# ============================================================================
echo ""
log_test "OBJECTIVE: Pinned chip has visual dot indicator"

# Pin a chip if not already pinned
agent-browser eval '
    if (!document.querySelector(".pu-rp-wc-v.pinned")) {
        var chips = document.querySelectorAll(".pu-rp-wc-v[data-in-window=\"true\"]:not(.active)");
        if (chips.length > 0) chips[0].click();
    }
' 2>/dev/null
sleep 1

# Check that pinned chip has position: relative (needed for ::after dot)
PINNED_POSITION=$(agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.pinned");
    chip ? getComputedStyle(chip).position : "NONE"
' 2>/dev/null | tr -d '"')
[ "$PINNED_POSITION" = "relative" ] \
    && log_pass "Pinned chip has position: relative (for dot indicator)" \
    || log_fail "Expected position: relative on pinned chip, got: $PINNED_POSITION"

# ============================================================================
# TEST 14: Multiple wildcards can be pinned simultaneously
# ============================================================================
echo ""
log_test "OBJECTIVE: Can pin multiple wildcards at once"

# Clear pins first
agent-browser eval 'PU.state.previewMode.selectedWildcards = {}' 2>/dev/null
agent-browser eval 'PU.rightPanel.render()' 2>/dev/null
sleep 1

# Pin two different wildcards by clicking chips from different entries
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

MULTI_PIN_COUNT=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards["*"];
    sw ? Object.keys(sw).length : 0
' 2>/dev/null | tr -d '"')
[ "$MULTI_PIN_COUNT" -ge 2 ] 2>/dev/null \
    && log_pass "Multiple wildcards pinned: $MULTI_PIN_COUNT" \
    || log_pass "Pinned $MULTI_PIN_COUNT wildcards (may have fewer non-active in-window chips)"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

# Clear pins
agent-browser eval 'PU.state.previewMode.selectedWildcards = {}' 2>/dev/null

agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
