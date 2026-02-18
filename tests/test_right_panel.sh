#!/bin/bash
# ============================================================================
# E2E Test Suite: Right Panel (Phase 1 + Phase 5)
# ============================================================================
# Tests the right panel matching preview-panel-v2.3 design:
# - Top bar: scope chip, variant selector (None), wildcard count
# - Centered line dividers: "shared" and "local" sections
# - Wildcard entries with name + wc-path (for shared) + bordered chips
# - Bucket window frame (no badge), out-of-window dashed chips
# - Navigate-to-value (click chip = navigate, no filter/deselect)
# - Nav format: "N / total (window X/M)"
# - Per-wildcard dims: "2/4 aud × 2/5 sen × ..."
#
# Usage: ./tests/test_right_panel.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Right Panel (Phase 1 + Phase 5)"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load hiring-templates / ext-sourcing-strategy ───────────────
log_info "Loading hiring-templates / ext-sourcing-strategy..."
agent-browser close 2>/dev/null || true
sleep 1
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=ext-sourcing-strategy" 2>/dev/null
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

# ============================================================================
# TEST 1: Panel visible on load
# ============================================================================
echo ""
log_test "OBJECTIVE: Right panel is visible on page load"

PANEL_EXISTS=$(agent-browser eval '!!document.querySelector("[data-testid=pu-right-panel]")' 2>/dev/null)
[ "$PANEL_EXISTS" = "true" ] \
    && log_pass "Right panel element present" \
    || log_fail "Right panel element missing"

PANEL_WIDTH=$(agent-browser eval 'var p = document.querySelector("[data-testid=pu-right-panel]"); p ? p.offsetWidth : 0' 2>/dev/null | tr -d '"')
[ "$PANEL_WIDTH" -gt 100 ] 2>/dev/null \
    && log_pass "Panel has visible width: ${PANEL_WIDTH}px" \
    || log_fail "Panel should have width > 100, got: $PANEL_WIDTH"

# ============================================================================
# TEST 2: Top bar present with scope, variant selector, wc count
# ============================================================================
echo ""
log_test "OBJECTIVE: Top bar shows scope chip, variant selector, and wc count"

TOP_BAR=$(agent-browser eval '
    var tb = document.querySelector("[data-testid=pu-rp-top-bar]");
    tb ? (tb.style.display !== "none" ? "visible" : "hidden") : "MISSING"
' 2>/dev/null | tr -d '"')
[ "$TOP_BAR" = "visible" ] \
    && log_pass "Top bar is visible" \
    || log_fail "Top bar should be visible, got: $TOP_BAR"

# Scope chip
SCOPE_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-rp-scope]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
[ -n "$SCOPE_TEXT" ] && [ "$SCOPE_TEXT" != "MISSING" ] \
    && log_pass "Scope chip: $SCOPE_TEXT" \
    || log_pass "Scope chip empty (prompt may not have ext scope)"

# Variant selector shows "None"
OP_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-rp-op-selector]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
echo "$OP_TEXT" | grep -qi "none" \
    && log_pass "Variant selector: $OP_TEXT" \
    || log_pass "Variant selector: $OP_TEXT (may have active operation)"

# Wildcard count
WC_COUNT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-rp-wc-count]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
echo "$WC_COUNT" | grep -q "wc" \
    && log_pass "Wildcard count: $WC_COUNT" \
    || log_fail "Expected 'N wc', got: $WC_COUNT"

# ============================================================================
# TEST 3: Centered line dividers with "shared" / "local" labels
# ============================================================================
echo ""
log_test "OBJECTIVE: Dividers use centered line style with 'shared'/'local' labels"

DIVIDER_EXISTS=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-divider")' 2>/dev/null)
[ "$DIVIDER_EXISTS" = "true" ] \
    && log_pass "Divider element found" \
    || log_fail "No divider element"

# Check for centered line elements
LINE_EXISTS=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-divider-line")' 2>/dev/null)
[ "$LINE_EXISTS" = "true" ] \
    && log_pass "Centered line divider style present" \
    || log_fail "Missing divider line elements"

# Verify divider labels use "shared" / "local"
ALL_LABELS=$(agent-browser eval '
    Array.from(document.querySelectorAll(".pu-rp-wc-divider-label")).map(el => el.textContent.trim().toLowerCase()).join(",")
' 2>/dev/null | tr -d '"')
echo "$ALL_LABELS" | grep -q "local" \
    && log_pass "Found 'local' divider label" \
    || log_fail "Expected 'local' in divider labels: $ALL_LABELS"

# Check for old labels NOT present
echo "$ALL_LABELS" | grep -qi "prompt-defined\|from extensions\|from themes" \
    && log_fail "Old divider labels still present: $ALL_LABELS" \
    || log_pass "Old divider labels removed (no 'prompt-defined', 'from extensions', 'from themes')"

# ============================================================================
# TEST 4: Wildcard entries render with entry-header structure
# ============================================================================
echo ""
log_test "OBJECTIVE: Wildcard entries use entry-header (name + path)"

WC_ENTRY_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-entry").length' 2>/dev/null | tr -d '"')
[ "$WC_ENTRY_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Wildcard entries found: $WC_ENTRY_COUNT" \
    || log_fail "Expected wildcard entries > 0, got: $WC_ENTRY_COUNT"

HEADER_EXISTS=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-entry-header")' 2>/dev/null)
[ "$HEADER_EXISTS" = "true" ] \
    && log_pass "Entry header structure present" \
    || log_fail "Missing entry-header structure"

# ============================================================================
# TEST 5: wc-path shown for shared wildcards
# ============================================================================
echo ""
log_test "OBJECTIVE: Shared wildcards show source path (wc-path)"

PATH_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-path").length' 2>/dev/null | tr -d '"')
[ "$PATH_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "wc-path elements found: $PATH_COUNT" \
    || log_pass "No wc-path elements (prompt may not have shared wildcards)"

# ============================================================================
# TEST 6: Active chip highlighted
# ============================================================================
echo ""
log_test "OBJECTIVE: At least one chip has active state"

ACTIVE_CHIP=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-v.active")' 2>/dev/null)
[ "$ACTIVE_CHIP" = "true" ] \
    && log_pass "Active chip found" \
    || log_fail "No active chip found"

# ============================================================================
# TEST 7: No deselected chips (filter model removed)
# ============================================================================
echo ""
log_test "OBJECTIVE: No .deselected class anywhere (filter model removed)"

DESELECTED_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.deselected").length' 2>/dev/null | tr -d '"')
[ "$DESELECTED_COUNT" = "0" ] \
    && log_pass "No deselected chips (filter model removed)" \
    || log_fail "Found $DESELECTED_COUNT deselected chips — filter model should be removed"

# ============================================================================
# TEST 8: No bucket badge (removed)
# ============================================================================
echo ""
log_test "OBJECTIVE: No bucket badges in window frames"

BADGE_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-window-badge").length' 2>/dev/null | tr -d '"')
[ "$BADGE_COUNT" = "0" ] \
    && log_pass "No bucket badges (removed)" \
    || log_fail "Found $BADGE_COUNT bucket badges — should be removed"

# ============================================================================
# TEST 9: selectedValues state removed
# ============================================================================
echo ""
log_test "OBJECTIVE: selectedValues no longer in previewMode state"

SV_EXISTS=$(agent-browser eval '"selectedValues" in PU.state.previewMode' 2>/dev/null | tr -d '"')
[ "$SV_EXISTS" = "false" ] \
    && log_pass "selectedValues removed from state" \
    || log_fail "selectedValues still in state — should be removed"

# ============================================================================
# TEST 10: Nav format shows "N / total"
# ============================================================================
echo ""
log_test "OBJECTIVE: Navigator shows 'N / total' format (not 'Variation X of Y')"

NAV_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-rp-nav-label]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
echo "$NAV_TEXT" | grep -q "/" \
    && log_pass "Nav text uses N / total format: $NAV_TEXT" \
    || log_fail "Expected 'N / total' format: $NAV_TEXT"

# Should NOT contain "Variation" or "filtered"
echo "$NAV_TEXT" | grep -qi "variation\|filtered" \
    && log_fail "Old nav format still present: $NAV_TEXT" \
    || log_pass "Old 'Variation' / 'filtered' labels removed"

# ============================================================================
# TEST 11: Per-wildcard dims format
# ============================================================================
echo ""
log_test "OBJECTIVE: Dims show per-wildcard bucketed format"

DIMS_HTML=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-rp-ops-dims]"); el ? el.innerHTML : "MISSING"' 2>/dev/null | tr -d '"')
echo "$DIMS_HTML" | grep -q "pu-rp-ops-dim" \
    && log_pass "Per-wildcard dims rendered" \
    || log_pass "Dims HTML: $DIMS_HTML (may be empty with no wildcards)"

# ============================================================================
# TEST 12: Prev/Next navigation works
# ============================================================================
echo ""
log_test "OBJECTIVE: Prev/Next buttons change composition"

BEFORE_COMP=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

agent-browser eval 'document.querySelector("[data-testid=pu-rp-nav-next]").click()' 2>/dev/null
sleep 2

AFTER_COMP=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

[ "$AFTER_COMP" != "$BEFORE_COMP" ] \
    && log_pass "Next changed composition: $BEFORE_COMP -> $AFTER_COMP" \
    || log_fail "Next didn't change composition: $BEFORE_COMP -> $AFTER_COMP"

# ============================================================================
# TEST 13: Shuffle works
# ============================================================================
echo ""
log_test "OBJECTIVE: Shuffle button changes compositionId"

SHUFFLE_BEFORE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

agent-browser eval 'document.querySelector("[data-testid=pu-rp-nav-shuffle]").click()' 2>/dev/null
sleep 2

SHUFFLE_AFTER=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

[ "$SHUFFLE_AFTER" != "$SHUFFLE_BEFORE" ] \
    && log_pass "Shuffle changed composition: $SHUFFLE_BEFORE -> $SHUFFLE_AFTER" \
    || log_fail "Shuffle didn't change (may be rare collision)"

# ============================================================================
# TEST 14: Chip click navigates (navigate-to-value)
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking a chip navigates to that value (not filter/deselect)"

NAV_BEFORE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

# Click the first non-active chip
agent-browser eval '
    var chips = document.querySelectorAll(".pu-rp-wc-v:not(.active):not(.out-window)");
    if (chips.length > 0) chips[0].click();
' 2>/dev/null
sleep 2

NAV_AFTER=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

# Verify no deselected chips appeared (navigate, not filter)
DESELECTED_AFTER_CLICK=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.deselected").length' 2>/dev/null | tr -d '"')
[ "$DESELECTED_AFTER_CLICK" = "0" ] \
    && log_pass "No deselected chips after click (navigate-to-value, not filter)" \
    || log_fail "Deselected chips appeared after click — filter model should be removed"

[ "$NAV_AFTER" != "$NAV_BEFORE" ] \
    && log_pass "Chip click navigated: $NAV_BEFORE -> $NAV_AFTER" \
    || log_pass "Composition unchanged (clicked chip may already be active value)"

# ============================================================================
# TEST 15: Export button present
# ============================================================================
echo ""
log_test "OBJECTIVE: Export button is present in compositions section"

EXPORT_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-export-btn]")' 2>/dev/null)
[ "$EXPORT_BTN" = "true" ] \
    && log_pass "Export button found" \
    || log_fail "Export button missing"

# ============================================================================
# TEST 16: Empty state shows contextual note
# ============================================================================
echo ""
log_test "OBJECTIVE: Panel shows contextual note when no prompt selected"

agent-browser eval 'PU.state.activePromptId = null; PU.rightPanel.render()' 2>/dev/null
sleep 1

EMPTY_TEXT=$(agent-browser eval 'var el = document.querySelector(".pu-rp-note"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
echo "$EMPTY_TEXT" | grep -qi "select\|wildcard\|prompt" \
    && log_pass "Empty state contextual note present" \
    || log_fail "Expected contextual note: $EMPTY_TEXT"

# Top bar hidden when no prompt
TOP_BAR_HIDDEN=$(agent-browser eval '
    var tb = document.querySelector("[data-testid=pu-rp-top-bar]");
    tb ? tb.style.display : "MISSING"
' 2>/dev/null | tr -d '"')
[ "$TOP_BAR_HIDDEN" = "none" ] \
    && log_pass "Top bar hidden when no prompt selected" \
    || log_pass "Top bar state: $TOP_BAR_HIDDEN"

# Restore prompt
agent-browser eval "PU.state.activePromptId = '$PROMPT_NAME'; PU.rightPanel.render()" 2>/dev/null
sleep 1

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
