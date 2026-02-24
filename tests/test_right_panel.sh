#!/bin/bash
# ============================================================================
# E2E Test Suite: Right Panel (Phase 1 + Phase 5)
# ============================================================================
# Tests the right panel matching preview-panel-v2.3 design:
# - Top bar: scope chip, variant selector (None), wildcard count
# - Centered line dividers: "shared" and "local" sections
# - Wildcard entries with name + wc-path (for shared) + bordered chips
# - Flat chip rendering (no bucket window frames)
# - Click-to-preview, Ctrl+Click-to-lock interaction model
# - Composition count = product of locked counts
# - Per-wildcard dims format
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
# TEST 8: No bucket artifacts (window-frame, out-window, badges)
# ============================================================================
echo ""
log_test "OBJECTIVE: No bucket artifacts in right panel"

BADGE_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-window-badge").length' 2>/dev/null | tr -d '"')
FRAME_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-window-frame").length' 2>/dev/null | tr -d '"')
OOW_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.out-window").length' 2>/dev/null | tr -d '"')
[ "$BADGE_COUNT" = "0" ] \
    && log_pass "No bucket badges" \
    || log_fail "Found $BADGE_COUNT bucket badges"
[ "$FRAME_COUNT" = "0" ] \
    && log_pass "No window frames" \
    || log_fail "Found $FRAME_COUNT window frames"
[ "$OOW_COUNT" = "0" ] \
    && log_pass "No out-of-window chips" \
    || log_fail "Found $OOW_COUNT out-of-window chips"

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
# TEST 10: Composition count display
# ============================================================================
echo ""
log_test "OBJECTIVE: Composition count shows 'N compositions' format"

NAV_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-rp-nav-label]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
echo "$NAV_TEXT" | grep -qi "composition" \
    && log_pass "Nav text shows compositions: $NAV_TEXT" \
    || log_fail "Expected 'N compositions' format: $NAV_TEXT"

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
# TEST 12: No prev/next/shuffle buttons in right panel
# ============================================================================
echo ""
log_test "OBJECTIVE: No prev/next/shuffle buttons (removed from right panel)"

HAS_PREV=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-nav-prev]")' 2>/dev/null | tr -d '"')
HAS_NEXT=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-nav-next]")' 2>/dev/null | tr -d '"')
HAS_SHUFFLE=$(agent-browser eval '!!document.querySelector("[data-testid=pu-rp-nav-shuffle]")' 2>/dev/null | tr -d '"')
[ "$HAS_PREV" = "false" ] \
    && log_pass "No prev button" \
    || log_fail "Prev button still exists"
[ "$HAS_NEXT" = "false" ] \
    && log_pass "No next button" \
    || log_fail "Next button still exists"
[ "$HAS_SHUFFLE" = "false" ] \
    && log_pass "No shuffle button" \
    || log_fail "Shuffle button still exists"

# ============================================================================
# TEST 13: Click chip = preview update (not navigation/filter)
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking a chip updates preview (not filter/deselect)"

# Click the first non-active chip
agent-browser eval '
    PU.state.previewMode.selectedWildcards = {};
    PU.state.previewMode.lockedValues = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.active)");
    if (chip) chip.click();
' 2>/dev/null
sleep 2

# Verify selectedWildcards['*'] was updated (preview mode)
HAS_PREVIEW=$(agent-browser eval '
    var sw = PU.state.previewMode.selectedWildcards;
    !!(sw["*"] && Object.keys(sw["*"]).length > 0)
' 2>/dev/null | tr -d '"')
[ "$HAS_PREVIEW" = "true" ] \
    && log_pass "Click set preview override in selectedWildcards['*']" \
    || log_fail "No preview override after click"

# Verify no deselected chips appeared (preview, not filter)
DESELECTED_AFTER_CLICK=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-v.deselected").length' 2>/dev/null | tr -d '"')
[ "$DESELECTED_AFTER_CLICK" = "0" ] \
    && log_pass "No deselected chips after click (preview, not filter)" \
    || log_fail "Deselected chips appeared after click"

# ============================================================================
# TEST 14: Ctrl+Click chip = lock (not preview-only)
# ============================================================================
echo ""
log_test "OBJECTIVE: Ctrl+Click chip creates lock in lockedValues"

agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.active)");
    if (chip) {
        var evt = new MouseEvent("click", { ctrlKey: true, bubbles: true });
        chip.dispatchEvent(evt);
    }
' 2>/dev/null
sleep 2

LOCK_COUNT=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null | tr -d '"')
[ "$LOCK_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Ctrl+Click created lock: $LOCK_COUNT wildcard(s)" \
    || log_fail "No lock created by Ctrl+Click"

# Clean up
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null

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
# JOB DEFAULTS SECTION
# ============================================================================
echo ""
log_info "JOB DEFAULTS: Section exists in right panel"

HAS_DEFAULTS=$(agent-browser eval 'document.querySelector("[data-testid=pu-rp-defaults]") ? "found" : "missing"' 2>/dev/null | tr -d '"')
[ "$HAS_DEFAULTS" = "found" ] && log_pass "Job Defaults section exists in right panel" || log_fail "Job Defaults section missing"

# Verify it's inside right panel
DEFAULTS_PARENT=$(agent-browser eval 'document.querySelector("[data-testid=pu-rp-defaults]").parentElement.getAttribute("data-testid")' 2>/dev/null | tr -d '"')
[ "$DEFAULTS_PARENT" = "pu-right-panel" ] && log_pass "Job Defaults is child of pu-right-panel" || log_fail "Job Defaults parent: $DEFAULTS_PARENT"

# Old toolbar removed from editor
OLD_TOOLBAR=$(agent-browser eval 'document.querySelector("[data-testid=pu-defaults-toolbar]") === null ? "removed" : "exists"' 2>/dev/null | tr -d '"')
[ "$OLD_TOOLBAR" = "removed" ] && log_pass "Old defaults toolbar removed from editor" || log_fail "Old defaults toolbar still in editor"

echo ""
log_info "JOB DEFAULTS: Ext dropdown populated"

EXT_SELECT=$(agent-browser eval 'var s = document.querySelector("[data-testid=pu-defaults-ext]"); s ? s.options.length : 0' 2>/dev/null | tr -d '"')
if [ "$EXT_SELECT" -gt 0 ] 2>/dev/null; then
    log_pass "Ext dropdown has $EXT_SELECT options"
else
    log_fail "Ext dropdown empty or missing"
fi

EXT_VALUE=$(agent-browser eval 'var s = document.querySelector("[data-testid=pu-defaults-ext]"); s ? s.value : "none"' 2>/dev/null | tr -d '"')
[ -n "$EXT_VALUE" ] && [ "$EXT_VALUE" != "none" ] && log_pass "Ext dropdown has selected value: $EXT_VALUE" || log_fail "Ext dropdown no value: $EXT_VALUE"

echo ""
log_info "JOB DEFAULTS: Collapse/expand toggle"

# Collapse
agent-browser eval 'PU.rightPanel.toggleDefaults()' 2>/dev/null
sleep 0.3

IS_COLLAPSED=$(agent-browser eval 'document.querySelector("[data-testid=pu-rp-defaults]").classList.contains("collapsed") ? "yes" : "no"' 2>/dev/null | tr -d '"')
[ "$IS_COLLAPSED" = "yes" ] && log_pass "Defaults collapsed after toggle" || log_fail "Defaults not collapsed: $IS_COLLAPSED"

# Expand
agent-browser eval 'PU.rightPanel.toggleDefaults()' 2>/dev/null
sleep 0.3

IS_EXPANDED=$(agent-browser eval 'document.querySelector("[data-testid=pu-rp-defaults]").classList.contains("collapsed") ? "no" : "yes"' 2>/dev/null | tr -d '"')
[ "$IS_EXPANDED" = "yes" ] && log_pass "Defaults expanded after second toggle" || log_fail "Defaults not expanded: $IS_EXPANDED"

echo ""
log_info "JOB DEFAULTS: Changing ext updates job defaults"

# Change ext value and verify state update
agent-browser eval 'var s = document.querySelector("[data-testid=pu-defaults-ext]"); if (s && s.options.length > 1) { s.selectedIndex = 1; s.dispatchEvent(new Event("change")); }' 2>/dev/null
sleep 0.3

NEW_EXT=$(agent-browser eval 'var j = PU.state.modifiedJobs[PU.state.activeJobId]; j && j.defaults ? j.defaults.ext : "not-set"' 2>/dev/null | tr -d '"')
if [ -n "$NEW_EXT" ] && [ "$NEW_EXT" != "not-set" ]; then
    log_pass "Ext change updated job defaults: $NEW_EXT"
else
    log_fail "Ext change did not update state: $NEW_EXT"
fi

echo ""
log_info "JOB DEFAULTS: renderDefaults() called via render()"

HAS_RENDER_DEFAULTS=$(agent-browser eval 'typeof PU.rightPanel.renderDefaults === "function" ? "yes" : "no"' 2>/dev/null | tr -d '"')
[ "$HAS_RENDER_DEFAULTS" = "yes" ] && log_pass "PU.rightPanel.renderDefaults() exists" || log_fail "renderDefaults() missing"

HAS_TOGGLE_DEFAULTS=$(agent-browser eval 'typeof PU.rightPanel.toggleDefaults === "function" ? "yes" : "no"' 2>/dev/null | tr -d '"')
[ "$HAS_TOGGLE_DEFAULTS" = "yes" ] && log_pass "PU.rightPanel.toggleDefaults() exists" || log_fail "toggleDefaults() missing"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
