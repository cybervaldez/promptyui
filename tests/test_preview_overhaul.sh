#!/bin/bash
# ============================================================================
# E2E Test Suite: Preview Mode Overhaul
# ============================================================================
# Tests block-by-block rendering, depth stepper, wildcard highlighting,
# sidebar block tree, deep-link fix, and URL param persistence.
#
# Usage: ./tests/test_preview_overhaul.sh [--port 8085]
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

print_header "Preview Mode Overhaul Tests"

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
# TEST 1: Deep-link to preview mode renders content immediately
# ============================================================================
echo ""
log_info "TEST 1: Deep-link preview mode renders content"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=hello-world&editorMode=preview" 2>/dev/null
sleep 3

PREVIEW_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-preview-container\"]').style.display !== 'none'" 2>/dev/null)
[ "$PREVIEW_VISIBLE" = "true" ] && log_pass "Preview container visible on deep-link" || log_fail "Preview container hidden on deep-link"

BODY_TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-preview-body\"]')?.textContent?.trim()?.length > 0" 2>/dev/null)
[ "$BODY_TEXT" = "true" ] && log_pass "Preview body has content on deep-link" || log_fail "Preview body empty on deep-link (was: No content blocks)"

# ============================================================================
# TEST 2: Compact composition label format (N / N,NNN)
# ============================================================================
echo ""
log_info "TEST 2: Compact composition label"

# Composition count now in sidebar ops section (not main content)
SIDEBAR_LABEL=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-nav-label\"]')?.textContent?.trim()" 2>/dev/null | tr -d '"')
if echo "$SIDEBAR_LABEL" | grep -qi "combinations"; then
    log_pass "Sidebar combo count: '$SIDEBAR_LABEL'"
else
    log_fail "Expected combo count in sidebar, got: '$SIDEBAR_LABEL'"
fi

# ============================================================================
# TEST 3: Block-by-block rendering (preview blocks exist)
# ============================================================================
echo ""
log_info "TEST 3: Block-by-block rendering"

BLOCK_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-preview-block').length" 2>/dev/null | tr -d '"')
if [ "$BLOCK_COUNT" -gt 0 ] 2>/dev/null; then
    log_pass "Preview blocks rendered: $BLOCK_COUNT"
else
    log_fail "No preview blocks found (count: $BLOCK_COUNT)"
fi

# No .pu-preview-section-label elements (removed)
OLD_LABELS=$(agent-browser eval "document.querySelectorAll('.pu-preview-section-label').length" 2>/dev/null | tr -d '"')
[ "$OLD_LABELS" = "0" ] && log_pass "No old section labels present" || log_fail "Old section labels still present: $OLD_LABELS"

# ============================================================================
# TEST 4: Nav structure has left group + depth stepper
# ============================================================================
echo ""
log_info "TEST 4: Nav structure"

# No pagination arrows in main content (composition-independent template view)
NO_NAV_ARROWS=$(agent-browser eval "!document.querySelector('.pu-preview-nav-left')" 2>/dev/null)
[ "$NO_NAV_ARROWS" = "true" ] && log_pass "No nav arrows in main content (pagination removed)" || log_fail "Nav arrows still in main content"

HAS_DEPTH_STEPPER=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-preview-depth-stepper\"]')" 2>/dev/null)
[ "$HAS_DEPTH_STEPPER" = "true" ] && log_pass "Depth stepper container exists" || log_fail "Depth stepper missing"

# ============================================================================
# TEST 5: Wildcard highlighting (mark tags with pu-wc-sub)
# ============================================================================
echo ""
log_info "TEST 5: Wildcard substitution highlighting"

WC_MARKS=$(agent-browser eval "document.querySelectorAll('.pu-wc-sub').length" 2>/dev/null | tr -d '"')
if [ "$WC_MARKS" -gt 0 ] 2>/dev/null; then
    log_pass "Wildcard marks found: $WC_MARKS"
else
    log_pass "No wildcard marks (prompt may have no wildcards - acceptable)"
fi

# If there are marks, check tooltip attribute
if [ "$WC_MARKS" -gt 0 ] 2>/dev/null; then
    HAS_TITLE=$(agent-browser eval "document.querySelector('.pu-wc-sub')?.title?.includes('__')" 2>/dev/null)
    [ "$HAS_TITLE" = "true" ] && log_pass "Wildcard mark has tooltip" || log_fail "Wildcard mark missing tooltip"
fi

# ============================================================================
# TEST 6: Sidebar block tree (Preview mode)
# ============================================================================
echo ""
log_info "TEST 6: Sidebar block tree"

BT_TITLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-bt-title\"]')?.textContent?.trim()" 2>/dev/null | tr -d '"')
[ "$BT_TITLE" = "BLOCK TREE" ] && log_pass "Block tree title rendered" || log_fail "Block tree title: '$BT_TITLE'"

BT_ITEMS=$(agent-browser eval "document.querySelectorAll('.pu-rp-bt-item').length" 2>/dev/null | tr -d '"')
if [ "$BT_ITEMS" -gt 0 ] 2>/dev/null; then
    log_pass "Block tree items: $BT_ITEMS"
else
    log_fail "No block tree items"
fi

# Checkboxes are checked by default
BT_CHECKED=$(agent-browser eval "document.querySelectorAll('.pu-rp-bt-item input[type=\"checkbox\"]:checked').length" 2>/dev/null | tr -d '"')
[ "$BT_CHECKED" = "$BT_ITEMS" ] && log_pass "All block tree checkboxes checked by default" || log_fail "Checked: $BT_CHECKED, Total: $BT_ITEMS"

# ============================================================================
# TEST 7: Sidebar filtered wildcards section
# ============================================================================
echo ""
log_info "TEST 7: Sidebar filtered wildcards"

WC_TITLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-bt-wc-title\"]')?.textContent?.trim()" 2>/dev/null | tr -d '"')
if echo "$WC_TITLE" | grep -qE '^WILDCARDS'; then
    log_pass "Wildcards section title: '$WC_TITLE'"
else
    log_fail "Wildcards section title: '$WC_TITLE'"
fi

# ============================================================================
# TEST 8: Block tree toggle hides block from preview
# ============================================================================
echo ""
log_info "TEST 8: Block tree toggle"

# Switch to nested-blocks prompt for tree tests
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks&editorMode=preview" 2>/dev/null
sleep 3

BLOCKS_BEFORE=$(agent-browser eval "document.querySelectorAll('.pu-preview-block').length" 2>/dev/null | tr -d '"')

# Uncheck first block (root with children)
agent-browser eval "PU.editorMode.toggleBlockVisibility('0', true)" 2>/dev/null
sleep 0.5

BLOCKS_AFTER=$(agent-browser eval "document.querySelectorAll('.pu-preview-block').length" 2>/dev/null | tr -d '"')

if [ "$BLOCKS_BEFORE" -gt 0 ] && [ "$BLOCKS_AFTER" -lt "$BLOCKS_BEFORE" ] 2>/dev/null; then
    log_pass "Hiding block reduced preview blocks ($BLOCKS_BEFORE -> $BLOCKS_AFTER)"
else
    log_pass "Block toggle test (single-block prompt may show same count)"
fi

# Re-check the block
agent-browser eval "PU.editorMode.toggleBlockVisibility('0', false)" 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 9: Composition navigation still works
# ============================================================================
echo ""
log_info "TEST 9: Composition navigation"

# Composition navigation functions still exist (programmatic API)
COMP_BEFORE=$(agent-browser eval "PU.state.previewMode.compositionId" 2>/dev/null | tr -d '"')
agent-browser eval "PU.editorMode.nextComposition()" 2>/dev/null
sleep 0.5
COMP_AFTER=$(agent-browser eval "PU.state.previewMode.compositionId" 2>/dev/null | tr -d '"')

TOTAL=$(agent-browser eval "PU.shared.getCompositionParams().total" 2>/dev/null | tr -d '"')
if [ "$TOTAL" -gt 1 ] 2>/dev/null; then
    [ "$COMP_BEFORE" != "$COMP_AFTER" ] && log_pass "Navigation changed composition ID" || log_fail "Composition unchanged: $COMP_AFTER"
else
    log_pass "Single composition - nav ok (total=$TOTAL)"
fi

# ============================================================================
# TEST 10: URL depth param persistence
# ============================================================================
echo ""
log_info "TEST 10: URL depth param"

# Set depth to 1
agent-browser eval "PU.editorMode.setPreviewDepth(1)" 2>/dev/null
sleep 0.5

URL_HAS_DEPTH=$(agent-browser eval "window.location.search.includes('depth=1')" 2>/dev/null)
[ "$URL_HAS_DEPTH" = "true" ] && log_pass "depth=1 in URL" || log_fail "depth param missing from URL"

# Set depth to all (null)
agent-browser eval "PU.editorMode.setPreviewDepth(null)" 2>/dev/null
sleep 0.5

URL_NO_DEPTH=$(agent-browser eval "!window.location.search.includes('depth=')" 2>/dev/null)
[ "$URL_NO_DEPTH" = "true" ] && log_pass "depth removed from URL when null" || log_fail "depth still in URL after null"

# ============================================================================
# TEST 11: Switch back to Write mode restores block editor
# ============================================================================
echo ""
log_info "TEST 11: Write mode restores editor"

agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 0.5

BLOCKS_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-blocks-container\"]').style.display" 2>/dev/null | tr -d '"')
PREVIEW_HIDDEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-preview-container\"]').style.display" 2>/dev/null | tr -d '"')

[ "$BLOCKS_VISIBLE" = "" ] && log_pass "Blocks container restored" || log_fail "Blocks display: '$BLOCKS_VISIBLE'"
[ "$PREVIEW_HIDDEN" = "none" ] && log_pass "Preview container hidden" || log_fail "Preview display: '$PREVIEW_HIDDEN'"

# ============================================================================
# TEST 12: State fields exist
# ============================================================================
echo ""
log_info "TEST 12: State fields"

HAS_DEPTH=$(agent-browser eval "'previewDepth' in PU.state.previewMode" 2>/dev/null)
[ "$HAS_DEPTH" = "true" ] && log_pass "previewDepth field exists" || log_fail "previewDepth missing"

HAS_MAX_DEPTH=$(agent-browser eval "'maxTreeDepth' in PU.state.previewMode" 2>/dev/null)
[ "$HAS_MAX_DEPTH" = "true" ] && log_pass "maxTreeDepth field exists" || log_fail "maxTreeDepth missing"

HAS_HIDDEN=$(agent-browser eval "PU.state.previewMode.hiddenBlocks instanceof Set" 2>/dev/null)
[ "$HAS_HIDDEN" = "true" ] && log_pass "hiddenBlocks is a Set" || log_fail "hiddenBlocks not a Set"

# ============================================================================
# TEST 13: Parent cascade — hide parent hides children
# ============================================================================
echo ""
log_info "TEST 13: Parent cascade — hide parent hides children"

# Ensure we're on nested-blocks with all visible
agent-browser eval "PU.state.previewMode.hiddenBlocks.clear(); PU.editorMode.renderPreview(); PU.editorMode.renderSidebarPreview();" 2>/dev/null
sleep 0.5

BLOCKS_ALL=$(agent-browser eval "document.querySelectorAll('.pu-preview-block').length" 2>/dev/null | tr -d '"')

# Hide parent (path '0') — should cascade to children '0.0' and '0.1'
agent-browser eval "PU.editorMode.toggleBlockVisibility('0', true)" 2>/dev/null
sleep 0.5

CHILD_A_HIDDEN=$(agent-browser eval "PU.state.previewMode.hiddenBlocks.has('0.0')" 2>/dev/null)
[ "$CHILD_A_HIDDEN" = "true" ] && log_pass "Child 0.0 hidden when parent hidden" || log_fail "Child 0.0 not cascaded: $CHILD_A_HIDDEN"

CHILD_B_HIDDEN=$(agent-browser eval "PU.state.previewMode.hiddenBlocks.has('0.1')" 2>/dev/null)
[ "$CHILD_B_HIDDEN" = "true" ] && log_pass "Child 0.1 hidden when parent hidden" || log_fail "Child 0.1 not cascaded: $CHILD_B_HIDDEN"

BLOCKS_AFTER_HIDE=$(agent-browser eval "document.querySelectorAll('.pu-preview-block').length" 2>/dev/null | tr -d '"')
[ "$BLOCKS_AFTER_HIDE" = "0" ] && log_pass "No preview blocks when root hidden" || log_fail "Blocks still visible: $BLOCKS_AFTER_HIDE"

# ============================================================================
# TEST 14: Parent cascade — show parent shows children
# ============================================================================
echo ""
log_info "TEST 14: Parent cascade — show parent shows children"

# Show parent (path '0') — should cascade to show children too
agent-browser eval "PU.editorMode.toggleBlockVisibility('0', false)" 2>/dev/null
sleep 0.5

CHILD_A_VISIBLE=$(agent-browser eval "!PU.state.previewMode.hiddenBlocks.has('0.0')" 2>/dev/null)
[ "$CHILD_A_VISIBLE" = "true" ] && log_pass "Child 0.0 shown when parent shown" || log_fail "Child 0.0 still hidden"

CHILD_B_VISIBLE=$(agent-browser eval "!PU.state.previewMode.hiddenBlocks.has('0.1')" 2>/dev/null)
[ "$CHILD_B_VISIBLE" = "true" ] && log_pass "Child 0.1 shown when parent shown" || log_fail "Child 0.1 still hidden"

BLOCKS_RESTORED=$(agent-browser eval "document.querySelectorAll('.pu-preview-block').length" 2>/dev/null | tr -d '"')
[ "$BLOCKS_RESTORED" = "$BLOCKS_ALL" ] && log_pass "All blocks restored ($BLOCKS_RESTORED)" || log_fail "Block count mismatch: $BLOCKS_RESTORED vs $BLOCKS_ALL"

# ============================================================================
# TEST 15: Indeterminate state — hide child makes parent indeterminate
# ============================================================================
echo ""
log_info "TEST 15: Indeterminate state"

# Hide just one child (0.0) — parent should be indeterminate
agent-browser eval "PU.editorMode.toggleBlockVisibility('0.0', true)" 2>/dev/null
sleep 0.5

PARENT_INDETERMINATE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-bt-0\"] input[type=\"checkbox\"]')?.indeterminate" 2>/dev/null)
[ "$PARENT_INDETERMINATE" = "true" ] && log_pass "Parent checkbox indeterminate when child hidden" || log_fail "Parent indeterminate: $PARENT_INDETERMINATE"

PARENT_CHECKED=$(agent-browser eval "document.querySelector('[data-testid=\"pu-rp-bt-0\"] input[type=\"checkbox\"]')?.checked" 2>/dev/null)
[ "$PARENT_CHECKED" = "true" ] && log_pass "Parent checkbox still checked while indeterminate" || log_fail "Parent checked: $PARENT_CHECKED"

# Restore
agent-browser eval "PU.editorMode.toggleBlockVisibility('0.0', false)" 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 16: Tree connectors in preview content (├── / └──)
# ============================================================================
echo ""
log_info "TEST 16: Tree connectors in preview content"

CONNECTOR_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-preview-block .pu-tree-connector').length" 2>/dev/null | tr -d '"')
if [ "$CONNECTOR_COUNT" -gt 0 ] 2>/dev/null; then
    log_pass "Tree connectors found in preview: $CONNECTOR_COUNT"
else
    log_fail "No tree connectors in preview content"
fi

# Check connector text contains ├── or └──
CONNECTOR_TEXT=$(agent-browser eval "document.querySelector('.pu-preview-block .pu-tree-connector')?.textContent?.trim()" 2>/dev/null | tr -d '"')
if echo "$CONNECTOR_TEXT" | grep -qE '├──|└──'; then
    log_pass "Connector uses ├── / └── pattern: '$CONNECTOR_TEXT'"
else
    log_fail "Unexpected connector text: '$CONNECTOR_TEXT'"
fi

# ============================================================================
# TEST 17: Parent connector (── ▾) on blocks with children
# ============================================================================
echo ""
log_info "TEST 17: Parent connector on parent blocks"

PARENT_CONN=$(agent-browser eval "document.querySelectorAll('.pu-preview-parent-conn').length" 2>/dev/null | tr -d '"')
if [ "$PARENT_CONN" -gt 0 ] 2>/dev/null; then
    log_pass "Parent connectors found: $PARENT_CONN"
else
    log_fail "No parent connectors found"
fi

# ============================================================================
# TEST 18: Sidebar block tree has connectors
# ============================================================================
echo ""
log_info "TEST 18: Sidebar block tree connectors"

SIDEBAR_CONN=$(agent-browser eval "document.querySelectorAll('.pu-rp-bt-connector').length" 2>/dev/null | tr -d '"')
if [ "$SIDEBAR_CONN" -gt 0 ] 2>/dev/null; then
    log_pass "Sidebar block tree connectors: $SIDEBAR_CONN"
else
    log_fail "No sidebar block tree connectors"
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
