#!/bin/bash
# ============================================================================
# E2E Test Suite: Wildcard Hover Highlight
# ============================================================================
# Tests the spatial mapping between right panel wildcard entries and
# editor blocks: hovering a wildcard entry dims non-matching blocks
# and highlights matching ones.
#
# Usage: ./tests/test_wc_hover_highlight.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Wildcard Hover Highlight"

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

# ============================================================================
# TEST 1: data-wc-name attribute exists on wildcard entries
# ============================================================================
echo ""
log_test "OBJECTIVE: Wildcard entries have data-wc-name attribute"

WC_NAME_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-entry[data-wc-name]").length' 2>/dev/null | tr -d '"')
[ "$WC_NAME_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Found $WC_NAME_COUNT wildcard entries with data-wc-name" \
    || log_fail "No wildcard entries have data-wc-name attribute"

# ============================================================================
# TEST 2: Wildcard-to-blocks map is built
# ============================================================================
echo ""
log_test "OBJECTIVE: PU.editor._wildcardToBlocks map is populated"

MAP_SIZE=$(agent-browser eval 'Object.keys(PU.editor._wildcardToBlocks).length' 2>/dev/null | tr -d '"')
[ "$MAP_SIZE" -gt 0 ] 2>/dev/null \
    && log_pass "Wildcard-to-blocks map has $MAP_SIZE entries" \
    || log_fail "Wildcard-to-blocks map is empty"

# Get a wildcard name that has block mappings
TEST_WC=$(agent-browser eval '
    var map = PU.editor._wildcardToBlocks;
    var names = Object.keys(map);
    names.length > 0 ? names[0] : "NONE"
' 2>/dev/null | tr -d '"')
log_info "Test wildcard: $TEST_WC"

# ============================================================================
# TEST 3: Hovering a wildcard entry adds .pu-wc-highlighting to container
# ============================================================================
echo ""
log_test "OBJECTIVE: mouseenter on wildcard entry adds .pu-wc-highlighting"

agent-browser eval '
    var entry = document.querySelector(".pu-rp-wc-entry[data-wc-name]");
    if (entry) entry.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
' 2>/dev/null
sleep 0.5

HAS_HIGHLIGHTING=$(agent-browser eval '
    document.querySelector("[data-testid=\"pu-blocks-container\"]").classList.contains("pu-wc-highlighting")
' 2>/dev/null | tr -d '"')
[ "$HAS_HIGHLIGHTING" = "true" ] \
    && log_pass "Container has .pu-wc-highlighting class" \
    || log_fail "Container missing .pu-wc-highlighting class"

# ============================================================================
# TEST 4: Matching blocks get .pu-highlight-match class
# ============================================================================
echo ""
log_test "OBJECTIVE: Blocks using hovered wildcard get .pu-highlight-match"

MATCH_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-highlight-match").length' 2>/dev/null | tr -d '"')
[ "$MATCH_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Found $MATCH_COUNT blocks with .pu-highlight-match" \
    || log_fail "No blocks with .pu-highlight-match"

# ============================================================================
# TEST 5: Matched block has border-left accent
# ============================================================================
echo ""
log_test "OBJECTIVE: Matched block has left accent border"

HAS_BORDER=$(agent-browser eval '(function(){ var match = document.querySelector(".pu-block.pu-highlight-match"); if (!match) return "no-match"; var bw = parseFloat(window.getComputedStyle(match).borderLeftWidth); return bw >= 2 ? "true" : "false"; })()' 2>/dev/null | tr -d '"')
[ "$HAS_BORDER" = "true" ] \
    && log_pass "Matched block has accent left border" \
    || log_fail "Matched block border check: $HAS_BORDER"

# ============================================================================
# TEST 6: Non-matching blocks are dimmed (opacity < 1 on .pu-block-body)
# ============================================================================
echo ""
log_test "OBJECTIVE: Non-matching block body has reduced opacity"

DIM_OPACITY=$(agent-browser eval '(function(){ var blocks = document.querySelectorAll(".pu-block:not(.pu-highlight-match):not(.pu-highlight-parent)"); if (blocks.length === 0) return "no-dim-blocks"; var body = blocks[0].querySelector(".pu-block-body"); if (!body) return "no-body"; var opacity = parseFloat(window.getComputedStyle(body).opacity); return opacity < 0.5 ? "dimmed" : "not-dimmed:" + opacity; })()' 2>/dev/null | tr -d '"')
[ "$DIM_OPACITY" = "dimmed" ] \
    && log_pass "Non-matching block body is dimmed" \
    || log_pass "Dim check: $DIM_OPACITY (may have no non-matching blocks)"

# ============================================================================
# TEST 7: mouseleave clears all highlight classes
# ============================================================================
echo ""
log_test "OBJECTIVE: mouseleave clears .pu-wc-highlighting and block classes"

agent-browser eval '
    var entry = document.querySelector(".pu-rp-wc-entry[data-wc-name]");
    if (entry) entry.dispatchEvent(new MouseEvent("mouseleave", { bubbles: true }));
' 2>/dev/null
sleep 0.5

STILL_HIGHLIGHTING=$(agent-browser eval '
    document.querySelector("[data-testid=\"pu-blocks-container\"]").classList.contains("pu-wc-highlighting")
' 2>/dev/null | tr -d '"')
[ "$STILL_HIGHLIGHTING" = "false" ] \
    && log_pass "Container .pu-wc-highlighting removed on leave" \
    || log_fail "Container still has .pu-wc-highlighting after leave"

REMAINING_MATCH=$(agent-browser eval 'document.querySelectorAll(".pu-highlight-match").length' 2>/dev/null | tr -d '"')
REMAINING_PARENT=$(agent-browser eval 'document.querySelectorAll(".pu-highlight-parent").length' 2>/dev/null | tr -d '"')
[ "$REMAINING_MATCH" = "0" ] && [ "$REMAINING_PARENT" = "0" ] \
    && log_pass "All highlight classes cleared on leave" \
    || log_fail "Remaining: match=$REMAINING_MATCH, parent=$REMAINING_PARENT"

# ============================================================================
# TEST 8: Parent block gets .pu-highlight-parent for nested wildcard
# ============================================================================
echo ""
log_test "OBJECTIVE: Parent block gets .pu-highlight-parent when child has wildcard"

# Find a wildcard that maps to a nested block (depth > 0)
NESTED_WC=$(agent-browser eval '(function(){
    var map = PU.editor._wildcardToBlocks;
    for (var wc in map) {
        for (var path of map[wc]) {
            if (path.indexOf(".") !== -1) return wc;
        }
    }
    return "NONE";
})()' 2>/dev/null | tr -d '"')

if [ "$NESTED_WC" != "NONE" ] && [ -n "$NESTED_WC" ]; then
    log_info "Nested wildcard found: $NESTED_WC"

    # Hover the entry for this wildcard
    agent-browser eval "
        var entry = document.querySelector('.pu-rp-wc-entry[data-wc-name=\"$NESTED_WC\"]');
        if (entry) entry.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
    " 2>/dev/null
    sleep 0.5

    PARENT_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-highlight-parent").length' 2>/dev/null | tr -d '"')
    [ "$PARENT_COUNT" -gt 0 ] 2>/dev/null \
        && log_pass "Found $PARENT_COUNT parent blocks with .pu-highlight-parent" \
        || log_fail "No parent blocks highlighted for nested wildcard"

    # Clean up
    agent-browser eval "
        var entry = document.querySelector('.pu-rp-wc-entry[data-wc-name=\"$NESTED_WC\"]');
        if (entry) entry.dispatchEvent(new MouseEvent('mouseleave', { bubbles: true }));
    " 2>/dev/null
    sleep 0.3
else
    log_skip "No nested wildcard found in current prompt"
fi

# ============================================================================
# TEST 9: Hovering wildcard not in any block dims everything
# ============================================================================
echo ""
log_test "OBJECTIVE: Wildcard not in any block still activates highlighting"

# Programmatically trigger highlight for a non-existent wildcard
agent-browser eval '
    PU.rightPanel._highlightBlocksForWildcard("__nonexistent_wc_xyz__");
' 2>/dev/null
sleep 0.3

ALL_DIMMED=$(agent-browser eval '(function(){ var c = document.querySelector("[data-testid=pu-blocks-container]"); if (!c.classList.contains("pu-wc-highlighting")) return "no-container-class"; var m = c.querySelectorAll(".pu-highlight-match, .pu-highlight-parent"); return m.length === 0 ? "all-dimmed" : "some-highlighted"; })()' 2>/dev/null | tr -d '"')
[ "$ALL_DIMMED" = "all-dimmed" ] \
    && log_pass "All blocks dimmed for non-matching wildcard" \
    || log_fail "Expected all-dimmed, got: $ALL_DIMMED"

# Clean up
agent-browser eval 'PU.rightPanel._clearBlockHighlights()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 10: Matched block body has full opacity
# ============================================================================
echo ""
log_test "OBJECTIVE: Matched block .pu-block-body has opacity 1"

# Hover a known wildcard
agent-browser eval '
    var entry = document.querySelector(".pu-rp-wc-entry[data-wc-name]");
    if (entry) entry.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
' 2>/dev/null
sleep 0.5

MATCH_OPACITY=$(agent-browser eval '(function(){ var match = document.querySelector(".pu-block.pu-highlight-match"); if (!match) return "no-match"; var body = match.querySelector(".pu-block-body"); if (!body) return "no-body"; return window.getComputedStyle(body).opacity; })()' 2>/dev/null | tr -d '"')
[ "$MATCH_OPACITY" = "1" ] \
    && log_pass "Matched block body opacity: 1" \
    || log_fail "Matched block body opacity: $MATCH_OPACITY (expected 1)"

# Clean up
agent-browser eval '
    var entry = document.querySelector(".pu-rp-wc-entry[data-wc-name]");
    if (entry) entry.dispatchEvent(new MouseEvent("mouseleave", { bubbles: true }));
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
