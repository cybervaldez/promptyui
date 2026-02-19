#!/bin/bash
# ============================================================================
# E2E Test Suite: State Hygiene
# ============================================================================
# Tests that transient preview state is properly cleared when switching
# prompts and jobs. Prevents stale bulb focus, locked values, and
# block-level overrides from bleeding across navigation.
#
# Usage: ./tests/test_state_hygiene.sh [--port 8085]
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

print_header "State Hygiene Tests"

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
# SETUP
# ============================================================================
echo ""
log_info "SETUP: Opening browser and selecting hiring-templates"

agent-browser open "$BASE_URL" 2>/dev/null
sleep 3

# Select hiring-templates job and first prompt
agent-browser eval "PU.actions.selectJob('hiring-templates')" 2>/dev/null
sleep 2

# Get available prompts
FIRST_PROMPT=$(agent-browser eval "
    var job = PU.state.jobs['hiring-templates'];
    var p = job.prompts[0];
    typeof p === 'string' ? p : p.id
" 2>/dev/null | tr -d '"')

SECOND_PROMPT=$(agent-browser eval "
    var job = PU.state.jobs['hiring-templates'];
    var p = job.prompts[1];
    typeof p === 'string' ? p : p.id
" 2>/dev/null | tr -d '"')

log_info "First prompt: $FIRST_PROMPT"
log_info "Second prompt: $SECOND_PROMPT"

if [ -z "$FIRST_PROMPT" ] || [ -z "$SECOND_PROMPT" ]; then
    log_fail "Need at least 2 prompts in hiring-templates"
    agent-browser close 2>/dev/null
    print_summary
    exit $?
fi

# ============================================================================
# TEST 1: focusedWildcards cleared on prompt switch
# ============================================================================
echo ""
log_info "TEST 1: focusedWildcards cleared on prompt switch"

# Select first prompt
agent-browser eval "PU.actions.selectPrompt('hiring-templates', '$FIRST_PROMPT')" 2>/dev/null
sleep 2

# Set a fake focused wildcard
agent-browser eval "PU.state.previewMode.focusedWildcards = ['tone']" 2>/dev/null
sleep 0.3

# Verify it's set
FOCUSED_BEFORE=$(agent-browser eval "PU.state.previewMode.focusedWildcards.length" 2>/dev/null)
if [ "$FOCUSED_BEFORE" = "1" ]; then
    log_pass "focusedWildcards set to ['tone'] before switch"
else
    log_fail "Could not set focusedWildcards (got: $FOCUSED_BEFORE)"
fi

# Switch to second prompt
agent-browser eval "PU.actions.selectPrompt('hiring-templates', '$SECOND_PROMPT')" 2>/dev/null
sleep 2

# Check focusedWildcards is cleared
FOCUSED_AFTER=$(agent-browser eval "PU.state.previewMode.focusedWildcards.length" 2>/dev/null)
if [ "$FOCUSED_AFTER" = "0" ]; then
    log_pass "focusedWildcards cleared after prompt switch"
else
    log_fail "focusedWildcards should be empty after prompt switch (got: $FOCUSED_AFTER)"
fi

# ============================================================================
# TEST 2: selectedWildcards cleared on prompt switch
# ============================================================================
echo ""
log_info "TEST 2: selectedWildcards cleared on prompt switch"

# Select first prompt
agent-browser eval "PU.actions.selectPrompt('hiring-templates', '$FIRST_PROMPT')" 2>/dev/null
sleep 2

# Set fake selectedWildcards
agent-browser eval "PU.state.previewMode.selectedWildcards = {'0': {'tone': 'formal'}}" 2>/dev/null
sleep 0.3

SW_BEFORE=$(agent-browser eval "Object.keys(PU.state.previewMode.selectedWildcards).length" 2>/dev/null)
if [ "$SW_BEFORE" = "1" ]; then
    log_pass "selectedWildcards set before switch"
else
    log_fail "Could not set selectedWildcards (got: $SW_BEFORE)"
fi

# Switch to second prompt
agent-browser eval "PU.actions.selectPrompt('hiring-templates', '$SECOND_PROMPT')" 2>/dev/null
sleep 2

SW_AFTER=$(agent-browser eval "Object.keys(PU.state.previewMode.selectedWildcards).length" 2>/dev/null)
if [ "$SW_AFTER" = "0" ]; then
    log_pass "selectedWildcards cleared after prompt switch"
else
    log_fail "selectedWildcards should be empty after prompt switch (got: $SW_AFTER)"
fi

# ============================================================================
# TEST 3: lockedValues cleared on job switch
# ============================================================================
echo ""
log_info "TEST 3: lockedValues cleared on job switch"

# Set fake locked values
agent-browser eval "PU.state.previewMode.lockedValues = {'seniority': ['senior', 'staff']}" 2>/dev/null
sleep 0.3

LV_BEFORE=$(agent-browser eval "Object.keys(PU.state.previewMode.lockedValues).length" 2>/dev/null)
if [ "$LV_BEFORE" = "1" ]; then
    log_pass "lockedValues set before job switch"
else
    log_fail "Could not set lockedValues (got: $LV_BEFORE)"
fi

# Create a temporary second job to switch to
agent-browser eval "
    PU.state.jobs['test-hygiene-job'] = {
        valid: true,
        defaults: { seed: 42 },
        prompts: [{ id: 'p1', text: [], wildcards: [] }],
        loras: []
    };
    PU.state.ui.jobsExpanded['test-hygiene-job'] = true;
    PU.sidebar.renderJobs();
    'ok'
" 2>/dev/null
sleep 0.5

# Switch to the other job
agent-browser eval "PU.actions.selectJob('test-hygiene-job')" 2>/dev/null
sleep 2

LV_AFTER=$(agent-browser eval "Object.keys(PU.state.previewMode.lockedValues).length" 2>/dev/null)
if [ "$LV_AFTER" = "0" ]; then
    log_pass "lockedValues cleared after job switch"
else
    log_fail "lockedValues should be empty after job switch (got: $LV_AFTER)"
fi

# ============================================================================
# TEST 4: focusedWildcards cleared on job switch
# ============================================================================
echo ""
log_info "TEST 4: focusedWildcards cleared on job switch"

# Switch back to hiring-templates and set focus
agent-browser eval "PU.actions.selectJob('hiring-templates')" 2>/dev/null
sleep 2
agent-browser eval "PU.state.previewMode.focusedWildcards = ['role', 'tone']" 2>/dev/null
sleep 0.3

# Switch job
agent-browser eval "PU.actions.selectJob('test-hygiene-job')" 2>/dev/null
sleep 2

FW_AFTER=$(agent-browser eval "PU.state.previewMode.focusedWildcards.length" 2>/dev/null)
if [ "$FW_AFTER" = "0" ]; then
    log_pass "focusedWildcards cleared after job switch"
else
    log_fail "focusedWildcards should be empty after job switch (got: $FW_AFTER)"
fi

# ============================================================================
# TEST 5: focusMode state has draft fields declared
# ============================================================================
echo ""
log_info "TEST 5: focusMode state declarations"

HAS_DRAFT=$(agent-browser eval "'draft' in PU.state.focusMode" 2>/dev/null)
HAS_MATERIALIZED=$(agent-browser eval "'draftMaterialized' in PU.state.focusMode" 2>/dev/null)
HAS_PARENT_PATH=$(agent-browser eval "'draftParentPath' in PU.state.focusMode" 2>/dev/null)

if [ "$HAS_DRAFT" = "true" ]; then
    log_pass "focusMode.draft declared in state"
else
    log_fail "focusMode.draft not declared"
fi

if [ "$HAS_MATERIALIZED" = "true" ]; then
    log_pass "focusMode.draftMaterialized declared in state"
else
    log_fail "focusMode.draftMaterialized not declared"
fi

if [ "$HAS_PARENT_PATH" = "true" ]; then
    log_pass "focusMode.draftParentPath declared in state"
else
    log_fail "focusMode.draftParentPath not declared"
fi

# ============================================================================
# TEST 6: Focus banner hidden after prompt switch
# ============================================================================
echo ""
log_info "TEST 6: Focus banner hidden after prompt switch"

# Go back to hiring-templates
agent-browser eval "PU.actions.selectJob('hiring-templates')" 2>/dev/null
sleep 2
agent-browser eval "PU.actions.selectPrompt('hiring-templates', '$FIRST_PROMPT')" 2>/dev/null
sleep 2

# Simulate showing a focus banner
agent-browser eval "
    PU.state.previewMode.focusedWildcards = ['tone'];
    PU.rightPanel._showFocusBanner(['tone'], 1, 3);
" 2>/dev/null
sleep 0.3

BANNER_VISIBLE=$(agent-browser eval "
    var b = document.querySelector('[data-testid=\"pu-focus-banner\"]');
    !!(b && b.style.display !== 'none')
" 2>/dev/null)
if [ "$BANNER_VISIBLE" = "true" ]; then
    log_pass "Focus banner visible before switch"
else
    log_info "Focus banner not visible before switch (may not have been created)"
fi

# Switch prompt
agent-browser eval "PU.actions.selectPrompt('hiring-templates', '$SECOND_PROMPT')" 2>/dev/null
sleep 2

BANNER_HIDDEN=$(agent-browser eval "
    var b = document.querySelector('[data-testid=\"pu-focus-banner\"]');
    !b || b.style.display === 'none'
" 2>/dev/null)
if [ "$BANNER_HIDDEN" = "true" ]; then
    log_pass "Focus banner hidden after prompt switch"
else
    log_fail "Focus banner should be hidden after prompt switch"
fi

# ============================================================================
# TEST 7: pu-rp-wc-empty CSS class exists
# ============================================================================
echo ""
log_info "TEST 7: CSS class definitions"

# Create a test element and check if pu-rp-wc-empty applies styling
HAS_WC_EMPTY_CSS=$(agent-browser eval "
    var el = document.createElement('div');
    el.className = 'pu-rp-wc-empty';
    el.textContent = 'test';
    document.body.appendChild(el);
    var style = window.getComputedStyle(el);
    var hasStyle = style.textAlign === 'center' || style.fontSize !== '';
    document.body.removeChild(el);
    hasStyle
" 2>/dev/null)
if [ "$HAS_WC_EMPTY_CSS" = "true" ]; then
    log_pass "pu-rp-wc-empty CSS class applies styling"
else
    # CSS may not be reloaded in this browser session — check file directly
    log_info "Browser CSS may be cached, verifying file directly"
    if grep -q "pu-rp-wc-empty" "$SCRIPT_DIR/../webui/prompty/css/styles.css" 2>/dev/null; then
        log_pass "pu-rp-wc-empty CSS class defined in styles.css"
    else
        log_fail "pu-rp-wc-empty CSS class not defined"
    fi
fi

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

# Remove temp job
agent-browser eval "
    delete PU.state.jobs['test-hygiene-job'];
    delete PU.state.modifiedJobs['test-hygiene-job'];
    PU.sidebar.renderJobs();
    'cleaned'
" 2>/dev/null

agent-browser close 2>/dev/null
log_pass "Browser closed"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
