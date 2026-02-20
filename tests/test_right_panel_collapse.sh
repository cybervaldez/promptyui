#!/bin/bash
# ============================================================================
# E2E Test Suite: Right Panel Collapse/Expand
# ============================================================================
# Tests the collapsible right panel: header collapse button, footer toggle,
# keyboard shortcut, build panel auto-collapse, and state persistence.
#
# Usage: ./tests/test_right_panel_collapse.sh [--port 8085]
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

print_header "Right Panel Collapse/Expand"

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
# TEST 1: Collapse button exists in panel top bar
# ============================================================================
echo ""
log_info "TEST 1: Collapse button exists in panel top bar"

agent-browser open "$BASE_URL" 2>/dev/null
sleep 3

HAS_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-collapse-btn\"]')" 2>/dev/null)
[ "$HAS_BTN" = "true" ] && log_pass "Collapse button found in top bar" || log_fail "Collapse button missing"

# ============================================================================
# TEST 2: Right panel starts expanded (default state)
# ============================================================================
echo ""
log_info "TEST 2: Right panel starts expanded"

# Clear persisted state first
agent-browser eval "localStorage.removeItem('pu_ui_state')" 2>/dev/null
sleep 0.3

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Right panel starts expanded" || log_fail "Right panel incorrectly collapsed: $IS_COLLAPSED"

# ============================================================================
# TEST 3: Click collapse button collapses panel
# ============================================================================
echo ""
log_info "TEST 3: Click collapse button collapses panel"

agent-browser eval "document.querySelector('[data-testid=\"pu-rp-collapse-btn\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Panel collapsed after click" || log_fail "Panel not collapsed: $IS_COLLAPSED"

STATE_VAL=$(agent-browser eval "PU.state.ui.rightPanelCollapsed" 2>/dev/null)
[ "$STATE_VAL" = "true" ] && log_pass "State updated to collapsed" || log_fail "State not updated: $STATE_VAL"

# ============================================================================
# TEST 4: Footer label expands panel
# ============================================================================
echo ""
log_info "TEST 4: Footer label expands panel"

agent-browser eval "document.querySelector('[data-testid=\"pu-footer-composer\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Panel expanded via footer click" || log_fail "Panel still collapsed: $IS_COLLAPSED"

STATE_VAL=$(agent-browser eval "PU.state.ui.rightPanelCollapsed" 2>/dev/null)
[ "$STATE_VAL" = "false" ] && log_pass "State updated to expanded" || log_fail "State not updated: $STATE_VAL"

# ============================================================================
# TEST 5: Keyboard shortcut ] toggles panel
# ============================================================================
echo ""
log_info "TEST 5: Keyboard shortcut ] toggles panel"

# Press ] to collapse
agent-browser eval "document.dispatchEvent(new KeyboardEvent('keydown', {key: ']', bubbles: true}))" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Panel collapsed via ] key" || log_fail "Panel not collapsed via ] key: $IS_COLLAPSED"

# Press ] again to expand
agent-browser eval "document.dispatchEvent(new KeyboardEvent('keydown', {key: ']', bubbles: true}))" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Panel expanded via ] key" || log_fail "Panel not expanded via ] key: $IS_COLLAPSED"

# ============================================================================
# TEST 6: Build panel open auto-collapses right panel
# ============================================================================
echo ""
log_info "TEST 6: Build panel open auto-collapses right panel"

# Ensure right panel is expanded first
agent-browser eval "PU.rightPanel.expand()" 2>/dev/null
sleep 0.3

# Open build panel
agent-browser eval "PU.buildComposition.open()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Right panel auto-collapsed when build panel opened" || log_fail "Right panel not collapsed: $IS_COLLAPSED"

# ============================================================================
# TEST 7: Build panel close restores right panel
# ============================================================================
echo ""
log_info "TEST 7: Build panel close restores right panel"

agent-browser eval "PU.buildComposition.close()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Right panel restored after build panel closed" || log_fail "Right panel still collapsed: $IS_COLLAPSED"

# ============================================================================
# TEST 8: State persists to localStorage
# ============================================================================
echo ""
log_info "TEST 8: State persists to localStorage"

# Collapse the panel
agent-browser eval "PU.rightPanel.collapse()" 2>/dev/null
sleep 0.3

SAVED=$(agent-browser eval "JSON.parse(localStorage.getItem('pu_ui_state')).rightPanelCollapsed" 2>/dev/null)
[ "$SAVED" = "true" ] && log_pass "Collapsed state saved to localStorage" || log_fail "State not persisted: $SAVED"

# Expand and check
agent-browser eval "PU.rightPanel.expand()" 2>/dev/null
sleep 0.3

SAVED=$(agent-browser eval "JSON.parse(localStorage.getItem('pu_ui_state')).rightPanelCollapsed" 2>/dev/null)
[ "$SAVED" = "false" ] && log_pass "Expanded state saved to localStorage" || log_fail "State not persisted: $SAVED"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

# Reset state
agent-browser eval "PU.rightPanel.expand(); localStorage.removeItem('pu_ui_state')" 2>/dev/null
agent-browser close 2>/dev/null
log_pass "Browser closed and state reset"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
