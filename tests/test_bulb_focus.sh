#!/bin/bash
# ============================================================================
# E2E Test Suite: Bulb Focus Mode
# ============================================================================
# Tests bulb (illuminate) feature: recursive block count, hover preview
# over active focus, preview mode bulb integration, placeholder text.
#
# Usage: ./tests/test_bulb_focus.sh [--port 8085]
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

print_header "Bulb Focus Mode Tests"

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

# ============================================================================
# TEST 1: Bulb icons appear on nested-blocks prompt (1 root + children)
# ============================================================================
echo ""
log_info "TEST 1: Bulb visible on nested prompt (recursive count)"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 2

# nested-blocks has 1 root block with nested children → total blocks >= 2
BULB_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-wc-focus-icon").length' 2>/dev/null)
[ "$BULB_COUNT" -ge 1 ] 2>/dev/null && log_pass "Bulb icons visible on nested prompt ($BULB_COUNT found)" || log_fail "No bulb icons on nested prompt (count: $BULB_COUNT)"

# Verify recursive count helper
TOTAL_BLOCKS=$(agent-browser eval 'PU.rightPanel._countAllBlocks(PU.helpers.getActivePrompt()?.text)' 2>/dev/null)
[ "$TOTAL_BLOCKS" -ge 2 ] 2>/dev/null && log_pass "Recursive block count = $TOTAL_BLOCKS (>= 2)" || log_fail "Recursive count: $TOTAL_BLOCKS"

# ============================================================================
# TEST 2: Bulb focus works on multi-block prompt
# ============================================================================
echo ""
log_info "TEST 2: Bulb focus on stress-test-prompt"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt" 2>/dev/null
sleep 3

# Click bulb for "seniority" (maps to blocks 1, 1.0)
agent-browser eval 'document.querySelector("[data-testid=\"pu-wc-focus-seniority\"]")?.click()' 2>/dev/null
sleep 0.5

FOCUSED=$(agent-browser eval 'JSON.stringify(PU.state.previewMode.focusedWildcards)' 2>/dev/null)
echo "$FOCUSED" | grep -q "seniority" && log_pass "Seniority added to focusedWildcards" || log_fail "Focus state: $FOCUSED"

HIDDEN=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-focus-hidden").length' 2>/dev/null)
[ "$HIDDEN" -ge 1 ] 2>/dev/null && log_pass "Non-matching blocks hidden ($HIDDEN)" || log_fail "No blocks hidden"

HAS_MATCH=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-highlight-match").length' 2>/dev/null)
[ "$HAS_MATCH" -ge 1 ] 2>/dev/null && log_pass "Matching blocks highlighted ($HAS_MATCH)" || log_fail "No matching blocks"

# ============================================================================
# TEST 3: Hover preview while focus active
# ============================================================================
echo ""
log_info "TEST 3: Hover preview over non-focused wildcard"

# Hover over "section" entry (not focused) — should show preview classes
agent-browser eval '
    const entry = document.querySelector("[data-testid=\"pu-rp-wc-entry-section\"]");
    if (entry) entry.dispatchEvent(new MouseEvent("mouseenter", {bubbles: true}));
' 2>/dev/null
sleep 0.3

PREVIEW_MATCH=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-hover-preview-match").length' 2>/dev/null)
[ "$PREVIEW_MATCH" -ge 1 ] 2>/dev/null && log_pass "Hover preview shows additional blocks ($PREVIEW_MATCH)" || log_fail "No hover preview blocks (count: $PREVIEW_MATCH)"

# Mouseleave should clear preview
agent-browser eval '
    const entry = document.querySelector("[data-testid=\"pu-rp-wc-entry-section\"]");
    if (entry) entry.dispatchEvent(new MouseEvent("mouseleave", {bubbles: true}));
' 2>/dev/null
sleep 0.3

PREVIEW_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-hover-preview-match").length' 2>/dev/null)
[ "$PREVIEW_AFTER" = "0" ] && log_pass "Hover preview cleared on mouseleave" || log_fail "Preview still showing: $PREVIEW_AFTER"

# Clear focus for next tests
agent-browser eval 'PU.rightPanel.clearFocus()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 4: Preview mode — bulb icons in sidebar
# ============================================================================
echo ""
log_info "TEST 4: Preview mode bulb icons"

agent-browser eval "PU.editorMode.setPreset('preview')" 2>/dev/null
sleep 1

# Check bulb icons in preview sidebar
PREVIEW_BULBS=$(agent-browser eval 'document.querySelectorAll("[data-testid^=\"pu-preview-focus-\"]").length' 2>/dev/null)
[ "$PREVIEW_BULBS" -ge 1 ] 2>/dev/null && log_pass "Bulb icons in preview sidebar ($PREVIEW_BULBS)" || log_fail "No bulb icons in preview sidebar"

# ============================================================================
# TEST 5: Preview mode — bulb click dims non-matching blocks
# ============================================================================
echo ""
log_info "TEST 5: Preview mode bulb dims blocks"

# Click bulb for "seniority" in preview sidebar
agent-browser eval 'document.querySelector("[data-testid=\"pu-preview-focus-seniority\"]")?.click()' 2>/dev/null
sleep 0.5

DIMMED=$(agent-browser eval 'document.querySelectorAll(".pu-preview-block.pu-preview-focus-dimmed").length' 2>/dev/null)
[ "$DIMMED" -ge 1 ] 2>/dev/null && log_pass "Non-matching preview blocks dimmed ($DIMMED)" || log_fail "No dimmed blocks: $DIMMED"

MATCH_BLOCKS=$(agent-browser eval 'document.querySelectorAll(".pu-preview-block.pu-preview-focus-match").length' 2>/dev/null)
[ "$MATCH_BLOCKS" -ge 1 ] 2>/dev/null && log_pass "Matching preview blocks highlighted ($MATCH_BLOCKS)" || log_fail "No match blocks: $MATCH_BLOCKS"

# ============================================================================
# TEST 6: Preview mode — focus banner in preview content
# ============================================================================
echo ""
log_info "TEST 6: Preview focus banner"

HAS_BANNER=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-preview-focus-banner\"]")' 2>/dev/null)
[ "$HAS_BANNER" = "true" ] && log_pass "Preview focus banner visible" || log_fail "No preview focus banner"

BANNER_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-preview-focus-banner\"]")?.textContent || ""' 2>/dev/null)
echo "$BANNER_TEXT" | grep -q "seniority" && log_pass "Banner shows focused wildcard name" || log_fail "Banner text: $BANNER_TEXT"

# ============================================================================
# TEST 7: Preview mode — clear focus via banner close button
# ============================================================================
echo ""
log_info "TEST 7: Clear preview focus"

agent-browser eval 'document.querySelector("[data-testid=\"pu-preview-focus-banner-close\"]")?.click()' 2>/dev/null
sleep 0.5

FOCUSED_AFTER=$(agent-browser eval 'PU.state.previewMode.focusedWildcards.length' 2>/dev/null)
[ "$FOCUSED_AFTER" = "0" ] && log_pass "Focus cleared after banner close" || log_fail "Focus not cleared: $FOCUSED_AFTER"

NO_DIMMED=$(agent-browser eval 'document.querySelectorAll(".pu-preview-block.pu-preview-focus-dimmed").length' 2>/dev/null)
[ "$NO_DIMMED" = "0" ] && log_pass "No dimmed blocks after clear" || log_fail "Still dimmed: $NO_DIMMED"

# ============================================================================
# TEST 8: Block tree + bulb compose with AND logic
# ============================================================================
echo ""
log_info "TEST 8: Block tree + bulb AND composition"

# Hide block 0 via tree, then focus on "persona" (which maps to block 0)
agent-browser eval "PU.editorMode.toggleBlockVisibility('0', true)" 2>/dev/null
sleep 0.3
agent-browser eval "PU.editorMode.togglePreviewFocus('persona')" 2>/dev/null
sleep 0.5

# Block 0 is hidden by tree AND matches focus — should NOT appear
BLOCK_0_HIDDEN=$(agent-browser eval '!document.querySelector(".pu-preview-block[data-path=\"0\"]")' 2>/dev/null)
[ "$BLOCK_0_HIDDEN" = "true" ] && log_pass "Block hidden by tree stays hidden even when focused" || log_fail "Hidden block appeared when focused"

# Cleanup
agent-browser eval "PU.editorMode.toggleBlockVisibility('0', false)" 2>/dev/null
agent-browser eval "PU.editorMode.clearPreviewFocus()" 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 9: Placeholder text doesn't say "preview"
# ============================================================================
echo ""
log_info "TEST 9: Placeholder text cleanup"

# Switch to write mode and check initial placeholder
agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.5

# Check index.html placeholder via source
PLACEHOLDER=$(agent-browser eval 'document.querySelector(".pu-preview-body .pu-rp-note")?.textContent || ""' 2>/dev/null | tr -d '"')
if [ -n "$PLACEHOLDER" ]; then
    echo "$PLACEHOLDER" | grep -qi "preview" && log_fail "Placeholder still says 'preview': $PLACEHOLDER" || log_pass "Placeholder text clean"
else
    log_pass "No placeholder visible (prompt loaded)"
fi

# ============================================================================
# TEST 10: Hover preview shows parent blocks for nested wildcards
# ============================================================================
echo ""
log_info "TEST 10: Hover preview shows parents for nested match"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt" 2>/dev/null
sleep 3

# Focus on "persona" (block 0), then hover over "metric" (block 1.0 — child of block 1)
agent-browser eval 'document.querySelector("[data-testid=\"pu-wc-focus-persona\"]")?.click()' 2>/dev/null
sleep 0.5

agent-browser eval '
    const entry = document.querySelector("[data-testid=\"pu-rp-wc-entry-metric\"]");
    if (entry) entry.dispatchEvent(new MouseEvent("mouseenter", {bubbles: true}));
' 2>/dev/null
sleep 0.3

# "metric" maps to block 1.0 — parent block 1 should get preview-parent class
PREVIEW_PARENT=$(agent-browser eval 'document.querySelectorAll(".pu-block.pu-hover-preview-parent").length' 2>/dev/null)
[ "$PREVIEW_PARENT" -ge 1 ] 2>/dev/null && log_pass "Parent blocks shown in hover preview ($PREVIEW_PARENT)" || log_fail "No parent preview blocks: $PREVIEW_PARENT"

# Clear
agent-browser eval '
    const entry = document.querySelector("[data-testid=\"pu-rp-wc-entry-metric\"]");
    if (entry) entry.dispatchEvent(new MouseEvent("mouseleave", {bubbles: true}));
' 2>/dev/null
agent-browser eval 'PU.rightPanel.clearFocus()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 11: Preview mode — child hover highlights parent connector + tree connector
# ============================================================================
echo ""
log_info "TEST 11: Preview child hover highlights connectors"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks&editorMode=preview" 2>/dev/null
sleep 3

# Find a child preview block (depth > 1) and hover it
HAS_CHILD=$(agent-browser eval 'document.querySelectorAll(".pu-preview-child").length' 2>/dev/null)
[ "$HAS_CHILD" -ge 1 ] 2>/dev/null && log_pass "Child preview blocks found ($HAS_CHILD)" || log_fail "No child preview blocks"

# Hover the first child block
agent-browser eval '
    const child = document.querySelector(".pu-preview-child");
    if (child) child.dispatchEvent(new MouseEvent("mouseenter", {bubbles: true}));
' 2>/dev/null
sleep 0.3

# Check tree connector got orange highlight class
TREE_HOVER=$(agent-browser eval 'document.querySelectorAll(".pu-tree-connector.pu-tree-hover").length' 2>/dev/null)
[ "$TREE_HOVER" -ge 1 ] 2>/dev/null && log_pass "Tree connector highlighted on child hover ($TREE_HOVER)" || log_fail "No tree connector highlight: $TREE_HOVER"

# Check parent block got child-hovered class
PARENT_HOVER=$(agent-browser eval 'document.querySelectorAll(".pu-preview-child-hovered").length' 2>/dev/null)
[ "$PARENT_HOVER" -ge 1 ] 2>/dev/null && log_pass "Parent block highlighted on child hover ($PARENT_HOVER)" || log_fail "No parent highlight: $PARENT_HOVER"

# Mouseleave should clear
agent-browser eval '
    const child = document.querySelector(".pu-preview-child");
    if (child) child.dispatchEvent(new MouseEvent("mouseleave", {bubbles: true}));
' 2>/dev/null
sleep 0.3

TREE_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-tree-connector.pu-tree-hover").length' 2>/dev/null)
[ "$TREE_AFTER" = "0" ] && log_pass "Tree connector highlight cleared on mouseleave" || log_fail "Tree highlight still showing: $TREE_AFTER"

PARENT_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-preview-child-hovered").length' 2>/dev/null)
[ "$PARENT_AFTER" = "0" ] && log_pass "Parent highlight cleared on mouseleave" || log_fail "Parent highlight still showing: $PARENT_AFTER"

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
