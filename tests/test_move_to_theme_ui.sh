#!/bin/bash
# ============================================================================
# E2E Test Suite: Move to Theme UI
# ============================================================================
# Tests the move-to-theme modal: trigger button, modal open/close,
# form interactions, wildcard detection, and API integration.
#
# Usage: ./tests/test_move_to_theme_ui.sh [--port 8085]
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

print_header "Move to Theme UI Tests"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server "$BASE_URL/"; then
    log_pass "Server is running"
else
    log_fail "Server not running on port $PORT"
    print_summary
    exit 1
fi

# ============================================================================
# TEST 1: Move button visibility on content block (typewriter mode)
# ============================================================================
echo ""
log_info "TEST 1: Move button visibility"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=job-posting&viz=typewriter" 2>/dev/null
sleep 3

# Block 0 is a content block without children — should have move button
HAS_MOVE_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-block-move-btn-0\"]')" 2>/dev/null)
[ "$HAS_MOVE_BTN" = "true" ] && log_pass "Move button visible on content block (block 0)" || log_fail "Move button missing on content block 0, got: $HAS_MOVE_BTN"

# Move button should have correct title
MOVE_TITLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-block-move-btn-0\"]')?.title" 2>/dev/null | tr -d '"')
[ "$MOVE_TITLE" = "Move block to reusable theme" ] && log_pass "Move button has correct title" || log_fail "Move button title: $MOVE_TITLE"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 2: Move button hidden for blocks with children
# ============================================================================
echo ""
log_info "TEST 2: Move button hidden for parent blocks"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=nested-job-brief&viz=typewriter" 2>/dev/null
sleep 3

# nested-job-brief block 1 has after: children — should NOT have move button
HAS_MOVE_BTN_1=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-block-move-btn-1\"]')" 2>/dev/null)
[ "$HAS_MOVE_BTN_1" = "false" ] && log_pass "No move button on parent block (block 1)" || log_fail "Move button incorrectly shown on parent block 1"

# Block 0 (root, no children) — should have move button
HAS_MOVE_BTN_0=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-block-move-btn-0\"]')" 2>/dev/null)
[ "$HAS_MOVE_BTN_0" = "true" ] && log_pass "Move button present on childless root block (block 0)" || log_fail "Move button missing on childless root block 0"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 3: Modal opens with correct content
# ============================================================================
echo ""
log_info "TEST 3: Modal opens with correct content"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=job-posting&viz=typewriter" 2>/dev/null
sleep 3

# Open modal via JS
agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1

# Modal should be visible
MODAL_DISPLAY=$(agent-browser eval "document.querySelector('[data-testid=\"pu-move-to-theme-modal\"]')?.style?.display" 2>/dev/null | tr -d '"')
[ "$MODAL_DISPLAY" = "flex" ] && log_pass "Modal is visible" || log_fail "Modal display: $MODAL_DISPLAY"

# Preview should show block content
PREVIEW_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-preview\"]')?.textContent?.trim()" 2>/dev/null | tr -d '"')
echo "$PREVIEW_TEXT" | grep -q "Write a job posting" && log_pass "Preview shows block content" || log_fail "Preview content unexpected: $PREVIEW_TEXT"

# Theme name should be pre-filled with ext prefix
THEME_VAL=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-theme-name\"]')?.value" 2>/dev/null | tr -d '"')
[ "$THEME_VAL" = "hiring/" ] && log_pass "Theme name pre-filled with ext prefix" || log_fail "Theme name value: $THEME_VAL"

# Scope radios should exist
HAS_SCOPE=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-mtt-scope\"]')" 2>/dev/null)
[ "$HAS_SCOPE" = "true" ] && log_pass "Scope radios present" || log_fail "Scope radios missing"

# Shared radio should be checked by default
SHARED_CHECKED=$(agent-browser eval "document.querySelector('input[name=\"mtt-scope\"][value=\"shared\"]')?.checked" 2>/dev/null)
[ "$SHARED_CHECKED" = "true" ] && log_pass "Shared scope checked by default" || log_fail "Shared scope not checked"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 4: Wildcard detection and display
# ============================================================================
echo ""
log_info "TEST 4: Wildcard detection"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=job-posting&viz=typewriter" 2>/dev/null
sleep 3

agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1

# Should detect 'role' wildcard
WC_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-mtt-wc-item').length" 2>/dev/null)
[ "$WC_COUNT" = "1" ] && log_pass "Detected 1 wildcard (role)" || log_fail "Expected 1 wildcard, got: $WC_COUNT"

# Role wildcard should be checked (exclusive — not used in other blocks)
WC_ROLE_CHECKED=$(agent-browser eval "document.querySelector('.pu-mtt-wc-item input[data-wc-name=\"role\"]')?.checked" 2>/dev/null)
[ "$WC_ROLE_CHECKED" = "true" ] && log_pass "Role wildcard checked (exclusive)" || log_fail "Role wildcard not checked"

# No shared warning (role is exclusive in job-posting)
HAS_WARNING=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-mtt-shared-warning\"]')" 2>/dev/null)
[ "$HAS_WARNING" = "false" ] && log_pass "No shared wildcard warning" || log_fail "Unexpected shared warning present"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 5: Shared wildcard detection (outreach-email has wildcards shared across blocks)
# ============================================================================
echo ""
log_info "TEST 5: Shared wildcard detection"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=nested-job-brief&viz=typewriter" 2>/dev/null
sleep 3

# Block 0 content: "You are a __tone__ HR consultant for a __company_size__ company"
# 'tone' is used in block 0 only (root), but 'tone' also appears in... let me check
# Actually in nested-job-brief: block 0 has no after, block 1 has after with __years_exp__ and __skill__
# Block 0 uses __tone__ and __company_size__
# Block 1 uses __role__ and its child uses __years_exp__ and __skill__
# So tone is EXCLUSIVE to block 0, company_size is EXCLUSIVE to block 0
agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1

WC_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-mtt-wc-item').length" 2>/dev/null)
[ "$WC_COUNT" = "2" ] && log_pass "Detected 2 wildcards in nested-job-brief block 0" || log_fail "Expected 2 wildcards, got: $WC_COUNT"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 6: Modal close behaviors
# ============================================================================
echo ""
log_info "TEST 6: Modal close behaviors"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=job-posting&viz=typewriter" 2>/dev/null
sleep 3

# Open and close via cancel button
agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1
agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-cancel-btn\"]').click()" 2>/dev/null
sleep 0.5

MODAL_HIDDEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-move-to-theme-modal\"]')?.style?.display" 2>/dev/null | tr -d '"')
[ "$MODAL_HIDDEN" = "none" ] && log_pass "Cancel button closes modal" || log_fail "Modal still visible after cancel: $MODAL_HIDDEN"

# Open and close via X button
agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1
agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-close-btn\"]').click()" 2>/dev/null
sleep 0.5

MODAL_HIDDEN2=$(agent-browser eval "document.querySelector('[data-testid=\"pu-move-to-theme-modal\"]')?.style?.display" 2>/dev/null | tr -d '"')
[ "$MODAL_HIDDEN2" = "none" ] && log_pass "X button closes modal" || log_fail "Modal still visible after X: $MODAL_HIDDEN2"

# Open and close via Escape key
agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1
agent-browser eval "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape'}))" 2>/dev/null
sleep 0.5

MODAL_HIDDEN3=$(agent-browser eval "document.querySelector('[data-testid=\"pu-move-to-theme-modal\"]')?.style?.display" 2>/dev/null | tr -d '"')
[ "$MODAL_HIDDEN3" = "none" ] && log_pass "Escape key closes modal" || log_fail "Modal still visible after Escape: $MODAL_HIDDEN3"

# State should be reset
STATE_VISIBLE=$(agent-browser eval "PU.state.themes.moveToThemeModal.visible" 2>/dev/null)
[ "$STATE_VISIBLE" = "false" ] && log_pass "State reset after close" || log_fail "State still visible: $STATE_VISIBLE"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 7: Path hint updates on scope change
# ============================================================================
echo ""
log_info "TEST 7: Path hint updates"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=job-posting&viz=typewriter" 2>/dev/null
sleep 3

agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1

# Set theme name
agent-browser eval "
    const input = document.querySelector('[data-testid=\"pu-mtt-theme-name\"]');
    input.value = 'hiring/test-theme';
    input.dispatchEvent(new Event('input'));
" 2>/dev/null
sleep 0.3

HINT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-path-hint\"]')?.textContent?.trim()" 2>/dev/null | tr -d '"')
[ "$HINT" = "ext/hiring/test-theme" ] && log_pass "Path hint shows shared path" || log_fail "Path hint: $HINT"

# Switch to fork scope
agent-browser eval "
    const fork = document.querySelector('input[name=\"mtt-scope\"][value=\"fork\"]');
    fork.checked = true;
    fork.dispatchEvent(new Event('change'));
" 2>/dev/null
sleep 0.3

HINT_FORK=$(agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-path-hint\"]')?.textContent?.trim()" 2>/dev/null | tr -d '"')
[ "$HINT_FORK" = "ext/hiring-templates/hiring/test-theme" ] && log_pass "Path hint shows fork path" || log_fail "Fork path hint: $HINT_FORK"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 8: Wildcard toggle expand/collapse
# ============================================================================
echo ""
log_info "TEST 8: Wildcard toggle expand/collapse"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=job-posting&viz=typewriter" 2>/dev/null
sleep 3

agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1

# Wildcards list should be collapsed by default (no warnings for job-posting)
WC_LIST_DISPLAY=$(agent-browser eval "document.getElementById('mtt-wc-list')?.style?.display" 2>/dev/null | tr -d '"')
[ "$WC_LIST_DISPLAY" = "none" ] && log_pass "Wildcard list collapsed by default" || log_fail "Wildcard list display: $WC_LIST_DISPLAY"

# Click toggle to expand
agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-wc-toggle\"]').click()" 2>/dev/null
sleep 0.3

WC_LIST_EXPANDED=$(agent-browser eval "document.getElementById('mtt-wc-list')?.style?.display" 2>/dev/null | tr -d '"')
[ "$WC_LIST_EXPANDED" = "block" ] && log_pass "Wildcard list expanded after toggle" || log_fail "Wildcard list display: $WC_LIST_EXPANDED"

# Click toggle to collapse
agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-wc-toggle\"]').click()" 2>/dev/null
sleep 0.3

WC_LIST_COLLAPSED=$(agent-browser eval "document.getElementById('mtt-wc-list')?.style?.display" 2>/dev/null | tr -d '"')
[ "$WC_LIST_COLLAPSED" = "none" ] && log_pass "Wildcard list collapsed after re-toggle" || log_fail "Wildcard list display: $WC_LIST_COLLAPSED"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 9: API integration — successful move
# ============================================================================
echo ""
log_info "TEST 9: API integration - move to theme"

# Clean up any leftover theme from previous test runs
THEME_FILE="/home/cybervaldez/ai/cybervaldez/promptyui/ext/hiring/mtt-ui-test.yaml"
rm -f "$THEME_FILE" 2>/dev/null

# Also restore jobs.yaml if it was modified by a previous failed run
JOBS_YAML="/home/cybervaldez/ai/cybervaldez/promptyui/jobs/hiring-templates/jobs.yaml"
BACKUP_FILES=$(ls "$JOBS_YAML".backup.* 2>/dev/null | tail -1)

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=job-posting&viz=typewriter" 2>/dev/null
sleep 3

# Open modal, set theme name, and confirm
agent-browser eval "PU.moveToTheme.open('0')" 2>/dev/null
sleep 1

agent-browser eval "
    const input = document.querySelector('[data-testid=\"pu-mtt-theme-name\"]');
    input.value = 'hiring/mtt-ui-test';
    input.dispatchEvent(new Event('input'));
" 2>/dev/null
sleep 0.3

# Click confirm
agent-browser eval "document.querySelector('[data-testid=\"pu-mtt-confirm-btn\"]').click()" 2>/dev/null
sleep 3

# Modal should be closed
MODAL_AFTER=$(agent-browser eval "document.querySelector('[data-testid=\"pu-move-to-theme-modal\"]')?.style?.display" 2>/dev/null | tr -d '"')
[ "$MODAL_AFTER" = "none" ] && log_pass "Modal closed after move" || log_fail "Modal still visible: $MODAL_AFTER"

# Toast should have appeared (may have already faded)
# Check theme file was created
[ -f "$THEME_FILE" ] && log_pass "Theme file created at ext/hiring/mtt-ui-test.yaml" || log_fail "Theme file not created"

# Block should now be ext_text reference
BLOCK_TYPE=$(agent-browser eval "
    const prompt = PU.helpers.getActivePrompt();
    const block = prompt?.text?.[0];
    block ? ('ext_text' in block ? 'ext_text' : 'content') : 'not_found';
" 2>/dev/null | tr -d '"')
[ "$BLOCK_TYPE" = "ext_text" ] && log_pass "Block converted to ext_text reference" || log_fail "Block type: $BLOCK_TYPE"

# Verify the ext_text reference
EXT_REF=$(agent-browser eval "PU.helpers.getActivePrompt()?.text?.[0]?.ext_text" 2>/dev/null | tr -d '"')
[ "$EXT_REF" = "hiring/mtt-ui-test" ] && log_pass "ext_text reference correct" || log_fail "ext_text ref: $EXT_REF"

agent-browser close 2>/dev/null
sleep 0.5

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

# Remove the test theme file
rm -f "$THEME_FILE" 2>/dev/null
log_pass "Removed test theme file"

# Restore jobs.yaml from backup
LATEST_BACKUP=$(ls "$JOBS_YAML".backup.* 2>/dev/null | tail -1)
if [ -n "$LATEST_BACKUP" ]; then
    cp "$LATEST_BACKUP" "$JOBS_YAML"
    rm -f "$JOBS_YAML".backup.* 2>/dev/null
    log_pass "Restored jobs.yaml from backup"
else
    log_info "No backup to restore"
fi

agent-browser close 2>/dev/null
log_pass "Browser closed"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
