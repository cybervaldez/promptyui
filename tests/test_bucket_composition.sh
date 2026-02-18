#!/bin/bash
# ============================================================================
# E2E Test Suite: Bucket Composition & Pin-Aware Navigation
# ============================================================================
# Tests bucket-aware right panel, pin toggle, out-of-window navigation,
# pin-aware next/prev/shuffle, and the ext_wildcards_max → wildcards_max rename.
#
# Usage: ./tests/test_bucket_composition.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Bucket Composition & Pin-Aware Navigation"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load a job with wildcards ──────────────────────────────────
log_info "Loading product-content job..."
agent-browser open "$BASE_URL" 2>/dev/null
sleep 3

agent-browser find text "product-content" click 2>/dev/null
sleep 3

PROMPT_NAME=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
if [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ]; then
    log_pass "Prompt loaded: $PROMPT_NAME"
else
    log_fail "Could not load prompt (activePromptId: $PROMPT_NAME)"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

# ============================================================================
# TEST 1: Rename — state uses wildcardsMax (not extWildcardsMax)
# ============================================================================
echo ""
log_test "OBJECTIVE: State uses wildcardsMax after rename"

HAS_NEW=$(agent-browser eval 'PU.state.previewMode.wildcardsMax !== undefined' 2>/dev/null)
[ "$HAS_NEW" = "true" ] \
    && log_pass "PU.state.previewMode.wildcardsMax exists" \
    || log_fail "wildcardsMax should exist: $HAS_NEW"

HAS_OLD=$(agent-browser eval 'PU.state.previewMode.extWildcardsMax !== undefined' 2>/dev/null)
[ "$HAS_OLD" = "false" ] \
    && log_pass "extWildcardsMax is gone" \
    || log_fail "extWildcardsMax should not exist: $HAS_OLD"

# ============================================================================
# TEST 2: Rename — URL param still wc_max
# ============================================================================
echo ""
log_test "OBJECTIVE: URL param wc_max still loads into wildcardsMax"

agent-browser open "$BASE_URL?job=product-content&prompt=$PROMPT_NAME&wc_max=2" 2>/dev/null
sleep 3

WC_MAX_STATE=$(agent-browser eval 'PU.state.previewMode.wildcardsMax' 2>/dev/null | tr -d '"')
[ "$WC_MAX_STATE" = "2" ] \
    && log_pass "wc_max=2 URL param loaded into wildcardsMax" \
    || log_fail "wildcardsMax should be 2, got: $WC_MAX_STATE"

# Reset to 0
agent-browser eval 'PU.state.previewMode.wildcardsMax = 0' 2>/dev/null
agent-browser open "$BASE_URL?job=product-content&prompt=$PROMPT_NAME" 2>/dev/null
sleep 3

# ============================================================================
# TEST 3: wcMax=0 — no window frame
# ============================================================================
echo ""
log_test "OBJECTIVE: No window frame when wildcardsMax=0"

NO_FRAME=$(agent-browser eval '!document.querySelector(".pu-rp-wc-window-frame")' 2>/dev/null)
[ "$NO_FRAME" = "true" ] \
    && log_pass "No window frame at wcMax=0" \
    || log_fail "Window frame should not exist at wcMax=0"

# ============================================================================
# TEST 4: wcMax=2 — window frame present
# ============================================================================
echo ""
log_test "OBJECTIVE: Window frame present when wildcardsMax=2"

# Set wcMax=2 via the Build panel input
agent-browser eval 'PU.buildComposition.open()' 2>/dev/null
sleep 1
agent-browser eval '
    var input = document.querySelector("[data-testid=pu-build-defaults-ext-wc-max]");
    if (input) {
        input.value = 2;
        input.dispatchEvent(new Event("change"));
    }
' 2>/dev/null
sleep 3

HAS_FRAME=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-window-frame")' 2>/dev/null)
[ "$HAS_FRAME" = "true" ] \
    && log_pass "Window frame present at wcMax=2" \
    || log_fail "Window frame should exist at wcMax=2"

# ============================================================================
# TEST 5: wcMax=2 — badge shows bucket N
# ============================================================================
echo ""
log_test "OBJECTIVE: Window badge shows bucket number"

BADGE_TEXT=$(agent-browser eval '
    var badge = document.querySelector(".pu-rp-wc-window-badge");
    badge ? badge.textContent.trim().toLowerCase() : "MISSING"
' 2>/dev/null | tr -d '"')
echo "$BADGE_TEXT" | grep -qi "bucket" \
    && log_pass "Badge shows bucket label: $BADGE_TEXT" \
    || log_fail "Badge should contain 'bucket': $BADGE_TEXT"

# ============================================================================
# TEST 6: wcMax=2 — correct chip count in frame
# ============================================================================
echo ""
log_test "OBJECTIVE: Frame contains <= wcMax chips"

FRAME_CHIP_COUNT=$(agent-browser eval '
    var frame = document.querySelector(".pu-rp-wc-window-frame");
    frame ? frame.querySelectorAll(".pu-rp-wc-v").length : -1
' 2>/dev/null | tr -d '"')
[ "$FRAME_CHIP_COUNT" -le 2 ] 2>/dev/null && [ "$FRAME_CHIP_COUNT" -ge 1 ] 2>/dev/null \
    && log_pass "Frame has $FRAME_CHIP_COUNT chips (<= wcMax=2)" \
    || log_fail "Frame chip count should be 1-2, got: $FRAME_CHIP_COUNT"

# ============================================================================
# TEST 7: Out-of-window chips have .out-window class
# ============================================================================
echo ""
log_test "OBJECTIVE: Out-of-window chips exist with .out-window class"

OUT_WINDOW_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-rp-wc-v.out-window").length
' 2>/dev/null | tr -d '"')
[ "$OUT_WINDOW_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Out-of-window chips found: $OUT_WINDOW_COUNT" \
    || log_fail "Should have out-of-window chips when wcMax=2"

# ============================================================================
# TEST 8: Click out-of-window chip → composition changes
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking out-of-window chip changes composition"

COMP_BEFORE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v.out-window");
    if (chip) chip.click();
' 2>/dev/null
sleep 2

COMP_AFTER=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
[ "$COMP_AFTER" != "$COMP_BEFORE" ] \
    && log_pass "Out-of-window click changed comp: $COMP_BEFORE -> $COMP_AFTER" \
    || log_fail "Comp should change on out-of-window click: $COMP_BEFORE -> $COMP_AFTER"

# ============================================================================
# TEST 9: Click in-window chip → pin toggles
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking in-window chip toggles pin"

agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-window-frame .pu-rp-wc-v");
    if (chip) chip.click();
' 2>/dev/null
sleep 2

HAS_PINNED=$(agent-browser eval '
    !!document.querySelector(".pu-rp-wc-window-frame .pu-rp-wc-v.pinned")
' 2>/dev/null)
[ "$HAS_PINNED" = "true" ] \
    && log_pass "In-window chip toggled to pinned" \
    || log_fail "Should have .pinned class after click"

# Check state has pin
PIN_COUNT=$(agent-browser eval '
    var pins = PU.state.previewMode.selectedWildcards["*"];
    pins ? Object.keys(pins).length : 0
' 2>/dev/null | tr -d '"')
[ "$PIN_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "State has $PIN_COUNT global pin(s)" \
    || log_fail "State should have pins"

# ============================================================================
# TEST 10: Navigate with pin — pinned bucket preserved
# ============================================================================
echo ""
log_test "OBJECTIVE: Next preserves pinned bucket index"

# Get pinned wildcard name and its bucket index
PINNED_WC=$(agent-browser eval '
    var pins = PU.state.previewMode.selectedWildcards["*"];
    pins ? Object.keys(pins)[0] : "NONE"
' 2>/dev/null | tr -d '"')
log_info "Pinned wildcard: $PINNED_WC"

BUCKET_BEFORE=$(agent-browser eval '
    var p = PU.buildComposition._getCompositionParams();
    var br = PU.preview.bucketCompositionToIndices(
        PU.state.previewMode.compositionId, p.extTextCount, p.extTextMax, p.wildcardCounts, p.wcMax
    );
    br.wcBucketIndices["'"$PINNED_WC"'"]
' 2>/dev/null | tr -d '"')

agent-browser eval 'document.querySelector("[data-testid=pu-rp-nav-next]").click()' 2>/dev/null
sleep 2

BUCKET_AFTER=$(agent-browser eval '
    var p = PU.buildComposition._getCompositionParams();
    var br = PU.preview.bucketCompositionToIndices(
        PU.state.previewMode.compositionId, p.extTextCount, p.extTextMax, p.wildcardCounts, p.wcMax
    );
    br.wcBucketIndices["'"$PINNED_WC"'"]
' 2>/dev/null | tr -d '"')

[ "$BUCKET_AFTER" = "$BUCKET_BEFORE" ] \
    && log_pass "Pinned bucket preserved after Next: bucket=$BUCKET_BEFORE" \
    || log_fail "Pinned bucket should be $BUCKET_BEFORE, got: $BUCKET_AFTER"

# ============================================================================
# TEST 11: Shuffle with pin — pinned bucket preserved
# ============================================================================
echo ""
log_test "OBJECTIVE: Shuffle preserves pinned bucket index"

BUCKET_BEFORE=$(agent-browser eval '
    var p = PU.buildComposition._getCompositionParams();
    var br = PU.preview.bucketCompositionToIndices(
        PU.state.previewMode.compositionId, p.extTextCount, p.extTextMax, p.wildcardCounts, p.wcMax
    );
    br.wcBucketIndices["'"$PINNED_WC"'"]
' 2>/dev/null | tr -d '"')

agent-browser eval 'document.querySelector("[data-testid=pu-rp-nav-shuffle]").click()' 2>/dev/null
sleep 2

BUCKET_AFTER=$(agent-browser eval '
    var p = PU.buildComposition._getCompositionParams();
    var br = PU.preview.bucketCompositionToIndices(
        PU.state.previewMode.compositionId, p.extTextCount, p.extTextMax, p.wildcardCounts, p.wcMax
    );
    br.wcBucketIndices["'"$PINNED_WC"'"]
' 2>/dev/null | tr -d '"')

[ "$BUCKET_AFTER" = "$BUCKET_BEFORE" ] \
    && log_pass "Pinned bucket preserved after Shuffle: bucket=$BUCKET_BEFORE" \
    || log_fail "Pinned bucket should be $BUCKET_BEFORE, got: $BUCKET_AFTER"

# ============================================================================
# TEST 12: Change wcMax clears pins
# ============================================================================
echo ""
log_test "OBJECTIVE: Changing wildcardsMax clears all pins"

# First confirm we have pins
PRE_PINS=$(agent-browser eval '
    var pins = PU.state.previewMode.selectedWildcards["*"];
    pins ? Object.keys(pins).length : 0
' 2>/dev/null | tr -d '"')
log_info "Pins before wcMax change: $PRE_PINS"

# Change wcMax from 2 to 3
agent-browser eval '
    var input = document.querySelector("[data-testid=pu-build-defaults-ext-wc-max]");
    if (input) {
        input.value = 3;
        input.dispatchEvent(new Event("change"));
    }
' 2>/dev/null
sleep 2

POST_PINS=$(agent-browser eval '
    var pins = PU.state.previewMode.selectedWildcards["*"];
    pins ? Object.keys(pins).length : 0
' 2>/dev/null | tr -d '"')
[ "$POST_PINS" = "0" ] \
    && log_pass "Pins cleared after wcMax change" \
    || log_fail "Pins should be cleared, got $POST_PINS pins"

# ============================================================================
# TEST 13: Block dropdown pin shows asterisk in right panel
# ============================================================================
echo ""
log_test "OBJECTIVE: Block dropdown pin shows asterisk indicator in right panel"

# Close build panel first
agent-browser eval 'PU.buildComposition.close()' 2>/dev/null
sleep 1

# Reset wcMax to 0 for cleaner test
agent-browser eval '
    PU.state.previewMode.wildcardsMax = 0;
' 2>/dev/null
sleep 1

# Find a wildcard dropdown in the editor and pin a value via block path
BLOCK_PIN_RESULT=$(agent-browser eval '
    // Find first block with a wildcard dropdown
    var dd = document.querySelector(".pu-wc-dropdown");
    if (dd) {
        var wcName = dd.dataset.wc;
        var blockPath = dd.closest(".pu-block[data-path]") ? dd.closest(".pu-block[data-path]").dataset.path : null;
        var values = JSON.parse(dd.dataset.values || "[]");
        if (wcName && blockPath && values.length > 0) {
            // Pin first value via state
            if (!PU.state.previewMode.selectedWildcards[blockPath]) {
                PU.state.previewMode.selectedWildcards[blockPath] = {};
            }
            PU.state.previewMode.selectedWildcards[blockPath][wcName] = values[0];
            "pinned:" + wcName;
        } else { "no-dropdown"; }
    } else { "no-dropdown"; }
' 2>/dev/null | tr -d '"')

if echo "$BLOCK_PIN_RESULT" | grep -q "pinned:"; then
    # Re-render right panel
    agent-browser eval 'PU.rightPanel.render()' 2>/dev/null
    sleep 1

    PINNED_WC_NAME=$(echo "$BLOCK_PIN_RESULT" | sed 's/pinned://')
    HAS_INDICATOR=$(agent-browser eval '
        !!document.querySelector(".pin-indicator")
    ' 2>/dev/null)
    [ "$HAS_INDICATOR" = "true" ] \
        && log_pass "Asterisk indicator shown for block-pinned wildcard: $PINNED_WC_NAME" \
        || log_fail "Pin indicator should appear for $PINNED_WC_NAME"

    # Clean up block pin
    agent-browser eval 'PU.state.previewMode.selectedWildcards = {}' 2>/dev/null
else
    log_skip "No wildcard dropdowns in editor to test block pins"
fi

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
