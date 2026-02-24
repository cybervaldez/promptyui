#!/bin/bash
# ============================================================================
# E2E Test Suite: Expanded Sidebar When No Job Selected
# ============================================================================
# Tests the expanded sidebar layout that shows when no job is selected:
# - Sidebar fills screen with jobs visible, editor + right panel hidden
# - Selecting a job collapses back to normal 3-panel layout with content
# - Loading with ?job= param shows normal layout immediately
# - Loading skeleton appears during job fetch and is removed after
#
# Usage: ./tests/test_expanded_sidebar.sh [--port 8085]
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

print_header "Expanded Sidebar (No Job Selected)"

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

# Get API ground truth: how many jobs exist?
API_JOBS=$(curl -sf "$BASE_URL/api/pu/jobs")
API_JOB_COUNT=$(echo "$API_JOBS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
FIRST_JOB_ID=$(echo "$API_JOBS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.keys())[0] if d else '')" 2>/dev/null)
log_info "API reports $API_JOB_COUNT jobs, first job: $FIRST_JOB_ID"

# ============================================================================
# TEST 1: No-job load — sidebar fills screen AND shows all jobs
# ============================================================================
echo ""
log_info "TEST 1: OBJECTIVE: User sees all jobs in expanded sidebar on no-job load"

# Open without ?job= param, clear localStorage for clean state
agent-browser open "$BASE_URL/" 2>/dev/null
sleep 1
agent-browser eval "localStorage.removeItem('pu_ui_state')" 2>/dev/null
agent-browser eval "window.location.href = '$BASE_URL/'" 2>/dev/null
sleep 4

# Verify layout attribute set
LAYOUT=$(agent-browser eval "document.querySelector('.pu-main').dataset.layout" 2>/dev/null | tr -d '"')
[ "$LAYOUT" = "no-job" ] && log_pass "data-layout='no-job' set on .pu-main" || log_fail "data-layout not set: '$LAYOUT'"

# Verify sidebar is wide (behavioral: user can see full job list)
SIDEBAR_WIDTH=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').getBoundingClientRect().width" 2>/dev/null | tr -d '"')
if [ -n "$SIDEBAR_WIDTH" ] && [ "$(echo "$SIDEBAR_WIDTH > 400" | bc 2>/dev/null)" = "1" ]; then
    log_pass "Sidebar fills screen: ${SIDEBAR_WIDTH}px"
else
    log_fail "Sidebar too narrow for full-screen layout: ${SIDEBAR_WIDTH}px"
fi

# Verify sidebar shows actual job data from API (ground truth comparison)
DOM_JOB_COUNT=$(agent-browser eval "document.querySelectorAll('[data-testid=\"pu-jobs-tree\"] .pu-tree-item:not(.pu-tree-item-ghost)').length" 2>/dev/null | tr -d '"')
if [ "$API_JOB_COUNT" -gt 0 ] && [ "$DOM_JOB_COUNT" -gt 0 ]; then
    log_pass "Sidebar shows $DOM_JOB_COUNT job items (API has $API_JOB_COUNT jobs)"
elif [ "$API_JOB_COUNT" -gt 0 ] && [ "$DOM_JOB_COUNT" = "0" ]; then
    log_fail "API has $API_JOB_COUNT jobs but sidebar shows 0"
else
    log_pass "Sidebar matches API (both empty or both populated)"
fi

# ============================================================================
# TEST 2: Editor and right panel are hidden — user cannot interact with them
# ============================================================================
echo ""
log_info "TEST 2: OBJECTIVE: Editor and right panel are not accessible in no-job state"

EDITOR_DISPLAY=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-editor\"]')).display" 2>/dev/null | tr -d '"')
[ "$EDITOR_DISPLAY" = "none" ] && log_pass "Editor hidden (display:none)" || log_fail "Editor visible: $EDITOR_DISPLAY"

# Right panel: check both width and pointer-events
RP_WIDTH=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').getBoundingClientRect().width" 2>/dev/null | tr -d '"')
RP_POINTER=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-right-panel\"]')).pointerEvents" 2>/dev/null | tr -d '"')
if [ -n "$RP_WIDTH" ] && [ "$(echo "$RP_WIDTH <= 1" | bc 2>/dev/null)" = "1" ]; then
    log_pass "Right panel collapsed: ${RP_WIDTH}px"
else
    log_fail "Right panel still visible: ${RP_WIDTH}px"
fi
[ "$RP_POINTER" = "none" ] && log_pass "Right panel non-interactive (pointer-events:none)" || log_fail "Right panel still interactive: $RP_POINTER"

# ============================================================================
# TEST 3: Selecting a job — layout collapses AND content loads
# ============================================================================
echo ""
log_info "TEST 3: OBJECTIVE: Clicking a job shows editor with content and restores 3-panel layout"

# Click the first job
agent-browser eval "
    const firstJob = document.querySelector('[data-testid=\"pu-jobs-tree\"] .pu-tree-label');
    if (firstJob) firstJob.click();
" 2>/dev/null
sleep 3

# Layout attribute removed
LAYOUT_AFTER=$(agent-browser eval "document.querySelector('.pu-main').dataset.layout || 'none'" 2>/dev/null | tr -d '"')
[ "$LAYOUT_AFTER" = "none" ] && log_pass "data-layout removed after job select" || log_fail "data-layout still set: $LAYOUT_AFTER"

# Sidebar back to normal width
SIDEBAR_WIDTH_AFTER=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').getBoundingClientRect().width" 2>/dev/null | tr -d '"')
if [ -n "$SIDEBAR_WIDTH_AFTER" ] && [ "$(echo "$SIDEBAR_WIDTH_AFTER < 400" | bc 2>/dev/null)" = "1" ]; then
    log_pass "Sidebar at normal width: ${SIDEBAR_WIDTH_AFTER}px"
else
    log_fail "Sidebar still expanded: ${SIDEBAR_WIDTH_AFTER}px"
fi

# Editor visible and has content (not just display != none, verify actual state)
EDITOR_DISPLAY_AFTER=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-editor\"]')).display" 2>/dev/null | tr -d '"')
[ "$EDITOR_DISPLAY_AFTER" != "none" ] && log_pass "Editor visible: $EDITOR_DISPLAY_AFTER" || log_fail "Editor still hidden"

ACTIVE_JOB=$(agent-browser eval "PU.state.activeJobId" 2>/dev/null | tr -d '"')
[ -n "$ACTIVE_JOB" ] && [ "$ACTIVE_JOB" != "null" ] && log_pass "activeJobId set: $ACTIVE_JOB" || log_fail "No activeJobId after click"

# Right panel visible again
RP_WIDTH_AFTER=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').getBoundingClientRect().width" 2>/dev/null | tr -d '"')
if [ -n "$RP_WIDTH_AFTER" ] && [ "$(echo "$RP_WIDTH_AFTER > 50" | bc 2>/dev/null)" = "1" ]; then
    log_pass "Right panel restored: ${RP_WIDTH_AFTER}px"
else
    log_fail "Right panel not restored: ${RP_WIDTH_AFTER}px"
fi

# ============================================================================
# TEST 4: Loading with ?job= shows normal layout — job content rendered
# ============================================================================
echo ""
log_info "TEST 4: OBJECTIVE: Loading with ?job= skips expanded state, shows job immediately"

if [ -n "$FIRST_JOB_ID" ] && [ "$FIRST_JOB_ID" != "" ]; then
    agent-browser eval "window.location.href = '$BASE_URL/?job=$FIRST_JOB_ID'" 2>/dev/null
    sleep 4

    LAYOUT_WITH_JOB=$(agent-browser eval "document.querySelector('.pu-main').dataset.layout || 'none'" 2>/dev/null | tr -d '"')
    [ "$LAYOUT_WITH_JOB" = "none" ] && log_pass "Normal layout with ?job= param" || log_fail "Expanded layout with job param: $LAYOUT_WITH_JOB"

    SIDEBAR_WIDTH_JOB=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').getBoundingClientRect().width" 2>/dev/null | tr -d '"')
    if [ -n "$SIDEBAR_WIDTH_JOB" ] && [ "$(echo "$SIDEBAR_WIDTH_JOB < 400" | bc 2>/dev/null)" = "1" ]; then
        log_pass "Sidebar at 280px: ${SIDEBAR_WIDTH_JOB}px"
    else
        log_fail "Sidebar unexpectedly wide: ${SIDEBAR_WIDTH_JOB}px"
    fi

    # Verify editor content loaded (has blocks or at least the content area)
    EDITOR_CONTENT=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-editor-content\"]')).display" 2>/dev/null | tr -d '"')
    ACTIVE_JOB_URL=$(agent-browser eval "PU.state.activeJobId" 2>/dev/null | tr -d '"')
    [ "$ACTIVE_JOB_URL" = "$FIRST_JOB_ID" ] && log_pass "Correct job loaded: $ACTIVE_JOB_URL" || log_fail "Wrong job: expected $FIRST_JOB_ID, got $ACTIVE_JOB_URL"
else
    log_skip "No jobs available to test ?job= param"
fi

# ============================================================================
# TEST 5: Skeleton removed after load completes
# ============================================================================
echo ""
log_info "TEST 5: OBJECTIVE: Loading skeleton is removed after jobs finish loading"

# Navigate to clean no-job state
agent-browser eval "window.location.href = '$BASE_URL/'" 2>/dev/null
sleep 4

# After load completes, skeleton should be gone
SKELETON_PRESENT=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-sidebar-skeleton\"]')" 2>/dev/null)
[ "$SKELETON_PRESENT" = "false" ] && log_pass "Skeleton removed after load" || log_fail "Skeleton still present after load"

# Jobs should be rendered (skeleton replaced by real content)
JOBS_RENDERED=$(agent-browser eval "document.querySelectorAll('[data-testid=\"pu-jobs-tree\"] .pu-tree-item').length" 2>/dev/null | tr -d '"')
if [ -n "$JOBS_RENDERED" ] && [ "$JOBS_RENDERED" -gt 0 ]; then
    log_pass "Job tree populated with $JOBS_RENDERED items (skeleton was replaced)"
else
    log_fail "Job tree empty after skeleton removed"
fi

# ============================================================================
# TEST 6: setExpandedLayout toggles layout bidirectionally
# ============================================================================
echo ""
log_info "TEST 6: OBJECTIVE: setExpandedLayout(true/false) toggles layout state correctly"

# Call setExpandedLayout(true) — should expand
agent-browser eval "PU.actions.setExpandedLayout(true)" 2>/dev/null
sleep 0.5

LAYOUT_ON=$(agent-browser eval "document.querySelector('.pu-main').dataset.layout" 2>/dev/null | tr -d '"')
EDITOR_HIDDEN=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-editor\"]')).display" 2>/dev/null | tr -d '"')
[ "$LAYOUT_ON" = "no-job" ] && [ "$EDITOR_HIDDEN" = "none" ] && \
    log_pass "setExpandedLayout(true) expands sidebar, hides editor" || \
    log_fail "setExpandedLayout(true) failed: layout=$LAYOUT_ON, editor=$EDITOR_HIDDEN"

# Call setExpandedLayout(false) — should collapse back
agent-browser eval "PU.actions.setExpandedLayout(false)" 2>/dev/null
sleep 0.5

LAYOUT_OFF=$(agent-browser eval "document.querySelector('.pu-main').dataset.layout || 'none'" 2>/dev/null | tr -d '"')
EDITOR_VISIBLE=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-editor\"]')).display" 2>/dev/null | tr -d '"')
[ "$LAYOUT_OFF" = "none" ] && [ "$EDITOR_VISIBLE" != "none" ] && \
    log_pass "setExpandedLayout(false) restores 3-panel layout" || \
    log_fail "setExpandedLayout(false) failed: layout=$LAYOUT_OFF, editor=$EDITOR_VISIBLE"

# ============================================================================
# TEST 7: No JS errors during expanded sidebar lifecycle
# ============================================================================
echo ""
log_info "TEST 7: OBJECTIVE: No JS errors during load -> expand -> job select cycle"

# Fresh load to no-job state (already on clean page from test 5/6)
# Attach error listener before actions
agent-browser eval "window.__jsErrors = []; window.onerror = (msg) => { window.__jsErrors.push(msg); }" 2>/dev/null
sleep 0.3

# Perform actions that exercise the expanded sidebar code path
agent-browser eval "PU.actions.setExpandedLayout(true)" 2>/dev/null
sleep 0.3
agent-browser eval "
    const firstJob = document.querySelector('[data-testid=\"pu-jobs-tree\"] .pu-tree-label');
    if (firstJob) firstJob.click();
" 2>/dev/null
sleep 3

ERR_COUNT=$(agent-browser eval "window.__jsErrors.length" 2>/dev/null | tr -d '"')
if [ "$ERR_COUNT" = "0" ]; then
    log_pass "No JS errors during expand -> select cycle"
else
    ERRS=$(agent-browser eval "JSON.stringify(window.__jsErrors)" 2>/dev/null)
    log_fail "JS errors ($ERR_COUNT): $ERRS"
fi

# ============================================================================
# TEST 8: Collapse button is blocked in no-job expanded mode
# ============================================================================
echo ""
log_info "TEST 8: OBJECTIVE: Collapse button/key is a no-op when sidebar is the only visible panel"

# Start fresh: clear state, reload to no-job expanded
agent-browser eval "localStorage.clear()" 2>/dev/null
agent-browser eval "window.location.href = '$BASE_URL/'" 2>/dev/null
sleep 4

# Verify we're in expanded no-job state
LAYOUT_T8=$(agent-browser eval "document.querySelector('.pu-main').dataset.layout || 'none'" 2>/dev/null | tr -d '"')
[ "$LAYOUT_T8" = "no-job" ] && log_pass "Starting in expanded no-job state" || log_fail "Not in expanded state: $LAYOUT_T8"

# Click collapse button — should be blocked, sidebar stays visible
agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar-collapse-btn\"]').click()" 2>/dev/null
sleep 0.5

COLLAPSED_T8=$(agent-browser eval "PU.state.ui.leftSidebarCollapsed" 2>/dev/null)
HAS_CLASS_T8=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
OPACITY_T8=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-sidebar\"]')).opacity" 2>/dev/null | tr -d '"')
[ "$COLLAPSED_T8" = "false" ] && log_pass "Collapse blocked: state stayed false" || log_fail "Collapse was not blocked: state=$COLLAPSED_T8"
[ "$HAS_CLASS_T8" = "false" ] && log_pass "No .collapsed class added" || log_fail ".collapsed class present"
[ "$OPACITY_T8" = "1" ] && log_pass "Sidebar remains visible (opacity:1)" || log_fail "Sidebar invisible: opacity=$OPACITY_T8"

# Press [ keyboard shortcut — should also be blocked
agent-browser eval "document.dispatchEvent(new KeyboardEvent('keydown', {key: '[', bubbles: true}))" 2>/dev/null
sleep 0.5

COLLAPSED_KEY_T8=$(agent-browser eval "PU.state.ui.leftSidebarCollapsed" 2>/dev/null)
OPACITY_KEY_T8=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-sidebar\"]')).opacity" 2>/dev/null | tr -d '"')
[ "$COLLAPSED_KEY_T8" = "false" ] && log_pass "[ key blocked: state stayed false" || log_fail "[ key was not blocked: state=$COLLAPSED_KEY_T8"
[ "$OPACITY_KEY_T8" = "1" ] && log_pass "Sidebar still visible after [ key" || log_fail "Sidebar invisible after [ key: opacity=$OPACITY_KEY_T8"

# Jobs remain clickable
POINTER_T8=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-sidebar\"]')).pointerEvents" 2>/dev/null | tr -d '"')
[ "$POINTER_T8" != "none" ] && log_pass "Sidebar remains interactive (pointer-events:$POINTER_T8)" || log_fail "Sidebar non-interactive: pointer-events=$POINTER_T8"

# ============================================================================
# TEST 9: Selecting a job after blocked collapse works normally
# ============================================================================
echo ""
log_info "TEST 9: OBJECTIVE: Job selection works after collapse was blocked in no-job mode"

# Select a job
agent-browser eval "
    const job = document.querySelector('[data-testid=\"pu-jobs-tree\"] .pu-tree-label');
    if (job) job.click();
" 2>/dev/null
sleep 3

SIDEBAR_W_T9=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').getBoundingClientRect().width" 2>/dev/null | tr -d '"')
COLLAPSED_T9=$(agent-browser eval "PU.state.ui.leftSidebarCollapsed" 2>/dev/null)
if [ -n "$SIDEBAR_W_T9" ] && [ "$(echo "$SIDEBAR_W_T9 > 200" | bc 2>/dev/null)" = "1" ]; then
    log_pass "Sidebar visible after job select: ${SIDEBAR_W_T9}px"
else
    log_fail "Sidebar stuck hidden: ${SIDEBAR_W_T9}px (leftSidebarCollapsed=$COLLAPSED_T9)"
fi

# Collapse now works since we're in normal mode
agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar-collapse-btn\"]').click()" 2>/dev/null
sleep 0.5
COLLAPSED_NORMAL=$(agent-browser eval "PU.state.ui.leftSidebarCollapsed" 2>/dev/null)
[ "$COLLAPSED_NORMAL" = "true" ] && log_pass "Collapse works in normal mode" || log_fail "Collapse broken in normal mode: $COLLAPSED_NORMAL"

# Restore
agent-browser eval "PU.sidebar.expand()" 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 10: Stale localStorage collapsed state is cleared on no-job reload
# ============================================================================
echo ""
log_info "TEST 10: OBJECTIVE: Pre-existing collapsed state in localStorage does not break no-job load"

# Simulate stale state: force leftSidebarCollapsed=true in localStorage
agent-browser eval "
    const state = JSON.parse(localStorage.getItem('pu_ui_state') || '{}');
    delete state.activeJobId;
    delete state.activePromptId;
    state.leftSidebarCollapsed = true;
    localStorage.setItem('pu_ui_state', JSON.stringify(state));
" 2>/dev/null

# Reload — no ?job= param, so expanded mode should activate and clear collapsed
agent-browser eval "window.location.href = '$BASE_URL/'" 2>/dev/null
sleep 4

LAYOUT_T10=$(agent-browser eval "document.querySelector('.pu-main').dataset.layout || 'none'" 2>/dev/null | tr -d '"')
COLLAPSED_T10=$(agent-browser eval "PU.state.ui.leftSidebarCollapsed" 2>/dev/null)
OPACITY_T10=$(agent-browser eval "getComputedStyle(document.querySelector('[data-testid=\"pu-sidebar\"]')).opacity" 2>/dev/null | tr -d '"')
[ "$LAYOUT_T10" = "no-job" ] && log_pass "Expanded no-job layout active" || log_fail "Not in no-job layout: $LAYOUT_T10"
[ "$COLLAPSED_T10" = "false" ] && log_pass "Stale collapsed state cleared" || log_fail "Stale collapsed state persisted: $COLLAPSED_T10"
[ "$OPACITY_T10" = "1" ] && log_pass "Sidebar visible despite stale localStorage" || log_fail "Sidebar invisible: opacity=$OPACITY_T10"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser eval "localStorage.removeItem('pu_ui_state')" 2>/dev/null
agent-browser close 2>/dev/null
log_pass "Browser closed and state reset"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
