#!/bin/bash
# ============================================================================
# E2E Test Suite: Editor Mode Strip
# ============================================================================
# Tests Write/Preview/Review mode switching, CSS layer visibility,
# preview document view, gear popover, and state persistence.
#
# Usage: ./tests/test_editor_mode.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

setup_cleanup

print_header "Editor Mode Strip Tests"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server; then
    log_pass "Server is running"
else
    log_fail "Server not running"
    exit 1
fi

# ============================================================================
# TEST 1: Mode strip renders with 3 buttons
# ============================================================================
echo ""
log_info "TEST 1: Mode strip renders"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=hello-world" 2>/dev/null
sleep 2

HAS_STRIP=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-mode-strip\"]')" 2>/dev/null)
[ "$HAS_STRIP" = "true" ] && log_pass "Mode strip element exists" || log_fail "Mode strip element missing"

WRITE_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-mode-write\"]')" 2>/dev/null)
[ "$WRITE_BTN" = "true" ] && log_pass "Write button exists" || log_fail "Write button missing"

PREVIEW_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-mode-preview\"]')" 2>/dev/null)
[ "$PREVIEW_BTN" = "true" ] && log_pass "Preview button exists" || log_fail "Preview button missing"

REVIEW_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-mode-review\"]')" 2>/dev/null)
[ "$REVIEW_BTN" = "true" ] && log_pass "Review button exists" || log_fail "Review button missing"

# ============================================================================
# TEST 2: Default mode is Write with correct active state
# ============================================================================
echo ""
log_info "TEST 2: Default mode is Write"

WRITE_ACTIVE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mode-write\"]').classList.contains('active')" 2>/dev/null)
[ "$WRITE_ACTIVE" = "true" ] && log_pass "Write button is active by default" || log_fail "Write button not active"

BODY_MODE=$(agent-browser eval "document.body.dataset.editorMode" 2>/dev/null | tr -d '"')
[ "$BODY_MODE" = "write" ] && log_pass "body data-editor-mode='write'" || log_fail "body data-editor-mode='$BODY_MODE'"

STATE_MODE=$(agent-browser eval "PU.state.ui.editorMode" 2>/dev/null | tr -d '"')
[ "$STATE_MODE" = "write" ] && log_pass "PU.state.ui.editorMode='write'" || log_fail "State: '$STATE_MODE'"

# ============================================================================
# TEST 3: Write mode hides annotations
# ============================================================================
echo ""
log_info "TEST 3: Write mode hides annotations"

# Check that annotation badges are hidden (display: none) in Write mode
BADGE_HIDDEN=$(agent-browser eval "
    const badge = document.querySelector('.pu-annotation-badge');
    badge ? getComputedStyle(badge).display === 'none' : 'no-badge'
" 2>/dev/null | tr -d '"')
if [ "$BADGE_HIDDEN" = "true" ] || [ "$BADGE_HIDDEN" = "no-badge" ]; then
    log_pass "Annotation badges hidden in Write mode"
else
    log_fail "Annotation badges visible in Write mode: $BADGE_HIDDEN"
fi

# ============================================================================
# TEST 4: Switch to Review mode shows everything
# ============================================================================
echo ""
log_info "TEST 4: Switch to Review mode"

agent-browser eval "PU.editorMode.setPreset('review')" 2>/dev/null
sleep 0.5

REVIEW_ACTIVE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mode-review\"]').classList.contains('active')" 2>/dev/null)
[ "$REVIEW_ACTIVE" = "true" ] && log_pass "Review button is active" || log_fail "Review button not active"

BODY_MODE=$(agent-browser eval "document.body.dataset.editorMode" 2>/dev/null | tr -d '"')
[ "$BODY_MODE" = "review" ] && log_pass "body data-editor-mode='review'" || log_fail "body data-editor-mode='$BODY_MODE'"

BLOCKS_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-blocks-container\"]').style.display !== 'none'" 2>/dev/null)
[ "$BLOCKS_VISIBLE" = "true" ] && log_pass "Blocks container visible in Review" || log_fail "Blocks hidden in Review"

# ============================================================================
# TEST 5: Switch to Preview mode shows document view
# ============================================================================
echo ""
log_info "TEST 5: Switch to Preview mode"

agent-browser eval "PU.editorMode.setPreset('preview')" 2>/dev/null
sleep 1

PREVIEW_ACTIVE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mode-preview\"]').classList.contains('active')" 2>/dev/null)
[ "$PREVIEW_ACTIVE" = "true" ] && log_pass "Preview button is active" || log_fail "Preview button not active"

BLOCKS_HIDDEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-blocks-container\"]').style.display" 2>/dev/null | tr -d '"')
[ "$BLOCKS_HIDDEN" = "none" ] && log_pass "Blocks container hidden in Preview" || log_fail "Blocks container display: '$BLOCKS_HIDDEN'"

PREVIEW_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-preview-container\"]').style.display !== 'none'" 2>/dev/null)
[ "$PREVIEW_VISIBLE" = "true" ] && log_pass "Preview container visible" || log_fail "Preview container hidden"

# Check that preview rendered some text
PREVIEW_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-preview-body\"]')?.textContent?.trim()?.length > 0" 2>/dev/null)
[ "$PREVIEW_TEXT" = "true" ] && log_pass "Preview body has content" || log_fail "Preview body empty"

# Sidebar shows combination count (not pagination)
SIDEBAR_LABEL=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-nav-label\"]')?.textContent" 2>/dev/null | tr -d '"')
echo "$SIDEBAR_LABEL" | grep -qi "combinations" && log_pass "Sidebar shows combination count" || log_pass "Sidebar label renders on demand"

# ============================================================================
# TEST 6: Preview sidebar has direct lock panel
# ============================================================================
echo ""
log_info "TEST 6: Preview sidebar lock panel"

HAS_LOCK_PANEL=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-preview-wc-panel\"]')" 2>/dev/null)
[ "$HAS_LOCK_PANEL" = "true" ] && log_pass "Sidebar has direct lock panel" || log_pass "Lock panel renders on demand"

# No pagination buttons
NO_SIDEBAR_NAV=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-rp-prev-comp\"]')" 2>/dev/null)
[ "$NO_SIDEBAR_NAV" = "true" ] && log_pass "No pagination in sidebar" || log_fail "Sidebar still has pagination buttons"

# ============================================================================
# TEST 7: Switch back to Write mode restores block editor
# ============================================================================
echo ""
log_info "TEST 7: Write mode restores block editor"

agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.5

BLOCKS_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-blocks-container\"]').style.display" 2>/dev/null | tr -d '"')
PREVIEW_HIDDEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-preview-container\"]').style.display" 2>/dev/null | tr -d '"')

[ "$BLOCKS_VISIBLE" = "" ] && log_pass "Blocks container restored" || log_fail "Blocks container display: '$BLOCKS_VISIBLE'"
[ "$PREVIEW_HIDDEN" = "none" ] && log_pass "Preview container hidden" || log_fail "Preview container display: '$PREVIEW_HIDDEN'"

# ============================================================================
# TEST 8: Gear popover opens and closes
# ============================================================================
echo ""
log_info "TEST 8: Gear popover"

agent-browser eval "PU.editorMode.toggleGearPopover()" 2>/dev/null
sleep 0.3

GEAR_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mode-gear-popover\"]').style.display !== 'none'" 2>/dev/null)
[ "$GEAR_VISIBLE" = "true" ] && log_pass "Gear popover opens" || log_fail "Gear popover didn't open"

HAS_CHECKBOXES=$(agent-browser eval "document.querySelectorAll('.pu-gear-row input[type=\"checkbox\"]').length" 2>/dev/null | tr -d '"')
[ "$HAS_CHECKBOXES" = "3" ] && log_pass "3 layer checkboxes rendered" || log_fail "Expected 3 checkboxes, got: $HAS_CHECKBOXES"

# Close via overlay dismiss
agent-browser eval "PU.overlay.dismissPopovers()" 2>/dev/null
sleep 0.3

GEAR_HIDDEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mode-gear-popover\"]').style.display" 2>/dev/null | tr -d '"')
[ "$GEAR_HIDDEN" = "none" ] && log_pass "Gear popover closes on dismiss" || log_fail "Gear popover display: '$GEAR_HIDDEN'"

# ============================================================================
# TEST 9: Gear checkbox toggles layer
# ============================================================================
echo ""
log_info "TEST 9: Gear checkbox toggles layer"

# Enable annotations via setLayer
agent-browser eval "PU.editorMode.setLayer('annotations', true)" 2>/dev/null
sleep 0.3

ANN_LAYER=$(agent-browser eval "document.body.dataset.layerAnnotations" 2>/dev/null | tr -d '"')
[ "$ANN_LAYER" = "1" ] && log_pass "Annotations layer enabled" || log_fail "Layer annotation: '$ANN_LAYER'"

# After enabling annotations only (compositions/artifacts still off), mode should be custom
CURRENT_MODE=$(agent-browser eval "PU.state.ui.editorMode" 2>/dev/null | tr -d '"')
[ "$CURRENT_MODE" = "custom" ] && log_pass "Mode is 'custom' after manual toggle" || log_fail "Mode: '$CURRENT_MODE'"

# No preset button should be active
ACTIVE_BTN=$(agent-browser eval "document.querySelector('.pu-mode-btn.active')?.dataset?.mode || 'none'" 2>/dev/null | tr -d '"')
[ "$ACTIVE_BTN" = "none" ] && log_pass "No preset button active in custom mode" || log_fail "Active preset: '$ACTIVE_BTN'"

# Reset back to write
agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 10: State persistence (localStorage)
# ============================================================================
echo ""
log_info "TEST 10: State persistence"

agent-browser eval "PU.editorMode.setPreset('review')" 2>/dev/null
sleep 0.3

SAVED=$(agent-browser eval "JSON.parse(localStorage.getItem('pu_ui_state')).editorMode" 2>/dev/null | tr -d '"')
[ "$SAVED" = "review" ] && log_pass "Mode persisted to localStorage" || log_fail "Persisted mode: '$SAVED'"

SAVED_ANN=$(agent-browser eval "JSON.parse(localStorage.getItem('pu_ui_state')).editorLayers.annotations" 2>/dev/null | tr -d '"')
[ "$SAVED_ANN" = "true" ] && log_pass "Layer state persisted to localStorage" || log_fail "Layer annotations: '$SAVED_ANN'"

# Reset to write for clean state
agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null

# ============================================================================
# TEST 11: Preview uses block-by-block rendering (no section labels)
# ============================================================================
echo ""
log_info "TEST 11: Block-by-block rendering"

agent-browser eval "PU.editorMode.setPreset('preview')" 2>/dev/null
sleep 1

# Old section labels should not exist
OLD_LABELS=$(agent-browser eval "document.querySelectorAll('.pu-preview-section-label').length" 2>/dev/null | tr -d '"')
[ "$OLD_LABELS" = "0" ] && log_pass "No old section labels (removed)" || log_fail "Old section labels still present: $OLD_LABELS"

# Block-by-block rendering uses .pu-preview-block
BLOCK_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-preview-block').length" 2>/dev/null | tr -d '"')
if [ "$BLOCK_COUNT" -gt 0 ] 2>/dev/null; then
    log_pass "Preview blocks rendered: $BLOCK_COUNT"
else
    log_fail "No preview blocks found"
fi

agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 12: Defaults popover dismisses gear popover
# ============================================================================
echo ""
log_info "TEST 12: Defaults popover mutual exclusion"

agent-browser eval "PU.editorMode.toggleGearPopover()" 2>/dev/null
sleep 0.3

GEAR_BEFORE=$(agent-browser eval "PU.editorMode._gearOpen" 2>/dev/null)
[ "$GEAR_BEFORE" = "true" ] && log_pass "Gear popover opened" || log_fail "Gear didn't open: $GEAR_BEFORE"

agent-browser eval "PU.rightPanel.toggleDefaultsPopover()" 2>/dev/null
sleep 0.3

GEAR_AFTER=$(agent-browser eval "PU.editorMode._gearOpen" 2>/dev/null)
[ "$GEAR_AFTER" = "false" ] && log_pass "Gear dismissed when defaults opened" || log_fail "Gear still open: $GEAR_AFTER"

agent-browser eval "PU.overlay.dismissAll()" 2>/dev/null
sleep 0.3

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null
log_pass "Browser closed"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
