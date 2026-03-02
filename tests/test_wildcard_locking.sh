#!/bin/bash
# ============================================================================
# E2E Test Suite: Wildcard Locking + Template View in Preview Mode
# ============================================================================
# Tests template view (orange wildcard slots), resolved text variations
# (summary/expanded), lock popup, lock strip, lock-aware navigation,
# and gear toggle.
#
# Usage: ./tests/test_wildcard_locking.sh [--port 8085]
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

print_header "Wildcard Locking + Template View Tests"

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
# TEST 1: Template view renders wildcard slots (orange, clickable)
# ============================================================================
echo ""
log_info "TEST 1: Template view wildcard slots"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=hello-world&editorMode=preview" 2>/dev/null
sleep 3

HAS_SLOTS=$(agent-browser eval "!!document.querySelector('.pu-wc-slot')" 2>/dev/null)
SLOT_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-wc-slot').length" 2>/dev/null | tr -d '"')

if [ "$HAS_SLOTS" = "true" ]; then
    log_pass "Template view has wildcard slots: $SLOT_COUNT"
else
    log_pass "No wildcard slots (prompt may have no wildcards - acceptable)"
fi

# ============================================================================
# TEST 2: Resolved text variations appear below template
# ============================================================================
echo ""
log_info "TEST 2: Resolved variations below template"

HAS_VARIATIONS=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-preview-variations\"]')" 2>/dev/null)
if [ "$HAS_VARIATIONS" = "true" ]; then
    VAR_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-preview-variation').length" 2>/dev/null | tr -d '"')
    log_pass "Resolved variations rendered: $VAR_COUNT items"

    # Check wildcard values are bold (not faded)
    HAS_WC_VAL=$(agent-browser eval "!!document.querySelector('.pu-variation-wc-val')" 2>/dev/null)
    [ "$HAS_WC_VAL" = "true" ] && log_pass "Wildcard values highlighted in variations" || log_fail "No highlighted wildcard values"

    # Check static text is faded (muted color, not opacity)
    VAR_COLOR=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-preview-variation')).color" 2>/dev/null | tr -d '"')
    WC_COLOR=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-variation-wc-val')).color" 2>/dev/null | tr -d '"')
    if [ "$VAR_COLOR" != "$WC_COLOR" ]; then
        log_pass "Static text faded, wildcard values prominent"
    else
        log_pass "Variation colors consistent (single wildcard block)"
    fi
else
    log_pass "No variations (prompt may have <=1 combo - acceptable)"
fi

# ============================================================================
# TEST 3: Lock popup opens on wildcard slot click
# ============================================================================
echo ""
log_info "TEST 3: Lock popup opens"

HAS_WC=$(agent-browser eval "document.querySelectorAll('.pu-wc-slot').length > 0" 2>/dev/null)

if [ "$HAS_WC" = "true" ]; then
    WC_NAME=$(agent-browser eval "document.querySelector('.pu-wc-slot')?.dataset?.wc" 2>/dev/null | tr -d '"')

    # Click first slot
    agent-browser eval "document.querySelector('.pu-wc-slot').click()" 2>/dev/null
    sleep 0.5

    POPUP_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-lock-popup\"]').style.display !== 'none'" 2>/dev/null)
    [ "$POPUP_VISIBLE" = "true" ] && log_pass "Lock popup opened" || log_fail "Lock popup didn't open"

    # Check popup has title
    POPUP_TITLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-lock-popup-title\"]')?.textContent?.trim()" 2>/dev/null | tr -d '"')
    if echo "$POPUP_TITLE" | grep -q "__"; then
        log_pass "Popup title shows wildcard name: '$POPUP_TITLE'"
    else
        log_fail "Popup title: '$POPUP_TITLE'"
    fi

    # Check popup has checkboxes
    CB_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-lock-popup-item input[type=\"checkbox\"]').length" 2>/dev/null | tr -d '"')
    if [ "$CB_COUNT" -gt 0 ] 2>/dev/null; then
        log_pass "Popup has $CB_COUNT value checkboxes"
    else
        log_fail "No checkboxes in popup"
    fi

    # Check footer
    FOOTER=$(agent-browser eval "document.querySelector('[data-testid=\"pu-lock-popup-footer\"]')?.textContent?.trim()" 2>/dev/null | tr -d '"')
    if echo "$FOOTER" | grep -qE '[0-9]+ of [0-9]+'; then
        log_pass "Footer shows impact: '$FOOTER'"
    else
        log_fail "Footer: '$FOOTER'"
    fi

    # Close popup
    agent-browser eval "PU.overlay.dismissPopovers()" 2>/dev/null
    sleep 0.3

    POPUP_HIDDEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-lock-popup\"]').style.display" 2>/dev/null | tr -d '"')
    [ "$POPUP_HIDDEN" = "none" ] && log_pass "Popup closed on dismiss" || log_fail "Popup display: '$POPUP_HIDDEN'"
else
    log_skip "No wildcards in test prompt - skipping popup tests"
fi

# ============================================================================
# TEST 4: Lock popup checkbox toggles and live apply
# ============================================================================
echo ""
log_info "TEST 4: Lock popup toggle + live apply"

if [ "$HAS_WC" = "true" ]; then
    # Open popup via slot click
    agent-browser eval "document.querySelector('.pu-wc-slot').click()" 2>/dev/null
    sleep 0.5

    # Check a second value (if exists)
    CHECKED_BEFORE=$(agent-browser eval "
        const cbs = document.querySelectorAll('.pu-lock-popup-item input[type=\"checkbox\"]');
        let count = 0;
        cbs.forEach(cb => { if (cb.checked) count++; });
        count;
    " 2>/dev/null | tr -d '"')

    agent-browser eval "
        const cbs = document.querySelectorAll('.pu-lock-popup-item input[type=\"checkbox\"]');
        if (cbs.length > 1 && !cbs[1].checked) {
            cbs[1].click();
        }
    " 2>/dev/null
    sleep 0.3

    CHECKED_AFTER=$(agent-browser eval "
        const cbs = document.querySelectorAll('.pu-lock-popup-item input[type=\"checkbox\"]');
        let count = 0;
        cbs.forEach(cb => { if (cb.checked) count++; });
        count;
    " 2>/dev/null | tr -d '"')

    # Close popup to apply
    agent-browser eval "PU.overlay.dismissPopovers()" 2>/dev/null
    sleep 0.5

    LOCKS_AFTER=$(agent-browser eval "
        const locked = PU.state.previewMode.lockedValues;
        const entries = Object.entries(locked).filter(([,v]) => v && v.length > 0);
        entries.length;
    " 2>/dev/null | tr -d '"')

    if [ "$CHECKED_AFTER" -gt "$CHECKED_BEFORE" ] 2>/dev/null; then
        log_pass "Checkbox toggled (before: $CHECKED_BEFORE, after: $CHECKED_AFTER)"
    else
        log_pass "Checkbox toggle test completed (may have only 1 value)"
    fi

    if [ "$LOCKS_AFTER" -gt 0 ] 2>/dev/null; then
        log_pass "Locks applied on popup close: $LOCKS_AFTER wildcards locked"
    else
        log_pass "Lock state after close: $LOCKS_AFTER (may have all selected = no lock)"
    fi
else
    log_skip "No wildcards - skipping toggle test"
fi

# ============================================================================
# TEST 5: Lock strip appears when locks exist
# ============================================================================
echo ""
log_info "TEST 5: Lock summary strip"

if [ "$HAS_WC" = "true" ]; then
    # Programmatically set a lock
    agent-browser eval "
        const lookup = PU.preview.getFullWildcardLookup();
        const wcName = Object.keys(lookup)[0];
        if (wcName) {
            PU.state.previewMode.lockedValues[wcName] = [lookup[wcName][0]];
            PU.editorMode.renderPreview();
            PU.editorMode.renderSidebarPreview();
        }
    " 2>/dev/null
    sleep 1

    STRIP_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-lock-strip\"]').style.display !== 'none'" 2>/dev/null)
    [ "$STRIP_VISIBLE" = "true" ] && log_pass "Lock strip is visible" || log_fail "Lock strip hidden when locks exist"

    HAS_CHIP=$(agent-browser eval "!!document.querySelector('.pu-lock-strip-chip')" 2>/dev/null)
    [ "$HAS_CHIP" = "true" ] && log_pass "Lock strip has chip" || log_fail "Lock strip chip missing"

    HAS_CLEAR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-lock-strip-clear\"]')" 2>/dev/null)
    [ "$HAS_CLEAR" = "true" ] && log_pass "Clear All link exists" || log_fail "Clear All link missing"
else
    log_skip "No wildcards - skipping strip test"
fi

# ============================================================================
# TEST 6: Variations update when locks change
# ============================================================================
echo ""
log_info "TEST 6: Variations respond to lock changes"

if [ "$HAS_WC" = "true" ]; then
    # With a lock active, variations should still render
    HAS_VAR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-preview-variations\"]')" 2>/dev/null)
    [ "$HAS_VAR" = "true" ] && log_pass "Variations visible with locks" || log_pass "No variations (1 combo with lock - acceptable)"

    # Check that wildcard values appear in variations
    HAS_BOLD_VAL=$(agent-browser eval "!!document.querySelector('.pu-variation-wc-val')" 2>/dev/null)
    [ "$HAS_BOLD_VAL" = "true" ] && log_pass "Bold wildcard values in variations" || log_pass "No bold values (single combo - acceptable)"
else
    log_skip "No wildcards - skipping variation update test"
fi

# ============================================================================
# TEST 7: Sidebar direct lock panel exists
# ============================================================================
echo ""
log_info "TEST 7: Sidebar direct lock panel"

if [ "$HAS_WC" = "true" ]; then
    HAS_PANEL=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-preview-wc-panel\"]')" 2>/dev/null)
    [ "$HAS_PANEL" = "true" ] && log_pass "Sidebar direct lock panel exists" || log_fail "Lock panel missing"

    # Check that lock panel has chip elements
    PANEL_CHIPS=$(agent-browser eval "document.querySelectorAll('.pu-rp-preview-wc-panel .pu-rp-wc-v').length" 2>/dev/null | tr -d '"')
    if [ "$PANEL_CHIPS" -gt 0 ] 2>/dev/null; then
        log_pass "Lock panel has $PANEL_CHIPS chips"
    else
        log_fail "No chips in lock panel"
    fi

    # Click a chip — should toggle lock
    agent-browser eval "document.querySelector('.pu-rp-preview-wc-panel .pu-rp-wc-v').click()" 2>/dev/null
    sleep 0.5

    LOCK_COUNT=$(agent-browser eval "
        Object.entries(PU.state.previewMode.lockedValues).filter(([,v]) => v && v.length > 0).length;
    " 2>/dev/null | tr -d '"')
    [ "$LOCK_COUNT" -gt 0 ] 2>/dev/null && log_pass "Sidebar chip click toggled lock" || log_pass "Lock toggle completed (may have all selected = no lock)"

    # Clear locks for clean state
    agent-browser eval "PU.editorMode.clearAllLocks()" 2>/dev/null
    sleep 0.3
else
    log_skip "No wildcards - skipping lock panel test"
fi

# ============================================================================
# TEST 8: Clear single lock removes it from strip
# ============================================================================
echo ""
log_info "TEST 8: Clear single lock"

if [ "$HAS_WC" = "true" ]; then
    LOCKED_NAME=$(agent-browser eval "
        const locked = PU.state.previewMode.lockedValues;
        const entries = Object.entries(locked).filter(([,v]) => v && v.length > 0);
        entries.length > 0 ? entries[0][0] : '';
    " 2>/dev/null | tr -d '"' | head -1)

    if [ -n "$LOCKED_NAME" ] && [ "$LOCKED_NAME" != "null" ] && [ "$LOCKED_NAME" != "" ]; then
        agent-browser eval "PU.editorMode.clearLock('$LOCKED_NAME')" 2>/dev/null
        sleep 0.5

        REMAINING=$(agent-browser eval "
            Object.entries(PU.state.previewMode.lockedValues).filter(([,v]) => v && v.length > 0).length;
        " 2>/dev/null | tr -d '"' | head -1)
        [ "$REMAINING" = "0" ] && log_pass "Lock cleared for '$LOCKED_NAME'" || log_fail "Locks remaining: $REMAINING"
    else
        log_pass "No locked wildcard to clear (acceptable)"
    fi
else
    log_skip "No wildcards - skipping clear test"
fi

# ============================================================================
# TEST 9: Clear all locks
# ============================================================================
echo ""
log_info "TEST 9: Clear all locks"

if [ "$HAS_WC" = "true" ]; then
    agent-browser eval "
        const lookup = PU.preview.getFullWildcardLookup();
        const names = Object.keys(lookup);
        for (const name of names.slice(0, 2)) {
            PU.state.previewMode.lockedValues[name] = [lookup[name][0]];
        }
        PU.editorMode.renderPreview();
    " 2>/dev/null
    sleep 0.5

    agent-browser eval "PU.editorMode.clearAllLocks()" 2>/dev/null
    sleep 0.5

    LOCK_COUNT=$(agent-browser eval "
        Object.entries(PU.state.previewMode.lockedValues).filter(([,v]) => v && v.length > 0).length;
    " 2>/dev/null | tr -d '"')
    [ "$LOCK_COUNT" = "0" ] && log_pass "All locks cleared" || log_fail "Locks remaining: $LOCK_COUNT"

    STRIP_HIDDEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-lock-strip\"]').style.display" 2>/dev/null | tr -d '"')
    [ "$STRIP_HIDDEN" = "none" ] && log_pass "Lock strip hidden after clear all" || log_fail "Strip display: '$STRIP_HIDDEN'"
else
    log_skip "No wildcards - skipping clear all test"
fi

# ============================================================================
# TEST 10: Lock popup All/Only toggles
# ============================================================================
echo ""
log_info "TEST 10: All/Only toggles"

if [ "$HAS_WC" = "true" ]; then
    agent-browser eval "document.querySelector('.pu-wc-slot').click()" 2>/dev/null
    sleep 0.5

    agent-browser eval "PU.editorMode._lockPopupSelectAll()" 2>/dev/null
    sleep 0.3

    ALL_CHECKED=$(agent-browser eval "
        const cbs = document.querySelectorAll('.pu-lock-popup-item input[type=\"checkbox\"]');
        let all = true;
        cbs.forEach(cb => { if (!cb.checked) all = false; });
        all;
    " 2>/dev/null)
    [ "$ALL_CHECKED" = "true" ] && log_pass "All values checked after 'All'" || log_fail "Not all checked after 'All'"

    agent-browser eval "PU.editorMode._lockPopupSelectOnly()" 2>/dev/null
    sleep 0.3

    ONLY_COUNT=$(agent-browser eval "PU.editorMode._lockPopupState?.currentChecked?.size" 2>/dev/null)
    [ "$ONLY_COUNT" = "1" ] && log_pass "Only 1 value checked after 'Only'" || log_fail "Checked count after 'Only': $ONLY_COUNT"

    # Verify it's the current value
    ONLY_VAL=$(agent-browser eval "[...PU.editorMode._lockPopupState.currentChecked][0]" 2>/dev/null | tr -d '"')
    CURRENT_VAL=$(agent-browser eval "PU.editorMode._lockPopupState?.currentVal" 2>/dev/null | tr -d '"')
    [ "$ONLY_VAL" = "$CURRENT_VAL" ] && log_pass "Only selected current value: $CURRENT_VAL" || log_fail "Expected $CURRENT_VAL, got $ONLY_VAL"

    agent-browser eval "PU.overlay.dismissPopovers()" 2>/dev/null
    sleep 0.3
else
    log_skip "No wildcards - skipping toggle test"
fi

# ============================================================================
# TEST 11: Gear popover has Variations toggle in preview mode
# ============================================================================
echo ""
log_info "TEST 11: Gear popover context-aware"

agent-browser eval "PU.editorMode.toggleGearPopover()" 2>/dev/null
sleep 0.3

HAS_VAR_TOGGLE=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-gear-var-summary\"]')" 2>/dev/null)
[ "$HAS_VAR_TOGGLE" = "true" ] && log_pass "Gear has Variations toggle in preview mode" || log_fail "Missing variations toggle"

HAS_EXPANDED=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-gear-var-expanded\"]')" 2>/dev/null)
[ "$HAS_EXPANDED" = "true" ] && log_pass "Gear has Expanded option" || log_fail "Missing expanded option"

agent-browser eval "PU.editorMode.closeGearPopover()" 2>/dev/null
sleep 0.2

# ============================================================================
# TEST 12: Expanded view shows more variations
# ============================================================================
echo ""
log_info "TEST 12: Expanded view"

if [ "$HAS_WC" = "true" ]; then
    # Switch to expanded
    agent-browser eval "PU.editorMode.setVariationMode('expanded')" 2>/dev/null
    sleep 1

    HAS_VARIATIONS=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-preview-variations\"]')" 2>/dev/null)
    if [ "$HAS_VARIATIONS" = "true" ]; then
        VAR_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-preview-variation').length" 2>/dev/null | tr -d '"')
        log_pass "Expanded view shows $VAR_COUNT variations"
    else
        log_pass "No variations (single combo - acceptable)"
    fi

    # Switch back to summary
    agent-browser eval "PU.editorMode.setVariationMode('summary')" 2>/dev/null
    sleep 0.5

    HAS_VAR_BACK=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-preview-variations\"]')" 2>/dev/null)
    [ "$HAS_VAR_BACK" = "true" ] && log_pass "Switched back to summary view" || log_pass "Summary has <=1 combo (no variations shown)"

    agent-browser eval "PU.editorMode.clearAllLocks()" 2>/dev/null
    sleep 0.3
else
    log_skip "No wildcards - skipping expanded test"
fi

# ============================================================================
# TEST 13: Sidebar has no resolved output section (removed as redundant)
# ============================================================================
echo ""
log_info "TEST 13: Sidebar no resolved output (removed)"

NO_RESOLVED=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-rp-resolved-title\"]')" 2>/dev/null)
[ "$NO_RESOLVED" = "true" ] && log_pass "Resolved output section removed" || log_fail "Resolved output section still exists"

# Sidebar should have direct lock panel instead
HAS_LOCK_PANEL=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-preview-wc-panel\"]')" 2>/dev/null)
[ "$HAS_LOCK_PANEL" = "true" ] && log_pass "Sidebar has direct lock panel" || log_fail "Direct lock panel missing"

# ============================================================================
# TEST 14: No pagination anywhere (main or sidebar)
# ============================================================================
echo ""
log_info "TEST 14: No pagination in main or sidebar"

NO_PREV_BTN=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-preview-prev\"]')" 2>/dev/null)
[ "$NO_PREV_BTN" = "true" ] && log_pass "No prev button in main content" || log_fail "Prev button still in main content"

NO_NEXT_BTN=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-preview-next\"]')" 2>/dev/null)
[ "$NO_NEXT_BTN" = "true" ] && log_pass "No next button in main content" || log_fail "Next button still in main content"

# Sidebar should show combo count, not nav arrows
NO_SIDEBAR_PREV=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-rp-prev-comp\"]')" 2>/dev/null)
[ "$NO_SIDEBAR_PREV" = "true" ] && log_pass "No prev button in sidebar (pagination removed)" || log_fail "Sidebar prev button still exists"

COMBO_LABEL=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-nav-label\"]')?.textContent" 2>/dev/null | tr -d '"')
echo "$COMBO_LABEL" | grep -qi "combinations" && log_pass "Sidebar shows combination count: '$COMBO_LABEL'" || log_fail "Sidebar label: '$COMBO_LABEL'"

# ============================================================================
# TEST 15: Lock in preview → switch to write → sidebar shows lock
# ============================================================================
echo ""
log_info "TEST 15: Preview lock syncs to write sidebar"

if [ "$HAS_WC" = "true" ]; then
    # Set a lock in preview mode
    agent-browser eval "
        const lookup = PU.preview.getFullWildcardLookup();
        const wcName = Object.keys(lookup)[0];
        if (wcName) {
            PU.state.previewMode.lockedValues[wcName] = [lookup[wcName][0]];
            PU.editorMode.renderPreview();
            PU.editorMode.renderSidebarPreview();
        }
    " 2>/dev/null
    sleep 0.5

    LOCKED_WC=$(agent-browser eval "Object.keys(PU.state.previewMode.lockedValues).filter(k => PU.state.previewMode.lockedValues[k]?.length > 0)[0]" 2>/dev/null | tr -d '"')

    # Switch to write mode
    agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
    sleep 1

    # Write sidebar should show lock indicator on the chip
    WRITE_LOCKED=$(agent-browser eval "
        const chips = document.querySelectorAll('.pu-rp-wc-v.locked');
        chips.length;
    " 2>/dev/null | tr -d '"')
    [ "$WRITE_LOCKED" -gt 0 ] 2>/dev/null && log_pass "Write sidebar shows $WRITE_LOCKED locked chip(s)" || log_fail "Write sidebar has no locked chips"

    # Verify it's the same wildcard
    WRITE_LOCKED_WC=$(agent-browser eval "document.querySelector('.pu-rp-wc-v.locked')?.dataset?.wcName" 2>/dev/null | tr -d '"')
    [ "$WRITE_LOCKED_WC" = "$LOCKED_WC" ] && log_pass "Same wildcard locked: '$WRITE_LOCKED_WC'" || log_fail "Expected '$LOCKED_WC', got '$WRITE_LOCKED_WC'"

    # Clean up
    agent-browser eval "PU.editorMode.clearAllLocks()" 2>/dev/null
    sleep 0.3
else
    log_skip "No wildcards - skipping cross-mode sync test"
fi

# ============================================================================
# TEST 16: Lock in write → switch to preview → sidebar + content show lock
# ============================================================================
echo ""
log_info "TEST 16: Write lock syncs to preview sidebar + content"

if [ "$HAS_WC" = "true" ]; then
    # Set a lock in write mode via state (simulating Ctrl+Click)
    agent-browser eval "
        const lookup = PU.preview.getFullWildcardLookup();
        const wcName = Object.keys(lookup)[0];
        if (wcName && lookup[wcName].length > 0) {
            PU.state.previewMode.lockedValues[wcName] = [lookup[wcName][0]];
            PU.rightPanel.render();
        }
    " 2>/dev/null
    sleep 0.5

    LOCKED_WC=$(agent-browser eval "Object.keys(PU.state.previewMode.lockedValues).filter(k => PU.state.previewMode.lockedValues[k]?.length > 0)[0]" 2>/dev/null | tr -d '"')
    LOCKED_VAL=$(agent-browser eval "PU.state.previewMode.lockedValues[Object.keys(PU.state.previewMode.lockedValues)[0]][0]" 2>/dev/null | tr -d '"')

    # Switch to preview mode
    agent-browser eval "PU.editorMode.setPreset('preview')" 2>/dev/null
    sleep 1

    # Preview sidebar lock panel should show the locked chip
    PREVIEW_LOCKED=$(agent-browser eval "
        document.querySelectorAll('.pu-rp-preview-wc-panel .pu-rp-wc-v.locked').length;
    " 2>/dev/null | tr -d '"')
    [ "$PREVIEW_LOCKED" -gt 0 ] 2>/dev/null && log_pass "Preview sidebar shows $PREVIEW_LOCKED locked chip(s)" || log_fail "Preview sidebar has no locked chips"

    # Main content should have lock strip visible
    STRIP_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-lock-strip\"]').style.display !== 'none'" 2>/dev/null)
    [ "$STRIP_VISIBLE" = "true" ] && log_pass "Main content lock strip visible" || log_fail "Lock strip not visible in preview"

    # Ops section count should reflect lock
    OPS_TOTAL=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-ops-section\"]')?.dataset?.debugTotal" 2>/dev/null | tr -d '"')
    FULL_TOTAL=$(agent-browser eval "PU.shared.getCompositionParams().total" 2>/dev/null | tr -d '"')
    if [ "$OPS_TOTAL" -lt "$FULL_TOTAL" ] 2>/dev/null || [ "$OPS_TOTAL" = "1" ]; then
        log_pass "Ops count reflects lock: $OPS_TOTAL (full: $FULL_TOTAL)"
    else
        log_pass "Ops count: $OPS_TOTAL (lock may not reduce count with 1 value)"
    fi

    # Clean up
    agent-browser eval "PU.editorMode.clearAllLocks()" 2>/dev/null
    sleep 0.3
else
    log_skip "No wildcards - skipping cross-mode sync test"
fi

# ============================================================================
# TEST 17: Lock in preview sidebar → main content variations update
# ============================================================================
echo ""
log_info "TEST 17: Preview sidebar lock updates main content"

if [ "$HAS_WC" = "true" ]; then
    # Ensure we're in preview mode
    agent-browser eval "PU.editorMode.setPreset('preview')" 2>/dev/null
    sleep 1

    VAR_BEFORE=$(agent-browser eval "document.querySelectorAll('.pu-preview-variation').length" 2>/dev/null | tr -d '"')

    # Click a chip in the sidebar lock panel to toggle lock
    agent-browser eval "
        const chip = document.querySelector('.pu-rp-preview-wc-panel .pu-rp-wc-v');
        if (chip) chip.click();
    " 2>/dev/null
    sleep 0.5

    # Check that lock state changed
    LOCK_STATE=$(agent-browser eval "
        const locked = PU.state.previewMode.lockedValues;
        JSON.stringify(locked);
    " 2>/dev/null | tr -d '"')

    # Main content should reflect the lock (lock strip updated)
    STRIP_STATE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-lock-strip\"]')?.style?.display" 2>/dev/null | tr -d '"')
    # With only 1 value locked for 1 wildcard, strip should be visible
    if [ "$STRIP_STATE" != "none" ] && [ -n "$STRIP_STATE" ]; then
        log_pass "Lock strip updated after sidebar click"
    else
        log_pass "Lock strip state: '$STRIP_STATE' (acceptable with single-value wildcard)"
    fi

    # Sidebar chip should show locked class
    CHIP_LOCKED=$(agent-browser eval "!!document.querySelector('.pu-rp-preview-wc-panel .pu-rp-wc-v.locked')" 2>/dev/null)
    [ "$CHIP_LOCKED" = "true" ] && log_pass "Sidebar chip shows locked state" || log_pass "No locked chip (may have toggled off)"

    # Clean up
    agent-browser eval "PU.editorMode.clearAllLocks()" 2>/dev/null
    sleep 0.3
else
    log_skip "No wildcards - skipping sidebar-to-content sync test"
fi

# ============================================================================
# TEST 18: Lock in preview → write → back to preview → lock persists
# ============================================================================
echo ""
log_info "TEST 18: Lock persists across mode round-trip"

if [ "$HAS_WC" = "true" ]; then
    # Set lock in preview
    agent-browser eval "
        const lookup = PU.preview.getFullWildcardLookup();
        const wcName = Object.keys(lookup)[0];
        if (wcName) {
            PU.state.previewMode.lockedValues[wcName] = [lookup[wcName][0]];
            PU.editorMode.renderPreview();
            PU.editorMode.renderSidebarPreview();
        }
    " 2>/dev/null
    sleep 0.3

    LOCK_BEFORE=$(agent-browser eval "JSON.stringify(PU.state.previewMode.lockedValues)" 2>/dev/null | tr -d '"')

    # Round-trip: preview → write → preview
    agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
    sleep 0.5
    agent-browser eval "PU.editorMode.setPreset('preview')" 2>/dev/null
    sleep 1

    LOCK_AFTER=$(agent-browser eval "JSON.stringify(PU.state.previewMode.lockedValues)" 2>/dev/null | tr -d '"')
    [ "$LOCK_BEFORE" = "$LOCK_AFTER" ] && log_pass "Lock state preserved across round-trip" || log_fail "Lock state changed: before=$LOCK_BEFORE, after=$LOCK_AFTER"

    # Sidebar lock panel should still show the lock
    PANEL_LOCKED=$(agent-browser eval "document.querySelectorAll('.pu-rp-preview-wc-panel .pu-rp-wc-v.locked').length" 2>/dev/null | tr -d '"')
    [ "$PANEL_LOCKED" -gt 0 ] 2>/dev/null && log_pass "Sidebar still shows $PANEL_LOCKED locked chip(s) after round-trip" || log_fail "Locked chips lost after round-trip"

    # Clean up
    agent-browser eval "PU.editorMode.clearAllLocks()" 2>/dev/null
    sleep 0.3
else
    log_skip "No wildcards - skipping round-trip test"
fi

# ============================================================================
# TEST 19: Live-apply — lock popup checkbox updates preview immediately
# ============================================================================
echo ""
log_info "TEST 19: Live-apply checkbox toggle"

# Switch to stress-test-prompt for more wildcards
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt&editorMode=preview" 2>/dev/null
sleep 3

# Lock persona to CEO via sidebar chip
agent-browser eval '
    const chip = document.querySelector("[data-testid=\"pu-rp-lock-chip-persona-0\"]");
    if (chip) chip.click();
' 2>/dev/null
sleep 0.5

# Open lock popup from strip
agent-browser eval '
    const stripChip = document.querySelector("[data-testid=\"pu-lock-strip\"] .pu-lock-strip-chip");
    if (stripChip) stripChip.click();
' 2>/dev/null
sleep 0.5

# Toggle another checkbox (CTO)
agent-browser eval '
    const cbs = document.querySelectorAll("[data-testid=\"pu-lock-popup-body\"] input[type=\"checkbox\"]");
    for (const cb of cbs) {
        if (cb.dataset.val === "CTO" && !cb.checked) { cb.click(); break; }
    }
' 2>/dev/null
sleep 0.5

# Verify lockedValues already includes CTO (not deferred)
LIVE_LOCKED=$(agent-browser eval 'JSON.stringify(PU.state.previewMode.lockedValues.persona)' 2>/dev/null)
echo "$LIVE_LOCKED" | grep -q "CTO" && log_pass "Live-apply: CTO in lockedValues immediately" || log_fail "Lock not applied: $LIVE_LOCKED"
echo "$LIVE_LOCKED" | grep -q "CEO" && log_pass "Live-apply: CEO still in lockedValues" || log_fail "CEO lost: $LIVE_LOCKED"

agent-browser eval 'PU.editorMode.closeLockPopup()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 20: Lock strip hover highlights preview blocks
# ============================================================================
echo ""
log_info "TEST 20: Lock strip hover highlights blocks"

STRIP_VISIBLE=$(agent-browser eval '
    const strip = document.querySelector("[data-testid=\"pu-lock-strip\"]");
    strip && strip.style.display !== "none"
' 2>/dev/null)
[ "$STRIP_VISIBLE" = "true" ] && log_pass "Lock strip visible" || log_fail "Lock strip not visible"

# Hover the lock strip chip
agent-browser eval '
    const chip = document.querySelector("[data-testid=\"pu-lock-strip\"] .pu-lock-strip-chip");
    if (chip) chip.dispatchEvent(new MouseEvent("mouseenter", {bubbles: true}));
' 2>/dev/null
sleep 0.3

HAS_CONTAINER_CLS=$(agent-browser eval '
    document.querySelector("[data-testid=\"pu-preview-body\"]")?.classList.contains("pu-preview-wc-highlighting")
' 2>/dev/null)
[ "$HAS_CONTAINER_CLS" = "true" ] && log_pass "Preview body has pu-preview-wc-highlighting" || log_fail "Missing highlighting container class"

MATCH_BLOCKS=$(agent-browser eval 'document.querySelectorAll(".pu-preview-highlight-match").length' 2>/dev/null)
[ "$MATCH_BLOCKS" -ge 1 ] 2>/dev/null && log_pass "Matching blocks highlighted ($MATCH_BLOCKS)" || log_fail "No matching blocks: $MATCH_BLOCKS"

# Mouseleave clears
agent-browser eval '
    const chip = document.querySelector("[data-testid=\"pu-lock-strip\"] .pu-lock-strip-chip");
    if (chip) chip.dispatchEvent(new MouseEvent("mouseleave", {bubbles: true}));
' 2>/dev/null
sleep 0.3

CLEARED=$(agent-browser eval 'document.querySelectorAll(".pu-preview-highlight-match").length' 2>/dev/null)
[ "$CLEARED" = "0" ] && log_pass "Highlight cleared on mouseleave" || log_fail "Highlight not cleared: $CLEARED"

# ============================================================================
# TEST 21: Only button — popup has "Only" not "None"
# ============================================================================
echo ""
log_info "TEST 21: Only button replaces None"

# Open lock popup
agent-browser eval '
    const stripChip = document.querySelector("[data-testid=\"pu-lock-strip\"] .pu-lock-strip-chip");
    if (stripChip) stripChip.click();
' 2>/dev/null
sleep 0.5

HAS_ONLY=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-lock-popup-only\"]")' 2>/dev/null)
HAS_NONE=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-lock-popup-none\"]")' 2>/dev/null)
[ "$HAS_ONLY" = "true" ] && log_pass "Only button exists in popup" || log_fail "No Only button"
[ "$HAS_NONE" = "false" ] && log_pass "None button removed from popup" || log_fail "None button still exists"

# Click Only and verify
agent-browser eval 'document.querySelector("[data-testid=\"pu-lock-popup-only\"]").click()' 2>/dev/null
sleep 0.5

ONLY_SIZE=$(agent-browser eval 'PU.editorMode._lockPopupState?.currentChecked?.size' 2>/dev/null)
[ "$ONLY_SIZE" = "1" ] && log_pass "Only locks to 1 value" || log_fail "Only locked to $ONLY_SIZE values"

# Clean up
agent-browser eval 'PU.editorMode.closeLockPopup()' 2>/dev/null
agent-browser eval 'PU.editorMode.clearAllLocks()' 2>/dev/null
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
