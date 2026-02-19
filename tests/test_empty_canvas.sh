#!/bin/bash
# ============================================================================
# E2E Test Suite: Empty Canvas Onboarding
# ============================================================================
# Tests 3 empty-canvas onboarding gaps:
#   Gap 1: Add Prompt — sidebar ghost button + center CTA
#   Gap 4: Hidden ext dropdown when ext/ is empty
#   Gap 5: Progressive operations (hidden when no wildcards)
#
# Usage: ./tests/test_empty_canvas.sh [--port 8085]
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

print_header "Empty Canvas Onboarding Tests"

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
# SETUP: Open browser and create test job with 0 prompts in JS state
# ============================================================================
echo ""
log_info "SETUP: Creating test job in JS state"

agent-browser open "$BASE_URL" 2>/dev/null
sleep 3

# Create test job directly in state (mirrors createNewJob pattern)
agent-browser eval "
    PU.state.jobs['test-empty-canvas'] = {
        valid: true,
        defaults: { seed: 42, trigger_delimiter: ', ', prompts_delimiter: ', ', ext: 'defaults' },
        prompts: [],
        loras: []
    };
    PU.state.modifiedJobs['test-empty-canvas'] = JSON.parse(JSON.stringify(PU.state.jobs['test-empty-canvas']));
    PU.state.ui.jobsExpanded['test-empty-canvas'] = true;
    PU.sidebar.renderJobs();
    'ok'
" 2>/dev/null
sleep 1
log_pass "Test job 'test-empty-canvas' created in state"

# ============================================================================
# TEST 1: No-prompts CTA appears when job has 0 prompts
# ============================================================================
echo ""
log_info "TEST 1: No-prompts CTA when job has 0 prompts"

# Select the test job
agent-browser eval "PU.actions.selectJob('test-empty-canvas')" 2>/dev/null
sleep 1

# Check that no-prompts state is visible
HAS_NO_PROMPTS=$(agent-browser eval "
    var el = document.querySelector('[data-testid=\"pu-editor-no-prompts\"]');
    !!(el && el.style.display !== 'none')
" 2>/dev/null)

if [ "$HAS_NO_PROMPTS" = "true" ]; then
    log_pass "No-prompts CTA is visible when job has 0 prompts"
else
    log_fail "No-prompts CTA not visible (got: $HAS_NO_PROMPTS)"
fi

# Check that the "Add Prompt" button exists in the CTA
HAS_ADD_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-add-first-prompt-btn\"]')" 2>/dev/null)
if [ "$HAS_ADD_BTN" = "true" ]; then
    log_pass "Add Prompt button exists in CTA"
else
    log_fail "Add Prompt button missing from CTA"
fi

# Check that editor content is hidden
EDITOR_HIDDEN=$(agent-browser eval "
    var el = document.querySelector('[data-testid=\"pu-editor-content\"]');
    !!(el && el.style.display === 'none')
" 2>/dev/null)
if [ "$EDITOR_HIDDEN" = "true" ]; then
    log_pass "Editor content is hidden when no prompts"
else
    log_fail "Editor content should be hidden when no prompts"
fi

# ============================================================================
# TEST 2: Sidebar ghost button exists for Add Prompt
# ============================================================================
echo ""
log_info "TEST 2: Sidebar ghost button for Add Prompt"

HAS_GHOST_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-add-prompt-test-empty-canvas\"]')" 2>/dev/null)
if [ "$HAS_GHOST_BTN" = "true" ]; then
    log_pass "Sidebar ghost '+ Prompt' button exists"
else
    log_fail "Sidebar ghost '+ Prompt' button missing"
fi

# Check ghost button has the ghost styling class
HAS_GHOST_CLASS=$(agent-browser eval "
    var el = document.querySelector('[data-testid=\"pu-add-prompt-test-empty-canvas\"]');
    !!(el && el.classList.contains('pu-tree-item-ghost'))
" 2>/dev/null)
if [ "$HAS_GHOST_CLASS" = "true" ]; then
    log_pass "Ghost button has pu-tree-item-ghost class"
else
    log_fail "Ghost button missing pu-tree-item-ghost class"
fi

# ============================================================================
# TEST 3: createNewPrompt action creates prompt and opens focus
# ============================================================================
echo ""
log_info "TEST 3: createNewPrompt creates prompt and opens focus overlay"

# Mock window.prompt to return a test prompt ID
agent-browser eval "
    window._origPrompt = window.prompt;
    window.prompt = function() { return 'test-prompt-1'; };
" 2>/dev/null
sleep 0.3

# Trigger createNewPrompt
agent-browser eval "PU.actions.createNewPrompt('test-empty-canvas')" 2>/dev/null
sleep 3

# Check prompt was created in state
HAS_PROMPT=$(agent-browser eval "
    var job = PU.state.jobs['test-empty-canvas'];
    !!(job && job.prompts && job.prompts.some(function(p) { return (typeof p === 'string' ? p : p.id) === 'test-prompt-1'; }))
" 2>/dev/null)
if [ "$HAS_PROMPT" = "true" ]; then
    log_pass "Prompt 'test-prompt-1' created in state"
else
    log_fail "Prompt 'test-prompt-1' not found in state"
fi

# Check focus overlay opened
FOCUS_VISIBLE=$(agent-browser eval "
    var overlay = document.querySelector('[data-testid=\"pu-focus-overlay\"]');
    !!(overlay && overlay.style.display !== 'none')
" 2>/dev/null)
if [ "$FOCUS_VISIBLE" = "true" ]; then
    log_pass "Focus overlay opened after prompt creation"
else
    log_fail "Focus overlay should open after prompt creation"
fi

# Check it's in draft mode
IS_DRAFT=$(agent-browser eval "PU.state.focusMode.draft === true" 2>/dev/null)
if [ "$IS_DRAFT" = "true" ]; then
    log_pass "Focus overlay is in draft mode"
else
    log_fail "Focus overlay should be in draft mode"
fi

# Restore original prompt and close focus
agent-browser eval "window.prompt = window._origPrompt" 2>/dev/null
agent-browser eval "PU.focus.exit()" 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 4: No-prompts CTA disappears after adding a prompt
# ============================================================================
echo ""
log_info "TEST 4: No-prompts CTA hidden after adding prompt"

NO_PROMPTS_HIDDEN=$(agent-browser eval "
    var el = document.querySelector('[data-testid=\"pu-editor-no-prompts\"]');
    !!(el && el.style.display === 'none')
" 2>/dev/null)
if [ "$NO_PROMPTS_HIDDEN" = "true" ]; then
    log_pass "No-prompts CTA is hidden after adding prompt"
else
    log_fail "No-prompts CTA should be hidden after adding prompt"
fi

# Check editor content is now visible
EDITOR_VISIBLE=$(agent-browser eval "
    var el = document.querySelector('[data-testid=\"pu-editor-content\"]');
    !!(el && el.style.display !== 'none')
" 2>/dev/null)
if [ "$EDITOR_VISIBLE" = "true" ]; then
    log_pass "Editor content is visible after adding prompt"
else
    log_fail "Editor content should be visible after adding prompt"
fi

# ============================================================================
# TEST 5: Sidebar shows prompt in tree after creation
# ============================================================================
echo ""
log_info "TEST 5: Sidebar shows new prompt"

HAS_PROMPT_IN_SIDEBAR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-prompt-test-empty-canvas-test-prompt-1\"]')" 2>/dev/null)
if [ "$HAS_PROMPT_IN_SIDEBAR" = "true" ]; then
    log_pass "Prompt appears in sidebar tree"
else
    log_fail "Prompt not found in sidebar tree"
fi

# ============================================================================
# TEST 6 (Gap 4): Ext dropdown hidden when ext/ is empty
# ============================================================================
echo ""
log_info "TEST 6 (Gap 4): Ext dropdown visibility"

# Check if ext tree is empty
EXT_TREE_EMPTY=$(agent-browser eval "
    var tree = PU.state.globalExtensions.tree;
    var keys = Object.keys(tree || {}).filter(function(k) { return k !== '_files'; });
    keys.length === 0
" 2>/dev/null)

if [ "$EXT_TREE_EMPTY" = "true" ]; then
    # ext/ is empty — ext row should be hidden
    EXT_ROW_HIDDEN=$(agent-browser eval "
        var row = document.querySelector('[data-testid=\"pu-defaults-ext-row\"]');
        !!(row && row.style.display === 'none')
    " 2>/dev/null)
    if [ "$EXT_ROW_HIDDEN" = "true" ]; then
        log_pass "Ext dropdown row hidden when ext/ is empty"
    else
        log_fail "Ext dropdown row should be hidden when ext/ is empty"
    fi

    # Check "No extension themes installed" message is visible
    NO_EXT_MSG=$(agent-browser eval "
        var msg = document.querySelector('[data-testid=\"pu-defaults-no-ext\"]');
        !!(msg && msg.style.display !== 'none')
    " 2>/dev/null)
    if [ "$NO_EXT_MSG" = "true" ]; then
        log_pass "'No extension themes installed' message shown"
    else
        log_fail "'No extension themes installed' message should be shown"
    fi
else
    # ext/ has content — ext row should be visible
    EXT_ROW_VISIBLE=$(agent-browser eval "
        var row = document.querySelector('[data-testid=\"pu-defaults-ext-row\"]');
        !!(row && row.style.display !== 'none')
    " 2>/dev/null)
    if [ "$EXT_ROW_VISIBLE" = "true" ]; then
        log_pass "Ext dropdown row visible when ext/ has content"
    else
        log_fail "Ext dropdown row should be visible when ext/ has content"
    fi

    NO_EXT_HIDDEN=$(agent-browser eval "
        var msg = document.querySelector('[data-testid=\"pu-defaults-no-ext\"]');
        !!(msg && msg.style.display === 'none')
    " 2>/dev/null)
    if [ "$NO_EXT_HIDDEN" = "true" ]; then
        log_pass "'No extension themes' message hidden when ext/ has content"
    else
        log_fail "'No extension themes' message should be hidden when ext/ has content"
    fi
fi

# ============================================================================
# TEST 7 (Gap 5): Ops section hidden when no wildcards
# ============================================================================
echo ""
log_info "TEST 7 (Gap 5): Progressive operations section"

# The test prompt has no wildcards yet — ops section should be empty
OPS_EMPTY=$(agent-browser eval "
    var ops = document.querySelector('[data-testid=\"pu-rp-ops-section\"]');
    !!(ops && ops.innerHTML.trim() === '')
" 2>/dev/null)
if [ "$OPS_EMPTY" = "true" ]; then
    log_pass "Ops section empty when prompt has no wildcards"
else
    log_fail "Ops section should be empty when no wildcards exist"
fi

# ============================================================================
# TEST 8: Validate createNewPrompt rejects invalid names
# ============================================================================
echo ""
log_info "TEST 8: createNewPrompt validation"

# Mock prompt to return invalid name
agent-browser eval "
    window._origPrompt = window.prompt;
    window.prompt = function() { return 'bad name!'; };
" 2>/dev/null

PROMPT_COUNT_BEFORE=$(agent-browser eval "PU.state.jobs['test-empty-canvas'].prompts.length" 2>/dev/null)

agent-browser eval "PU.actions.createNewPrompt('test-empty-canvas')" 2>/dev/null
sleep 0.5

PROMPT_COUNT_AFTER=$(agent-browser eval "PU.state.jobs['test-empty-canvas'].prompts.length" 2>/dev/null)

if [ "$PROMPT_COUNT_BEFORE" = "$PROMPT_COUNT_AFTER" ]; then
    log_pass "Invalid prompt name rejected (count unchanged)"
else
    log_fail "Invalid prompt name should be rejected (before=$PROMPT_COUNT_BEFORE, after=$PROMPT_COUNT_AFTER)"
fi

# Test duplicate rejection
agent-browser eval "window.prompt = function() { return 'test-prompt-1'; };" 2>/dev/null
agent-browser eval "PU.actions.createNewPrompt('test-empty-canvas')" 2>/dev/null
sleep 0.5

PROMPT_COUNT_DUP=$(agent-browser eval "PU.state.jobs['test-empty-canvas'].prompts.length" 2>/dev/null)
if [ "$PROMPT_COUNT_AFTER" = "$PROMPT_COUNT_DUP" ]; then
    log_pass "Duplicate prompt name rejected"
else
    log_fail "Duplicate prompt name should be rejected (after=$PROMPT_COUNT_AFTER, dup=$PROMPT_COUNT_DUP)"
fi

# Restore original prompt
agent-browser eval "window.prompt = window._origPrompt" 2>/dev/null

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

# Remove test job from state
agent-browser eval "
    delete PU.state.jobs['test-empty-canvas'];
    delete PU.state.modifiedJobs['test-empty-canvas'];
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
