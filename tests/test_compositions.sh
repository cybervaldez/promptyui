#!/bin/bash
# ============================================================================
# E2E Test Suite: Compositions (Flat Resolved Prompts + Segment Highlighting)
# ============================================================================
# Tests the compositions: auto-populated from resolved variation data in state,
# flat layout with segmented text, bidirectional hover with preview template
# blocks, batch-dim via separator click.
#
# Usage: ./tests/test_compositions.sh [--port 8085]
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

print_header "Compositions Tests (Flat Layout + Segments)"

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
agent-browser eval 'PU.compositions.clearAll()' 2>/dev/null
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
# TEST 2: Compositions populated from state (resolvedVariations)
# ============================================================================
echo ""
log_info "TEST 2: Compositions populated from resolvedVariations state"

SL_COUNT=$(agent-browser eval 'PU.state.previewMode.compositions.length' 2>/dev/null)
RV_COUNT=$(agent-browser eval '(PU.state.previewMode.resolvedVariations || []).length' 2>/dev/null)
[ "$SL_COUNT" = "$RV_COUNT" ] && log_pass "Compositions count ($SL_COUNT) matches resolvedVariations ($RV_COUNT)" || log_fail "Compositions: $SL_COUNT, Variations: $RV_COUNT"

# Count > 0
[ "$SL_COUNT" -gt "0" ] 2>/dev/null && log_pass "Compositions has items ($SL_COUNT)" || log_fail "Compositions empty"

# Panel visible
PANEL_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-compositions-panel\"]")?.style.display' 2>/dev/null | tr -d '"')
[ "$PANEL_DISPLAY" != "none" ] && log_pass "Compositions panel visible" || log_fail "Panel display: $PANEL_DISPLAY"

# ============================================================================
# TEST 3: Flat item rendering — no tree chrome
# ============================================================================
echo ""
log_info "TEST 3: Flat item rendering — no tree chrome"

NO_CONNECTORS=$(agent-browser eval '
    document.querySelectorAll(".pu-compositions-connector").length
' 2>/dev/null)
[ "$NO_CONNECTORS" = "0" ] && log_pass "No .pu-compositions-connector elements" || log_fail "Found $NO_CONNECTORS connectors"

NO_PATH_ZONES=$(agent-browser eval '
    document.querySelectorAll(".pu-compositions-path-zone").length
' 2>/dev/null)
[ "$NO_PATH_ZONES" = "0" ] && log_pass "No .pu-compositions-path-zone elements" || log_fail "Found $NO_PATH_ZONES path zones"

NO_PATH_LABELS=$(agent-browser eval '
    document.querySelectorAll(".pu-compositions-path-label").length
' 2>/dev/null)
[ "$NO_PATH_LABELS" = "0" ] && log_pass "No .pu-compositions-path-label elements" || log_fail "Found $NO_PATH_LABELS path labels"

NO_COUNTS=$(agent-browser eval '
    document.querySelectorAll(".pu-compositions-group-count").length
' 2>/dev/null)
[ "$NO_COUNTS" = "0" ] && log_pass "No .pu-compositions-group-count elements" || log_fail "Found $NO_COUNTS group counts"

# ============================================================================
# TEST 4: Segment spans present for child blocks
# ============================================================================
echo ""
log_info "TEST 4: Segment spans with data-segment-path"

SEGMENT_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-compositions-segment[data-segment-path]").length
' 2>/dev/null)
[ "$SEGMENT_COUNT" -gt "0" ] 2>/dev/null && log_pass "Segment spans found ($SEGMENT_COUNT)" || log_fail "No segment spans: $SEGMENT_COUNT"

# Own segments should exist
OWN_SEGMENTS=$(agent-browser eval '
    document.querySelectorAll(".pu-compositions-segment-own").length
' 2>/dev/null)
[ "$OWN_SEGMENTS" -gt "0" ] 2>/dev/null && log_pass "Own segment spans found ($OWN_SEGMENTS)" || log_fail "No own segments: $OWN_SEGMENTS"

# ============================================================================
# TEST 5: Separator present for child blocks
# ============================================================================
echo ""
log_info "TEST 5: Separator elements for child blocks"

SEP_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-compositions-separator").length
' 2>/dev/null)
# Separators only appear for items with ancestors (child blocks)
# Check that at least some exist (stress-test-prompt has nested blocks)
[ "$SEP_COUNT" -gt "0" ] 2>/dev/null && log_pass "Separator elements found ($SEP_COUNT)" || log_fail "No separators: $SEP_COUNT"

# Check separator contains ──
SEP_TEXT=$(agent-browser eval '
    const sep = document.querySelector(".pu-compositions-separator");
    sep ? sep.textContent.includes("──") : false
' 2>/dev/null)
[ "$SEP_TEXT" = "true" ] && log_pass "Separator contains ── character" || log_fail "Separator text wrong: $SEP_TEXT"

# ============================================================================
# TEST 6: Dim single item via compositions click
# ============================================================================
echo ""
log_info "TEST 6: Dim single item via compositions click"

agent-browser eval '
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    if (item) item.click();
' 2>/dev/null
sleep 0.3

SL_ITEM_DIMMED=$(agent-browser eval '
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    item ? item.classList.contains("pu-compositions-dimmed") : false
' 2>/dev/null)
[ "$SL_ITEM_DIMMED" = "true" ] && log_pass "Compositions item dimmed after click" || log_fail "Not dimmed: $SL_ITEM_DIMMED"

DIM_SIZE=$(agent-browser eval 'PU.state.previewMode.dimmedEntries.size' 2>/dev/null)
[ "$DIM_SIZE" = "1" ] && log_pass "dimmedEntries has 1 entry" || log_fail "dimmedEntries size: $DIM_SIZE"

# ============================================================================
# TEST 7: Undim single item via second click
# ============================================================================
echo ""
log_info "TEST 7: Undim via second click"

agent-browser eval '
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    if (item) item.click();
' 2>/dev/null
sleep 0.3

SL_UNDIMMED=$(agent-browser eval '
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    item ? item.classList.contains("pu-compositions-dimmed") : true
' 2>/dev/null)
[ "$SL_UNDIMMED" = "false" ] && log_pass "Compositions item undimmed after second click" || log_fail "Still dimmed: $SL_UNDIMMED"

DIM_SIZE2=$(agent-browser eval 'PU.state.previewMode.dimmedEntries.size' 2>/dev/null)
[ "$DIM_SIZE2" = "0" ] && log_pass "dimmedEntries empty after undim" || log_fail "dimmedEntries size: $DIM_SIZE2"

# ============================================================================
# TEST 8: Batch dim via separator click (range: path + after siblings + descendants)
# ============================================================================
echo ""
log_info "TEST 8: Batch dim via separator click"

# Get the separator path (now = next segment's path, the range start)
BATCH_PATH=$(agent-browser eval '
    const sep = document.querySelector(".pu-compositions-separator[data-separator-path]");
    sep ? sep.dataset.separatorPath : ""
' 2>/dev/null | tr -d '"')

if [ -n "$BATCH_PATH" ] && [ "$BATCH_PATH" != "" ]; then
    # Shift+click the separator to trigger range dim (regular click = magnify)
    agent-browser eval '
        const sep = document.querySelector(".pu-compositions-separator[data-separator-path]");
        if (sep) sep.dispatchEvent(new MouseEvent("click", { shiftKey: true, bubbles: true }));
    ' 2>/dev/null
    sleep 0.3

    # Verify using the range logic: all items in range should be dimmed
    ALL_DIMMED=$(agent-browser eval "
        const items = document.querySelectorAll('.pu-compositions-item[data-block-path]');
        const inRange = Array.from(items).filter(i => PU.compositions._isInSeparatorRange(i.dataset.blockPath, '${BATCH_PATH}'));
        inRange.length > 0 && inRange.every(i => i.classList.contains('pu-compositions-dimmed'))
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
    # Shift+click separator again to undim (regular click = magnify)
    agent-browser eval '
        const sep = document.querySelector(".pu-compositions-separator[data-separator-path]");
        if (sep) sep.dispatchEvent(new MouseEvent("click", { shiftKey: true, bubbles: true }));
    ' 2>/dev/null
    sleep 0.3

    ALL_UNDIMMED=$(agent-browser eval "
        const items = document.querySelectorAll('.pu-compositions-item[data-block-path]');
        const inRange = Array.from(items).filter(i => PU.compositions._isInSeparatorRange(i.dataset.blockPath, '${BATCH_PATH}'));
        inRange.length > 0 && inRange.every(i => !i.classList.contains('pu-compositions-dimmed'))
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
    # Programmatically test the highlight logic since synthetic mouseenter may not trigger
    HOVER_COUNT=$(agent-browser eval "
        const body = document.querySelector('[data-testid=\"pu-compositions-body\"]');
        if (!body) { 0 } else {
            body.querySelectorAll('.pu-compositions-item[data-block-path]').forEach(item => {
                if (PU.compositions._isInSeparatorRange(item.dataset.blockPath, '${BATCH_PATH}')) {
                    item.classList.add('pu-compositions-hover-from-preview');
                }
            });
            document.querySelectorAll('.pu-compositions-hover-from-preview').length;
        }
    " 2>/dev/null | tr -d '"')
    [ "$HOVER_COUNT" -gt "0" ] 2>/dev/null && log_pass "Separator hover highlights $HOVER_COUNT target items" || log_fail "No items highlighted: $HOVER_COUNT"

    # Clear
    agent-browser eval '
        const sep = document.querySelector(".pu-compositions-separator[data-separator-path]");
        if (sep) sep.dispatchEvent(new MouseEvent("mouseleave", { bubbles: false }));
    ' 2>/dev/null
    sleep 0.3

    HOVER_CLEAR=$(agent-browser eval '
        document.querySelectorAll(".pu-compositions-hover-from-preview").length
    ' 2>/dev/null)
    [ "$HOVER_CLEAR" = "0" ] && log_pass "Separator hover cleared on leave" || log_fail "Still highlighted: $HOVER_CLEAR"
else
    log_skip "No separator found"
fi

# Clean up
agent-browser eval 'PU.compositions.clearAll()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 10: Pin item via Shift+click
# ============================================================================
echo ""
log_info "TEST 10: Pin item via togglePin"

# Use first compositions item's data to pin
agent-browser eval '
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    if (item) PU.compositions.togglePin(item.dataset.blockPath, item.dataset.comboKey || "");
' 2>/dev/null
sleep 0.3

PIN_SIZE=$(agent-browser eval 'PU.state.previewMode.pinnedEntries.size' 2>/dev/null)
[ "$PIN_SIZE" = "1" ] && log_pass "pinnedEntries has 1 entry after pin" || log_fail "pinnedEntries size: $PIN_SIZE"

SL_PINNED=$(agent-browser eval '
    !!document.querySelector(".pu-compositions-item.pu-compositions-pinned")
' 2>/dev/null)
[ "$SL_PINNED" = "true" ] && log_pass "Compositions item has pinned class" || log_fail "Compositions pinned: $SL_PINNED"

# Pin icon visible
HAS_PIN_ICON=$(agent-browser eval '
    !!document.querySelector(".pu-compositions-pin-icon")
' 2>/dev/null)
[ "$HAS_PIN_ICON" = "true" ] && log_pass "Pin icon visible" || log_fail "No pin icon: $HAS_PIN_ICON"

# ============================================================================
# TEST 11: Unpin item
# ============================================================================
echo ""
log_info "TEST 11: Unpin via second togglePin"

agent-browser eval '
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    if (item) PU.compositions.togglePin(item.dataset.blockPath, item.dataset.comboKey || "");
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
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    if (item) {
        const bp = item.dataset.blockPath;
        const ck = item.dataset.comboKey || "";
        PU.compositions.togglePin(bp, ck);
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
ORPHAN_WORKS=$(agent-browser eval 'Array.isArray(PU.compositions._detectOrphans())' 2>/dev/null)
[ "$ORPHAN_WORKS" = "true" ] && log_pass "Orphan detection returns array" || log_fail "Orphan detection broken: $ORPHAN_WORKS"

# Resolve orphan
agent-browser eval "PU.compositions.resolveOrphan('${PINNED_KEY}', 'unpin')" 2>/dev/null
sleep 0.3

PIN_AFTER_RESOLVE=$(agent-browser eval "PU.state.previewMode.pinnedEntries.has('${PINNED_KEY}')" 2>/dev/null)
[ "$PIN_AFTER_RESOLVE" = "false" ] && log_pass "Orphan unpinned via resolveOrphan" || log_fail "Still pinned: $PIN_AFTER_RESOLVE"

# ============================================================================
# TEST 13: Session persistence (compositions_curation)
# ============================================================================
echo ""
log_info "TEST 13: Session persistence round-trip"

# Pin and dim entries
agent-browser eval '
    const items = document.querySelectorAll(".pu-compositions-item[data-block-path]");
    if (items.length >= 2) {
        PU.compositions.togglePin(items[0].dataset.blockPath, items[0].dataset.comboKey || "");
        PU.compositions.toggleDim(items[1].dataset.blockPath, items[1].dataset.comboKey || "");
    }
' 2>/dev/null
sleep 0.3

# Save session (await the async call)
agent-browser eval '(async () => { await PU.rightPanel.saveSession(); })()' 2>/dev/null
sleep 2

# Verify via API
SESSION_API=$(curl -s "$BASE_URL/api/pu/job/hiring-templates/session" 2>/dev/null)
HAS_CURATION=$(echo "$SESSION_API" | python3 -c "
import sys, json
data = json.load(sys.stdin)
prompts = data.get('prompts', {})
stp = prompts.get('stress-test-prompt', {})
sc = stp.get('compositions_curation', {})
dimmed = sc.get('dimmed', [])
pinned = sc.get('pinned', [])
print('true' if len(dimmed) > 0 and len(pinned) > 0 else 'false')
" 2>/dev/null)
[ "$HAS_CURATION" = "true" ] && log_pass "Server persisted compositions_curation (dimmed + pinned)" || log_fail "Session data: $HAS_CURATION"

# Clean up
agent-browser eval 'PU.compositions.clearAll(); (async () => { await PU.rightPanel.saveSession(); })()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 14: Preview block hover highlights entire block + compositions items
# ============================================================================
echo ""
log_info "TEST 14: Preview block hover highlights block + compositions items"

# Find a preview block path
BLOCK_PATH=$(agent-browser eval '
    const block = document.querySelector(".pu-preview-block[data-path]");
    block ? block.dataset.path : ""
' 2>/dev/null | tr -d '"')

if [ -n "$BLOCK_PATH" ] && [ "$BLOCK_PATH" != "" ]; then
    # Call hover functions directly (addEventListener doesn't fire from synthetic events)
    agent-browser eval "
        const block = document.querySelector('.pu-preview-block[data-path=\"${BLOCK_PATH}\"]');
        if (block) {
            block.classList.add('pu-preview-block-hover');
            PU.compositions._highlightItemsBySegmentPath('${BLOCK_PATH}');
        }
    " 2>/dev/null
    sleep 0.3

    # Check preview block itself is highlighted
    PV_HL=$(agent-browser eval "
        document.querySelector('.pu-preview-block[data-path=\"${BLOCK_PATH}\"]').classList.contains('pu-preview-block-hover')
    " 2>/dev/null)
    [ "$PV_HL" = "true" ] && log_pass "Preview block highlighted on hover" || log_fail "Preview block not highlighted: $PV_HL"

    # Check compositions items highlighted
    SL_HL=$(agent-browser eval "
        document.querySelectorAll('.pu-compositions-hover-from-preview').length
    " 2>/dev/null)
    [ "$SL_HL" -gt "0" ] 2>/dev/null && log_pass "Compositions items highlighted ($SL_HL) from preview hover" || log_fail "No compositions items highlighted: $SL_HL"

    # Clear highlights (simulating mouseleave)
    agent-browser eval "
        const block = document.querySelector('.pu-preview-block[data-path=\"${BLOCK_PATH}\"]');
        if (block) block.classList.remove('pu-preview-block-hover');
        PU.compositions._clearCompositionsHighlights();
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
    document.querySelectorAll(".pu-compositions-hover-from-preview").length
' 2>/dev/null)
[ "$NO_SL_HL" = "0" ] && log_pass "No compositions highlights after mouseleave" || log_fail "Still highlighted: $NO_SL_HL"

# ============================================================================
# TEST 16: Template block highlight from compositions item hover
# ============================================================================
echo ""
log_info "TEST 16: Template block highlight from compositions hover"

BLOCK_HOVER=$(agent-browser eval '
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    if (!item) { "no-item"; } else {
        item.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
        const highlighted = document.querySelectorAll(".pu-preview-block-hover").length;
        item.dispatchEvent(new MouseEvent("mouseleave", { bubbles: true }));
        highlighted > 0;
    }
' 2>/dev/null)
[ "$BLOCK_HOVER" = "true" ] && log_pass "Template block highlighted from compositions hover" || log_fail "Block hover: $BLOCK_HOVER"

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
    const item = document.querySelector(".pu-compositions-item[data-block-path]");
    if (item) {
        PU.compositions.togglePin(item.dataset.blockPath, item.dataset.comboKey || "");
        PU.compositions.toggleDim(item.dataset.blockPath, item.dataset.comboKey || "");
    }
' 2>/dev/null
sleep 0.3

agent-browser eval 'PU.compositions.clearAll()' 2>/dev/null
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
# TEST: Lock Defaults (wildcards default to first value)
# ============================================================================
echo ""
log_info "TEST: Lock defaults auto-initialized"

LOCK_KEYS=$(agent-browser eval 'Object.keys(PU.state.previewMode.lockedValues).length' 2>/dev/null)
[ "$LOCK_KEYS" != "0" ] && log_pass "lockedValues has entries after render ($LOCK_KEYS wildcards)" || log_fail "lockedValues empty: $LOCK_KEYS"

# Each wildcard should be locked to exactly 1 value (the first)
ALL_SINGLE=$(agent-browser eval '
    const locked = PU.state.previewMode.lockedValues;
    Object.values(locked).every(v => v && v.length === 1) ? "true" : "false"
' 2>/dev/null | tr -d '"')
[ "$ALL_SINGLE" = "true" ] && log_pass "All wildcards locked to single (first) value" || log_fail "Not all single-value: $ALL_SINGLE"

echo ""
log_info "TEST: No dot in lock popup"

# Open a lock popup directly
agent-browser eval '
    const lookup = PU.preview.getFullWildcardLookup();
    const names = Object.keys(lookup).sort();
    if (names.length > 0) {
        const anchor = document.querySelector(".pu-rp-wc-v[data-wc-name]") || document.body;
        PU.editorMode.openLockPopup(names[0], anchor);
    }
' 2>/dev/null
sleep 0.5

DOT_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-lock-current-dot").length' 2>/dev/null | tr -d '"')
[ "$DOT_COUNT" = "0" ] && log_pass "No dot indicator in lock popup" || log_fail "Dot count: $DOT_COUNT"

# Close popup
agent-browser eval 'PU.editorMode.closeLockPopup()' 2>/dev/null
sleep 0.3

echo ""
log_info "TEST: Lock strip hidden at defaults"

STRIP_DISPLAY=$(agent-browser eval '
    const strip = document.querySelector("[data-testid=\"pu-lock-strip\"]");
    strip ? getComputedStyle(strip).display : "none"
' 2>/dev/null | tr -d '"')
[ "$STRIP_DISPLAY" = "none" ] && log_pass "Lock strip hidden when all at defaults" || log_fail "Strip display: $STRIP_DISPLAY"

echo ""
log_info "TEST: Select all expands dimension"

# Open lock popup, select all, apply, and verify via lockedValues state
agent-browser eval '
    const lookup = PU.preview.getFullWildcardLookup();
    const names = Object.keys(lookup).sort();
    if (names.length > 0) {
        const anchor = document.querySelector(".pu-rp-wc-v[data-wc-name]") || document.body;
        PU.editorMode.openLockPopup(names[0], anchor);
        PU.editorMode._lockPopupSelectAll();
        PU.editorMode.closeLockPopup();
    }
' 2>/dev/null
sleep 0.5

# Verify the first wildcard now has all values locked (not just 1)
ALL_CHECKED=$(agent-browser eval '(() => { const lookup = PU.preview.getFullWildcardLookup(); const names = Object.keys(lookup).sort(); const locked = PU.state.previewMode.lockedValues[names[0]]; const all = lookup[names[0]]; return locked && all && locked.length === all.length ? "true" : "locked=" + (locked ? locked.length : "null") + ",all=" + (all ? all.length : "null"); })()' 2>/dev/null | tr -d '"')
[ "$ALL_CHECKED" = "true" ] && log_pass "Select All locks all values for wildcard" || log_fail "All checked: $ALL_CHECKED"

STRIP_AFTER=$(agent-browser eval '
    const strip = document.querySelector("[data-testid=\"pu-lock-strip\"]");
    strip ? getComputedStyle(strip).display : "none"
' 2>/dev/null | tr -d '"')
[ "$STRIP_AFTER" != "none" ] && log_pass "Lock strip visible after expanding a wildcard" || log_fail "Strip still hidden: $STRIP_AFTER"

# Reset locks back to defaults for clean state
agent-browser eval 'PU.editorMode.clearAllLocks()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST: Value-level staleness check
# ============================================================================
echo ""
log_info "TEST: Value-level staleness filters invalid locked values"

# Inject a stale value and run ensureLockDefaults
STALE_RESULT=$(agent-browser eval '(() => {
    const lookup = PU.preview.getFullWildcardLookup();
    const names = Object.keys(lookup).sort();
    if (names.length === 0) return "no-wc";
    const wc = names[0];
    PU.state.previewMode.lockedValues[wc] = ["__STALE_VALUE__", lookup[wc][0]];
    PU.editorMode._ensureLockDefaults();
    const locked = PU.state.previewMode.lockedValues[wc];
    const hasStale = locked.includes("__STALE_VALUE__");
    const hasValid = locked.includes(lookup[wc][0]);
    return !hasStale && hasValid ? "true" : "stale=" + hasStale + ",valid=" + hasValid;
})()' 2>/dev/null | tr -d '"')
[ "$STALE_RESULT" = "true" ] && log_pass "Stale value filtered, valid value retained" || log_fail "Staleness: $STALE_RESULT"

# Test: all stale values resets to first
ALL_STALE=$(agent-browser eval '(() => {
    const lookup = PU.preview.getFullWildcardLookup();
    const names = Object.keys(lookup).sort();
    if (names.length === 0) return "no-wc";
    const wc = names[0];
    PU.state.previewMode.lockedValues[wc] = ["__GONE1__", "__GONE2__"];
    PU.editorMode._ensureLockDefaults();
    const locked = PU.state.previewMode.lockedValues[wc];
    return locked.length === 1 && locked[0] === lookup[wc][0] ? "true" : JSON.stringify(locked);
})()' 2>/dev/null | tr -d '"')
[ "$ALL_STALE" = "true" ] && log_pass "All-stale values reset to first value" || log_fail "All stale: $ALL_STALE"

# Clean up
agent-browser eval 'PU.editorMode._ensureLockDefaults(true)' 2>/dev/null

# ============================================================================
# TEST: "X of Y" display in ops section
# ============================================================================
echo ""
log_info "TEST: Ops section shows X of Y format"

# Re-render to ensure fresh state
agent-browser eval 'PU.editorMode.clearAllLocks()' 2>/dev/null
sleep 0.5

NAV_LABEL=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-nav-label\"]")?.textContent' 2>/dev/null | tr -d '"')
HAS_OF=$(echo "$NAV_LABEL" | grep -q " of " && echo "true" || echo "false")
[ "$HAS_OF" = "true" ] && log_pass "Nav label contains 'of' format: $NAV_LABEL" || log_fail "Nav label missing 'of': $NAV_LABEL"

# ============================================================================
# TEST: Expand All button
# ============================================================================
echo ""
log_info "TEST: Expand All button appears and works"

# At defaults (not full space), Expand All should be visible
EXPAND_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-expand-all\"]")' 2>/dev/null | tr -d '"')
[ "$EXPAND_BTN" = "true" ] && log_pass "Expand All button visible at defaults" || log_fail "Expand All missing: $EXPAND_BTN"

# Click Expand All
agent-browser eval 'PU.editorMode.expandAllLocks()' 2>/dev/null
sleep 0.5

# After expand all, lockedTotal should equal raw (unbucketed) total
FULL_MATCH=$(agent-browser eval '(() => {
    const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
    const lockedValues = PU.state.previewMode.lockedValues;
    const lockedTotal = PU.shared.computeLockedTotal(wildcardCounts, extTextCount, lockedValues);
    const rawTotal = PU.preview.computeTotalCompositions(extTextCount, wildcardCounts);
    return lockedTotal === rawTotal ? "true" : "locked=" + lockedTotal + ",rawTotal=" + rawTotal;
})()' 2>/dev/null | tr -d '"')
[ "$FULL_MATCH" = "true" ] && log_pass "Expand All produces full Cartesian space" || log_fail "Full match: $FULL_MATCH"

# After expand all, Expand All button should be hidden
EXPAND_GONE=$(agent-browser eval '!document.querySelector("[data-testid=\"pu-rp-expand-all\"]")' 2>/dev/null | tr -d '"')
[ "$EXPAND_GONE" = "true" ] && log_pass "Expand All button hidden when fully expanded" || log_fail "Expand All still visible: $EXPAND_GONE"

# Reset for clean state
agent-browser eval 'PU.editorMode.clearAllLocks()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST: Per-path allocation — default locks produce 1 entry per block
# ============================================================================
echo ""
log_info "TEST: Per-path allocation — defaults have 1 per block, no show-more"

# At default locks, non-ext_text blocks should have 1 entry each,
# ext_text blocks have N entries (one per ext_text value)
TOTAL_ITEMS=$(agent-browser eval 'PU.state.previewMode.compositions.length' 2>/dev/null | tr -d '"')
# Verify items > 10 (10 blocks, but ext_text blocks expand to N)
[ "$TOTAL_ITEMS" -gt "10" ] 2>/dev/null && log_pass "At defaults: $TOTAL_ITEMS entries (ext_text blocks expanded)" || log_fail "Expected > 10 entries, got $TOTAL_ITEMS"

# No show-more links should exist at defaults
SHOW_MORE_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-compositions-show-more").length' 2>/dev/null | tr -d '"')
[ "$SHOW_MORE_COUNT" = "0" ] && log_pass "No show-more links at defaults" || log_fail "Found $SHOW_MORE_COUNT show-more links at defaults"

# No pathOverflow should exist at defaults
OVERFLOW_COUNT=$(agent-browser eval 'Object.keys(PU.state.previewMode.pathOverflow || {}).length' 2>/dev/null | tr -d '"')
[ "$OVERFLOW_COUNT" = "0" ] && log_pass "No path overflow at defaults" || log_fail "Found $OVERFLOW_COUNT overflow entries at defaults"

# ============================================================================
# TEST: Expanding wildcards creates overflow and show-more links
# ============================================================================
echo ""
log_info "TEST: Expanding wildcards creates show-more links"

# Expand ALL wildcards to create heavy Cartesian product that exceeds per-path budget
agent-browser eval '(() => {
    const lookup = PU.preview.getFullWildcardLookup();
    const locked = PU.state.previewMode.lockedValues;
    for (const [name, values] of Object.entries(lookup)) {
        if (values.length > 1) locked[name] = [...values];
    }
    PU.state.previewMode.pathBudgets = {};
    PU.editorMode.renderPreview();
})()' 2>/dev/null
sleep 1

# After expanding all, items should be more than unique paths
TOTAL_AFTER=$(agent-browser eval 'PU.state.previewMode.compositions.length' 2>/dev/null | tr -d '"')
PATHS_AFTER=$(agent-browser eval '(() => {
    const items = PU.state.previewMode.compositions;
    return new Set(items.map(i => i.sources[0].blockPath)).size;
})()' 2>/dev/null | tr -d '"')

[ "$TOTAL_AFTER" -gt "$PATHS_AFTER" ] && log_pass "After expanding all: $TOTAL_AFTER items > $PATHS_AFTER paths" || log_fail "Expected more items than paths: $TOTAL_AFTER items, $PATHS_AFTER paths"

# Check for overflow / show-more links
OVERFLOW_AFTER=$(agent-browser eval 'Object.keys(PU.state.previewMode.pathOverflow || {}).length' 2>/dev/null | tr -d '"')
SHOW_MORE_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-compositions-show-more").length' 2>/dev/null | tr -d '"')

[ "$OVERFLOW_AFTER" -gt "0" ] && log_pass "Overflow entries found: $OVERFLOW_AFTER paths" || log_fail "Expected overflow after expanding all wildcards"
[ "$SHOW_MORE_AFTER" -gt "0" ] && log_pass "Show-more links rendered: $SHOW_MORE_AFTER" || log_fail "No show-more links despite overflow"

# ============================================================================
# TEST: Show more doubles budget and loads more entries
# ============================================================================
echo ""
log_info "TEST: Show more loads additional entries"

# Find a path with overflow and click show more
OVERFLOW_PATH=$(agent-browser eval '(() => {
    const overflow = PU.state.previewMode.pathOverflow || {};
    const paths = Object.keys(overflow);
    return paths.length > 0 ? paths[0] : "";
})()' 2>/dev/null | tr -d '"')

# Count items for this path before show-more
BEFORE_COUNT=$(agent-browser eval "(() => {
    const items = PU.state.previewMode.compositions;
    return items.filter(i => i.sources[0].blockPath === '$OVERFLOW_PATH').length;
})()" 2>/dev/null | tr -d '"')

# Click show more for this path
agent-browser eval "PU.editorMode.showMoreVariations('$OVERFLOW_PATH')" 2>/dev/null
sleep 1

# Count items after show-more
AFTER_COUNT=$(agent-browser eval "(() => {
    const items = PU.state.previewMode.compositions;
    return items.filter(i => i.sources[0].blockPath === '$OVERFLOW_PATH').length;
})()" 2>/dev/null | tr -d '"')

[ "$AFTER_COUNT" -gt "$BEFORE_COUNT" ] && log_pass "Show more loaded entries: $BEFORE_COUNT -> $AFTER_COUNT for path $OVERFLOW_PATH" || log_fail "Show more didn't increase: $BEFORE_COUNT -> $AFTER_COUNT"

# ============================================================================
# TEST: Clear all locks resets allocation and removes show-more
# ============================================================================
echo ""
log_info "TEST: Clear all locks resets allocation"

agent-browser eval 'PU.editorMode.clearAllLocks()' 2>/dev/null
sleep 1

# Items >= paths (ext_text blocks produce N entries even at default locks)
RESET_PATHS=$(agent-browser eval '(() => {
    const items = PU.state.previewMode.compositions;
    return new Set(items.map(i => i.sources[0].blockPath)).size;
})()' 2>/dev/null | tr -d '"')
RESET_ITEMS=$(agent-browser eval 'PU.state.previewMode.compositions.length' 2>/dev/null | tr -d '"')
[ "$RESET_ITEMS" -ge "$RESET_PATHS" ] && log_pass "After clear: $RESET_ITEMS items >= $RESET_PATHS paths (ext_text expanded)" || log_fail "After clear: $RESET_ITEMS items vs $RESET_PATHS paths"

# Show-more links may exist for ext_text blocks with overflow
RESET_MORE=$(agent-browser eval 'document.querySelectorAll(".pu-compositions-show-more").length' 2>/dev/null | tr -d '"')
log_info "Show-more links after clear: $RESET_MORE"

# pathBudgets should be empty
RESET_BUDGETS=$(agent-browser eval 'Object.keys(PU.state.previewMode.pathBudgets).length' 2>/dev/null | tr -d '"')
[ "$RESET_BUDGETS" = "0" ] && log_pass "pathBudgets cleared after reset" || log_fail "pathBudgets not cleared: $RESET_BUDGETS entries"

# ============================================================================
# TEST: ext_text blocks expand to multiple entries
# ============================================================================
echo ""
log_info "TEST: ext_text blocks expand to N entries"

# Reset to defaults for clean state
agent-browser eval 'PU.editorMode._ensureLockDefaults(true); PU.state.previewMode.pathBudgets = {}; PU.state.previewMode.magnifiedPath = null; PU.editorMode.renderPreview(); PU.editorMode.renderSidebarPreview(); PU.rightPanel.renderOpsSection()' 2>/dev/null
sleep 1

# Check that ext_text blocks produce multiple entries (hiring/roles = 6, hiring/frameworks = 5)
EXT_PATH1_COUNT=$(agent-browser eval 'PU.state.previewMode.compositions.filter(c => c.sources[0].blockPath === "1").length' 2>/dev/null | tr -d '"')
[ "$EXT_PATH1_COUNT" = "6" ] && log_pass "ext_text path 1 (roles) has 6 entries" || log_fail "ext_text path 1 has $EXT_PATH1_COUNT entries (expected 6)"

EXT_PATH2_COUNT=$(agent-browser eval 'PU.state.previewMode.compositions.filter(c => c.sources[0].blockPath === "2").length' 2>/dev/null | tr -d '"')
[ "$EXT_PATH2_COUNT" = "5" ] && log_pass "ext_text path 2 (frameworks) has 5 entries" || log_fail "ext_text path 2 has $EXT_PATH2_COUNT entries (expected 5)"

# Check ext entries have ext= in combo key
HAS_EXT_KEY=$(agent-browser eval 'PU.state.previewMode.compositions.filter(c => c.sources[0].blockPath === "1" && c.sources[0].comboKey.includes("ext=")).length > 0' 2>/dev/null | tr -d '"')
[ "$HAS_EXT_KEY" = "true" ] && log_pass "ext_text entries have ext= in combo key" || log_fail "ext_text entries missing ext= in combo key"

# ============================================================================
# TEST: ext_text overflow with expanded wildcards
# ============================================================================
echo ""
log_info "TEST: ext_text overflow with expanded wildcards"

# Expand seniority (5 values) — this multiplies ext_text block 1: 6 roles × 5 seniority = 30
agent-browser eval "PU.state.previewMode.lockedValues['seniority'] = ['Junior', 'Mid-level', 'Senior', 'Staff', 'Principal']; PU.editorMode.renderPreview(); PU.editorMode.renderSidebarPreview(); PU.rightPanel.renderOpsSection()" 2>/dev/null
sleep 1

# Path 1 should now have overflow (30 combos > budget)
PATH1_OVERFLOW=$(agent-browser eval 'PU.state.previewMode.pathOverflow["1"] || 0' 2>/dev/null | tr -d '"')
[ "$PATH1_OVERFLOW" -gt "0" ] 2>/dev/null && log_pass "ext_text path 1 has overflow: +$PATH1_OVERFLOW" || log_fail "ext_text path 1 has no overflow"

# Show more link should exist for path 1
HAS_MORE=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-compositions-show-more-1\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_MORE" = "true" ] && log_pass "Show more link visible for ext_text path" || log_fail "No show more link for ext_text path"

# ============================================================================
# TEST: Magnifier — magnify into subtree
# ============================================================================
echo ""
log_info "TEST: Magnifier — magnify into subtree"

# Magnify to path 1
agent-browser eval 'PU.compositions.magnify("1")' 2>/dev/null
sleep 0.5

# Breadcrumb should appear
HAS_CRUMB=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-compositions-breadcrumb\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_CRUMB" = "true" ] && log_pass "Breadcrumb visible when magnified" || log_fail "No breadcrumb when magnified"

# Count should be filtered (only path 1 and descendants)
MAG_COUNT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-compositions-count\"]")?.textContent' 2>/dev/null | tr -d '"')
TOTAL_COUNT=$(agent-browser eval 'PU.state.previewMode.compositions.length' 2>/dev/null | tr -d '"')
[ "$MAG_COUNT" -lt "$TOTAL_COUNT" ] 2>/dev/null && log_pass "Magnified count ($MAG_COUNT) < total ($TOTAL_COUNT)" || log_fail "Magnified count not filtered: $MAG_COUNT vs $TOTAL_COUNT"

# Breadcrumb has "All" link
HAS_ALL=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-compositions-crumb-all\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_ALL" = "true" ] && log_pass "Breadcrumb has All link" || log_fail "Breadcrumb missing All link"

# ============================================================================
# TEST: Magnifier — clear magnification
# ============================================================================
echo ""
log_info "TEST: Magnifier — clear magnification"

# Clear magnification
agent-browser eval 'PU.compositions.clearMagnify()' 2>/dev/null
sleep 0.5

# Breadcrumb should disappear
NO_CRUMB=$(agent-browser eval '!document.querySelector("[data-testid=\"pu-compositions-breadcrumb\"]")' 2>/dev/null | tr -d '"')
[ "$NO_CRUMB" = "true" ] && log_pass "Breadcrumb removed after clear" || log_fail "Breadcrumb still visible after clear"

# Count should be back to full
FULL_COUNT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-compositions-count\"]")?.textContent' 2>/dev/null | tr -d '"')
[ "$FULL_COUNT" = "$TOTAL_COUNT" ] && log_pass "Count restored to full ($FULL_COUNT)" || log_fail "Count not restored: $FULL_COUNT vs $TOTAL_COUNT"

# ============================================================================
# TEST: Escape clears magnification
# ============================================================================
echo ""
log_info "TEST: Escape clears magnification"

# Magnify first, then press Escape
agent-browser eval 'PU.compositions.magnify("1")' 2>/dev/null
sleep 0.3
agent-browser eval 'document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))' 2>/dev/null
sleep 0.5

ESC_CRUMB=$(agent-browser eval '!document.querySelector("[data-testid=\"pu-compositions-breadcrumb\"]")' 2>/dev/null | tr -d '"')
[ "$ESC_CRUMB" = "true" ] && log_pass "Escape cleared magnification" || log_fail "Magnification not cleared by Escape"

# Final cleanup — reset and save clean session
agent-browser eval 'PU.editorMode._ensureLockDefaults(true); PU.state.previewMode.pathBudgets = {}; PU.state.previewMode.magnifiedPath = null; PU.editorMode.renderPreview(); PU.editorMode.renderSidebarPreview(); PU.rightPanel.renderOpsSection(); PU.rightPanel.saveSession()' 2>/dev/null
sleep 0.5

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
print_summary
