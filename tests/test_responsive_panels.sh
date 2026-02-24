#!/bin/bash
# ============================================================================
# E2E Test Suite: Responsive Panel Overlays
# ============================================================================
# Tests mobile/tablet responsive behavior for sidebar and right panel.
# Since agent-browser cannot resize viewports, we verify:
# - Backdrop overlay element exists
# - PU.responsive module is initialized
# - pu-panel-open class + backdrop visibility via JS
# - Desktop mode unaffected (panels use flex, not fixed)
# - Footer shortcuts hide on mobile via CSS rules
#
# Usage: ./tests/test_responsive_panels.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

setup_cleanup

print_header "Responsive Panel Overlays"

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

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=base" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: Backdrop overlay element exists in DOM
# ============================================================================
echo ""
log_info "TEST 1: Backdrop overlay element exists"

HAS_BACKDROP=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-backdrop\"]')" 2>/dev/null)
if [ "$HAS_BACKDROP" = "true" ]; then
    log_pass "Backdrop element exists in DOM"
else
    log_fail "Backdrop element missing from DOM"
fi

BACKDROP_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-backdrop\"]').classList.contains('visible')" 2>/dev/null)
if [ "$BACKDROP_VISIBLE" = "false" ]; then
    log_pass "Backdrop hidden by default (no 'visible' class)"
else
    log_fail "Backdrop unexpectedly visible on load"
fi

# ============================================================================
# TEST 2: PU.responsive module is initialized
# ============================================================================
echo ""
log_info "TEST 2: PU.responsive module initialized"

HAS_MODULE=$(agent-browser eval "typeof PU.responsive === 'object' && typeof PU.responsive.isMobile === 'function'" 2>/dev/null)
if [ "$HAS_MODULE" = "true" ]; then
    log_pass "PU.responsive module exists with isMobile()"
else
    log_fail "PU.responsive module missing or incomplete"
fi

HAS_OVERLAY=$(agent-browser eval "typeof PU.responsive.isOverlay === 'function'" 2>/dev/null)
if [ "$HAS_OVERLAY" = "true" ]; then
    log_pass "PU.responsive.isOverlay() exists"
else
    log_fail "PU.responsive.isOverlay() missing"
fi

HAS_OPEN=$(agent-browser eval "typeof PU.responsive.openPanel === 'function'" 2>/dev/null)
if [ "$HAS_OPEN" = "true" ]; then
    log_pass "PU.responsive.openPanel() exists"
else
    log_fail "PU.responsive.openPanel() missing"
fi

HAS_CLOSE=$(agent-browser eval "typeof PU.responsive.closePanels === 'function'" 2>/dev/null)
if [ "$HAS_CLOSE" = "true" ]; then
    log_pass "PU.responsive.closePanels() exists"
else
    log_fail "PU.responsive.closePanels() missing"
fi

# ============================================================================
# TEST 3: Desktop mode — panels use flex layout, not fixed
# ============================================================================
echo ""
log_info "TEST 3: Desktop mode — panels use flex, not fixed"

SIDEBAR_POS=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-sidebar\"]')).position" 2>/dev/null | tr -d '"')
if [ "$SIDEBAR_POS" = "static" ] || [ "$SIDEBAR_POS" = "relative" ]; then
    log_pass "Sidebar uses $SIDEBAR_POS position (flex layout, not fixed)"
else
    log_fail "Sidebar has position: $SIDEBAR_POS (expected static/relative)"
fi

RP_POS=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-right-panel\"]')).position" 2>/dev/null | tr -d '"')
if [ "$RP_POS" = "static" ] || [ "$RP_POS" = "relative" ]; then
    log_pass "Right panel uses $RP_POS position (flex layout, not fixed)"
else
    log_fail "Right panel has position: $RP_POS (expected static/relative)"
fi

# ============================================================================
# TEST 4: openPanel adds pu-panel-open class and shows backdrop
# ============================================================================
echo ""
log_info "TEST 4: openPanel() adds class and shows backdrop"

# Open sidebar via PU.responsive
agent-browser eval "PU.responsive.openPanel('pu-sidebar')" 2>/dev/null
sleep 0.3

HAS_OPEN_CLASS=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('pu-panel-open')" 2>/dev/null)
if [ "$HAS_OPEN_CLASS" = "true" ]; then
    log_pass "Sidebar has pu-panel-open class after openPanel()"
else
    log_fail "Sidebar missing pu-panel-open class"
fi

BACKDROP_VIS=$(agent-browser eval "document.querySelector('[data-testid=\"pu-backdrop\"]').classList.contains('visible')" 2>/dev/null)
if [ "$BACKDROP_VIS" = "true" ]; then
    log_pass "Backdrop visible after openPanel()"
else
    log_fail "Backdrop not visible after openPanel()"
fi

# ============================================================================
# TEST 5: closePanel removes class and hides backdrop
# ============================================================================
echo ""
log_info "TEST 5: closePanel() removes class and hides backdrop"

agent-browser eval "PU.responsive.closePanel('pu-sidebar')" 2>/dev/null
sleep 0.3

HAS_OPEN_CLASS=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('pu-panel-open')" 2>/dev/null)
if [ "$HAS_OPEN_CLASS" = "false" ]; then
    log_pass "Sidebar pu-panel-open removed after closePanel()"
else
    log_fail "Sidebar still has pu-panel-open after closePanel()"
fi

BACKDROP_VIS=$(agent-browser eval "document.querySelector('[data-testid=\"pu-backdrop\"]').classList.contains('visible')" 2>/dev/null)
if [ "$BACKDROP_VIS" = "false" ]; then
    log_pass "Backdrop hidden after closePanel()"
else
    log_fail "Backdrop still visible after closePanel()"
fi

# ============================================================================
# TEST 6: closePanels() closes all open panels
# ============================================================================
echo ""
log_info "TEST 6: closePanels() closes all open panels"

# Open both panels
agent-browser eval "PU.responsive.openPanel('pu-sidebar'); PU.responsive.openPanel('pu-right-panel');" 2>/dev/null
sleep 0.3

BOTH_OPEN=$(agent-browser eval "
    document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('pu-panel-open') &&
    document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('pu-panel-open')
" 2>/dev/null)
if [ "$BOTH_OPEN" = "true" ]; then
    log_pass "Both panels opened"
else
    log_fail "Failed to open both panels"
fi

# Close all
agent-browser eval "PU.responsive.closePanels()" 2>/dev/null
sleep 0.3

NONE_OPEN=$(agent-browser eval "document.querySelectorAll('.pu-panel-open').length === 0" 2>/dev/null)
if [ "$NONE_OPEN" = "true" ]; then
    log_pass "All panels closed after closePanels()"
else
    log_fail "Some panels still open after closePanels()"
fi

BACKDROP_VIS=$(agent-browser eval "document.querySelector('[data-testid=\"pu-backdrop\"]').classList.contains('visible')" 2>/dev/null)
if [ "$BACKDROP_VIS" = "false" ]; then
    log_pass "Backdrop hidden after closePanels()"
else
    log_fail "Backdrop still visible after closePanels()"
fi

# ============================================================================
# TEST 7: Backdrop click dispatches close
# ============================================================================
echo ""
log_info "TEST 7: Backdrop click closes panels"

agent-browser eval "PU.responsive.openPanel('pu-sidebar')" 2>/dev/null
sleep 0.3

# Simulate click on backdrop
agent-browser eval "document.querySelector('[data-testid=\"pu-backdrop\"]').click()" 2>/dev/null
sleep 0.3

AFTER_CLICK=$(agent-browser eval "document.querySelectorAll('.pu-panel-open').length === 0" 2>/dev/null)
if [ "$AFTER_CLICK" = "true" ]; then
    log_pass "Panels closed after backdrop click"
else
    log_fail "Panels still open after backdrop click"
fi

# ============================================================================
# TEST 8: CSS media query rules exist (responsive selectors present)
# ============================================================================
echo ""
log_info "TEST 8: CSS responsive rules exist"

# Check that @media rules exist in the stylesheet
HAS_MEDIA=$(agent-browser eval "
    const sheets = [...document.styleSheets];
    let mediaCount = 0;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule instanceof CSSMediaRule) {
                    if (rule.conditionText && (rule.conditionText.includes('767') || rule.conditionText.includes('1024'))) {
                        mediaCount++;
                    }
                }
            }
        } catch(e) {}
    }
    mediaCount;
" 2>/dev/null | tr -d '"')

if [ "$HAS_MEDIA" -ge 2 ] 2>/dev/null; then
    log_pass "Found $HAS_MEDIA responsive @media rules (767px, 1024px)"
else
    log_fail "Expected 2+ @media rules, found: $HAS_MEDIA"
fi

# ============================================================================
# TEST 9: isMobile/isTablet return false on desktop viewport
# ============================================================================
echo ""
log_info "TEST 9: Desktop viewport — isMobile/isTablet return false"

IS_MOBILE=$(agent-browser eval "PU.responsive.isMobile()" 2>/dev/null)
if [ "$IS_MOBILE" = "false" ]; then
    log_pass "isMobile() returns false on desktop"
else
    log_fail "isMobile() returns $IS_MOBILE on desktop (expected false)"
fi

IS_TABLET=$(agent-browser eval "PU.responsive.isTablet()" 2>/dev/null)
if [ "$IS_TABLET" = "false" ]; then
    log_pass "isTablet() returns false on desktop"
else
    log_fail "isTablet() returns $IS_TABLET on desktop (expected false)"
fi

IS_OVERLAY=$(agent-browser eval "PU.responsive.isOverlay()" 2>/dev/null)
if [ "$IS_OVERLAY" = "false" ]; then
    log_pass "isOverlay() returns false on desktop"
else
    log_fail "isOverlay() returns $IS_OVERLAY on desktop (expected false)"
fi

# ============================================================================
# TEST 10: pu-panel-open overrides .collapsed class (CSS specificity fix)
# ============================================================================
echo ""
log_info "TEST 10: pu-panel-open overrides .collapsed (CSS order fix)"

# Add both collapsed AND pu-panel-open to right panel, check transform
RP_OVERRIDE=$(agent-browser eval "
    const rp = document.querySelector('[data-testid=\"pu-right-panel\"]');
    rp.classList.add('collapsed');
    rp.classList.add('pu-panel-open');
    const t = getComputedStyle(rp).transform;
    // Clean up
    rp.classList.remove('collapsed');
    rp.classList.remove('pu-panel-open');
    t;
" 2>/dev/null | tr -d '"')

# On desktop, transform is 'none' since media queries don't apply.
# The real test is that no JS error occurs and the classes coexist.
# We verify the CSS rules exist in order by checking stylesheet.
RULE_ORDER=$(agent-browser eval "
    const sheets = [...document.styleSheets];
    let collapsedIdx = -1, openIdx = -1;
    for (const sheet of sheets) {
        try {
            let idx = 0;
            for (const rule of sheet.cssRules) {
                if (rule instanceof CSSMediaRule && rule.conditionText && rule.conditionText.includes('767')) {
                    let subIdx = 0;
                    for (const sub of rule.cssRules) {
                        if (sub.selectorText === '.pu-right-panel.collapsed') collapsedIdx = subIdx;
                        if (sub.selectorText === '.pu-right-panel.pu-panel-open') openIdx = subIdx;
                        subIdx++;
                    }
                }
                idx++;
            }
        } catch(e) {}
    }
    openIdx > collapsedIdx ? 'correct' : 'wrong:collapsed=' + collapsedIdx + ',open=' + openIdx;
" 2>/dev/null | tr -d '"')

if [ "$RULE_ORDER" = "correct" ]; then
    log_pass "Mobile CSS: .pu-panel-open comes after .collapsed (wins specificity)"
else
    log_fail "Mobile CSS rule order wrong: $RULE_ORDER"
fi

# Same check for sidebar
SIDEBAR_ORDER=$(agent-browser eval "
    const sheets = [...document.styleSheets];
    let collapsedIdx = -1, openIdx = -1;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule instanceof CSSMediaRule && rule.conditionText && rule.conditionText.includes('767')) {
                    let subIdx = 0;
                    for (const sub of rule.cssRules) {
                        if (sub.selectorText === '.pu-sidebar.collapsed') collapsedIdx = subIdx;
                        if (sub.selectorText === '.pu-sidebar.pu-panel-open') openIdx = subIdx;
                        subIdx++;
                    }
                }
            }
        } catch(e) {}
    }
    openIdx > collapsedIdx ? 'correct' : 'wrong:collapsed=' + collapsedIdx + ',open=' + openIdx;
" 2>/dev/null | tr -d '"')

if [ "$SIDEBAR_ORDER" = "correct" ]; then
    log_pass "Mobile CSS: sidebar .pu-panel-open comes after .collapsed"
else
    log_fail "Mobile CSS sidebar rule order wrong: $SIDEBAR_ORDER"
fi

# Same check for tablet (1024px query)
TABLET_ORDER=$(agent-browser eval "
    const sheets = [...document.styleSheets];
    let collapsedIdx = -1, openIdx = -1;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule instanceof CSSMediaRule && rule.conditionText && rule.conditionText.includes('1024')) {
                    let subIdx = 0;
                    for (const sub of rule.cssRules) {
                        if (sub.selectorText === '.pu-right-panel.collapsed') collapsedIdx = subIdx;
                        if (sub.selectorText === '.pu-right-panel.pu-panel-open') openIdx = subIdx;
                        subIdx++;
                    }
                }
            }
        } catch(e) {}
    }
    openIdx > collapsedIdx ? 'correct' : 'wrong:collapsed=' + collapsedIdx + ',open=' + openIdx;
" 2>/dev/null | tr -d '"')

if [ "$TABLET_ORDER" = "correct" ]; then
    log_pass "Tablet CSS: .pu-panel-open comes after .collapsed"
else
    log_fail "Tablet CSS rule order wrong: $TABLET_ORDER"
fi

# ============================================================================
# TEST 11: Mobile header panel buttons exist in DOM
# ============================================================================
echo ""
log_info "TEST 11: Mobile header panel buttons exist"

HAS_SIDEBAR_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-mobile-sidebar-btn\"]')" 2>/dev/null)
if [ "$HAS_SIDEBAR_BTN" = "true" ]; then
    log_pass "Mobile sidebar button exists in header"
else
    log_fail "Mobile sidebar button missing"
fi

HAS_RP_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-mobile-rp-btn\"]')" 2>/dev/null)
if [ "$HAS_RP_BTN" = "true" ]; then
    log_pass "Mobile right panel button exists in header"
else
    log_fail "Mobile right panel button missing"
fi

# On desktop, they should be hidden
SIDEBAR_BTN_DISPLAY=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-mobile-sidebar-btn\"]')).display" 2>/dev/null | tr -d '"')
if [ "$SIDEBAR_BTN_DISPLAY" = "none" ]; then
    log_pass "Mobile sidebar button hidden on desktop"
else
    log_fail "Mobile sidebar button visible on desktop: display=$SIDEBAR_BTN_DISPLAY"
fi

# ============================================================================
# TEST 12: viewport-fit=cover meta tag present
# ============================================================================
echo ""
log_info "TEST 12: viewport-fit=cover meta tag"

HAS_VIEWPORT_FIT=$(agent-browser eval "
    const meta = document.querySelector('meta[name=\"viewport\"]');
    meta && meta.content.includes('viewport-fit=cover');
" 2>/dev/null)
if [ "$HAS_VIEWPORT_FIT" = "true" ]; then
    log_pass "viewport meta includes viewport-fit=cover"
else
    log_fail "viewport meta missing viewport-fit=cover"
fi

# ============================================================================
# TEST 13: overscroll-behavior-x prevents Safari back gesture
# ============================================================================
echo ""
log_info "TEST 13: overscroll-behavior-x: none on html/body (Safari back gesture prevention)"

HTML_OVERSCROLL=$(agent-browser eval "getComputedStyle(document.documentElement).overscrollBehaviorX" 2>/dev/null | tr -d '"')
BODY_OVERSCROLL=$(agent-browser eval "getComputedStyle(document.body).overscrollBehaviorX" 2>/dev/null | tr -d '"')

if [ "$HTML_OVERSCROLL" = "none" ]; then
    log_pass "html has overscroll-behavior-x: none"
else
    log_fail "html overscroll-behavior-x: $HTML_OVERSCROLL (expected none)"
fi

if [ "$BODY_OVERSCROLL" = "none" ]; then
    log_pass "body has overscroll-behavior-x: none"
else
    log_fail "body overscroll-behavior-x: $BODY_OVERSCROLL (expected none)"
fi

# ============================================================================
# TEST 14: sidebar.togglePanel() uses overlay mode when isOverlay()
# ============================================================================
echo ""
log_info "TEST 14: OBJECTIVE: togglePanel() uses overlay path when in overlay mode"

# Simulate overlay mode by overriding matchMedia results
agent-browser eval "
    PU.responsive._origMobile = PU.responsive._mobileQuery;
    PU.responsive._mobileQuery = { matches: true };
" 2>/dev/null

# Call sidebar togglePanel — should use overlay (add pu-panel-open, not desktop collapse)
agent-browser eval "PU.sidebar.togglePanel()" 2>/dev/null
sleep 0.3

SIDEBAR_PANEL_OPEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('pu-panel-open')" 2>/dev/null)
if [ "$SIDEBAR_PANEL_OPEN" = "true" ]; then
    log_pass "Sidebar togglePanel() opened via overlay path (pu-panel-open added)"
else
    log_fail "Sidebar togglePanel() did not use overlay path"
fi

# Toggle again — should close
agent-browser eval "PU.sidebar.togglePanel()" 2>/dev/null
sleep 0.3

SIDEBAR_CLOSED=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('pu-panel-open')" 2>/dev/null)
if [ "$SIDEBAR_CLOSED" = "true" ]; then
    log_pass "Sidebar togglePanel() closed via overlay path"
else
    log_fail "Sidebar still has pu-panel-open after second toggle"
fi

# Test right panel togglePanel via overlay
agent-browser eval "PU.rightPanel.togglePanel()" 2>/dev/null
sleep 0.3

RP_PANEL_OPEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('pu-panel-open')" 2>/dev/null)
if [ "$RP_PANEL_OPEN" = "true" ]; then
    log_pass "Right panel togglePanel() opened via overlay path"
else
    log_fail "Right panel togglePanel() did not use overlay path"
fi

# Close and restore
agent-browser eval "PU.rightPanel.togglePanel()" 2>/dev/null
sleep 0.3
agent-browser eval "PU.responsive._mobileQuery = PU.responsive._origMobile; delete PU.responsive._origMobile;" 2>/dev/null

# ============================================================================
# TEST 15: Mobile header buttons trigger panel toggles
# ============================================================================
echo ""
log_info "TEST 15: OBJECTIVE: Clicking mobile header buttons opens/closes panels"

# Simulate overlay mode
agent-browser eval "
    PU.responsive._origMobile = PU.responsive._mobileQuery;
    PU.responsive._mobileQuery = { matches: true };
" 2>/dev/null

# Click mobile sidebar button
agent-browser eval "document.querySelector('[data-testid=\"pu-mobile-sidebar-btn\"]').click()" 2>/dev/null
sleep 0.3

SIDEBAR_AFTER_BTN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('pu-panel-open')" 2>/dev/null)
if [ "$SIDEBAR_AFTER_BTN" = "true" ]; then
    log_pass "Mobile sidebar button opens sidebar overlay"
else
    log_fail "Mobile sidebar button did not open sidebar"
fi

# Close sidebar
agent-browser eval "PU.responsive.closePanel('pu-sidebar')" 2>/dev/null
sleep 0.3

# Click mobile right panel button
agent-browser eval "document.querySelector('[data-testid=\"pu-mobile-rp-btn\"]').click()" 2>/dev/null
sleep 0.3

RP_AFTER_BTN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('pu-panel-open')" 2>/dev/null)
if [ "$RP_AFTER_BTN" = "true" ]; then
    log_pass "Mobile right panel button opens right panel overlay"
else
    log_fail "Mobile right panel button did not open right panel"
fi

# Clean up
agent-browser eval "PU.responsive.closePanels()" 2>/dev/null
agent-browser eval "PU.responsive._mobileQuery = PU.responsive._origMobile; delete PU.responsive._origMobile;" 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 16: Auto-close sidebar on mobile after job selection
# ============================================================================
echo ""
log_info "TEST 16: OBJECTIVE: Sidebar overlay auto-closes on mobile after selecting a job"

# Simulate mobile + open sidebar overlay
agent-browser eval "
    PU.responsive._origMobile = PU.responsive._mobileQuery;
    PU.responsive._mobileQuery = { matches: true };
    PU.responsive.openPanel('pu-sidebar');
" 2>/dev/null
sleep 0.3

SIDEBAR_OPEN_BEFORE_SELECT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('pu-panel-open')" 2>/dev/null)
[ "$SIDEBAR_OPEN_BEFORE_SELECT" = "true" ] && log_pass "Sidebar overlay open before job select" || log_fail "Sidebar not open before job select"

# Click first job
agent-browser eval "
    const job = document.querySelector('[data-testid=\"pu-jobs-tree\"] .pu-tree-label');
    if (job) job.click();
" 2>/dev/null
sleep 3

SIDEBAR_AFTER_SELECT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('pu-panel-open')" 2>/dev/null)
if [ "$SIDEBAR_AFTER_SELECT" = "false" ]; then
    log_pass "Sidebar auto-closed after job selection on mobile"
else
    log_fail "Sidebar still open after job selection on mobile"
fi

# Restore
agent-browser eval "PU.responsive._mobileQuery = PU.responsive._origMobile; delete PU.responsive._origMobile;" 2>/dev/null

# ============================================================================
# TEST 17: No JavaScript errors
# ============================================================================
echo ""
log_info "TEST 17: No JavaScript errors during responsive lifecycle"

# Reload and exercise responsive functions
agent-browser eval "
    PU.responsive.openPanel('pu-sidebar');
    PU.responsive.openPanel('pu-right-panel');
    PU.responsive.closePanels();
    PU.responsive.closePanel('pu-sidebar');
    PU.responsive.closePanel('nonexistent');
" 2>/dev/null
sleep 0.5

JS_ERRORS=$(agent-browser eval "
    window.__testErrors = window.__testErrors || [];
    JSON.stringify(window.__testErrors);
" 2>/dev/null)

if [ -z "$JS_ERRORS" ] || [ "$JS_ERRORS" = "[]" ] || [ "$JS_ERRORS" = '""' ] || [ "$JS_ERRORS" = '"[]"' ]; then
    log_pass "No JS errors during responsive operations"
else
    log_fail "JS errors: $JS_ERRORS"
fi

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
