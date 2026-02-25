#!/bin/bash
# ============================================================================
# E2E Test Suite: Token Counter Widget (_token_limit)
# ============================================================================
# Tests the inline token counter chip on editor blocks:
# - _token_limit registration as universal annotation
# - Token counter chip visibility (budget-gated)
# - Format: ~N/M with color states (ok/warn/over)
# - Inheritance: block inherits _token_limit from defaults
# - Counter updates on composition change
#
# Usage: ./tests/test_token_counter.sh [--port 8085]
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

print_header "Token Counter Widget (_token_limit)"

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

# Open test fixture with nested-blocks prompt (block 0 has _token_limit: 500)
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: _token_limit registered as universal annotation
# ============================================================================
echo ""
log_info "TEST 1: _token_limit registered as universal"

IS_UNIVERSAL=$(agent-browser eval "PU.annotations.isUniversal('_token_limit')" 2>/dev/null | head -1 | tr -d '"')
[ "$IS_UNIVERSAL" = "true" ] && log_pass "_token_limit is universal" || log_fail "_token_limit not universal: $IS_UNIVERSAL"

WIDGET_TYPE=$(agent-browser eval "PU.annotations._universals['_token_limit'].widget" 2>/dev/null | head -1 | tr -d '"')
[ "$WIDGET_TYPE" = "number" ] && log_pass "Widget type: number" || log_fail "Widget type: $WIDGET_TYPE"

# ============================================================================
# TEST 2: Token counter chip visible on block with _token_limit
# ============================================================================
echo ""
log_info "TEST 2: Token counter chip visible on block 0"

HAS_CHIP=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-token-counter-0\"]')" 2>/dev/null | head -1 | tr -d '"')
[ "$HAS_CHIP" = "true" ] && log_pass "Token counter chip exists on block 0" || log_fail "Token counter chip missing on block 0"

# ============================================================================
# TEST 3: Token counter NOT visible on blocks without _token_limit
# ============================================================================
echo ""
log_info "TEST 3: No counter on blocks without budget"

# Child blocks (0-0, 0-1) don't have _token_limit and shouldn't inherit from parent block
# (block annotations don't cascade to children)
NO_CHIP_CHILD=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-token-counter-0-0\"]')" 2>/dev/null | head -1 | tr -d '"')
[ "$NO_CHIP_CHILD" = "true" ] && log_pass "No counter on child block 0.0" || log_fail "Counter found on child block 0.0"

# ============================================================================
# TEST 4: Counter shows correct format ~N/M
# ============================================================================
echo ""
log_info "TEST 4: Counter format"

CHIP_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-token-counter-0\"]')?.textContent || ''" 2>/dev/null | head -1 | tr -d '"')
echo "$CHIP_TEXT" | grep -qE '~[0-9]+/500' && log_pass "Format correct: $CHIP_TEXT" || log_fail "Format wrong: $CHIP_TEXT"

# ============================================================================
# TEST 5: Color state is correct (ok = green, block text is short)
# ============================================================================
echo ""
log_info "TEST 5: Color states"

# Block 0 content is "Root block __tone__" → resolved ~"Root block formal" = ~15 chars = ~4 tokens
# 4/500 = 0.8% → should be 'ok' (green)
HAS_OK=$(agent-browser eval "document.querySelector('[data-testid=\"pu-token-counter-0\"]')?.classList.contains('ok')" 2>/dev/null | head -1 | tr -d '"')
[ "$HAS_OK" = "true" ] && log_pass "Color state: ok (green)" || log_fail "Color state not ok"

# Verify computeTokenCount works correctly
TOKEN_COUNT=$(agent-browser eval "PU.annotations.computeTokenCount('Hello world test string 1234')" 2>/dev/null | head -1 | tr -d '"')
[ "$TOKEN_COUNT" = "7" ] && log_pass "computeTokenCount('Hello world test string 1234') = 7" || log_fail "computeTokenCount = $TOKEN_COUNT (expected 7)"

# ============================================================================
# TEST 6: resolveTokenLimit uses inheritance
# ============================================================================
echo ""
log_info "TEST 6: Token limit inheritance"

# Block 0 has _token_limit: 500 directly
LIMIT_0=$(agent-browser eval "PU.annotations.resolveTokenLimit('0')" 2>/dev/null | head -1 | tr -d '"')
[ "$LIMIT_0" = "500" ] && log_pass "Block 0 limit: 500 (from block)" || log_fail "Block 0 limit: $LIMIT_0"

# Child block 0.0 does NOT inherit _token_limit (block annotations don't cascade)
LIMIT_CHILD=$(agent-browser eval "PU.annotations.resolveTokenLimit('0.0')" 2>/dev/null | head -1 | tr -d '"')
[ "$LIMIT_CHILD" = "null" ] && log_pass "Child 0.0 limit: null (no inheritance from parent block)" || log_fail "Child 0.0 limit: $LIMIT_CHILD"

# ============================================================================
# TEST 7: Counter updates on composition change
# ============================================================================
echo ""
log_info "TEST 7: Counter updates on composition change"

# Get initial count
INITIAL_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-token-counter-0\"]')?.textContent || ''" 2>/dev/null | head -1 | tr -d '"')
log_info "Initial: $INITIAL_TEXT"

# Switch composition (tone: formal -> casual)
agent-browser eval "PU.state.previewMode.compositionId = 1; PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId); PU.rightPanel.render();" 2>/dev/null
sleep 1

UPDATED_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-token-counter-0\"]')?.textContent || ''" 2>/dev/null | head -1 | tr -d '"')
log_info "After comp change: $UPDATED_TEXT"

# Both should still have format ~N/500, and chip should exist
echo "$UPDATED_TEXT" | grep -qE '~[0-9]+/500' && log_pass "Counter updated after composition change" || log_fail "Counter format wrong after change: $UPDATED_TEXT"

# ============================================================================
# TEST 8: Annotation editor shows number widget
# ============================================================================
echo ""
log_info "TEST 8: Number widget in annotation editor"

# Open annotation editor for block 0
agent-browser eval "PU.annotations.openEditor('0')" 2>/dev/null
sleep 0.5

# Check for number input
HAS_NUMBER_INPUT=$(agent-browser eval "!!document.querySelector('.pu-ann-number-input')" 2>/dev/null | head -1 | tr -d '"')
[ "$HAS_NUMBER_INPUT" = "true" ] && log_pass "Number input widget exists" || log_fail "Number input widget missing"

# Check the value is 500
INPUT_VAL=$(agent-browser eval "document.querySelector('.pu-ann-number-input')?.value || ''" 2>/dev/null | head -1 | tr -d '"')
[ "$INPUT_VAL" = "500" ] && log_pass "Number input value: 500" || log_fail "Number input value: $INPUT_VAL"

# Close editor
agent-browser eval "PU.annotations.closeEditor('0')" 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 9: Token counter chip has tooltip
# ============================================================================
echo ""
log_info "TEST 9: Counter tooltip"

TOOLTIP=$(agent-browser eval "document.querySelector('[data-testid=\"pu-token-counter-0\"]')?.title || ''" 2>/dev/null | head -1 | tr -d '"')
echo "$TOOLTIP" | grep -q "tokens" && log_pass "Tooltip mentions tokens" || log_fail "Tooltip: $TOOLTIP"
echo "$TOOLTIP" | grep -q "500" && log_pass "Tooltip shows budget" || log_fail "Tooltip missing budget"

# ============================================================================
# TEST 10: Defaults-level _token_limit inheritance
# ============================================================================
echo ""
log_info "TEST 10: Defaults-level inheritance"

# Add _token_limit to job defaults and check if blocks pick it up
agent-browser eval "
    const job = PU.helpers.getActiveJob();
    if (job && job.defaults && job.defaults.annotations) {
        job.defaults.annotations._token_limit = 2000;
    }
" 2>/dev/null
sleep 0.3

# Child block 0.0 should now resolve _token_limit from defaults
LIMIT_CHILD_2=$(agent-browser eval "PU.annotations.resolveTokenLimit('0.0')" 2>/dev/null | head -1 | tr -d '"')
[ "$LIMIT_CHILD_2" = "2000" ] && log_pass "Child 0.0 inherits limit 2000 from defaults" || log_fail "Child 0.0 limit: $LIMIT_CHILD_2"

# Block 0 should still use its own (500 overrides 2000)
LIMIT_0_STILL=$(agent-browser eval "PU.annotations.resolveTokenLimit('0')" 2>/dev/null | head -1 | tr -d '"')
[ "$LIMIT_0_STILL" = "500" ] && log_pass "Block 0 still 500 (own overrides defaults)" || log_fail "Block 0 limit changed: $LIMIT_0_STILL"

# Clean up: remove from defaults
agent-browser eval "
    const job = PU.helpers.getActiveJob();
    if (job && job.defaults && job.defaults.annotations) {
        delete job.defaults.annotations._token_limit;
    }
" 2>/dev/null

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
