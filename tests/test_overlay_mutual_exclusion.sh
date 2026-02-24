#!/bin/bash
# ============================================================================
# E2E Test Suite: Overlay Mutual Exclusion & Extension Picker Positioning
# ============================================================================
# Tests that opening one overlay dismisses all others, and that the
# extension picker anchors to the trigger button with top-right origin.
#
# Usage: ./tests/test_overlay_mutual_exclusion.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

setup_cleanup  # Trap-based cleanup ensures browser closes on exit

# Helper: run agent-browser eval and return only the JS result (first line, stripped)
browser_eval() {
    agent-browser eval "$1" 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*m//g' | tr -d '"'
}

print_header "Overlay Mutual Exclusion & Picker Positioning"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_pass "Server is running"
else
    log_fail "Server not running"
    exit 1
fi

# Open the page with a known test fixture job
agent-browser open "$BASE_URL/?job=test-fixtures" 2>/dev/null
sleep 3

# Verify page loaded
PAGE_TITLE=$(agent-browser get title 2>/dev/null | head -1)
if echo "$PAGE_TITLE" | grep -qi "prompty"; then
    log_pass "Page loaded"
else
    log_fail "Page did not load: $PAGE_TITLE"
    exit 1
fi

# ============================================================================
# TEST 1: PU.overlay registry exists and has registrations
# ============================================================================
echo ""
log_info "TEST 1: Overlay registry exists with registrations"

HAS_REGISTRY=$(browser_eval "typeof PU.overlay === 'object' && typeof PU.overlay.dismissAll === 'function'")
if [ "$HAS_REGISTRY" = "true" ]; then
    log_pass "PU.overlay registry exists with dismissAll()"
else
    log_fail "PU.overlay registry missing: $HAS_REGISTRY"
fi

POPOVER_COUNT=$(browser_eval "PU.overlay._popovers.length")
MODAL_COUNT=$(browser_eval "PU.overlay._modals.length")

if [ "$POPOVER_COUNT" -ge 3 ] 2>/dev/null; then
    log_pass "Popover registrations: $POPOVER_COUNT"
else
    log_fail "Expected >= 3 popover registrations, got: $POPOVER_COUNT"
fi

if [ "$MODAL_COUNT" -ge 3 ] 2>/dev/null; then
    log_pass "Modal registrations: $MODAL_COUNT"
else
    log_fail "Expected >= 3 modal registrations, got: $MODAL_COUNT"
fi

# ============================================================================
# TEST 2: Registered overlay names
# ============================================================================
echo ""
log_info "TEST 2: Registered overlay names"

POPOVER_NAMES=$(browser_eval "PU.overlay._popovers.map(p => p.name).join(',')")
MODAL_NAMES=$(browser_eval "PU.overlay._modals.map(m => m.name).join(',')")

for name in contextMenu swapDropdown addMenu opDropdown replacePopover pushPopover; do
    if echo "$POPOVER_NAMES" | grep -q "$name"; then
        log_pass "Popover registered: $name"
    else
        log_fail "Popover missing: $name (found: $POPOVER_NAMES)"
    fi
done

for name in saveModal moveToTheme extPicker export focus; do
    if echo "$MODAL_NAMES" | grep -q "$name"; then
        log_pass "Modal registered: $name"
    else
        log_fail "Modal missing: $name (found: $MODAL_NAMES)"
    fi
done

# ============================================================================
# TEST 3: dismissAll() closes add menu
# ============================================================================
echo ""
log_info "TEST 3: dismissAll() closes open overlays"

# Show add menu
browser_eval "PU.actions.toggleAddMenu(true); 'ok'" > /dev/null
sleep 0.3

ADD_VIS=$(browser_eval "document.querySelector('.pu-add-menu') ? document.querySelector('.pu-add-menu').style.display : 'missing'")
if [ "$ADD_VIS" = "block" ]; then
    log_pass "Add menu opened for test"
else
    log_fail "Could not open add menu: $ADD_VIS"
fi

# Call dismissAll
browser_eval "PU.overlay.dismissAll(); 'done'" > /dev/null
sleep 0.3

ADD_AFTER=$(browser_eval "document.querySelector('.pu-add-menu') ? document.querySelector('.pu-add-menu').style.display : 'missing'")
if [ "$ADD_AFTER" = "none" ]; then
    log_pass "dismissAll() closed add menu"
else
    log_fail "Add menu still visible after dismissAll(): $ADD_AFTER"
fi

# ============================================================================
# TEST 4: dismissPopovers() closes popovers only, not modals
# ============================================================================
echo ""
log_info "TEST 4: dismissPopovers() closes popovers only"

# Open add menu (popover)
browser_eval "PU.actions.toggleAddMenu(true); 'ok'" > /dev/null
sleep 0.3

# Set export modal state visible (modal layer)
browser_eval "PU.state.exportModal.visible = true; 'ok'" > /dev/null

# Call dismissPopovers (should close add menu but NOT export modal)
browser_eval "PU.overlay.dismissPopovers(); 'done'" > /dev/null
sleep 0.3

ADD_CLOSED=$(browser_eval "document.querySelector('.pu-add-menu') ? document.querySelector('.pu-add-menu').style.display : 'missing'")
EXPORT_STATE=$(browser_eval "PU.state.exportModal.visible")

if [ "$ADD_CLOSED" = "none" ]; then
    log_pass "dismissPopovers() closed add menu"
else
    log_fail "Add menu still visible after dismissPopovers(): $ADD_CLOSED"
fi

if [ "$EXPORT_STATE" = "true" ]; then
    log_pass "dismissPopovers() did NOT touch export modal state"
else
    log_fail "dismissPopovers() affected export modal: $EXPORT_STATE"
fi

# Clean up
browser_eval "PU.state.exportModal.visible = false; 'ok'" > /dev/null

# ============================================================================
# TEST 5: Opening export modal dismisses add menu
# ============================================================================
echo ""
log_info "TEST 5: Opening export modal dismisses other overlays"

# Show add menu
browser_eval "PU.actions.toggleAddMenu(true); 'ok'" > /dev/null
sleep 0.3

# Open export modal (calls dismissAll inside)
browser_eval "PU.export.open(); 'ok'" > /dev/null
sleep 1.5

ADD_AFTER_EXPORT=$(browser_eval "document.querySelector('.pu-add-menu') ? document.querySelector('.pu-add-menu').style.display : 'missing'")
EXPORT_VIS=$(browser_eval "PU.state.exportModal.visible")

if [ "$ADD_AFTER_EXPORT" = "none" ]; then
    log_pass "Opening export closed add menu"
else
    log_fail "Add menu still open after opening export: $ADD_AFTER_EXPORT"
fi

if [ "$EXPORT_VIS" = "true" ]; then
    log_pass "Export modal is open"
else
    log_fail "Export modal not open: $EXPORT_VIS"
fi

# Close export
browser_eval "PU.export.close(); 'ok'" > /dev/null
sleep 0.3

# ============================================================================
# TEST 6: Extension picker dismisses add menu on open
# ============================================================================
echo ""
log_info "TEST 6: Extension picker dismisses other overlays on open"

# Open add menu
browser_eval "PU.actions.toggleAddMenu(true); 'ok'" > /dev/null
sleep 0.3

# Open extension picker
browser_eval "PU.rightPanel.showExtensionPicker(function(){}); 'ok'" > /dev/null
sleep 0.5

ADD_AFTER_PICKER=$(browser_eval "document.querySelector('.pu-add-menu') ? document.querySelector('.pu-add-menu').style.display : 'missing'")
PICKER_VIS=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]') ? document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').style.display : 'missing'")

if [ "$ADD_AFTER_PICKER" = "none" ]; then
    log_pass "Extension picker opening closed add menu"
else
    log_fail "Add menu not closed when ext picker opened: $ADD_AFTER_PICKER"
fi

if [ "$PICKER_VIS" = "flex" ]; then
    log_pass "Extension picker is visible"
else
    log_fail "Extension picker not visible: $PICKER_VIS"
fi

# Close picker
browser_eval "PU.rightPanel.closeExtPicker(); 'ok'" > /dev/null
sleep 0.3

# ============================================================================
# TEST 7: Extension picker anchored positioning (desktop)
# ============================================================================
echo ""
log_info "TEST 7: Extension picker anchored to button (top-right origin)"

# Create a fake anchor button at a known position
browser_eval "var btn=document.createElement('button'); btn.id='test-anchor-btn'; btn.textContent='Anchor'; btn.style.cssText='position:fixed;top:200px;left:400px;width:100px;height:30px;z-index:9999'; document.body.appendChild(btn); 'ok'" > /dev/null
sleep 0.3

# Open ext picker with anchor
browser_eval "PU.rightPanel.showExtensionPicker(function(){}, document.getElementById('test-anchor-btn')); 'ok'" > /dev/null
sleep 0.5

# Check anchored positioning
ANCHORED=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').dataset.anchored || 'none'")
POPUP_TOP=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').style.top || 'none'")
POPUP_LEFT=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').style.left || 'none'")
POPUP_TRANSFORM=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').style.transform || 'none'")

if [ "$ANCHORED" = "true" ]; then
    log_pass "Extension picker has data-anchored='true'"
else
    log_fail "Missing anchored attribute: $ANCHORED"
fi

if echo "$POPUP_TOP" | grep -q "px"; then
    log_pass "Picker has explicit top: $POPUP_TOP"
else
    log_fail "Missing top position: $POPUP_TOP"
fi

if echo "$POPUP_LEFT" | grep -q "px"; then
    log_pass "Picker has explicit left: $POPUP_LEFT"
else
    log_fail "Missing left position: $POPUP_LEFT"
fi

if [ "$POPUP_TRANSFORM" = "none" ]; then
    log_pass "Transform set to none (not CSS default centered)"
else
    log_fail "Transform not overridden: $POPUP_TRANSFORM"
fi

# Close picker and verify cleanup
browser_eval "PU.rightPanel.closeExtPicker(); 'ok'" > /dev/null
sleep 0.3

ANCHORED_AFTER=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').dataset.anchored || 'cleared'")
LEFT_AFTER=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').style.left || 'cleared'")

if [ "$ANCHORED_AFTER" = "cleared" ]; then
    log_pass "Anchored attribute removed on close"
else
    log_fail "Anchored attribute not cleaned up: $ANCHORED_AFTER"
fi

if [ "$LEFT_AFTER" = "cleared" ]; then
    log_pass "Inline left style reset on close"
else
    log_fail "Inline left still set: $LEFT_AFTER"
fi

# Clean up test button
browser_eval "document.getElementById('test-anchor-btn').remove(); 'ok'" > /dev/null

# ============================================================================
# TEST 8: Extension picker without anchor uses CSS defaults
# ============================================================================
echo ""
log_info "TEST 8: Extension picker without anchor uses CSS defaults"

browser_eval "PU.rightPanel.showExtensionPicker(function(){}); 'ok'" > /dev/null
sleep 0.5

NO_ANCHOR=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').dataset.anchored || 'cleared'")
NO_ANCHOR_LEFT=$(browser_eval "document.querySelector('[data-testid=\"pu-ext-picker-popup\"]').style.left || 'cleared'")

if [ "$NO_ANCHOR" = "cleared" ]; then
    log_pass "No anchor: data-anchored not set"
else
    log_fail "Unexpected anchored attribute without anchor: $NO_ANCHOR"
fi

if [ "$NO_ANCHOR_LEFT" = "cleared" ]; then
    log_pass "No anchor: no inline left (CSS defaults apply)"
else
    log_fail "Unexpected inline left without anchor: $NO_ANCHOR_LEFT"
fi

browser_eval "PU.rightPanel.closeExtPicker(); 'ok'" > /dev/null
sleep 0.3

# ============================================================================
# TEST 9: addThemeAsChild passes anchor to showExtensionPicker
# ============================================================================
echo ""
log_info "TEST 9: addThemeAsChild passes anchor element"

HAS_ANCHOR_PARAM=$(browser_eval "PU.themes.addThemeAsChild.toString().includes('anchorEl')")
if [ "$HAS_ANCHOR_PARAM" = "true" ]; then
    log_pass "addThemeAsChild accepts anchorEl parameter"
else
    log_fail "addThemeAsChild does not accept anchorEl"
fi

# ============================================================================
# TEST 10: Opening a popup shows the popup overlay
# ============================================================================
echo ""
log_info "TEST 10: Opening a popup shows the popup overlay"

# Ensure overlay starts hidden
browser_eval "PU.overlay.hideOverlay(); 'ok'" > /dev/null
sleep 0.2

OVERLAY_BEFORE=$(browser_eval "document.querySelector('[data-testid=\"pu-popup-overlay\"]').classList.contains('visible')")
if [ "$OVERLAY_BEFORE" = "false" ]; then
    log_pass "Popup overlay starts hidden"
else
    log_fail "Popup overlay was already visible: $OVERLAY_BEFORE"
fi

# Open add menu (triggers showOverlay)
browser_eval "PU.actions.toggleAddMenu(true); 'ok'" > /dev/null
sleep 0.3

OVERLAY_AFTER=$(browser_eval "document.querySelector('[data-testid=\"pu-popup-overlay\"]').classList.contains('visible')")
if [ "$OVERLAY_AFTER" = "true" ]; then
    log_pass "Opening add menu shows popup overlay"
else
    log_fail "Popup overlay not visible after opening add menu: $OVERLAY_AFTER"
fi

# Clean up
browser_eval "PU.overlay.dismissAll(); 'ok'" > /dev/null
sleep 0.2

# ============================================================================
# TEST 11: Clicking popup overlay dismisses popup and hides overlay
# ============================================================================
echo ""
log_info "TEST 11: Clicking popup overlay dismisses popup and hides overlay"

# Open add menu
browser_eval "PU.actions.toggleAddMenu(true); 'ok'" > /dev/null
sleep 0.3

# Simulate clicking the popup overlay
browser_eval "document.querySelector('[data-testid=\"pu-popup-overlay\"]').click(); 'ok'" > /dev/null
sleep 0.3

MENU_AFTER_CLICK=$(browser_eval "document.querySelector('.pu-add-menu') ? document.querySelector('.pu-add-menu').style.display : 'missing'")
OVERLAY_AFTER_CLICK=$(browser_eval "document.querySelector('[data-testid=\"pu-popup-overlay\"]').classList.contains('visible')")

if [ "$MENU_AFTER_CLICK" = "none" ]; then
    log_pass "Clicking popup overlay closed add menu"
else
    log_fail "Add menu still visible after overlay click: $MENU_AFTER_CLICK"
fi

if [ "$OVERLAY_AFTER_CLICK" = "false" ]; then
    log_pass "Popup overlay hidden after click"
else
    log_fail "Popup overlay still visible after click: $OVERLAY_AFTER_CLICK"
fi

# ============================================================================
# TEST 12: dismissAll() hides the popup overlay
# ============================================================================
echo ""
log_info "TEST 12: dismissAll() hides the popup overlay"

# Show overlay manually
browser_eval "PU.overlay.showOverlay(); 'ok'" > /dev/null
sleep 0.2

OVERLAY_SHOWN=$(browser_eval "document.querySelector('[data-testid=\"pu-popup-overlay\"]').classList.contains('visible')")
if [ "$OVERLAY_SHOWN" = "true" ]; then
    log_pass "Overlay shown for test"
else
    log_fail "Could not show overlay: $OVERLAY_SHOWN"
fi

# Call dismissAll
browser_eval "PU.overlay.dismissAll(); 'ok'" > /dev/null
sleep 0.2

OVERLAY_DISMISSED=$(browser_eval "document.querySelector('[data-testid=\"pu-popup-overlay\"]').classList.contains('visible')")
if [ "$OVERLAY_DISMISSED" = "false" ]; then
    log_pass "dismissAll() hides popup overlay"
else
    log_fail "Popup overlay still visible after dismissAll(): $OVERLAY_DISMISSED"
fi

# ============================================================================
# TEST 13: Modals (export) do NOT show the popup overlay
# ============================================================================
echo ""
log_info "TEST 13: Export modal does NOT show popup overlay"

# Ensure overlay is hidden
browser_eval "PU.overlay.hideOverlay(); 'ok'" > /dev/null
sleep 0.2

# Open export modal
browser_eval "PU.export.open(); 'ok'" > /dev/null
sleep 1

OVERLAY_DURING_EXPORT=$(browser_eval "document.querySelector('[data-testid=\"pu-popup-overlay\"]').classList.contains('visible')")
EXPORT_OPEN=$(browser_eval "PU.state.exportModal.visible")

if [ "$EXPORT_OPEN" = "true" ]; then
    log_pass "Export modal is open"
else
    log_fail "Export modal not open: $EXPORT_OPEN"
fi

if [ "$OVERLAY_DURING_EXPORT" = "false" ]; then
    log_pass "Popup overlay NOT shown for export modal (has own overlay)"
else
    log_fail "Popup overlay incorrectly shown for export modal: $OVERLAY_DURING_EXPORT"
fi

# Close export
browser_eval "PU.export.close(); 'ok'" > /dev/null
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
