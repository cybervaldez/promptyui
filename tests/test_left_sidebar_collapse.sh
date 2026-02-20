#!/bin/bash
# ============================================================================
# E2E Test Suite: Left Sidebar Collapse/Expand
# ============================================================================
# Tests the collapsible left sidebar: header collapse button, footer toggle,
# keyboard shortcut, and state persistence.
#
# Usage: ./tests/test_left_sidebar_collapse.sh [--port 8085]
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

print_header "Left Sidebar Collapse/Expand"

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
# TEST 1: Collapse button exists in sidebar header
# ============================================================================
echo ""
log_info "TEST 1: Collapse button exists in sidebar header"

agent-browser open "$BASE_URL" 2>/dev/null
sleep 3

HAS_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-sidebar-collapse-btn\"]')" 2>/dev/null)
[ "$HAS_BTN" = "true" ] && log_pass "Collapse button found in sidebar header" || log_fail "Collapse button missing"

# ============================================================================
# TEST 2: Left sidebar starts expanded (default state)
# ============================================================================
echo ""
log_info "TEST 2: Left sidebar starts expanded"

# Clear persisted state first
agent-browser eval "localStorage.removeItem('pu_ui_state')" 2>/dev/null
sleep 0.3

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Left sidebar starts expanded" || log_fail "Left sidebar incorrectly collapsed: $IS_COLLAPSED"

# ============================================================================
# TEST 3: Click collapse button collapses sidebar
# ============================================================================
echo ""
log_info "TEST 3: Click collapse button collapses sidebar"

agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar-collapse-btn\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Sidebar collapsed after click" || log_fail "Sidebar not collapsed: $IS_COLLAPSED"

STATE_VAL=$(agent-browser eval "PU.state.ui.leftSidebarCollapsed" 2>/dev/null)
[ "$STATE_VAL" = "true" ] && log_pass "State updated to collapsed" || log_fail "State not updated: $STATE_VAL"

# ============================================================================
# TEST 4: Footer label expands sidebar
# ============================================================================
echo ""
log_info "TEST 4: Footer label expands sidebar"

agent-browser eval "document.querySelector('[data-testid=\"pu-footer-job-browser\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Sidebar expanded via footer click" || log_fail "Sidebar still collapsed: $IS_COLLAPSED"

STATE_VAL=$(agent-browser eval "PU.state.ui.leftSidebarCollapsed" 2>/dev/null)
[ "$STATE_VAL" = "false" ] && log_pass "State updated to expanded" || log_fail "State not updated: $STATE_VAL"

# ============================================================================
# TEST 5: Keyboard shortcut [ toggles sidebar
# ============================================================================
echo ""
log_info "TEST 5: Keyboard shortcut [ toggles sidebar"

# Press [ to collapse
agent-browser eval "document.dispatchEvent(new KeyboardEvent('keydown', {key: '[', bubbles: true}))" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Sidebar collapsed via [ key" || log_fail "Sidebar not collapsed via [ key: $IS_COLLAPSED"

# Press [ again to expand
agent-browser eval "document.dispatchEvent(new KeyboardEvent('keydown', {key: '[', bubbles: true}))" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Sidebar expanded via [ key" || log_fail "Sidebar not expanded via [ key: $IS_COLLAPSED"

# ============================================================================
# TEST 6: State persists to localStorage
# ============================================================================
echo ""
log_info "TEST 6: State persists to localStorage"

# Collapse the sidebar
agent-browser eval "PU.sidebar.collapse()" 2>/dev/null
sleep 0.3

SAVED=$(agent-browser eval "JSON.parse(localStorage.getItem('pu_ui_state')).leftSidebarCollapsed" 2>/dev/null)
[ "$SAVED" = "true" ] && log_pass "Collapsed state saved to localStorage" || log_fail "State not persisted: $SAVED"

# Expand and check
agent-browser eval "PU.sidebar.expand()" 2>/dev/null
sleep 0.3

SAVED=$(agent-browser eval "JSON.parse(localStorage.getItem('pu_ui_state')).leftSidebarCollapsed" 2>/dev/null)
[ "$SAVED" = "false" ] && log_pass "Expanded state saved to localStorage" || log_fail "State not persisted: $SAVED"

# ============================================================================
# TEST 7: Toggle icon updates correctly
# ============================================================================
echo ""
log_info "TEST 7: Toggle icon updates correctly"

# When expanded, header icon should be ◀ (pointing left = collapse action)
agent-browser eval "PU.sidebar.expand()" 2>/dev/null
sleep 0.3

ICON=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar-collapse-btn\"]').innerHTML.trim()" 2>/dev/null | tr -d '"')
[ "$ICON" = "◀" ] && log_pass "Header icon shows ◀ when expanded" || log_fail "Header icon wrong when expanded: $ICON"

# When collapsed, icon should be ▶ (pointing right = expand action)
agent-browser eval "PU.sidebar.collapse()" 2>/dev/null
sleep 0.3

ICON=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar-collapse-btn\"]').innerHTML.trim()" 2>/dev/null | tr -d '"')
[ "$ICON" = "▶" ] && log_pass "Header icon shows ▶ when collapsed" || log_fail "Header icon wrong when collapsed: $ICON"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

# Reset state
agent-browser eval "PU.sidebar.expand(); localStorage.removeItem('pu_ui_state')" 2>/dev/null
agent-browser close 2>/dev/null
log_pass "Browser closed and state reset"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
