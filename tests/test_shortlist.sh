#!/bin/bash
# ============================================================================
# E2E Test Suite: Shortlist (Flat Resolved Prompts + Segment Highlighting)
# ============================================================================
# Tests the shortlist: auto-populated from resolved variation data in state,
# flat layout with segmented text, bidirectional hover with preview template
# blocks, batch-dim via separator click.
#
# Usage: ./tests/test_shortlist.sh [--port 8085]
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

print_header "Shortlist Tests (Flat Layout + Segments)"

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
# TEST 1: No variation divs in preview body
# ============================================================================
echo ""
log_info "TEST 1: No variation divs in preview body"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt&composition=0&editorMode=preview" 2>/dev/null
sleep 3

# Clear any stale state from previous runs
agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

VAR_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-preview-variations").length' 2>/dev/null)
[ "$VAR_COUNT" = "0" ] && log_pass "No .pu-preview-variations in preview body" || log_fail "Found $VAR_COUNT variation containers"

VAR_DIV_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-preview-variation").length' 2>/dev/null)
[ "$VAR_DIV_COUNT" = "0" ] && log_pass "No .pu-preview-variation divs in preview body" || log_fail "Found $VAR_DIV_COUNT variation divs"

# No tree connectors in preview (flat layout)
TREE_CONN=$(agent-browser eval 'document.querySelectorAll(".pu-preview-block .pu-tree-connector").length' 2>/dev/null)
[ "$TREE_CONN" = "0" ] && log_pass "No tree connectors in preview blocks" || log_fail "Found $TREE_CONN tree connectors"

# No depth-based indentation attributes
DEPTH_ATTR=$(agent-browser eval 'document.querySelectorAll(".pu-preview-block[data-depth]").length' 2>/dev/null)
[ "$DEPTH_ATTR" = "0" ] && log_pass "No data-depth attributes on preview blocks" || log_fail "Found $DEPTH_ATTR blocks with data-depth"

# Preview blocks have segments
PV_SEG_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-preview-segment[data-segment-path]").length' 2>/dev/null)
[ "$PV_SEG_COUNT" -gt "0" ] 2>/dev/null && log_pass "Preview has segment spans ($PV_SEG_COUNT)" || log_fail "No preview segments: $PV_SEG_COUNT"

# Preview has ancestor segments (faded) for child blocks
PV_ANCESTOR_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-preview-segment-ancestor").length' 2>/dev/null)
[ "$PV_ANCESTOR_COUNT" -gt "0" ] 2>/dev/null && log_pass "Preview has faded ancestor segments ($PV_ANCESTOR_COUNT)" || log_fail "No ancestor segments: $PV_ANCESTOR_COUNT"

# Preview has own segments
PV_OWN_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-preview-segment-own").length' 2>/dev/null)
[ "$PV_OWN_COUNT" -gt "0" ] 2>/dev/null && log_pass "Preview has own segments ($PV_OWN_COUNT)" || log_fail "No own segments: $PV_OWN_COUNT"

# Preview has separators for child blocks
PV_SEP_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-preview-separator").length' 2>/dev/null)
[ "$PV_SEP_COUNT" -gt "0" ] 2>/dev/null && log_pass "Preview has separators ($PV_SEP_COUNT)" || log_fail "No preview separators: $PV_SEP_COUNT"

# ============================================================================
# TEST 2: Shortlist populated from state (resolvedVariations)
# ============================================================================
echo ""
log_info "TEST 2: Shortlist populated from resolvedVariations state"

SL_COUNT=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
RV_COUNT=$(agent-browser eval '(PU.state.previewMode.resolvedVariations || []).length' 2>/dev/null)
[ "$SL_COUNT" = "$RV_COUNT" ] && log_pass "Shortlist count ($SL_COUNT) matches resolvedVariations ($RV_COUNT)" || log_fail "Shortlist: $SL_COUNT, Variations: $RV_COUNT"

# Count > 0
[ "$SL_COUNT" -gt "0" ] 2>/dev/null && log_pass "Shortlist has items ($SL_COUNT)" || log_fail "Shortlist empty"

# Panel visible
PANEL_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-shortlist-panel\"]")?.style.display' 2>/dev/null | tr -d '"')
[ "$PANEL_DISPLAY" != "none" ] && log_pass "Shortlist panel visible" || log_fail "Panel display: $PANEL_DISPLAY"

# ============================================================================
# TEST 3: Flat item rendering — no tree chrome
# ============================================================================
echo ""
log_info "TEST 3: Flat item rendering — no tree chrome"

NO_CONNECTORS=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-connector").length
' 2>/dev/null)
[ "$NO_CONNECTORS" = "0" ] && log_pass "No .pu-shortlist-connector elements" || log_fail "Found $NO_CONNECTORS connectors"

NO_PATH_ZONES=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-path-zone").length
' 2>/dev/null)
[ "$NO_PATH_ZONES" = "0" ] && log_pass "No .pu-shortlist-path-zone elements" || log_fail "Found $NO_PATH_ZONES path zones"

NO_PATH_LABELS=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-path-label").length
' 2>/dev/null)
[ "$NO_PATH_LABELS" = "0" ] && log_pass "No .pu-shortlist-path-label elements" || log_fail "Found $NO_PATH_LABELS path labels"

NO_COUNTS=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-group-count").length
' 2>/dev/null)
[ "$NO_COUNTS" = "0" ] && log_pass "No .pu-shortlist-group-count elements" || log_fail "Found $NO_COUNTS group counts"

# ============================================================================
# TEST 4: Segment spans present for child blocks
# ============================================================================
echo ""
log_info "TEST 4: Segment spans with data-segment-path"

SEGMENT_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-segment[data-segment-path]").length
' 2>/dev/null)
[ "$SEGMENT_COUNT" -gt "0" ] 2>/dev/null && log_pass "Segment spans found ($SEGMENT_COUNT)" || log_fail "No segment spans: $SEGMENT_COUNT"

# Own segments should exist
OWN_SEGMENTS=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-segment-own").length
' 2>/dev/null)
[ "$OWN_SEGMENTS" -gt "0" ] 2>/dev/null && log_pass "Own segment spans found ($OWN_SEGMENTS)" || log_fail "No own segments: $OWN_SEGMENTS"

# ============================================================================
# TEST 5: Separator present for child blocks
# ============================================================================
echo ""
log_info "TEST 5: Separator elements for child blocks"

SEP_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-separator").length
' 2>/dev/null)
# Separators only appear for items with ancestors (child blocks)
# Check that at least some exist (stress-test-prompt has nested blocks)
[ "$SEP_COUNT" -gt "0" ] 2>/dev/null && log_pass "Separator elements found ($SEP_COUNT)" || log_fail "No separators: $SEP_COUNT"

# Check separator contains ──
SEP_TEXT=$(agent-browser eval '
    const sep = document.querySelector(".pu-shortlist-separator");
    sep ? sep.textContent.includes("──") : false
' 2>/dev/null)
[ "$SEP_TEXT" = "true" ] && log_pass "Separator contains ── character" || log_fail "Separator text wrong: $SEP_TEXT"

# ============================================================================
# TEST 6: Dim single item via shortlist click
# ============================================================================
echo ""
log_info "TEST 6: Dim single item via shortlist click"

agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    if (item) item.click();
' 2>/dev/null
sleep 0.3

SL_ITEM_DIMMED=$(agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    item ? item.classList.contains("pu-shortlist-dimmed") : false
' 2>/dev/null)
[ "$SL_ITEM_DIMMED" = "true" ] && log_pass "Shortlist item dimmed after click" || log_fail "Not dimmed: $SL_ITEM_DIMMED"

DIM_SIZE=$(agent-browser eval 'PU.state.previewMode.dimmedEntries.size' 2>/dev/null)
[ "$DIM_SIZE" = "1" ] && log_pass "dimmedEntries has 1 entry" || log_fail "dimmedEntries size: $DIM_SIZE"

# ============================================================================
# TEST 7: Undim single item via second click
# ============================================================================
echo ""
log_info "TEST 7: Undim via second click"

agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    if (item) item.click();
' 2>/dev/null
sleep 0.3

SL_UNDIMMED=$(agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    item ? item.classList.contains("pu-shortlist-dimmed") : true
' 2>/dev/null)
[ "$SL_UNDIMMED" = "false" ] && log_pass "Shortlist item undimmed after second click" || log_fail "Still dimmed: $SL_UNDIMMED"

DIM_SIZE2=$(agent-browser eval 'PU.state.previewMode.dimmedEntries.size' 2>/dev/null)
[ "$DIM_SIZE2" = "0" ] && log_pass "dimmedEntries empty after undim" || log_fail "dimmedEntries size: $DIM_SIZE2"

# ============================================================================
# TEST 8: Batch dim via separator click (range: path + after siblings + descendants)
# ============================================================================
echo ""
log_info "TEST 8: Batch dim via separator click"

# Get the separator path (now = next segment's path, the range start)
BATCH_PATH=$(agent-browser eval '
    const sep = document.querySelector(".pu-shortlist-separator[data-separator-path]");
    sep ? sep.dataset.separatorPath : ""
' 2>/dev/null | tr -d '"')

if [ -n "$BATCH_PATH" ] && [ "$BATCH_PATH" != "" ]; then
    # Click the separator to trigger range dim
    agent-browser eval '
        const sep = document.querySelector(".pu-shortlist-separator[data-separator-path]");
        if (sep) sep.click();
    ' 2>/dev/null
    sleep 0.3

    # Verify using the range logic: all items in range should be dimmed
    ALL_DIMMED=$(agent-browser eval "
        const items = document.querySelectorAll('.pu-shortlist-item[data-block-path]');
        const inRange = Array.from(items).filter(i => PU.shortlist._isInSeparatorRange(i.dataset.blockPath, '${BATCH_PATH}'));
        inRange.length > 0 && inRange.every(i => i.classList.contains('pu-shortlist-dimmed'))
    " 2>/dev/null)
    [ "$ALL_DIMMED" = "true" ] && log_pass "All items in range of $BATCH_PATH dimmed via separator" || log_fail "Not all dimmed: $ALL_DIMMED"

    # Count how many were dimmed (should be > 1 for range to be meaningful)
    DIM_RANGE_COUNT=$(agent-browser eval "PU.state.previewMode.dimmedEntries.size" 2>/dev/null)
    log_info "Dimmed $DIM_RANGE_COUNT items in range"
else
    log_skip "No separator found (may need nested blocks)"
fi

# ============================================================================
# TEST 9: Batch undim via separator click
# ============================================================================
echo ""
log_info "TEST 9: Batch undim via second separator click"

if [ -n "$BATCH_PATH" ] && [ "$BATCH_PATH" != "" ]; then
    # Click separator again to undim
    agent-browser eval '
        const sep = document.querySelector(".pu-shortlist-separator[data-separator-path]");
        if (sep) sep.click();
    ' 2>/dev/null
    sleep 0.3

    ALL_UNDIMMED=$(agent-browser eval "
        const items = document.querySelectorAll('.pu-shortlist-item[data-block-path]');
        const inRange = Array.from(items).filter(i => PU.shortlist._isInSeparatorRange(i.dataset.blockPath, '${BATCH_PATH}'));
        inRange.length > 0 && inRange.every(i => !i.classList.contains('pu-shortlist-dimmed'))
    " 2>/dev/null)
    [ "$ALL_UNDIMMED" = "true" ] && log_pass "All items in range undimmed via separator" || log_fail "Not all undimmed: $ALL_UNDIMMED"
else
    log_skip "No separator found"
fi

# ============================================================================
# TEST 9b: Separator hover previews range targets
# ============================================================================
echo ""
log_info "TEST 9b: Separator hover previews range targets"

if [ -n "$BATCH_PATH" ] && [ "$BATCH_PATH" != "" ]; then
    agent-browser eval '
        const sep = document.querySelector(".pu-shortlist-separator[data-separator-path]");
        if (sep) sep.dispatchEvent(new MouseEvent("mouseenter", { bubbles: false }));
    ' 2>/dev/null
    sleep 0.3

    HOVER_COUNT=$(agent-browser eval '
        document.querySelectorAll(".pu-shortlist-hover-from-preview").length
    ' 2>/dev/null)
    [ "$HOVER_COUNT" -gt "0" ] 2>/dev/null && log_pass "Separator hover highlights $HOVER_COUNT target items" || log_fail "No items highlighted: $HOVER_COUNT"

    # Clear
    agent-browser eval '
        const sep = document.querySelector(".pu-shortlist-separator[data-separator-path]");
        if (sep) sep.dispatchEvent(new MouseEvent("mouseleave", { bubbles: false }));
    ' 2>/dev/null
    sleep 0.3

    HOVER_CLEAR=$(agent-browser eval '
        document.querySelectorAll(".pu-shortlist-hover-from-preview").length
    ' 2>/dev/null)
    [ "$HOVER_CLEAR" = "0" ] && log_pass "Separator hover cleared on leave" || log_fail "Still highlighted: $HOVER_CLEAR"
else
    log_skip "No separator found"
fi

# Clean up
agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 10: Pin item via Shift+click
# ============================================================================
echo ""
log_info "TEST 10: Pin item via togglePin"

# Use first shortlist item's data to pin
agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    if (item) PU.shortlist.togglePin(item.dataset.blockPath, item.dataset.comboKey || "");
' 2>/dev/null
sleep 0.3

PIN_SIZE=$(agent-browser eval 'PU.state.previewMode.pinnedEntries.size' 2>/dev/null)
[ "$PIN_SIZE" = "1" ] && log_pass "pinnedEntries has 1 entry after pin" || log_fail "pinnedEntries size: $PIN_SIZE"

SL_PINNED=$(agent-browser eval '
    !!document.querySelector(".pu-shortlist-item.pu-shortlist-pinned")
' 2>/dev/null)
[ "$SL_PINNED" = "true" ] && log_pass "Shortlist item has pinned class" || log_fail "Shortlist pinned: $SL_PINNED"

# Pin icon visible
HAS_PIN_ICON=$(agent-browser eval '
    !!document.querySelector(".pu-shortlist-pin-icon")
' 2>/dev/null)
[ "$HAS_PIN_ICON" = "true" ] && log_pass "Pin icon visible" || log_fail "No pin icon: $HAS_PIN_ICON"

# ============================================================================
# TEST 11: Unpin item
# ============================================================================
echo ""
log_info "TEST 11: Unpin via second togglePin"

agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    if (item) PU.shortlist.togglePin(item.dataset.blockPath, item.dataset.comboKey || "");
' 2>/dev/null
sleep 0.3

PIN_SIZE2=$(agent-browser eval 'PU.state.previewMode.pinnedEntries.size' 2>/dev/null)
[ "$PIN_SIZE2" = "0" ] && log_pass "pinnedEntries empty after unpin" || log_fail "pinnedEntries size: $PIN_SIZE2"

# ============================================================================
# TEST 12: Orphan detection
# ============================================================================
echo ""
log_info "TEST 12: Orphan detection after composition change"

# Pin first item
PINNED_KEY=$(agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    if (item) {
        const bp = item.dataset.blockPath;
        const ck = item.dataset.comboKey || "";
        PU.shortlist.togglePin(bp, ck);
        bp + "|" + ck;
    }
' 2>/dev/null | tr -d '"')
sleep 0.3

# Navigate to next composition
agent-browser eval 'PU.preview.nextComposition()' 2>/dev/null
sleep 1.5

# Check pinned entry survived
STILL_PINNED=$(agent-browser eval "PU.state.previewMode.pinnedEntries.has('${PINNED_KEY}')" 2>/dev/null)
[ "$STILL_PINNED" = "true" ] && log_pass "Pin survived composition navigation" || log_fail "Pin lost: $STILL_PINNED"

# Check orphan detection works
ORPHAN_WORKS=$(agent-browser eval 'Array.isArray(PU.shortlist._detectOrphans())' 2>/dev/null)
[ "$ORPHAN_WORKS" = "true" ] && log_pass "Orphan detection returns array" || log_fail "Orphan detection broken: $ORPHAN_WORKS"

# Resolve orphan
agent-browser eval "PU.shortlist.resolveOrphan('${PINNED_KEY}', 'unpin')" 2>/dev/null
sleep 0.3

PIN_AFTER_RESOLVE=$(agent-browser eval "PU.state.previewMode.pinnedEntries.has('${PINNED_KEY}')" 2>/dev/null)
[ "$PIN_AFTER_RESOLVE" = "false" ] && log_pass "Orphan unpinned via resolveOrphan" || log_fail "Still pinned: $PIN_AFTER_RESOLVE"

# ============================================================================
# TEST 13: Session persistence (shortlist_curation)
# ============================================================================
echo ""
log_info "TEST 13: Session persistence round-trip"

# Pin and dim entries
agent-browser eval '
    const items = document.querySelectorAll(".pu-shortlist-item[data-block-path]");
    if (items.length >= 2) {
        PU.shortlist.togglePin(items[0].dataset.blockPath, items[0].dataset.comboKey || "");
        PU.shortlist.toggleDim(items[1].dataset.blockPath, items[1].dataset.comboKey || "");
    }
' 2>/dev/null
sleep 0.3

# Save session
agent-browser eval 'PU.rightPanel.saveSession()' 2>/dev/null
sleep 1

# Verify via API
SESSION_API=$(curl -s "$BASE_URL/api/pu/job/hiring-templates/session" 2>/dev/null)
HAS_CURATION=$(echo "$SESSION_API" | python3 -c "
import sys, json
data = json.load(sys.stdin)
prompts = data.get('prompts', {})
stp = prompts.get('stress-test-prompt', {})
sc = stp.get('shortlist_curation', {})
dimmed = sc.get('dimmed', [])
pinned = sc.get('pinned', [])
print('true' if len(dimmed) > 0 and len(pinned) > 0 else 'false')
" 2>/dev/null)
[ "$HAS_CURATION" = "true" ] && log_pass "Server persisted shortlist_curation (dimmed + pinned)" || log_fail "Session data: $HAS_CURATION"

# Clean up
agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
agent-browser eval 'PU.rightPanel.saveSession()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 14: Preview block hover highlights entire block + shortlist items
# ============================================================================
echo ""
log_info "TEST 14: Preview block hover highlights block + shortlist items"

# Find a preview block path
BLOCK_PATH=$(agent-browser eval '
    const block = document.querySelector(".pu-preview-block[data-path]");
    block ? block.dataset.path : ""
' 2>/dev/null | tr -d '"')

if [ -n "$BLOCK_PATH" ] && [ "$BLOCK_PATH" != "" ]; then
    # Dispatch mouseenter on the preview block
    agent-browser eval "
        const block = document.querySelector('.pu-preview-block[data-path=\"${BLOCK_PATH}\"]');
        if (block) block.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
    " 2>/dev/null
    sleep 0.3

    # Check preview block itself is highlighted
    PV_HL=$(agent-browser eval "
        document.querySelector('.pu-preview-block[data-path=\"${BLOCK_PATH}\"]').classList.contains('pu-preview-block-hover')
    " 2>/dev/null)
    [ "$PV_HL" = "true" ] && log_pass "Preview block highlighted on hover" || log_fail "Preview block not highlighted: $PV_HL"

    # Check shortlist items highlighted
    SL_HL=$(agent-browser eval "
        document.querySelectorAll('.pu-shortlist-hover-from-preview').length
    " 2>/dev/null)
    [ "$SL_HL" -gt "0" ] 2>/dev/null && log_pass "Shortlist items highlighted ($SL_HL) from preview hover" || log_fail "No shortlist items highlighted: $SL_HL"

    # Mouseleave should clear both
    agent-browser eval "
        const block = document.querySelector('.pu-preview-block[data-path=\"${BLOCK_PATH}\"]');
        if (block) block.dispatchEvent(new MouseEvent('mouseleave', { bubbles: true }));
    " 2>/dev/null
    sleep 0.3
else
    log_skip "No preview blocks found"
fi

# ============================================================================
# TEST 15: Preview hover cleanup on mouseleave
# ============================================================================
echo ""
log_info "TEST 15: Preview hover cleanup on mouseleave"

NO_PV_HL=$(agent-browser eval '
    document.querySelectorAll(".pu-preview-block-hover").length
' 2>/dev/null)
[ "$NO_PV_HL" = "0" ] && log_pass "No preview block highlights after mouseleave" || log_fail "Still highlighted: $NO_PV_HL"

NO_SL_HL=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-hover-from-preview").length
' 2>/dev/null)
[ "$NO_SL_HL" = "0" ] && log_pass "No shortlist highlights after mouseleave" || log_fail "Still highlighted: $NO_SL_HL"

# ============================================================================
# TEST 16: Template block highlight from shortlist item hover
# ============================================================================
echo ""
log_info "TEST 16: Template block highlight from shortlist hover"

BLOCK_HOVER=$(agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    if (!item) { "no-item"; } else {
        item.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
        const highlighted = document.querySelectorAll(".pu-preview-block-hover").length;
        item.dispatchEvent(new MouseEvent("mouseleave", { bubbles: true }));
        highlighted > 0;
    }
' 2>/dev/null)
[ "$BLOCK_HOVER" = "true" ] && log_pass "Template block highlighted from shortlist hover" || log_fail "Block hover: $BLOCK_HOVER"

# ============================================================================
# TEST 17: Template block highlight cleanup
# ============================================================================
echo ""
log_info "TEST 17: Template block highlight cleanup"

NO_BLOCK_HL=$(agent-browser eval '
    document.querySelectorAll(".pu-preview-block-hover").length
' 2>/dev/null)
[ "$NO_BLOCK_HL" = "0" ] && log_pass "No template block highlights after mouseleave" || log_fail "Still highlighted: $NO_BLOCK_HL"

# ============================================================================
# TEST 18: Clear All resets all state
# ============================================================================
echo ""
log_info "TEST 18: Clear All resets all state"

# Pin and dim first
agent-browser eval '
    const item = document.querySelector(".pu-shortlist-item[data-block-path]");
    if (item) {
        PU.shortlist.togglePin(item.dataset.blockPath, item.dataset.comboKey || "");
        PU.shortlist.toggleDim(item.dataset.blockPath, item.dataset.comboKey || "");
    }
' 2>/dev/null
sleep 0.3

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

DIM_CLR=$(agent-browser eval 'PU.state.previewMode.dimmedEntries.size' 2>/dev/null)
PIN_CLR=$(agent-browser eval 'PU.state.previewMode.pinnedEntries.size' 2>/dev/null)
TXT_CLR=$(agent-browser eval 'PU.state.previewMode.pinnedTexts.size' 2>/dev/null)

[ "$DIM_CLR" = "0" ] && log_pass "dimmedEntries cleared" || log_fail "dimmedEntries: $DIM_CLR"
[ "$PIN_CLR" = "0" ] && log_pass "pinnedEntries cleared" || log_fail "pinnedEntries: $PIN_CLR"
[ "$TXT_CLR" = "0" ] && log_pass "pinnedTexts cleared" || log_fail "pinnedTexts: $TXT_CLR"

# Final cleanup — save clean session
agent-browser eval 'PU.rightPanel.saveSession()' 2>/dev/null
sleep 0.5

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
print_summary
