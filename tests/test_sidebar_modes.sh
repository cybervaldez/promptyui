#!/bin/bash
# ============================================================================
# E2E Test Suite: Mode-Aware Sidebar
# ============================================================================
# Tests right panel content swap per editor mode (Write/Preview/Review),
# sidebar preview composition values, ops section variants, URL params,
# and PU.debug.sidebar() API.
#
# Usage: ./tests/test_sidebar_modes.sh [--port 8085]
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

print_header "Mode-Aware Sidebar Tests"

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
# TEST 1: Sidebar containers exist
# ============================================================================
echo ""
log_info "TEST 1: Sidebar containers exist"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 2

HAS_EDITOR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-editor-content\"]')" 2>/dev/null)
[ "$HAS_EDITOR" = "true" ] && log_pass "Editor content container exists" || log_fail "Editor content container missing"

HAS_PREVIEW=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-rp-preview-content\"]')" 2>/dev/null)
[ "$HAS_PREVIEW" = "true" ] && log_pass "Preview content container exists" || log_fail "Preview content container missing"

# ============================================================================
# TEST 2: Write mode sidebar — editor content visible, preview hidden
# ============================================================================
echo ""
log_info "TEST 2: Write mode sidebar layout"

# Default mode is Write
EDITOR_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-editor-content\"]").style.display' 2>/dev/null | tr -d '"')
[ "$EDITOR_DISPLAY" = "" ] && log_pass "Editor content visible in Write mode" || log_fail "Editor content display: '$EDITOR_DISPLAY'"

PREVIEW_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-preview-content\"]").style.display' 2>/dev/null | tr -d '"')
[ "$PREVIEW_DISPLAY" = "none" ] && log_pass "Preview content hidden in Write mode" || log_fail "Preview content display: '$PREVIEW_DISPLAY'"

# ============================================================================
# TEST 3: Write mode — tab strip hidden
# ============================================================================
echo ""
log_info "TEST 3: Write mode — tab strip hidden"

TAB_VISIBLE=$(agent-browser eval 'getComputedStyle(document.querySelector("[data-testid=\"pu-rp-tab-strip\"]")).display' 2>/dev/null | tr -d '"')
[ "$TAB_VISIBLE" = "none" ] && log_pass "Tab strip hidden in Write mode" || log_fail "Tab strip display: '$TAB_VISIBLE'"

# ============================================================================
# TEST 4: Write mode — inline prompt annotations visible
# ============================================================================
echo ""
log_info "TEST 4: Write mode — inline annotations visible"

ANN_INLINE=$(agent-browser eval 'getComputedStyle(document.querySelector("[data-testid=\"pu-rp-prompt-ann-inline\"]")).display' 2>/dev/null | tr -d '"')
[ "$ANN_INLINE" != "none" ] && log_pass "Inline prompt annotations visible in Write mode" || log_fail "Inline annotations display: '$ANN_INLINE'"

# ============================================================================
# TEST 5: Write mode — ops section hidden
# ============================================================================
echo ""
log_info "TEST 5: Write mode — ops section hidden"

OPS_DISPLAY=$(agent-browser eval 'getComputedStyle(document.querySelector("[data-testid=\"pu-rp-ops-section\"]")).display' 2>/dev/null | tr -d '"')
[ "$OPS_DISPLAY" = "none" ] && log_pass "Ops section hidden in Write mode" || log_fail "Ops section display: '$OPS_DISPLAY'"

# Check no export button in Write mode
HAS_EXPORT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-export-btn\"]")' 2>/dev/null)
[ "$HAS_EXPORT" = "false" ] && log_pass "No export button in Write mode" || log_fail "Export button found in Write mode"

# ============================================================================
# TEST 6: Write mode — operation selector hidden
# ============================================================================
echo ""
log_info "TEST 6: Write mode — operation selector hidden"

OP_SEL_DISPLAY=$(agent-browser eval 'getComputedStyle(document.querySelector("[data-testid=\"pu-rp-op-selector\"]")).display' 2>/dev/null | tr -d '"')
[ "$OP_SEL_DISPLAY" = "none" ] && log_pass "Operation selector hidden in Write mode" || log_fail "Op selector display: '$OP_SEL_DISPLAY'"

# ============================================================================
# TEST 7: Switch to Preview — sidebar swaps content
# ============================================================================
echo ""
log_info "TEST 7: Preview mode — sidebar content swap"

agent-browser eval "PU.editorMode.setPreset('preview')" 2>/dev/null
sleep 1

EDITOR_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-editor-content\"]").style.display' 2>/dev/null | tr -d '"')
[ "$EDITOR_DISPLAY" = "none" ] && log_pass "Editor content hidden in Preview mode" || log_fail "Editor content display: '$EDITOR_DISPLAY'"

PREVIEW_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-preview-content\"]").style.display' 2>/dev/null | tr -d '"')
[ "$PREVIEW_DISPLAY" = "" ] && log_pass "Preview content visible in Preview mode" || log_fail "Preview content display: '$PREVIEW_DISPLAY'"

# ============================================================================
# TEST 8: Preview mode — composition values rendered
# ============================================================================
echo ""
log_info "TEST 8: Preview mode — composition values"

COMP_VALUES=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-comp-values\"]")?.textContent' 2>/dev/null)
# Sidebar now shows BLOCK TREE + WILDCARDS (direct lock panel)
echo "$COMP_VALUES" | grep -qi "block tree\|wildcards" && log_pass "Composition values has block tree / wildcards sections" || log_fail "Comp values content: '$COMP_VALUES'"

# ============================================================================
# TEST 9: Preview mode — ops section shows combo count (no pagination)
# ============================================================================
echo ""
log_info "TEST 9: Preview mode — ops combo count"

OPS_VARIANT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-ops-section\"]")?.dataset?.debugVariant' 2>/dev/null | tr -d '"')
[ "$OPS_VARIANT" = "preview-count" ] && log_pass "Ops section variant is preview-count" || log_fail "Ops variant: '$OPS_VARIANT'"

# No prev/next buttons (pagination removed)
NO_PREV=$(agent-browser eval '!document.querySelector("[data-testid=\"pu-rp-prev-comp\"]")' 2>/dev/null)
[ "$NO_PREV" = "true" ] && log_pass "No prev button (pagination removed)" || log_fail "Prev button still exists"

# Combo count label exists
HAS_NAV_LABEL=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-nav-label\"]")' 2>/dev/null)
[ "$HAS_NAV_LABEL" = "true" ] && log_pass "Combination count label exists" || log_fail "Combo count label missing"

# ============================================================================
# TEST 10: Preview mode — tab strip hidden
# ============================================================================
echo ""
log_info "TEST 10: Preview mode — tab strip hidden"

TAB_VISIBLE=$(agent-browser eval 'getComputedStyle(document.querySelector("[data-testid=\"pu-rp-tab-strip\"]")).display' 2>/dev/null | tr -d '"')
[ "$TAB_VISIBLE" = "none" ] && log_pass "Tab strip hidden in Preview mode" || log_fail "Tab strip display: '$TAB_VISIBLE'"

# ============================================================================
# TEST 11: Switch to Review — full power sidebar
# ============================================================================
echo ""
log_info "TEST 11: Review mode — full power sidebar"

agent-browser eval "PU.editorMode.setPreset('review')" 2>/dev/null
sleep 1

EDITOR_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-editor-content\"]").style.display' 2>/dev/null | tr -d '"')
[ "$EDITOR_DISPLAY" = "" ] && log_pass "Editor content visible in Review mode" || log_fail "Editor content display: '$EDITOR_DISPLAY'"

PREVIEW_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-preview-content\"]").style.display' 2>/dev/null | tr -d '"')
[ "$PREVIEW_DISPLAY" = "none" ] && log_pass "Preview content hidden in Review mode" || log_fail "Preview content display: '$PREVIEW_DISPLAY'"

# ============================================================================
# TEST 12: Review mode — tab strip visible
# ============================================================================
echo ""
log_info "TEST 12: Review mode — tab strip visible"

TAB_VISIBLE=$(agent-browser eval 'getComputedStyle(document.querySelector("[data-testid=\"pu-rp-tab-strip\"]")).display' 2>/dev/null | tr -d '"')
[ "$TAB_VISIBLE" = "flex" ] && log_pass "Tab strip visible in Review mode" || log_fail "Tab strip display: '$TAB_VISIBLE'"

# ============================================================================
# TEST 13: Review mode — ops section shows full variant
# ============================================================================
echo ""
log_info "TEST 13: Review mode — ops full variant"

OPS_VARIANT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-ops-section\"]")?.dataset?.debugVariant' 2>/dev/null | tr -d '"')
[ "$OPS_VARIANT" = "full" ] && log_pass "Ops section variant is full" || log_fail "Ops variant: '$OPS_VARIANT'"

HAS_EXPORT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-export-btn\"]")' 2>/dev/null)
[ "$HAS_EXPORT" = "true" ] && log_pass "Export button present in Review mode" || log_fail "Export button missing in Review mode"

# ============================================================================
# TEST 14: Review mode — inline annotations hidden
# ============================================================================
echo ""
log_info "TEST 14: Review mode — inline annotations hidden"

ANN_INLINE=$(agent-browser eval 'getComputedStyle(document.querySelector("[data-testid=\"pu-rp-prompt-ann-inline\"]")).display' 2>/dev/null | tr -d '"')
[ "$ANN_INLINE" = "none" ] && log_pass "Inline prompt annotations hidden in Review mode" || log_fail "Inline annotations display: '$ANN_INLINE'"

# ============================================================================
# TEST 15: Review mode — annotations tab works
# ============================================================================
echo ""
log_info "TEST 15: Review mode — annotations tab switching"

agent-browser eval "PU.rightPanel.switchTab('annotations')" 2>/dev/null
sleep 0.3

ANN_PANE=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-tab-pane-annotations\"]")?.classList?.contains("active")' 2>/dev/null)
[ "$ANN_PANE" = "true" ] && log_pass "Annotations pane active after tab switch" || log_fail "Annotations pane not active"

# Switch back to wildcards for later tests
agent-browser eval "PU.rightPanel.switchTab('wildcards')" 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 16: Write mode forces wildcards tab when annotations was active
# ============================================================================
echo ""
log_info "TEST 16: Write mode forces wildcards tab"

# Set annotations tab active, then switch to Write
agent-browser eval "PU.rightPanel.switchTab('annotations')" 2>/dev/null
sleep 0.2
agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.3

ACTIVE_TAB=$(agent-browser eval 'PU.state.ui.rightPanelTab' 2>/dev/null | tr -d '"')
[ "$ACTIVE_TAB" = "wildcards" ] && log_pass "Write mode forced wildcards tab" || log_fail "Active tab: '$ACTIVE_TAB'"

# ============================================================================
# TEST 17: PU.debug.sidebar() API
# ============================================================================
echo ""
log_info "TEST 17: Debug sidebar API"

DEBUG_MODE=$(agent-browser eval 'PU.debug.sidebar().mode' 2>/dev/null | tr -d '"')
[ "$DEBUG_MODE" = "write" ] && log_pass "debug.sidebar().mode = write" || log_fail "debug mode: '$DEBUG_MODE'"

DEBUG_CONTENT=$(agent-browser eval 'PU.debug.sidebar().activeContent' 2>/dev/null | tr -d '"')
[ "$DEBUG_CONTENT" = "editor" ] && log_pass "debug.sidebar().activeContent = editor" || log_fail "debug content: '$DEBUG_CONTENT'"

DEBUG_TAB_STRIP=$(agent-browser eval 'PU.debug.sidebar().tabStrip' 2>/dev/null | tr -d '"')
[ "$DEBUG_TAB_STRIP" = "hidden" ] && log_pass "debug.sidebar().tabStrip = hidden (Write)" || log_fail "debug tabStrip: '$DEBUG_TAB_STRIP'"

# Switch to Review and check debug values
agent-browser eval "PU.editorMode.setPreset('review')" 2>/dev/null
sleep 0.3

DEBUG_TAB_STRIP=$(agent-browser eval 'PU.debug.sidebar().tabStrip' 2>/dev/null | tr -d '"')
[ "$DEBUG_TAB_STRIP" = "visible" ] && log_pass "debug.sidebar().tabStrip = visible (Review)" || log_fail "debug tabStrip: '$DEBUG_TAB_STRIP'"

# ============================================================================
# TEST 18: URL rightTab param (Review mode)
# ============================================================================
echo ""
log_info "TEST 18: URL rightTab param"

agent-browser eval "PU.rightPanel.switchTab('annotations')" 2>/dev/null
sleep 0.2
agent-browser eval "PU.actions.updateUrl()" 2>/dev/null
sleep 0.2

URL=$(agent-browser get url 2>/dev/null)
echo "$URL" | grep -q "rightTab=annotations" && log_pass "URL contains rightTab=annotations" || log_fail "URL: '$URL'"

# Switch back to write for clean state
agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.2

# ============================================================================
# TEST 19: URL editorMode=preview loads sidebar in preview mode
# ============================================================================
echo ""
log_info "TEST 19: URL deep-link to preview mode"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks&editorMode=preview" 2>/dev/null
sleep 2

EDITOR_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-editor-content\"]").style.display' 2>/dev/null | tr -d '"')
[ "$EDITOR_DISPLAY" = "none" ] && log_pass "Deep-link: editor content hidden in Preview" || log_fail "Editor display: '$EDITOR_DISPLAY'"

PREVIEW_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-preview-content\"]").style.display' 2>/dev/null | tr -d '"')
[ "$PREVIEW_DISPLAY" = "" ] && log_pass "Deep-link: preview content visible" || log_fail "Preview display: '$PREVIEW_DISPLAY'"

# ============================================================================
# TEST 20: Toggle label shows correct text per mode
# ============================================================================
echo ""
log_info "TEST 20: Toggle label per mode"

# Currently in Preview from deep-link above
LABEL=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-toggle-label\"]")?.textContent' 2>/dev/null | tr -d '"')
[ "$LABEL" = "Filters" ] && log_pass "Toggle label is 'Filters' in Preview mode" || log_fail "Toggle label in Preview: '$LABEL'"

agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.5

LABEL=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-toggle-label\"]")?.textContent' 2>/dev/null | tr -d '"')
[ "$LABEL" = "Wildcards" ] && log_pass "Toggle label is 'Wildcards' in Write mode" || log_fail "Toggle label in Write: '$LABEL'"

agent-browser eval "PU.editorMode.setPreset('review')" 2>/dev/null
sleep 0.5

LABEL=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-toggle-label\"]")?.textContent' 2>/dev/null | tr -d '"')
[ "$LABEL" = "Inspector" ] && log_pass "Toggle label is 'Inspector' in Review mode" || log_fail "Toggle label in Review: '$LABEL'"

# ============================================================================
# TEST 21: Toggle button title updates per mode
# ============================================================================
echo ""
log_info "TEST 21: Toggle button title per mode"

# Still in Review mode
BTN_TITLE=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-collapse-btn\"]")?.title' 2>/dev/null | tr -d '"')
echo "$BTN_TITLE" | grep -q "Inspector" && log_pass "Button title contains 'Inspector' in Review mode" || log_fail "Button title in Review: '$BTN_TITLE'"

agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.3

BTN_TITLE=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-collapse-btn\"]")?.title' 2>/dev/null | tr -d '"')
echo "$BTN_TITLE" | grep -q "Wildcards" && log_pass "Button title contains 'Wildcards' in Write mode" || log_fail "Button title in Write: '$BTN_TITLE'"

# ============================================================================
# TEST 22: Wildcard chip tooltip says "select" not "preview"
# ============================================================================
echo ""
log_info "TEST 22: Wildcard chip tooltip text"

# In Write mode, find a wildcard chip with a title attribute
# The nested-blocks prompt has wildcards — chips should be rendered in the sidebar
CHIP_TITLE=$(agent-browser eval '(document.querySelector("[data-testid^=\"pu-rp-wc-chip-\"][title]") || {}).title || ""' 2>/dev/null | tr -d '"')
if [ -n "$CHIP_TITLE" ]; then
    echo "$CHIP_TITLE" | grep -qi "select" && log_pass "Chip tooltip contains 'select'" || log_fail "Chip tooltip: '$CHIP_TITLE'"
    echo "$CHIP_TITLE" | grep -qi "preview" && log_fail "Chip tooltip still says 'preview'" || log_pass "Chip tooltip does not say 'preview'"
else
    # Fallback: check any chip element
    CHIP_COUNT=$(agent-browser eval 'document.querySelectorAll("[data-testid^=\"pu-rp-wc-chip-\"]").length' 2>/dev/null | tr -d '"')
    if [ "$CHIP_COUNT" = "0" ] || [ -z "$CHIP_COUNT" ]; then
        log_skip "No wildcard chips rendered for this prompt"
    else
        log_fail "Chips exist ($CHIP_COUNT) but none have title attribute"
    fi
fi

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
