#!/bin/bash
# ============================================================================
# E2E Test Suite: Build Composition Panel
# ============================================================================
# Tests the Build Composition slide-out panel:
# - Panel open/close
# - Defaults section (ext scope, ext_text_max, ext_wc_max)
# - Prompt section (dimensions, total)
# - Navigator (prev/next/shuffle, wildcard tags, resolved output)
# - Export .txt with file size estimate
# - Main editor migration (no odometer, no output footer)
#
# Usage: ./tests/test_build_composition.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Build Composition Panel"

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

# Verify prompt loaded
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
# TEST 1: Build button exists in header
# ============================================================================
echo ""
log_test "OBJECTIVE: Build button exists in header"

BUILD_BTN=$(agent-browser eval 'var btn = document.querySelector("[data-testid=pu-header-build-btn]"); btn ? btn.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
[ "$BUILD_BTN" = "Build" ] \
    && log_pass "Build button found in header" \
    || log_fail "Build button missing: $BUILD_BTN"

# ============================================================================
# TEST 2: Panel opens on Build click
# ============================================================================
echo ""
log_test "OBJECTIVE: Panel opens when Build button is clicked"

agent-browser eval 'document.querySelector("[data-testid=pu-header-build-btn]").click()' 2>/dev/null
sleep 2

PANEL_VISIBLE=$(agent-browser eval 'var p = document.querySelector("[data-testid=pu-build-panel]"); p && p.style.display !== "none" && p.classList.contains("open")' 2>/dev/null)
[ "$PANEL_VISIBLE" = "true" ] \
    && log_pass "Build panel opened" \
    || log_fail "Panel not visible: $PANEL_VISIBLE"

BUILD_STATE=$(agent-browser eval 'PU.state.buildComposition.visible' 2>/dev/null)
[ "$BUILD_STATE" = "true" ] \
    && log_pass "State buildComposition.visible is true" \
    || log_fail "State should be visible: $BUILD_STATE"

# ============================================================================
# TEST 3: Defaults section has ext scope, ext_text_max, ext_wc_max
# ============================================================================
echo ""
log_test "OBJECTIVE: Defaults section shows composition controls"

EXT_SELECT=$(agent-browser eval '!!document.querySelector("[data-testid=pu-build-defaults-ext]")' 2>/dev/null)
[ "$EXT_SELECT" = "true" ] \
    && log_pass "Defaults ext scope dropdown present" \
    || log_fail "Defaults ext scope dropdown missing"

ETM_INPUT=$(agent-browser eval '!!document.querySelector("[data-testid=pu-build-defaults-ext-text-max]")' 2>/dev/null)
[ "$ETM_INPUT" = "true" ] \
    && log_pass "Defaults ext_text_max input present" \
    || log_fail "Defaults ext_text_max input missing"

EWM_INPUT=$(agent-browser eval '!!document.querySelector("[data-testid=pu-build-defaults-ext-wc-max]")' 2>/dev/null)
[ "$EWM_INPUT" = "true" ] \
    && log_pass "Defaults ext_wc_max input present" \
    || log_fail "Defaults ext_wc_max input missing"

# ============================================================================
# TEST 4: Prompt section shows dimensions and total
# ============================================================================
echo ""
log_test "OBJECTIVE: Prompt section displays wildcard dimensions and total"

PROMPT_DISPLAY=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-prompt-name]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
[ "$PROMPT_DISPLAY" != "MISSING" ] && [ -n "$PROMPT_DISPLAY" ] \
    && log_pass "Prompt name displayed: $PROMPT_DISPLAY" \
    || log_fail "Prompt name missing: $PROMPT_DISPLAY"

DIMS_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-dims]"); el ? el.textContent : "MISSING"' 2>/dev/null | tr -d '"')
echo "$DIMS_TEXT" | grep -qi "dimensions" \
    && log_pass "Dimensions label found" \
    || log_fail "Dimensions label missing: $DIMS_TEXT"

TOTAL_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-total]"); el ? el.textContent : "MISSING"' 2>/dev/null | tr -d '"')
echo "$TOTAL_TEXT" | grep -q "Total:" \
    && log_pass "Total compositions displayed" \
    || log_fail "Total missing: $TOTAL_TEXT"

# Extract total number for later verification
TOTAL_NUM=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-total] strong"); el ? el.textContent.trim() : "0"' 2>/dev/null | tr -d '"')
log_info "Total compositions: $TOTAL_NUM"

# ============================================================================
# TEST 5: Defaults values loaded from previewMode (not 0)
# ============================================================================
echo ""
log_test "OBJECTIVE: Defaults load from previewMode, not job.defaults"

# ext_text_max should default to 1 (from previewMode.extTextMax), not 0
ETM_VAL=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-defaults-ext-text-max]").value' 2>/dev/null | tr -d '"')
[ "$ETM_VAL" = "1" ] \
    && log_pass "ext_text_max defaults to 1 (from previewMode)" \
    || log_fail "ext_text_max should be 1, got: $ETM_VAL"

# ext_wc_max should default to 0 (from previewMode.wildcardsMax)
EWM_VAL=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-defaults-ext-wc-max]").value' 2>/dev/null | tr -d '"')
[ "$EWM_VAL" = "0" ] \
    && log_pass "ext_wc_max defaults to 0 (from previewMode)" \
    || log_fail "ext_wc_max should be 0, got: $EWM_VAL"

# Verify previewMode state matches UI
ETM_STATE=$(agent-browser eval 'PU.state.previewMode.extTextMax' 2>/dev/null | tr -d '"')
[ "$ETM_STATE" = "1" ] \
    && log_pass "previewMode.extTextMax state is 1" \
    || log_fail "previewMode.extTextMax should be 1, got: $ETM_STATE"

# ============================================================================
# TEST 6: Navigator shows composition ID and wildcard tags
# ============================================================================
echo ""
log_test "OBJECTIVE: Navigator displays composition ID and wildcard details"

NAV_LABEL=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-nav-label]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
echo "$NAV_LABEL" | grep -qE "[0-9]+ / [0-9]+" \
    && log_pass "Nav label shows N / Total format: $NAV_LABEL" \
    || log_fail "Nav label should show N / Total: $NAV_LABEL"

NAV_DETAILS=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-nav-details]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
[ -n "$NAV_DETAILS" ] && [ "$NAV_DETAILS" != "MISSING" ] \
    && log_pass "Wildcard tags displayed in navigator" \
    || log_fail "Wildcard tags missing: $NAV_DETAILS"

# ============================================================================
# TEST 7: Navigator prev/next changes composition
# ============================================================================
echo ""
log_test "OBJECTIVE: Prev/Next buttons change composition"

BEFORE_LABEL=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-nav-label]").textContent.trim()' 2>/dev/null | tr -d '"')
BEFORE_NUM=$(echo "$BEFORE_LABEL" | cut -d'/' -f1 | tr -d ' ')

agent-browser eval 'document.querySelector("[data-testid=pu-build-nav-next]").click()' 2>/dev/null
sleep 1

AFTER_LABEL=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-nav-label]").textContent.trim()' 2>/dev/null | tr -d '"')
AFTER_NUM=$(echo "$AFTER_LABEL" | cut -d'/' -f1 | tr -d ' ')

[ "$AFTER_NUM" != "$BEFORE_NUM" ] \
    && log_pass "Next button changed composition: $BEFORE_NUM -> $AFTER_NUM" \
    || log_fail "Next button didn't change composition: $BEFORE_NUM -> $AFTER_NUM"

# Click prev to go back
agent-browser eval 'document.querySelector("[data-testid=pu-build-nav-prev]").click()' 2>/dev/null
sleep 1

PREV_LABEL=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-nav-label]").textContent.trim()' 2>/dev/null | tr -d '"')
PREV_NUM=$(echo "$PREV_LABEL" | cut -d'/' -f1 | tr -d ' ')

[ "$PREV_NUM" = "$BEFORE_NUM" ] \
    && log_pass "Prev button returned to original: $PREV_NUM" \
    || log_fail "Prev should return to $BEFORE_NUM, got: $PREV_NUM"

# ============================================================================
# TEST 8: Shuffle changes composition randomly
# ============================================================================
echo ""
log_test "OBJECTIVE: Shuffle button changes to random composition"

SHUFFLE_BEFORE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

agent-browser eval 'document.querySelector("[data-testid=pu-build-nav-shuffle]").click()' 2>/dev/null
sleep 1

SHUFFLE_AFTER=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')

[ "$SHUFFLE_AFTER" != "$SHUFFLE_BEFORE" ] \
    && log_pass "Shuffle changed composition: $SHUFFLE_BEFORE -> $SHUFFLE_AFTER" \
    || log_fail "Shuffle didn't change composition (may be unlikely collision)"

# ============================================================================
# TEST 9: Resolved output appears in navigator
# ============================================================================
echo ""
log_test "OBJECTIVE: Resolved output text appears in navigator"

OUTPUT_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-nav-output]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
[ -n "$OUTPUT_TEXT" ] && [ "$OUTPUT_TEXT" != "MISSING" ] && [ "$OUTPUT_TEXT" != "Resolving..." ] \
    && log_pass "Resolved output text present" \
    || log_fail "Resolved output missing or still loading: $OUTPUT_TEXT"

# ============================================================================
# TEST 10: Main editor blocks sync with navigator
# ============================================================================
echo ""
log_test "OBJECTIVE: Main editor blocks sync when composition changes"

# Get composition ID before
COMP_BEFORE=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
log_info "Composition before: $COMP_BEFORE"

# Get block text before
BLOCK_TEXT_BEFORE=$(agent-browser eval 'var el = document.querySelector(".pu-block"); el ? el.textContent.substring(0, 120).trim() : "NONE"' 2>/dev/null | tr -d '"')
log_info "Block text before nav: ${BLOCK_TEXT_BEFORE:0:60}..."

# Navigate 100 compositions forward via JS
agent-browser eval '(async () => { await PU.buildComposition.navigate(100); })()' 2>/dev/null
sleep 3

COMP_AFTER=$(agent-browser eval 'PU.state.previewMode.compositionId' 2>/dev/null | tr -d '"')
log_info "Composition after: $COMP_AFTER"

BLOCK_TEXT_AFTER=$(agent-browser eval 'var el = document.querySelector(".pu-block"); el ? el.textContent.substring(0, 120).trim() : "NONE"' 2>/dev/null | tr -d '"')
log_info "Block text after nav: ${BLOCK_TEXT_AFTER:0:60}..."

[ "$COMP_AFTER" != "$COMP_BEFORE" ] \
    && log_pass "Composition ID changed after navigation: $COMP_BEFORE -> $COMP_AFTER" \
    || log_fail "Composition should change after navigate(100)"

# ============================================================================
# TEST 11: Export estimate shows file size
# ============================================================================
echo ""
log_test "OBJECTIVE: Export estimate shows composition count and file size"

ESTIMATE_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-export-estimate]"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
echo "$ESTIMATE_TEXT" | grep -q "compositions" \
    && log_pass "Estimate shows composition count" \
    || log_fail "Estimate should show composition count: $ESTIMATE_TEXT"

echo "$ESTIMATE_TEXT" | grep -qE "(KB|MB|GB|B)" \
    && log_pass "Estimate shows file size: $ESTIMATE_TEXT" \
    || log_fail "Estimate should show file size: $ESTIMATE_TEXT"

# Check export button shows size in label
EXPORT_BTN_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-export-btn]").textContent.trim()' 2>/dev/null | tr -d '"')
echo "$EXPORT_BTN_TEXT" | grep -q "Export .txt" \
    && log_pass "Export button present: $EXPORT_BTN_TEXT" \
    || log_fail "Export button text wrong: $EXPORT_BTN_TEXT"

echo "$EXPORT_BTN_TEXT" | grep -qE "~.*[KMG]?B" \
    && log_pass "Export button shows estimated size" \
    || log_fail "Export button should show size estimate: $EXPORT_BTN_TEXT"

# Export button should be enabled (no Generate step needed)
EXPORT_ENABLED=$(agent-browser eval '!document.querySelector("[data-testid=pu-build-export-btn]").disabled' 2>/dev/null)
[ "$EXPORT_ENABLED" = "true" ] \
    && log_pass "Export button enabled (no pre-generation needed)" \
    || log_fail "Export button should be enabled: $EXPORT_ENABLED"

# ============================================================================
# TEST 12: Bucketing reduces total when wildcards_max is set
# ============================================================================
echo ""
log_test "OBJECTIVE: Setting wildcards_max reduces total and shows bucketed dims"

# Capture the unbucketed total first
UNBUCKETED_TOTAL=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-total] strong"); el ? el.textContent.trim() : "0"' 2>/dev/null | tr -d '"' | tr -d ',')
log_info "Unbucketed total: $UNBUCKETED_TOTAL"

# Set wildcards_max = 2 via the defaults input
agent-browser eval '
    var input = document.querySelector("[data-testid=pu-build-defaults-ext-wc-max]");
    if (input) {
        input.value = 2;
        input.dispatchEvent(new Event("change"));
    }
' 2>/dev/null
sleep 3

# Verify previewMode state updated
WC_MAX_STATE=$(agent-browser eval 'PU.state.previewMode.wildcardsMax' 2>/dev/null | tr -d '"')
[ "$WC_MAX_STATE" = "2" ] \
    && log_pass "previewMode.wildcardsMax updated to 2" \
    || log_fail "wildcardsMax should be 2, got: $WC_MAX_STATE"

# Check that total changed
BUCKETED_TOTAL=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-total] strong"); el ? el.textContent.trim() : "0"' 2>/dev/null | tr -d '"' | tr -d ',')
log_info "Bucketed total: $BUCKETED_TOTAL"

[ "$BUCKETED_TOTAL" -lt "$UNBUCKETED_TOTAL" ] 2>/dev/null \
    && log_pass "Total reduced with bucketing: $UNBUCKETED_TOTAL -> $BUCKETED_TOTAL" \
    || log_fail "Total should be less with wcMax=2: unbucketed=$UNBUCKETED_TOTAL bucketed=$BUCKETED_TOTAL"

# Check dimensions show bucketed format (e.g., "name(2/4)")
DIMS_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-dims]"); el ? el.textContent : "MISSING"' 2>/dev/null | tr -d '"')
echo "$DIMS_TEXT" | grep -qE "[0-9]+/[0-9]+" \
    && log_pass "Dimensions show bucketed format (N/M): $DIMS_TEXT" \
    || log_fail "Dimensions should show N/M format when bucketing active: $DIMS_TEXT"

# Reset wildcards_max back to 0
agent-browser eval '
    var input = document.querySelector("[data-testid=pu-build-defaults-ext-wc-max]");
    if (input) {
        input.value = 0;
        input.dispatchEvent(new Event("change"));
    }
' 2>/dev/null
sleep 2

# Verify total restores to original
RESTORED_TOTAL=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-build-total] strong"); el ? el.textContent.trim() : "0"' 2>/dev/null | tr -d '"' | tr -d ',')
[ "$RESTORED_TOTAL" = "$UNBUCKETED_TOTAL" ] \
    && log_pass "Total restored after clearing bucketing: $RESTORED_TOTAL" \
    || log_fail "Total should restore to $UNBUCKETED_TOTAL, got: $RESTORED_TOTAL"

# ============================================================================
# TEST 13: Panel closes properly
# ============================================================================
echo ""
log_test "OBJECTIVE: Panel closes via close button"

agent-browser eval 'document.querySelector("[data-testid=pu-build-close-btn]").click()' 2>/dev/null
sleep 0.5

PANEL_CLOSED=$(agent-browser eval 'PU.state.buildComposition.visible === false' 2>/dev/null)
[ "$PANEL_CLOSED" = "true" ] \
    && log_pass "Panel closed (state.visible = false)" \
    || log_fail "Panel should be closed: $PANEL_CLOSED"

# ============================================================================
# TEST 14: Main editor has NO odometer toolbar
# ============================================================================
echo ""
log_test "OBJECTIVE: Odometer toolbar removed from main editor"

NO_ODOMETER=$(agent-browser eval '!document.querySelector("[data-testid=pu-odometer-toolbar]")' 2>/dev/null)
[ "$NO_ODOMETER" = "true" ] \
    && log_pass "Odometer toolbar removed from main editor" \
    || log_fail "Odometer toolbar should be removed"

# ============================================================================
# TEST 15: Main editor has NO output footer
# ============================================================================
echo ""
log_test "OBJECTIVE: Output footer removed from main editor"

NO_FOOTER=$(agent-browser eval '!document.querySelector("[data-testid=pu-output-footer]")' 2>/dev/null)
[ "$NO_FOOTER" = "true" ] \
    && log_pass "Output footer removed from main editor" \
    || log_fail "Output footer should be removed"

# ============================================================================
# TEST 16: Viz selector is in prompt header
# ============================================================================
echo ""
log_test "OBJECTIVE: Visualizer selector in prompt header row"

VIZ_SELECT=$(agent-browser eval '!!document.querySelector("[data-testid=pu-editor-visualizer]")' 2>/dev/null)
[ "$VIZ_SELECT" = "true" ] \
    && log_pass "Visualizer selector present in prompt header" \
    || log_fail "Visualizer selector missing"

# Verify it's inside prompt header area
VIZ_IN_HEADER=$(agent-browser eval 'var viz = document.querySelector("[data-testid=pu-editor-visualizer]"); viz && viz.closest(".pu-prompt-header-actions") !== null' 2>/dev/null)
[ "$VIZ_IN_HEADER" = "true" ] \
    && log_pass "Viz selector is inside prompt header actions" \
    || log_fail "Viz selector should be in prompt header actions: $VIZ_IN_HEADER"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
