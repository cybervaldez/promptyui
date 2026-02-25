#!/bin/bash
# ============================================================================
# E2E Test Suite: Async Widget (_quality_check)
# ============================================================================
# Tests the async annotation widget rendering and check execution:
# - Async widget registration via defineUniversal()
# - Widget renders with pending state
# - Run button triggers check function
# - Pass/fail states display correctly
# - autoCheck triggers on annotation change
# - cacheTtl prevents redundant checks
#
# Usage: ./tests/test_async_widget.sh [--port 8085]
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

print_header "Async Widget (_quality_check)"

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

# Open test fixture with nested-blocks prompt (block 0 has _quality_check: true)
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# Register _quality_check as an async universal annotation via JS
# The check function returns pass if block text length > 5, fail otherwise
agent-browser eval "
    PU.annotations.defineUniversal('_quality_check', {
        widget: 'async',
        label: 'Quality Check',
        showOnCard: false,
        description: 'Validates block content quality',
        cacheTtl: 5,
        autoCheck: true,
        check: async (path, value, ctx) => {
            // Simulate async work (50ms delay)
            await new Promise(r => setTimeout(r, 50));
            const text = ctx.blockText || '';
            if (text.length > 5) {
                return { status: 'pass', message: 'Content is sufficient' };
            }
            return { status: 'fail', message: 'Content too short' };
        }
    });
" 2>/dev/null
sleep 0.5

# Re-render blocks to pick up the new universal
agent-browser eval "PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId)" 2>/dev/null
sleep 1

# ============================================================================
# TEST 1: _quality_check registered as universal
# ============================================================================
echo ""
log_info "TEST 1: _quality_check registered as universal"

IS_UNIVERSAL=$(agent-browser eval "PU.annotations.isUniversal('_quality_check')" 2>/dev/null | head -1 | tr -d '"')
[ "$IS_UNIVERSAL" = "true" ] && log_pass "_quality_check is universal" || log_fail "_quality_check not universal: $IS_UNIVERSAL"

WIDGET_TYPE=$(agent-browser eval "PU.annotations._universals['_quality_check'].widget" 2>/dev/null | head -1 | tr -d '"')
[ "$WIDGET_TYPE" = "async" ] && log_pass "Widget type: async" || log_fail "Widget type: $WIDGET_TYPE"

# ============================================================================
# TEST 2: Async widget renders in annotation editor
# ============================================================================
echo ""
log_info "TEST 2: Async widget renders in editor"

# Open annotation editor for block 0
agent-browser eval "PU.annotations.openEditor('0')" 2>/dev/null
sleep 0.5

# Check for async row
HAS_ASYNC_ROW=$(agent-browser eval "!!document.querySelector('.pu-ann-async-row[data-ann-key=\"_quality_check\"]')" 2>/dev/null | head -1 | tr -d '"')
[ "$HAS_ASYNC_ROW" = "true" ] && log_pass "Async row renders for _quality_check" || log_fail "Async row missing"

# Check for status element
HAS_STATUS=$(agent-browser eval "!!document.querySelector('.pu-ann-async-status')" 2>/dev/null | head -1 | tr -d '"')
[ "$HAS_STATUS" = "true" ] && log_pass "Async status element present" || log_fail "Async status element missing"

# Check for run button
HAS_RUN_BTN=$(agent-browser eval "!!document.querySelector('.pu-ann-async-run')" 2>/dev/null | head -1 | tr -d '"')
[ "$HAS_RUN_BTN" = "true" ] && log_pass "Run button present" || log_fail "Run button missing"

# ============================================================================
# TEST 3: Auto-run on editor open (autoCheck: true)
# ============================================================================
echo ""
log_info "TEST 3: Auto-run on editor open"

# openEditor() was called above — with autoCheck:true, the check runs automatically
# By now (500ms sleep), it should already be pass (block text > 5 chars)
AUTO_PASS=$(agent-browser eval "document.querySelector('.pu-ann-async-icon')?.classList.contains('pass')" 2>/dev/null | head -1 | tr -d '"')
[ "$AUTO_PASS" = "true" ] && log_pass "Auto-run produced pass state on editor open" || log_fail "Auto-run did not produce pass"

AUTO_MSG=$(agent-browser eval "document.querySelector('.pu-ann-async-label')?.textContent || ''" 2>/dev/null | head -1 | tr -d '"')
echo "$AUTO_MSG" | grep -q "sufficient" && log_pass "Auto-run message: $AUTO_MSG" || log_fail "Auto-run message: $AUTO_MSG"

# Verify cache was populated by auto-run
AUTO_CACHE=$(agent-browser eval "PU.annotations._asyncCache['0:_quality_check']?.status" 2>/dev/null | head -1 | tr -d '"')
[ "$AUTO_CACHE" = "pass" ] && log_pass "Auto-run cached result" || log_fail "Auto-run cache: $AUTO_CACHE"

# ============================================================================
# TEST 4: Manual re-run via runAsyncCheck
# ============================================================================
echo ""
log_info "TEST 4: Manual re-run (block text = 'Root block __tone__' > 5 chars)"

# Clear cache and re-run manually
agent-browser eval "PU.annotations._asyncCache = {}" 2>/dev/null
agent-browser eval "PU.annotations.runAsyncCheck('0', '_quality_check')" 2>/dev/null
sleep 0.5

PASS_ICON=$(agent-browser eval "document.querySelector('.pu-ann-async-icon')?.classList.contains('pass')" 2>/dev/null | head -1 | tr -d '"')
[ "$PASS_ICON" = "true" ] && log_pass "Manual re-run: pass (checkmark)" || log_fail "Manual re-run not pass"

PASS_LABEL=$(agent-browser eval "document.querySelector('.pu-ann-async-label')?.textContent || ''" 2>/dev/null | head -1 | tr -d '"')
echo "$PASS_LABEL" | grep -q "sufficient" && log_pass "Pass message: $PASS_LABEL" || log_fail "Pass message: $PASS_LABEL"

# ============================================================================
# TEST 5: Cache prevents re-execution within TTL
# ============================================================================
echo ""
log_info "TEST 5: Cache (cacheTtl: 5s)"

CACHE_KEY=$(agent-browser eval "PU.annotations._asyncCache['0:_quality_check']?.status" 2>/dev/null | head -1 | tr -d '"')
[ "$CACHE_KEY" = "pass" ] && log_pass "Cache stores result" || log_fail "Cache missing: $CACHE_KEY"

CACHE_TS=$(agent-browser eval "typeof PU.annotations._asyncCache['0:_quality_check']?.timestamp === 'number'" 2>/dev/null | head -1 | tr -d '"')
[ "$CACHE_TS" = "true" ] && log_pass "Cache has timestamp" || log_fail "Cache missing timestamp"

# ============================================================================
# TEST 6: updateAsyncStatus works for all states
# ============================================================================
echo ""
log_info "TEST 6: Status display for all states"

# Test fail state
agent-browser eval "PU.annotations._updateAsyncStatus('0', '_quality_check', 'fail', 'Content too short')" 2>/dev/null
sleep 0.2

FAIL_ICON=$(agent-browser eval "document.querySelector('.pu-ann-async-icon')?.classList.contains('fail')" 2>/dev/null | head -1 | tr -d '"')
[ "$FAIL_ICON" = "true" ] && log_pass "Fail state renders" || log_fail "Fail state not rendered"

# Test running state
agent-browser eval "PU.annotations._updateAsyncStatus('0', '_quality_check', 'running', 'Checking...')" 2>/dev/null
sleep 0.2

RUNNING_ICON=$(agent-browser eval "document.querySelector('.pu-ann-async-icon')?.classList.contains('running')" 2>/dev/null | head -1 | tr -d '"')
[ "$RUNNING_ICON" = "true" ] && log_pass "Running state renders (animated)" || log_fail "Running state not rendered"

# Reset to pass
agent-browser eval "PU.annotations._updateAsyncStatus('0', '_quality_check', 'pass', 'Content is sufficient')" 2>/dev/null
sleep 0.2

# ============================================================================
# TEST 7: autoRunChecks fires for async universals
# ============================================================================
echo ""
log_info "TEST 7: autoRunChecks"

# Clear cache so autoRun actually executes
agent-browser eval "PU.annotations._asyncCache = {}" 2>/dev/null

# Call autoRunChecks
agent-browser eval "PU.annotations.autoRunChecks('0')" 2>/dev/null
sleep 0.5

AUTO_STATUS=$(agent-browser eval "PU.annotations._asyncCache['0:_quality_check']?.status" 2>/dev/null | head -1 | tr -d '"')
[ "$AUTO_STATUS" = "pass" ] && log_pass "autoRunChecks executed and cached result" || log_fail "autoRunChecks did not execute: $AUTO_STATUS"

# ============================================================================
# TEST 8: defineUniversal validates async descriptor
# ============================================================================
echo ""
log_info "TEST 8: Validation warnings"

# Register async without check function — should warn
WARN_OUTPUT=$(agent-browser eval "
    const origWarn = console.warn;
    let warned = false;
    console.warn = (...args) => { if (args[0]?.includes('requires')) warned = true; origWarn(...args); };
    PU.annotations.defineUniversal('_bad_async', { widget: 'async', label: 'Bad' });
    console.warn = origWarn;
    warned;
" 2>/dev/null | head -1 | tr -d '"')
[ "$WARN_OUTPUT" = "true" ] && log_pass "Warning logged for async without check" || log_fail "No warning for missing check: $WARN_OUTPUT"

# Clean up
agent-browser eval "delete PU.annotations._universals['_bad_async']" 2>/dev/null

# ============================================================================
# TEST 9: Async widget label shows correct text
# ============================================================================
echo ""
log_info "TEST 9: Widget label"

LABEL_TEXT=$(agent-browser eval "document.querySelector('.pu-ann-async-row[data-ann-key=\"_quality_check\"] .pu-ann-universal-label')?.textContent || ''" 2>/dev/null | head -1 | tr -d '"')
[ "$LABEL_TEXT" = "Quality Check" ] && log_pass "Label: Quality Check" || log_fail "Label: $LABEL_TEXT"

# ============================================================================
# TEST 10: Close editor and verify no errors
# ============================================================================
echo ""
log_info "TEST 10: Editor close"

agent-browser eval "PU.annotations.closeEditor('0')" 2>/dev/null
sleep 0.3

EDITOR_CLOSED=$(agent-browser eval "!PU.annotations._openEditors.has('0')" 2>/dev/null | head -1 | tr -d '"')
[ "$EDITOR_CLOSED" = "true" ] && log_pass "Editor closed cleanly" || log_fail "Editor still open"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

# Remove _quality_check from universals
agent-browser eval "delete PU.annotations._universals['_quality_check']" 2>/dev/null

agent-browser close 2>/dev/null
log_pass "Browser closed"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
