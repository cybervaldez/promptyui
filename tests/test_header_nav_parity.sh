#!/bin/bash
# ============================================================================
# E2E Test Suite: Panel Toggle Buttons & Visual Parity
# ============================================================================
# Tests: toggle buttons in panel headers, footer helper, visual parity
#
# Usage: ./tests/test_header_nav_parity.sh [--port 8085]
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

print_header "Panel Toggle Buttons & Visual Parity"

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

# ============================================================================
# TEST 1: Toggle buttons in correct panel locations
# ============================================================================
echo ""
log_info "TEST 1: Toggle buttons in correct panel locations"

agent-browser open "$BASE_URL" 2>/dev/null
sleep 3

# Left sidebar collapse button should be in sidebar header
LS_IN_HEADER=$(agent-browser eval "!!document.querySelector('.pu-sidebar-header [data-testid=\"pu-sidebar-collapse-btn\"]')" 2>/dev/null)
[ "$LS_IN_HEADER" = "true" ] && log_pass "Left collapse button is in sidebar header" || log_fail "Left collapse button not in sidebar header: $LS_IN_HEADER"

# Right panel collapse button should be in top bar
RP_IN_TOP=$(agent-browser eval "!!document.querySelector('.pu-rp-top-bar [data-testid=\"pu-rp-collapse-btn\"]')" 2>/dev/null)
[ "$RP_IN_TOP" = "true" ] && log_pass "Right collapse button is in top bar" || log_fail "Right collapse button not in top bar: $RP_IN_TOP"

# Footer helper bar exists
HAS_FOOTER=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-footer\"]')" 2>/dev/null)
[ "$HAS_FOOTER" = "true" ] && log_pass "Footer helper bar exists" || log_fail "Footer helper bar missing"

# ============================================================================
# TEST 2: Header job label
# ============================================================================
echo ""
log_info "TEST 2: Header job label"

HAS_LABEL=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-header-active-job\"]')" 2>/dev/null)
[ "$HAS_LABEL" = "true" ] && log_pass "Job label found in header" || log_fail "Job label missing"

LABEL_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-header-active-job\"]').textContent" 2>/dev/null | tr -d '"')
[ "$LABEL_TEXT" = "No job selected" ] && log_pass "Default label text correct" || log_fail "Label text: $LABEL_TEXT"

# ============================================================================
# TEST 3: Visual parity - sidebar header styles
# ============================================================================
echo ""
log_info "TEST 3: Visual parity - sidebar header"

# Check sidebar header background matches right panel top bar (bg-primary = #191919)
SB_HEADER_BG=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-sidebar-header')).backgroundColor" 2>/dev/null | tr -d '"')
RP_TOP_BG=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-rp-top-bar')).backgroundColor" 2>/dev/null | tr -d '"')
[ "$SB_HEADER_BG" = "$RP_TOP_BG" ] && log_pass "Header backgrounds match: $SB_HEADER_BG" || log_fail "Header bg mismatch: sidebar=$SB_HEADER_BG vs right=$RP_TOP_BG"

# Check sidebar title text-transform is uppercase
SB_TRANSFORM=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-sidebar-title')).textTransform" 2>/dev/null | tr -d '"')
[ "$SB_TRANSFORM" = "uppercase" ] && log_pass "Sidebar title is uppercase" || log_fail "Sidebar title transform: $SB_TRANSFORM"

# Check sidebar footer background matches right panel ops section
SB_FOOTER_BG=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-sidebar-footer')).backgroundColor" 2>/dev/null | tr -d '"')
RP_OPS_BG=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-rp-ops-section')).backgroundColor" 2>/dev/null | tr -d '"')
[ "$SB_FOOTER_BG" = "$RP_OPS_BG" ] && log_pass "Footer backgrounds match: $SB_FOOTER_BG" || log_fail "Footer bg mismatch: sidebar=$SB_FOOTER_BG vs right=$RP_OPS_BG"

# Check user-select parity
SB_SELECT=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-sidebar-header')).userSelect" 2>/dev/null | tr -d '"')
RP_SELECT=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-rp-top-bar')).userSelect" 2>/dev/null | tr -d '"')
[ "$SB_SELECT" = "$RP_SELECT" ] && log_pass "user-select matches: $SB_SELECT" || log_fail "user-select mismatch: sidebar=$SB_SELECT vs right=$RP_SELECT"

# Check header padding parity
SB_PADDING=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-sidebar-header')).padding" 2>/dev/null | tr -d '"')
RP_PADDING=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-rp-top-bar')).padding" 2>/dev/null | tr -d '"')
[ "$SB_PADDING" = "$RP_PADDING" ] && log_pass "Header padding matches: $SB_PADDING" || log_fail "Header padding mismatch: sidebar=$SB_PADDING vs right=$RP_PADDING"

# Check panel body background parity (both use bg-secondary)
SB_BODY_BG=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-sidebar')).backgroundColor" 2>/dev/null | tr -d '"')
RP_BODY_BG=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-right-panel')).backgroundColor" 2>/dev/null | tr -d '"')
[ "$SB_BODY_BG" = "$RP_BODY_BG" ] && log_pass "Panel backgrounds match: $SB_BODY_BG" || log_fail "Panel bg mismatch: sidebar=$SB_BODY_BG vs right=$RP_BODY_BG"

# ============================================================================
# TEST 4: Panel toggles functional from header buttons
# ============================================================================
echo ""
log_info "TEST 4: Panel toggles functional from header buttons"

agent-browser eval "PU.sidebar.expand(); PU.rightPanel.expand()" 2>/dev/null
sleep 0.3

# Click the left collapse button (in sidebar header)
agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar-collapse-btn\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Left collapse button works from sidebar header" || log_fail "Left collapse failed: $IS_COLLAPSED"

# Expand via footer
agent-browser eval "document.querySelector('[data-testid=\"pu-footer-job-browser\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Footer Job Browser expands sidebar" || log_fail "Footer expand failed: $IS_COLLAPSED"

# Click the right collapse button (in top bar)
agent-browser eval "document.querySelector('[data-testid=\"pu-rp-collapse-btn\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Right collapse button works from top bar" || log_fail "Right collapse failed: $IS_COLLAPSED"

# Expand via footer
agent-browser eval "document.querySelector('[data-testid=\"pu-footer-composer\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Footer Composer expands panel" || log_fail "Footer expand failed: $IS_COLLAPSED"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser eval "PU.sidebar.expand(); PU.rightPanel.expand(); localStorage.removeItem('pu_ui_state')" 2>/dev/null
agent-browser close 2>/dev/null
log_pass "Browser closed and state reset"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
