#!/bin/bash
# ============================================================================
# E2E Test Suite: Right Panel Annotations Tab
# ============================================================================
# Tests the tab strip (Wildcards | Annotations) in the right panel,
# the annotations overview hierarchy, and click-to-scroll behavior.
#
# Usage: ./tests/test_annotations_tab.sh [--port 8085]
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

print_header "Right Panel Annotations Tab"

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

# Open the test fixture with nested-blocks prompt (has annotations)
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: Tab strip exists in DOM
# ============================================================================
echo ""
log_info "TEST 1: Tab strip exists in DOM"

HAS_STRIP=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-tab-strip\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_STRIP" = "true" ] && log_pass "Tab strip exists" || log_fail "Tab strip missing"

# ============================================================================
# TEST 2: Both tabs exist
# ============================================================================
echo ""
log_info "TEST 2: Both tabs exist"

HAS_WC_TAB=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-tab-wildcards\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_WC_TAB" = "true" ] && log_pass "Wildcards tab exists" || log_fail "Wildcards tab missing"

HAS_ANN_TAB=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-tab-annotations\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_ANN_TAB" = "true" ] && log_pass "Annotations tab exists" || log_fail "Annotations tab missing"

# ============================================================================
# TEST 3: Wildcards tab is active by default
# ============================================================================
echo ""
log_info "TEST 3: Wildcards tab active by default"

WC_ACTIVE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-wildcards\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$WC_ACTIVE" = "true" ] && log_pass "Wildcards tab active" || log_fail "Wildcards tab not active"

WC_PANE_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-pane-wildcards\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$WC_PANE_VISIBLE" = "true" ] && log_pass "Wildcards pane visible" || log_fail "Wildcards pane not visible"

ANN_PANE_HIDDEN=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-rp-tab-pane-annotations\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$ANN_PANE_HIDDEN" = "true" ] && log_pass "Annotations pane hidden" || log_fail "Annotations pane not hidden"

# ============================================================================
# TEST 4: Switch to annotations tab
# ============================================================================
echo ""
log_info "TEST 4: Switch to annotations tab"

agent-browser eval "PU.rightPanel.switchTab('annotations')" 2>/dev/null
sleep 0.5

ANN_ACTIVE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-annotations\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$ANN_ACTIVE" = "true" ] && log_pass "Annotations tab now active" || log_fail "Annotations tab not active"

WC_INACTIVE=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-rp-tab-wildcards\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$WC_INACTIVE" = "true" ] && log_pass "Wildcards tab now inactive" || log_fail "Wildcards tab still active"

ANN_PANE_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-pane-annotations\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$ANN_PANE_VISIBLE" = "true" ] && log_pass "Annotations pane now visible" || log_fail "Annotations pane still hidden"

# ============================================================================
# TEST 5: Annotations tab has hierarchy sections
# ============================================================================
echo ""
log_info "TEST 5: Annotations tab has hierarchy sections"

HAS_DEFAULTS=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-ann-section-defaults\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_DEFAULTS" = "true" ] && log_pass "Defaults section exists" || log_fail "Defaults section missing"

HAS_PROMPT=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-ann-section-prompt\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_PROMPT" = "true" ] && log_pass "Prompt section exists" || log_fail "Prompt section missing"

# ============================================================================
# TEST 6: Defaults section shows annotations from job defaults
# ============================================================================
echo ""
log_info "TEST 6: Defaults section content"

# test-fixtures has defaults.annotations: quality: strict, audience: general
DEFAULTS_BODY=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-ann-body-defaults\"]')?.innerHTML || ''" 2>/dev/null | tr -d '"')
echo "$DEFAULTS_BODY" | grep -q "quality" && log_pass "Defaults: quality key present" || log_fail "Defaults: quality key missing"
echo "$DEFAULTS_BODY" | grep -q "audience" && log_pass "Defaults: audience key present" || log_fail "Defaults: audience key missing"

# ============================================================================
# TEST 7: Prompt section shows prompt-level annotations
# ============================================================================
echo ""
log_info "TEST 7: Prompt section content"

# nested-blocks prompt has annotations: audience: technical
PROMPT_BODY=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-ann-body-prompt\"]')?.innerHTML || ''" 2>/dev/null | tr -d '"')
echo "$PROMPT_BODY" | grep -q "audience" && log_pass "Prompt: audience key present" || log_fail "Prompt: audience key missing"

# ============================================================================
# TEST 8: Block sections exist for blocks with annotations
# ============================================================================
echo ""
log_info "TEST 8: Block sections for annotated blocks"

# Block 0 (root) has annotations: quality: null, tone: conversational, _comment, _priority, _draft
HAS_BLOCK_0=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-ann-section-block-0\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_BLOCK_0" = "true" ] && log_pass "Block 0 section exists" || log_fail "Block 0 section missing"

# ============================================================================
# TEST 9: Block section shows resolved annotations with sources
# ============================================================================
echo ""
log_info "TEST 9: Resolved annotations with source labels"

BLOCK_0_BODY=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-ann-body-block-0\"]')?.innerHTML || ''" 2>/dev/null | tr -d '"')

# Should have tone annotation with source = block
echo "$BLOCK_0_BODY" | grep -q "tone" && log_pass "Block 0: tone present" || log_fail "Block 0: tone missing"

# Should have _comment with source = block
echo "$BLOCK_0_BODY" | grep -q "_comment" && log_pass "Block 0: _comment present" || log_fail "Block 0: _comment missing"

# ============================================================================
# TEST 10: Block section has scroll-to-block link
# ============================================================================
echo ""
log_info "TEST 10: Scroll-to-block links"

HAS_SCROLL_LINK=$(agent-browser eval "!!document.querySelector('[data-scroll-to-block=\"0\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_SCROLL_LINK" = "true" ] && log_pass "Block 0 scroll link exists" || log_fail "Block 0 scroll link missing"

# ============================================================================
# TEST 11: Switch back to wildcards tab
# ============================================================================
echo ""
log_info "TEST 11: Switch back to wildcards tab"

agent-browser eval "PU.rightPanel.switchTab('wildcards')" 2>/dev/null
sleep 0.5

WC_ACTIVE_AGAIN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-wildcards\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$WC_ACTIVE_AGAIN" = "true" ] && log_pass "Wildcards tab active again" || log_fail "Wildcards tab not active"

WC_PANE_VISIBLE_AGAIN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-pane-wildcards\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$WC_PANE_VISIBLE_AGAIN" = "true" ] && log_pass "Wildcards pane visible again" || log_fail "Wildcards pane not visible"

# ============================================================================
# TEST 12: Prompt annotations bar location and wildcard pane content
# ============================================================================
echo ""
log_info "TEST 12: Prompt annotations bar in annotations pane, not wildcards"

HAS_WC_STREAM=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-wc-stream\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_WC_STREAM" = "true" ] && log_pass "Wildcard stream exists in wildcards pane" || log_fail "Wildcard stream missing"

# Prompt annotations bar should NOT be in the wildcards pane
BAR_IN_WC=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-tab-pane-wildcards\"] [data-testid=\"pu-rp-prompt-ann\"]')" 2>/dev/null | tr -d '"')
[ "$BAR_IN_WC" = "false" ] && log_pass "Prompt annotations bar NOT in wildcards pane" || log_fail "Prompt annotations bar still in wildcards pane"

# Prompt annotations bar should BE in the annotations pane
BAR_IN_ANN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-tab-pane-annotations\"] [data-testid=\"pu-rp-prompt-ann\"]')" 2>/dev/null | tr -d '"')
[ "$BAR_IN_ANN" = "true" ] && log_pass "Prompt annotations bar IS in annotations pane" || log_fail "Prompt annotations bar missing from annotations pane"

# Bar should be functional (can toggle open/close)
agent-browser eval "PU.rightPanel.switchTab('annotations')" 2>/dev/null
sleep 0.3
HAS_PROMPT_ANN_BAR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-prompt-ann\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_PROMPT_ANN_BAR" = "true" ] && log_pass "Prompt annotations bar exists and accessible" || log_fail "Prompt annotations bar missing"

# Switch back to wildcards for subsequent tests
agent-browser eval "PU.rightPanel.switchTab('wildcards')" 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 13: Compositions footer stays visible across both tabs
# ============================================================================
echo ""
log_info "TEST 13: Compositions footer visible across tabs"

# Check footer visible on wildcards tab
HAS_OPS=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-ops-section\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_OPS" = "true" ] && log_pass "Compositions footer on wildcards tab" || log_fail "Compositions footer missing on wildcards tab"

# Switch to annotations and check
agent-browser eval "PU.rightPanel.switchTab('annotations')" 2>/dev/null
sleep 0.3

HAS_OPS_ANN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-ops-section\"]')" 2>/dev/null | tr -d '"')
[ "$HAS_OPS_ANN" = "true" ] && log_pass "Compositions footer on annotations tab" || log_fail "Compositions footer missing on annotations tab"

# ============================================================================
# TEST 14: Section collapsibility
# ============================================================================
echo ""
log_info "TEST 14: Section collapsibility"

# Click to collapse the defaults section
agent-browser eval "document.querySelector('[data-testid=\"pu-rp-ann-section-defaults\"] .pu-rp-ann-section-header').click()" 2>/dev/null
sleep 0.3

IS_COLLAPSED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-ann-section-defaults\"]').classList.contains('collapsed')" 2>/dev/null | tr -d '"')
[ "$IS_COLLAPSED" = "true" ] && log_pass "Defaults section collapsed" || log_fail "Defaults section not collapsed"

# Click again to expand
agent-browser eval "document.querySelector('[data-testid=\"pu-rp-ann-section-defaults\"] .pu-rp-ann-section-header').click()" 2>/dev/null
sleep 0.3

IS_EXPANDED=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-rp-ann-section-defaults\"]').classList.contains('collapsed')" 2>/dev/null | tr -d '"')
[ "$IS_EXPANDED" = "true" ] && log_pass "Defaults section expanded" || log_fail "Defaults section not expanded"

# ============================================================================
# TEST 15: State object tracks active tab
# ============================================================================
echo ""
log_info "TEST 15: State tracks active tab"

ACTIVE_TAB=$(agent-browser eval "PU.state.ui.rightPanelTab" 2>/dev/null | tr -d '"')
[ "$ACTIVE_TAB" = "annotations" ] && log_pass "State: rightPanelTab = annotations" || log_fail "State: rightPanelTab = $ACTIVE_TAB"

agent-browser eval "PU.rightPanel.switchTab('wildcards')" 2>/dev/null
sleep 0.3

ACTIVE_TAB_2=$(agent-browser eval "PU.state.ui.rightPanelTab" 2>/dev/null | tr -d '"')
[ "$ACTIVE_TAB_2" = "wildcards" ] && log_pass "State: rightPanelTab = wildcards after switch" || log_fail "State: rightPanelTab = $ACTIVE_TAB_2"

# ============================================================================
# TEST 16: Null overrides shown as removed
# ============================================================================
echo ""
log_info "TEST 16: Null overrides shown as removed"

# Block 0 has quality: null (removes defaults.annotations.quality)
agent-browser eval "PU.rightPanel.switchTab('annotations')" 2>/dev/null
sleep 0.3

BLOCK_0_HTML=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-ann-body-block-0\"]')?.innerHTML || ''" 2>/dev/null | tr -d '"')
echo "$BLOCK_0_HTML" | grep -q "removed" && log_pass "Null override shown as removed" || log_fail "Null override not shown"

# ============================================================================
# TEST 17: Annotations tab shows count badge
# ============================================================================
echo ""
log_info "TEST 17: Annotations tab count badge"

# Tab should show "Annotations (N)" where N > 0
ANN_TAB_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-annotations\"]').textContent" 2>/dev/null | tr -d '"')
echo "$ANN_TAB_TEXT" | grep -qE 'Annotations \([0-9]+\)' && log_pass "Tab shows count: $ANN_TAB_TEXT" || log_fail "Tab missing count badge: $ANN_TAB_TEXT"

# Count should be > 0 (test-fixtures has defaults:2 + prompt:1 + block:5 = 8)
ANN_COUNT=$(echo "$ANN_TAB_TEXT" | grep -oE '[0-9]+')
[ -n "$ANN_COUNT" ] && [ "$ANN_COUNT" -gt 0 ] && log_pass "Count is positive: $ANN_COUNT" || log_fail "Count not positive: $ANN_COUNT"

# ============================================================================
# TEST 18: Tab selection persists via localStorage
# ============================================================================
echo ""
log_info "TEST 18: Tab persistence via localStorage"

# Currently on annotations tab (from test 16). Verify state was saved.
SAVED_TAB=$(agent-browser eval "JSON.parse(localStorage.getItem('pu_ui_state') || '{}').rightPanelTab" 2>/dev/null | head -1 | tr -d '"')
[ "$SAVED_TAB" = "annotations" ] && log_pass "localStorage has rightPanelTab = annotations" || log_fail "localStorage rightPanelTab = $SAVED_TAB"

# Switch to wildcards and verify it updates localStorage
agent-browser eval "PU.rightPanel.switchTab('wildcards')" 2>/dev/null
sleep 0.3

SAVED_TAB_2=$(agent-browser eval "JSON.parse(localStorage.getItem('pu_ui_state') || '{}').rightPanelTab" 2>/dev/null | head -1 | tr -d '"')
[ "$SAVED_TAB_2" = "wildcards" ] && log_pass "localStorage updated to wildcards" || log_fail "localStorage not updated: $SAVED_TAB_2"

# Simulate page reload and check tab is restored
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# After reload with wildcards saved, wildcards tab should be active
WC_ACTIVE_RELOAD=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-wildcards\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$WC_ACTIVE_RELOAD" = "true" ] && log_pass "Wildcards tab active after reload" || log_fail "Wildcards tab not active after reload"

# Now switch to annotations, save, and reload to verify annotations persists
agent-browser eval "PU.rightPanel.switchTab('annotations')" 2>/dev/null
sleep 0.5

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

ANN_ACTIVE_RELOAD=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-tab-annotations\"]').classList.contains('active')" 2>/dev/null | tr -d '"')
[ "$ANN_ACTIVE_RELOAD" = "true" ] && log_pass "Annotations tab restored after reload" || log_fail "Annotations tab not restored after reload"

# Reset back to wildcards for clean state
agent-browser eval "PU.rightPanel.switchTab('wildcards')" 2>/dev/null
sleep 0.3

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
