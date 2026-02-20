#!/bin/bash
# ============================================================================
# E2E Test Suite: Footer Helper Bar
# ============================================================================
# Tests the persistent footer bar with shortcut labels, clickable toggles,
# and contextual helper tips on hover.
#
# Usage: ./tests/test_footer_helper.sh [--port 8085]
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

print_header "Footer Helper Bar"

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
# TEST 1: Footer bar exists with correct structure
# ============================================================================
echo ""
log_info "TEST 1: Footer bar exists with correct structure"

agent-browser open "$BASE_URL" 2>/dev/null
sleep 3

HAS_FOOTER=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-footer\"]')" 2>/dev/null)
[ "$HAS_FOOTER" = "true" ] && log_pass "Footer bar found" || log_fail "Footer bar missing"

HAS_SHORTCUTS=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-footer-shortcuts\"]')" 2>/dev/null)
[ "$HAS_SHORTCUTS" = "true" ] && log_pass "Shortcuts section found" || log_fail "Shortcuts section missing"

HAS_TIP=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-footer-tip\"]')" 2>/dev/null)
[ "$HAS_TIP" = "true" ] && log_pass "Tip section found" || log_fail "Tip section missing"

KBD_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-footer kbd').length" 2>/dev/null)
[ "$KBD_COUNT" = "2" ] && log_pass "Two kbd hint elements found" || log_fail "Expected 2 kbd elements, got: $KBD_COUNT"

# ============================================================================
# TEST 2: Footer label text content
# ============================================================================
echo ""
log_info "TEST 2: Footer label text content"

JB_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-footer-job-browser\"]').textContent" 2>/dev/null | tr -d '"')
[ "$JB_TEXT" = "Open" ] && log_pass "Open label text correct" || log_fail "Open label text: $JB_TEXT"

COMP_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-footer-composer\"]').textContent" 2>/dev/null | tr -d '"')
[ "$COMP_TEXT" = "Compose" ] && log_pass "Compose label text correct" || log_fail "Compose label text: $COMP_TEXT"

PREFIX=$(agent-browser eval "document.querySelector('.pu-footer-prefix').textContent" 2>/dev/null | tr -d '"')
[ "$PREFIX" = "Keyboard Shortcuts" ] && log_pass "Prefix text correct" || log_fail "Prefix text: $PREFIX"

# ============================================================================
# TEST 3: Clicking Open toggles left sidebar
# ============================================================================
echo ""
log_info "TEST 3: Clicking Open toggles left sidebar"

agent-browser eval "PU.sidebar.expand()" 2>/dev/null
sleep 0.3

agent-browser eval "document.querySelector('[data-testid=\"pu-footer-job-browser\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Sidebar collapsed via Open click" || log_fail "Sidebar not collapsed: $IS_COLLAPSED"

agent-browser eval "document.querySelector('[data-testid=\"pu-footer-job-browser\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-sidebar\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Sidebar expanded via Open click" || log_fail "Sidebar still collapsed: $IS_COLLAPSED"

# ============================================================================
# TEST 4: Clicking Compose toggles right panel
# ============================================================================
echo ""
log_info "TEST 4: Clicking Compose toggles right panel"

agent-browser eval "PU.rightPanel.expand()" 2>/dev/null
sleep 0.3

agent-browser eval "document.querySelector('[data-testid=\"pu-footer-composer\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "true" ] && log_pass "Right panel collapsed via Compose click" || log_fail "Right panel not collapsed: $IS_COLLAPSED"

agent-browser eval "document.querySelector('[data-testid=\"pu-footer-composer\"]').click()" 2>/dev/null
sleep 0.5

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-right-panel\"]').classList.contains('collapsed')" 2>/dev/null)
[ "$IS_COLLAPSED" = "false" ] && log_pass "Right panel expanded via Compose click" || log_fail "Right panel still collapsed: $IS_COLLAPSED"

# ============================================================================
# TEST 5: Footer tip hidden by default
# ============================================================================
echo ""
log_info "TEST 5: Footer tip hidden by default"

TIP_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-footer-tip\"]').classList.contains('visible')" 2>/dev/null)
[ "$TIP_VISIBLE" = "false" ] && log_pass "Tip hidden by default" || log_fail "Tip unexpectedly visible"

# ============================================================================
# TEST 6: Hover wildcard chip shows footer tip
# ============================================================================
echo ""
log_info "TEST 6: Hover wildcard chip shows footer tip"

# Load a job with wildcards first
JOBS=$(curl -sf "$BASE_URL/api/pu/jobs" 2>/dev/null)
FIRST_JOB=$(echo "$JOBS" | python3 -c "import sys,json; jobs=json.load(sys.stdin); print(list(jobs.keys())[0] if jobs else '')" 2>/dev/null)

if [ -n "$FIRST_JOB" ]; then
    # Select the job and its first prompt
    agent-browser eval "PU.actions.selectJob('$FIRST_JOB')" 2>/dev/null
    sleep 2

    FIRST_PROMPT=$(agent-browser eval "(function(){ var j=PU.state.jobs['$FIRST_JOB']; if(j&&j.prompts&&j.prompts.length) return typeof j.prompts[0]==='string'?j.prompts[0]:j.prompts[0].id; return ''; })()" 2>/dev/null | tr -d '"')

    if [ -n "$FIRST_PROMPT" ]; then
        agent-browser eval "PU.actions.selectPrompt('$FIRST_JOB', '$FIRST_PROMPT')" 2>/dev/null
        sleep 2

        # Check if there are any wildcard chips
        CHIP_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-rp-wc-v').length" 2>/dev/null)

        if [ "$CHIP_COUNT" != "0" ] && [ -n "$CHIP_COUNT" ]; then
            # Simulate mouseenter on first chip
            agent-browser eval "document.querySelector('.pu-rp-wc-v').dispatchEvent(new MouseEvent('mouseenter', {bubbles: true}))" 2>/dev/null
            sleep 0.3

            TIP_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-footer-tip\"]').classList.contains('visible')" 2>/dev/null)
            [ "$TIP_VISIBLE" = "true" ] && log_pass "Tip visible on chip hover" || log_fail "Tip not visible on hover: $TIP_VISIBLE"

            TIP_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-footer-tip\"]').textContent" 2>/dev/null | tr -d '"')
            echo "$TIP_TEXT" | grep -qi "lock wildcard" && log_pass "Tip text contains 'lock wildcard'" || log_fail "Tip text: $TIP_TEXT"

            TIP_KBD=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-footer-tip\"] kbd')" 2>/dev/null)
            [ "$TIP_KBD" = "true" ] && log_pass "Tip has kbd-styled Ctrl key" || log_fail "Tip missing kbd element"

            # Simulate mouseleave
            agent-browser eval "document.querySelector('.pu-rp-wc-v').dispatchEvent(new MouseEvent('mouseleave', {bubbles: true}))" 2>/dev/null
            sleep 0.3

            TIP_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-footer-tip\"]').classList.contains('visible')" 2>/dev/null)
            [ "$TIP_VISIBLE" = "false" ] && log_pass "Tip hidden after mouse leave" || log_fail "Tip still visible after leave"
        else
            log_skip "No wildcard chips found (job has no wildcards)"
            log_skip "Skipping tip text check"
            log_skip "Skipping tip kbd check"
            log_skip "Skipping tip hide check"
        fi
    else
        log_skip "No prompts found in job"
        log_skip "Skipping tip text check"
        log_skip "Skipping tip kbd check"
        log_skip "Skipping tip hide check"
    fi
else
    log_skip "No jobs available"
    log_skip "Skipping tip text check"
    log_skip "Skipping tip kbd check"
    log_skip "Skipping tip hide check"
fi

# ============================================================================
# TEST 7: Shortcut keys have kbd styling (white text)
# ============================================================================
echo ""
log_info "TEST 7: Shortcut keys styling"

KBD_COLOR=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-footer kbd')).color" 2>/dev/null | tr -d '"')
# pu-text-primary = #ebebeb = rgb(235, 235, 235)
[ "$KBD_COLOR" = "rgb(235, 235, 235)" ] && log_pass "kbd keys are white (text-primary)" || log_fail "kbd color: $KBD_COLOR"

LABEL_COLOR=$(agent-browser eval "getComputedStyle(document.querySelector('.pu-footer-label')).color" 2>/dev/null | tr -d '"')
# pu-text-muted = #7a7a7a = rgb(122, 122, 122)
[ "$LABEL_COLOR" = "rgb(122, 122, 122)" ] && log_pass "Labels are gray (text-muted)" || log_fail "Label color: $LABEL_COLOR"

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
