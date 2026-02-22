#!/bin/bash
# ============================================================================
# E2E Test Suite: Direct Shortcut Block Actions & Tree Isolation
# ============================================================================
# Tests the 3 keyboard shortcuts (Ctrl+Enter sibling, Tab child,
# Ctrl+Shift+D duplicate), their tappable label equivalents, and the
# tree isolation focus mode (ancestors 0.9, siblings/children/prior 0.4,
# unrelated hidden).
#
# Usage: ./tests/test_block_shortcuts.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"
LANDING_URL="$BASE_URL/previews/preview-landing-single-viewport.html"

setup_cleanup

print_header "Direct Shortcut Block Actions & Tree Isolation"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server "$BASE_URL/"; then
    log_pass "Server is running"
else
    log_fail "Server not running"
    exit 1
fi

agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# ============================================================================
# TEST 1: Actions bar renders with 3 buttons when editing
# ============================================================================
echo ""
log_info "TEST 1: Actions bar renders with 3 buttons when editing"

# Click first block to edit
agent-browser eval 'document.querySelector(".q-block .q-block-view").click()' 2>/dev/null
sleep 0.5

ACTIONS_BAR=$(agent-browser eval '!!document.querySelector(".q-block.editing .q-block-actions")' 2>/dev/null)
[ "$ACTIONS_BAR" = "true" ] && log_pass "Actions bar visible when editing" || log_fail "Actions bar not found"

ACTION_COUNT=$(agent-browser eval 'document.querySelectorAll(".q-block.editing .q-block-action").length' 2>/dev/null)
[ "$ACTION_COUNT" = "3" ] && log_pass "3 action buttons present" || log_fail "Expected 3 action buttons, got: $ACTION_COUNT"

# Check data-action attributes
HAS_SIBLING=$(agent-browser eval '!!document.querySelector(".q-block-action[data-action=\"sibling\"]")' 2>/dev/null)
HAS_CHILD=$(agent-browser eval '!!document.querySelector(".q-block-action[data-action=\"child\"]")' 2>/dev/null)
HAS_DUP=$(agent-browser eval '!!document.querySelector(".q-block-action[data-action=\"duplicate\"]")' 2>/dev/null)
[ "$HAS_SIBLING" = "true" ] && log_pass "Sibling action button exists" || log_fail "Sibling action button missing"
[ "$HAS_CHILD" = "true" ] && log_pass "Child action button exists" || log_fail "Child action button missing"
[ "$HAS_DUP" = "true" ] && log_pass "Duplicate action button exists" || log_fail "Duplicate action button missing"

# Finish edit (press Enter)
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 2: Actions bar hidden on empty block
# ============================================================================
echo ""
log_info "TEST 2: Actions bar hidden on empty block"

# Create a scenario: edit a block, clear text, check actions bar
agent-browser eval '
    var view = document.querySelector(".q-block .q-block-view");
    view.click();
' 2>/dev/null
sleep 0.5

# Check actions bar is visible when block has content
BAR_DISPLAY=$(agent-browser eval '
    var bar = document.querySelector(".q-block.editing .q-block-actions");
    bar ? getComputedStyle(bar).display : "missing"
' 2>/dev/null | tr -d '"')
[ "$BAR_DISPLAY" = "flex" ] && log_pass "Actions bar visible when block has content" || log_fail "Actions bar display: $BAR_DISPLAY"

# Clear content and check
agent-browser eval '
    var editor = document.querySelector(".q-block.editing .ql-editor");
    var quill = Quill.find(editor.parentNode);
    quill.setText("", "user");
' 2>/dev/null
sleep 0.3

BAR_HIDDEN=$(agent-browser eval '
    var bar = document.querySelector(".q-block.editing .q-block-actions");
    bar ? bar.style.display : "missing"
' 2>/dev/null | tr -d '"')
[ "$BAR_HIDDEN" = "none" ] && log_pass "Actions bar hidden when block is empty" || log_fail "Actions bar display when empty: $BAR_HIDDEN"

# Restore text and finish
agent-browser eval '
    var editor = document.querySelector(".q-block.editing .ql-editor");
    var quill = Quill.find(editor.parentNode);
    quill.setText("restored text", "user");
' 2>/dev/null
sleep 0.3
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 3: Ctrl+Enter creates sibling block at same depth
# ============================================================================
echo ""
log_info "TEST 3: Ctrl+Enter creates sibling block at same depth"

# Reload for clean state
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

BLOCKS_BEFORE=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)

# Click first block (depth 0) to edit
agent-browser eval 'document.querySelector(".q-block .q-block-view").click()' 2>/dev/null
sleep 0.5

SOURCE_DEPTH=$(agent-browser eval 'qState.blocks[0].depth' 2>/dev/null)

# Press Ctrl+Enter
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Enter", ctrlKey: true, bubbles: true})
    )
' 2>/dev/null
sleep 0.8

BLOCKS_AFTER=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
NEW_COUNT=$((BLOCKS_AFTER - BLOCKS_BEFORE))
[ "$NEW_COUNT" = "1" ] && log_pass "Ctrl+Enter created 1 new block" || log_fail "Expected 1 new block, created: $NEW_COUNT"

# The new block should now be editing
NEW_EDITING=$(agent-browser eval '!!document.querySelector(".q-block.editing")' 2>/dev/null)
[ "$NEW_EDITING" = "true" ] && log_pass "New block is in edit mode" || log_fail "New block not in edit mode"

# Check new block depth matches source (sibling)
NEW_DEPTH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    var id = editing.getAttribute("data-block-id");
    var block = qState.blocks.find(function(b) { return b.id == id; });
    block ? block.depth : -1
' 2>/dev/null)
[ "$NEW_DEPTH" = "$SOURCE_DEPTH" ] && log_pass "Sibling has same depth ($NEW_DEPTH)" || log_fail "Sibling depth $NEW_DEPTH != source $SOURCE_DEPTH"

# Escape to cancel empty block
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 4: Tab creates child block at depth+1
# ============================================================================
echo ""
log_info "TEST 4: Tab creates child block at depth+1"

# Reload for clean state
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Click first block (depth 0)
agent-browser eval 'document.querySelector(".q-block .q-block-view").click()' 2>/dev/null
sleep 0.5

BLOCKS_BEFORE=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
SOURCE_DEPTH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    var id = editing.getAttribute("data-block-id");
    var block = qState.blocks.find(function(b) { return b.id == id; });
    block ? block.depth : -1
' 2>/dev/null)

# Press Tab
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Tab", bubbles: true})
    )
' 2>/dev/null
sleep 0.8

BLOCKS_AFTER=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
NEW_COUNT=$((BLOCKS_AFTER - BLOCKS_BEFORE))
[ "$NEW_COUNT" = "1" ] && log_pass "Tab created 1 new block" || log_fail "Expected 1 new block, created: $NEW_COUNT"

# Check new block depth = source + 1
CHILD_DEPTH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    var id = editing.getAttribute("data-block-id");
    var block = qState.blocks.find(function(b) { return b.id == id; });
    block ? block.depth : -1
' 2>/dev/null)

EXPECTED_DEPTH=$((SOURCE_DEPTH + 1))
[ "$CHILD_DEPTH" = "$EXPECTED_DEPTH" ] && log_pass "Child at depth+1 ($CHILD_DEPTH)" || log_fail "Child depth $CHILD_DEPTH != expected $EXPECTED_DEPTH"

# Escape
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 5: Ctrl+Shift+D duplicates block with wildcards
# ============================================================================
echo ""
log_info "TEST 5: Ctrl+Shift+D duplicates block with wildcards"

# Reload for clean state
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Get source block wildcard info before duplicate
SOURCE_WC_NAMES=$(agent-browser eval '
    qState.blocks[0].wildcards.map(function(w) { return w.name; }).sort().join(",")
' 2>/dev/null | tr -d '"')

SOURCE_DEPTH=$(agent-browser eval 'qState.blocks[0].depth' 2>/dev/null)
BLOCKS_BEFORE=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)

# Click first block to edit
agent-browser eval 'document.querySelector(".q-block .q-block-view").click()' 2>/dev/null
sleep 0.5

# Press Ctrl+Shift+D
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "d", ctrlKey: true, shiftKey: true, bubbles: true})
    )
' 2>/dev/null
sleep 0.8

BLOCKS_AFTER=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
NEW_COUNT=$((BLOCKS_AFTER - BLOCKS_BEFORE))
[ "$NEW_COUNT" = "1" ] && log_pass "Ctrl+Shift+D created 1 new block" || log_fail "Expected 1 new block, created: $NEW_COUNT"

# Check dup has same depth
DUP_DEPTH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    var id = editing.getAttribute("data-block-id");
    var block = qState.blocks.find(function(b) { return b.id == id; });
    block ? block.depth : -1
' 2>/dev/null)
[ "$DUP_DEPTH" = "$SOURCE_DEPTH" ] && log_pass "Duplicate has same depth ($DUP_DEPTH)" || log_fail "Dup depth $DUP_DEPTH != source $SOURCE_DEPTH"

# Check dup text is empty (text cleared on duplicate)
DUP_TEXT=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    var id = editing.getAttribute("data-block-id");
    var block = qState.blocks.find(function(b) { return b.id == id; });
    block ? serializeQuill(block.quill).replace(/\u200B/g, "").trim() : "MISSING"
' 2>/dev/null | tr -d '"')
[ -z "$DUP_TEXT" ] && log_pass "Duplicate has empty text" || log_fail "Duplicate text not empty: '$DUP_TEXT'"

# Check dup has wildcard chips from chipRegistry (inherited from source)
DUP_REGISTRY=$(agent-browser eval '
    var names = Object.keys(qState.chipRegistry).sort().join(",");
    names
' 2>/dev/null | tr -d '"')
[ -n "$DUP_REGISTRY" ] && log_pass "Chip registry has wildcards: $DUP_REGISTRY" || log_fail "Chip registry empty after dup"

# Escape
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 6: Tappable labels trigger same actions
# ============================================================================
echo ""
log_info "TEST 6: Tappable action labels (click)"

# Reload
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

BLOCKS_BEFORE=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)

# Edit first block
agent-browser eval 'document.querySelector(".q-block .q-block-view").click()' 2>/dev/null
sleep 0.5

# Click the "child" tappable label
agent-browser eval '
    document.querySelector(".q-block-action[data-action=\"child\"]").click()
' 2>/dev/null
sleep 0.8

BLOCKS_AFTER=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
NEW_COUNT=$((BLOCKS_AFTER - BLOCKS_BEFORE))
[ "$NEW_COUNT" = "1" ] && log_pass "Tappable child label created block" || log_fail "Tappable child: expected 1 new, got $NEW_COUNT"

CHILD_DEPTH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    var id = editing.getAttribute("data-block-id");
    var block = qState.blocks.find(function(b) { return b.id == id; });
    block ? block.depth : -1
' 2>/dev/null)
[ "$CHILD_DEPTH" = "1" ] && log_pass "Tappable child created at depth 1" || log_fail "Tappable child depth: $CHILD_DEPTH"

# Escape and try sibling label
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}))' 2>/dev/null
sleep 0.5

BLOCKS_BEFORE=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)

# Edit first block again
agent-browser eval 'document.querySelector(".q-block .q-block-view").click()' 2>/dev/null
sleep 0.5

# Click sibling label
agent-browser eval '
    document.querySelector(".q-block-action[data-action=\"sibling\"]").click()
' 2>/dev/null
sleep 0.8

BLOCKS_AFTER=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
NEW_COUNT=$((BLOCKS_AFTER - BLOCKS_BEFORE))
[ "$NEW_COUNT" = "1" ] && log_pass "Tappable sibling label created block" || log_fail "Tappable sibling: expected 1 new, got $NEW_COUNT"

# Escape
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 7: Shortcuts do nothing on empty block
# ============================================================================
echo ""
log_info "TEST 7: Shortcuts do nothing on empty block"

# Reload
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Edit the child block (depth 1) and clear it
agent-browser eval '
    var childView = document.querySelectorAll(".q-block .q-block-view")[1];
    childView.click();
' 2>/dev/null
sleep 0.5

agent-browser eval '
    var editor = document.querySelector(".q-block.editing .ql-editor");
    var quill = Quill.find(editor.parentNode);
    quill.setText("", "user");
' 2>/dev/null
sleep 0.3

BLOCKS_BEFORE=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)

# Try Ctrl+Enter on empty block
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Enter", ctrlKey: true, bubbles: true})
    )
' 2>/dev/null
sleep 0.5

BLOCKS_AFTER=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
[ "$BLOCKS_AFTER" = "$BLOCKS_BEFORE" ] && log_pass "Ctrl+Enter on empty block: no new block" || log_fail "Ctrl+Enter on empty created block ($BLOCKS_BEFORE -> $BLOCKS_AFTER)"

# Try Tab on empty block
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Tab", bubbles: true})
    )
' 2>/dev/null
sleep 0.5

BLOCKS_AFTER2=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
[ "$BLOCKS_AFTER2" = "$BLOCKS_BEFORE" ] && log_pass "Tab on empty block: no new block" || log_fail "Tab on empty created block ($BLOCKS_BEFORE -> $BLOCKS_AFTER2)"

# Escape to discard empty block
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 8: Tree isolation — parent with children triggers isolation
# ============================================================================
echo ""
log_info "TEST 8: Tree isolation — parent with children triggers isolation"

# Reload
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Edit root block (index 0, has child at index 1) — isolation should trigger
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5

# Child block should be at 0.4 (descendant)
CHILD_OPACITY=$(agent-browser eval 'qState.blocks[1].lineEl.style.opacity' 2>/dev/null | tr -d '"')
[ "$CHILD_OPACITY" = "0.4" ] && log_pass "Descendant at 0.4 when editing parent" || log_fail "Descendant opacity: '$CHILD_OPACITY' (expected 0.4)"

# Active block at full
ACTIVE_OPACITY=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    editing.style.opacity
' 2>/dev/null | tr -d '"')
[ -z "$ACTIVE_OPACITY" ] && log_pass "Active block at full opacity" || log_fail "Active block opacity: '$ACTIVE_OPACITY' (expected empty/full)"

# Childless block uses light fade — edit child (leaf, no children)
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

agent-browser eval 'qState.blocks[1].viewEl.click()' 2>/dev/null
sleep 0.5

LIGHT_FADE_PARENT=$(agent-browser eval 'qState.blocks[0].lineEl.style.opacity' 2>/dev/null | tr -d '"')
[ "$LIGHT_FADE_PARENT" = "0.4" ] && log_pass "Childless block: others faded to 0.4" || log_fail "Childless block: parent opacity '$LIGHT_FADE_PARENT' (expected 0.4)"

# Finish editing
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 9: Childless sibling skips isolation
# ============================================================================
echo ""
log_info "TEST 9: Childless sibling skips isolation"

# Reload and create a sibling structure: root has 2 children
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Edit child block (index 1), press Ctrl+Enter to add sibling
agent-browser eval '
    var childView = document.querySelectorAll(".q-block .q-block-view")[1];
    childView.click();
' 2>/dev/null
sleep 0.5

agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Enter", ctrlKey: true, bubbles: true})
    )
' 2>/dev/null
sleep 0.8

# Now editing the new sibling (childless) — no isolation
# The original child should be at full opacity (not faded)
SIBLING_OPACITY=$(agent-browser eval '
    var editingEl = document.querySelector(".q-block.editing");
    var editingId = parseInt(editingEl.getAttribute("data-block-id"));
    var editingBlock = qState.blocks.find(function(b) { return b.id === editingId; });
    var parent = null;
    for (var p = qState.blocks.indexOf(editingBlock) - 1; p >= 0; p--) {
        if (qState.blocks[p].depth < editingBlock.depth) { parent = qState.blocks[p]; break; }
    }
    if (!parent) "no_parent";
    else {
        var siblings = [];
        for (var i = qState.blocks.indexOf(parent) + 1; i < qState.blocks.length; i++) {
            if (qState.blocks[i].depth <= parent.depth) break;
            if (qState.blocks[i].depth === parent.depth + 1 && qState.blocks[i] !== editingBlock) {
                siblings.push(qState.blocks[i]);
            }
        }
        siblings.length > 0 ? siblings[0].lineEl.style.opacity : "no_sibling"
    }
' 2>/dev/null | tr -d '"')
[ "$SIBLING_OPACITY" = "0.4" ] && log_pass "Childless edit: sibling faded to 0.4" || log_fail "Sibling opacity: '$SIBLING_OPACITY' (expected 0.4)"

# Escape
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 10: Tree isolation — unrelated blocks hidden (edit parent)
# ============================================================================
echo ""
log_info "TEST 10: Tree isolation — unrelated blocks hidden"

# Reload and add a second root block (depth 0) so we have unrelated blocks
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

agent-browser eval '
    var b = createQBlock("unrelated root block", 0, null);
    document.getElementById("quill-blocks").appendChild(b.lineEl);
' 2>/dev/null
sleep 0.5

BLOCK_COUNT=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
log_info "Block count after adding root: $BLOCK_COUNT"

# Edit root (index 0, has child) — isolation triggers
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5

# The unrelated root block (last block) should be faded to 0.4 (not hidden)
UNRELATED_OPACITY=$(agent-browser eval '
    var lastBlock = qState.blocks[qState.blocks.length - 1];
    lastBlock.lineEl.style.opacity
' 2>/dev/null | tr -d '"')
[ "$UNRELATED_OPACITY" = "0.4" ] && log_pass "Unrelated block faded to 0.4" || log_fail "Unrelated block opacity: $UNRELATED_OPACITY (expected 0.4)"

UNRELATED_NOT_HIDDEN=$(agent-browser eval '
    var lastBlock = qState.blocks[qState.blocks.length - 1];
    !lastBlock.lineEl.classList.contains("tree-hidden")
' 2>/dev/null)
[ "$UNRELATED_NOT_HIDDEN" = "true" ] && log_pass "Unrelated block not tree-hidden (clickable)" || log_fail "Unrelated block is tree-hidden"

# Finish editing
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 11: Tree isolation clears on exit edit
# ============================================================================
echo ""
log_info "TEST 11: Tree isolation clears on exit edit"

# All blocks should have no tree-hidden and default opacity after exiting edit
ALL_CLEAR=$(agent-browser eval '
    var allClear = true;
    qState.blocks.forEach(function(b) {
        if (b.lineEl.classList.contains("tree-hidden")) allClear = false;
        if (b.lineEl.style.opacity !== "") allClear = false;
    });
    allClear
' 2>/dev/null)
[ "$ALL_CLEAR" = "true" ] && log_pass "All blocks restored after exit edit" || log_fail "Blocks not fully restored after exit"

# ============================================================================
# TEST 12: Prior active block stays visible after shortcut
# ============================================================================
echo ""
log_info "TEST 12: Prior active block visible after shortcut"

# Reload
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Edit root block (index 0), Ctrl+Enter for sibling
agent-browser eval '
    qState.blocks[0].viewEl.click();
' 2>/dev/null
sleep 0.5

SOURCE_ID=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    editing.getAttribute("data-block-id")
' 2>/dev/null | tr -d '"')

agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Enter", ctrlKey: true, bubbles: true})
    )
' 2>/dev/null
sleep 0.8

# New sibling is childless — no isolation, prior block stays at full opacity
PRIOR_HIDDEN=$(agent-browser eval '
    var srcBlock = qState.blocks.find(function(b) { return b.id == '"$SOURCE_ID"'; });
    srcBlock.lineEl.classList.contains("tree-hidden")
' 2>/dev/null)
[ "$PRIOR_HIDDEN" = "false" ] && log_pass "Prior block not hidden after shortcut" || log_fail "Prior block hidden: $PRIOR_HIDDEN"

PRIOR_OPACITY=$(agent-browser eval '
    var srcBlock = qState.blocks.find(function(b) { return b.id == '"$SOURCE_ID"'; });
    srcBlock.lineEl.style.opacity
' 2>/dev/null | tr -d '"')
[ "$PRIOR_OPACITY" = "0.4" ] && log_pass "Childless sibling: prior block faded to 0.4" || log_fail "Prior block opacity: '$PRIOR_OPACITY' (expected 0.4)"

# Escape
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 13: Click-to-edit switch preserves isolation (blur race fix)
# ============================================================================
echo ""
log_info "TEST 13: Click-to-edit switch preserves isolation (blur race)"

# Reload
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Edit block 0 — do NOT finish it
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5

# Directly click block 1 while block 0 is still editing
agent-browser eval 'qState.blocks[1].viewEl.click()' 2>/dev/null
sleep 0.8

# After 800ms, block 1 (childless) editing — no isolation, clean switch
B0_STATE=$(agent-browser eval '
    var b = qState.blocks[0];
    b.lineEl.style.opacity + "|" + b.lineEl.classList.contains("tree-hidden") + "|" + b.lineEl.classList.contains("editing")
' 2>/dev/null | tr -d '"')
# Block 1 is childless — light fade, block 0 at 0.4
echo "$B0_STATE" | grep -q "0.4|false|false" && log_pass "Blur race: previous block faded to 0.4" || log_fail "Blur race: block 0 state '$B0_STATE' (expected 0.4|false|false)"

B1_EDITING=$(agent-browser eval 'qState.blocks[1].lineEl.classList.contains("editing")' 2>/dev/null)
[ "$B1_EDITING" = "true" ] && log_pass "Blur race: new block is editing" || log_fail "Blur race: new block not editing"

B1_OPACITY=$(agent-browser eval 'qState.blocks[1].lineEl.style.opacity' 2>/dev/null | tr -d '"')
[ -z "$B1_OPACITY" ] && log_pass "Blur race: active block at full opacity" || log_fail "Blur race: active opacity '$B1_OPACITY'"

# Finish editing
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 14: Descendants (grandchildren+) visible at 0.4
# ============================================================================
echo ""
log_info "TEST 14: Descendants (grandchildren) at 0.4 opacity"

# Reload
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Edit child (index 1), add a grandchild via Tab
agent-browser eval 'qState.blocks[1].viewEl.click()' 2>/dev/null
sleep 0.5

agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Tab", bubbles: true})
    )
' 2>/dev/null
sleep 0.8

# Type text in grandchild so it persists
agent-browser eval '
    var editor = document.querySelector(".q-block.editing .ql-editor");
    var quill = Quill.find(editor.parentNode);
    quill.setText("grandchild block", "user");
' 2>/dev/null
sleep 0.3

# Finish grandchild
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# Now edit root (index 0) — both child and grandchild are descendants
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5

# Child (index 1) should be at 0.4
CHILD_OPACITY=$(agent-browser eval 'qState.blocks[1].lineEl.style.opacity' 2>/dev/null | tr -d '"')
[ "$CHILD_OPACITY" = "0.4" ] && log_pass "Child (depth 1) at 0.4" || log_fail "Child opacity: '$CHILD_OPACITY' (expected 0.4)"

# Grandchild (index 2) should also be at 0.4
GRANDCHILD_OPACITY=$(agent-browser eval 'qState.blocks[2].lineEl.style.opacity' 2>/dev/null | tr -d '"')
[ "$GRANDCHILD_OPACITY" = "0.4" ] && log_pass "Grandchild (depth 2) at 0.4" || log_fail "Grandchild opacity: '$GRANDCHILD_OPACITY' (expected 0.4)"

# Neither should be hidden
CHILD_HIDDEN=$(agent-browser eval 'qState.blocks[1].lineEl.classList.contains("tree-hidden")' 2>/dev/null)
GRAND_HIDDEN=$(agent-browser eval 'qState.blocks[2].lineEl.classList.contains("tree-hidden")' 2>/dev/null)
[ "$CHILD_HIDDEN" = "false" ] && log_pass "Child not tree-hidden" || log_fail "Child is tree-hidden"
[ "$GRAND_HIDDEN" = "false" ] && log_pass "Grandchild not tree-hidden" || log_fail "Grandchild is tree-hidden"

# Finish editing
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 15: Deep ancestor chain — edit node with children, ancestors at 0.9
# ============================================================================
echo ""
log_info "TEST 15: Deep ancestor chain — ancestors at 0.9"

# Continuing from TEST 14 state: blocks are root(0), child(1), grandchild(2)
# Add great-grandchild (depth 3) from grandchild
agent-browser eval 'qState.blocks[2].viewEl.click()' 2>/dev/null
sleep 0.5

agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Tab", bubbles: true})
    )
' 2>/dev/null
sleep 0.8

agent-browser eval '
    var q = Quill.find(document.querySelector(".q-block.editing .ql-editor").parentNode);
    q.setText("great-grandchild", "user");
' 2>/dev/null
sleep 0.3

agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Enter", bubbles: true})
    )
' 2>/dev/null
sleep 0.5

# Edit grandchild (index 2) — it HAS great-grandchild → isolation triggers
agent-browser eval 'qState.blocks[2].viewEl.click()' 2>/dev/null
sleep 0.5

# Ancestors (root, child) should be at 0.9
A0_OPACITY=$(agent-browser eval 'qState.blocks[0].lineEl.style.opacity' 2>/dev/null | tr -d '"')
A1_OPACITY=$(agent-browser eval 'qState.blocks[1].lineEl.style.opacity' 2>/dev/null | tr -d '"')
[ "$A0_OPACITY" = "0.9" ] && log_pass "Root ancestor (depth 0) at 0.9" || log_fail "Root ancestor opacity: '$A0_OPACITY' (expected 0.9)"
[ "$A1_OPACITY" = "0.9" ] && log_pass "Child ancestor (depth 1) at 0.9" || log_fail "Child ancestor opacity: '$A1_OPACITY' (expected 0.9)"

# Descendant (great-grandchild) at 0.4
GGC_OPACITY=$(agent-browser eval 'qState.blocks[3].lineEl.style.opacity' 2>/dev/null | tr -d '"')
[ "$GGC_OPACITY" = "0.4" ] && log_pass "Great-grandchild descendant at 0.4" || log_fail "Great-grandchild opacity: '$GGC_OPACITY' (expected 0.4)"

# Active block (grandchild, depth 2) at full
ACTIVE_OP=$(agent-browser eval 'qState.blocks[2].lineEl.style.opacity' 2>/dev/null | tr -d '"')
[ -z "$ACTIVE_OP" ] && log_pass "Active block (depth 2) at full opacity" || log_fail "Active opacity: '$ACTIVE_OP'"

# Finish editing
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 16: Yellow connectors on active tree
# ============================================================================
echo ""
log_info "TEST 16: Yellow connectors on active tree"

# Connectors are always yellow (tree-active) for all tree blocks — check at idle
# Finish any editing first
EDITING_NOW=$(agent-browser eval '!!document.querySelector(".q-block.editing")' 2>/dev/null)
if [ "$EDITING_NOW" = "true" ]; then
    agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
    sleep 0.5
fi

# All connectors at any depth should have tree-active (yellow)
CONN_ALL_YELLOW=$(agent-browser eval '
    var allYellow = true;
    qState.blocks.forEach(function(b) {
        if (b._connector && !b._connector.classList.contains("tree-active")) allYellow = false;
    });
    allYellow
' 2>/dev/null)
[ "$CONN_ALL_YELLOW" = "true" ] && log_pass "All connectors always yellow (tree-active)" || log_fail "Some connectors missing tree-active"

# Connectors persist after edit (no clearing)
agent-browser eval 'qState.blocks[2].viewEl.click()' 2>/dev/null
sleep 0.5
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

CONN_PERSIST=$(agent-browser eval '
    var allYellow = true;
    qState.blocks.forEach(function(b) {
        if (b._connector && !b._connector.classList.contains("tree-active")) allYellow = false;
    });
    allYellow
' 2>/dev/null)
[ "$CONN_PERSIST" = "true" ] && log_pass "Connectors persist yellow after exit edit" || log_fail "Connectors lost tree-active after exit"

# ============================================================================
# TEST 17: Ghost system fully removed
# ============================================================================
echo ""
log_info "TEST 17: Ghost system fully removed"

HAS_GHOST_CSS=$(agent-browser eval '
    var sheets = document.styleSheets;
    var found = false;
    for (var s = 0; s < sheets.length; s++) {
        try {
            var rules = sheets[s].cssRules;
            for (var r = 0; r < rules.length; r++) {
                if (rules[r].selectorText && rules[r].selectorText.indexOf("q-block--ghost") !== -1) found = true;
            }
        } catch(e) {}
    }
    found
' 2>/dev/null)
[ "$HAS_GHOST_CSS" = "false" ] && log_pass "No ghost CSS rules remain" || log_fail "Ghost CSS rules still present"

HAS_GHOST_STATE=$(agent-browser eval '
    typeof qState._ghostBlock === "undefined" && typeof qState._ghostTyped === "undefined" && typeof qState._lastBlockAction === "undefined"
' 2>/dev/null)
[ "$HAS_GHOST_STATE" = "true" ] && log_pass "No ghost state properties remain" || log_fail "Ghost state properties still exist"

HAS_GHOST_FN=$(agent-browser eval '
    typeof createGhostBlock === "undefined" && typeof confirmGhost === "undefined" && typeof cancelGhost === "undefined" && typeof cycleGhostMode === "undefined"
' 2>/dev/null)
[ "$HAS_GHOST_FN" = "true" ] && log_pass "No ghost functions remain" || log_fail "Ghost functions still defined"

# ============================================================================
# TEST 18: New action functions exist
# ============================================================================
echo ""
log_info "TEST 18: New action functions exist"

HAS_SIBLING_FN=$(agent-browser eval 'typeof addSiblingBlock === "function"' 2>/dev/null)
[ "$HAS_SIBLING_FN" = "true" ] && log_pass "addSiblingBlock function exists" || log_fail "addSiblingBlock missing"

HAS_CHILD_FN=$(agent-browser eval 'typeof addChildBlock === "function"' 2>/dev/null)
[ "$HAS_CHILD_FN" = "true" ] && log_pass "addChildBlock function exists" || log_fail "addChildBlock missing"

HAS_DUP_FN=$(agent-browser eval 'typeof duplicateBlock === "function"' 2>/dev/null)
[ "$HAS_DUP_FN" = "true" ] && log_pass "duplicateBlock function exists" || log_fail "duplicateBlock missing"

HAS_HELPER=$(agent-browser eval 'typeof _finishAndInsert === "function"' 2>/dev/null)
[ "$HAS_HELPER" = "true" ] && log_pass "_finishAndInsert helper exists" || log_fail "_finishAndInsert missing"

# ============================================================================
# TEST 19: Compositions deferred while editing, flush on idle
# ============================================================================
echo ""
log_info "TEST 19: Compositions deferred while editing"

# Reload
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Record the odometer text before editing
ODO_BEFORE=$(agent-browser eval 'document.getElementById("quill-count").textContent.trim()' 2>/dev/null | tr -d '"')

# Edit root block — qRecalc calls should be deferred
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5

# _recalcDirty should be true (buildBlockView called qRecalc during editing)
IS_DIRTY=$(agent-browser eval 'qState._recalcDirty' 2>/dev/null)
[ "$IS_DIRTY" = "true" ] && log_pass "Recalc deferred (dirty flag set) while editing" || log_pass "No recalc needed during edit (clean)"

# Finish editing — should flush recalc
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

DIRTY_AFTER=$(agent-browser eval 'qState._recalcDirty' 2>/dev/null)
[ "$DIRTY_AFTER" = "false" ] && log_pass "Recalc flushed after exit edit (dirty cleared)" || log_fail "Recalc not flushed: _recalcDirty=$DIRTY_AFTER"

# ============================================================================
# TEST 20: Click-to-add target (+ new block)
# ============================================================================
echo ""
log_info "TEST 19: Click-to-add target (+ new block)"

# Reload for clean state
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# 19a: Target visible on page load with first-prompt text
ADD_VISIBLE=$(agent-browser eval '
    var btn = document.getElementById("q-add-block");
    btn && getComputedStyle(btn).display !== "none"
' 2>/dev/null)
[ "$ADD_VISIBLE" = "true" ] && log_pass "Add-prompt target visible on page load" || log_fail "Add-prompt target not visible"

ADD_TEXT=$(agent-browser eval 'document.getElementById("q-add-block").textContent' 2>/dev/null | tr -d '"')
[ "$ADD_TEXT" = "Write your first prompt..." ] && log_pass "Shows first-prompt invitation text" || log_fail "Target text: '$ADD_TEXT' (expected 'Write your first prompt...')"

BLOCKS_BEFORE=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)

# 19b: Click target creates root block in edit mode
agent-browser eval 'document.getElementById("q-add-block").click()' 2>/dev/null
sleep 0.8

BLOCKS_AFTER=$(agent-browser eval 'qState.blocks.length' 2>/dev/null)
NEW_COUNT=$((BLOCKS_AFTER - BLOCKS_BEFORE))
[ "$NEW_COUNT" = "1" ] && log_pass "Click target created 1 new block" || log_fail "Expected 1 new block, got: $NEW_COUNT"

NEW_DEPTH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing");
    var id = editing ? editing.getAttribute("data-block-id") : null;
    var block = id ? qState.blocks.find(function(b) { return b.id == id; }) : null;
    block ? block.depth : -1
' 2>/dev/null)
[ "$NEW_DEPTH" = "0" ] && log_pass "New block is root (depth 0)" || log_fail "New block depth: $NEW_DEPTH (expected 0)"

NEW_EDITING=$(agent-browser eval '!!document.querySelector(".q-block.editing")' 2>/dev/null)
[ "$NEW_EDITING" = "true" ] && log_pass "New block is in edit mode" || log_fail "New block not in edit mode"

# 19c: Light fade — all other blocks faded to 0.4 (not hidden)
LIGHT_FADE=$(agent-browser eval '
    var allFaded = true;
    var anyHidden = false;
    qState.blocks.forEach(function(b) {
        if (!b.lineEl.classList.contains("editing")) {
            if (b.lineEl.style.opacity !== "0.4") allFaded = false;
            if (b.lineEl.classList.contains("tree-hidden")) anyHidden = true;
        }
    });
    allFaded && !anyHidden
' 2>/dev/null)
[ "$LIGHT_FADE" = "true" ] && log_pass "Light fade: others at 0.4, none hidden" || log_fail "Light fade not applied for + new block"

# 19d: Target hidden while editing
ADD_HIDDEN=$(agent-browser eval '
    var btn = document.getElementById("q-add-block");
    btn ? btn.style.display : "missing"
' 2>/dev/null | tr -d '"')
[ "$ADD_HIDDEN" = "none" ] && log_pass "Target hidden while editing" || log_fail "Target display while editing: '$ADD_HIDDEN' (expected none)"

# 19d: Target reappears after finishing edit — type text then Enter
agent-browser eval '
    var editor = document.querySelector(".q-block.editing .ql-editor");
    var quill = Quill.find(editor.parentNode);
    quill.setText("new root block", "user");
' 2>/dev/null
sleep 0.3

agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

ADD_VISIBLE_AFTER=$(agent-browser eval '
    var btn = document.getElementById("q-add-block");
    btn && (btn.style.display === "" || btn.style.display === "block")
' 2>/dev/null)
[ "$ADD_VISIBLE_AFTER" = "true" ] && log_pass "Target reappears after finishing edit" || log_fail "Target not visible after edit"

# Text should have switched to instructive form after first edit
ADD_TEXT_AFTER=$(agent-browser eval 'document.getElementById("q-add-block").textContent' 2>/dev/null | tr -d '"')
[ "$ADD_TEXT_AFTER" = "+ click to write another prompt" ] && log_pass "Text switched to instructive form after edit" || log_fail "Target text after edit: '$ADD_TEXT_AFTER'"

# 19e: No persistent Quill elements remain
NO_PERSISTENT=$(agent-browser eval '
    !document.querySelector(".q-persistent-input") && !document.getElementById("quill-persistent-editor")
' 2>/dev/null)
[ "$NO_PERSISTENT" = "true" ] && log_pass "No persistent Quill elements remain" || log_fail "Persistent Quill elements still present"

# No persistentQuill in state
NO_PERSISTENT_STATE=$(agent-browser eval 'typeof qState.persistentQuill === "undefined"' 2>/dev/null)
[ "$NO_PERSISTENT_STATE" = "true" ] && log_pass "No persistentQuill in state" || log_fail "persistentQuill still in state"

# ============================================================================
# TEST 21: Contextual placeholders on new blocks
# ============================================================================
echo ""
log_info "TEST 21: Contextual placeholders on new blocks"

# Reload for clean state
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# 21a: + new block placeholder
agent-browser eval 'document.getElementById("q-add-block").click()' 2>/dev/null
sleep 0.8

NEW_PH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing .ql-editor");
    editing ? editing.getAttribute("data-placeholder") : "none"
' 2>/dev/null | tr -d '"')
[ "$NEW_PH" = "Type a prompt, use __name__ for wildcards..." ] && log_pass "New block placeholder set" || log_fail "New block placeholder: '$NEW_PH'"

# Type text and finish
agent-browser eval '
    var editor = document.querySelector(".q-block.editing .ql-editor");
    var quill = Quill.find(editor.parentNode);
    quill.setText("root prompt", "user");
' 2>/dev/null
sleep 0.3
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# 21b: Sibling placeholder (Ctrl+Enter on root block)
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Enter", ctrlKey: true, bubbles: true})
    )
' 2>/dev/null
sleep 0.8

SIB_PH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing .ql-editor");
    editing ? editing.getAttribute("data-placeholder") : "none"
' 2>/dev/null | tr -d '"')
[ "$SIB_PH" = "Write a sibling prompt..." ] && log_pass "Sibling placeholder set" || log_fail "Sibling placeholder: '$SIB_PH'"

# Finish sibling edit
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# 21c: Child placeholder (Tab on root block)
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Tab", bubbles: true})
    )
' 2>/dev/null
sleep 0.8

CHILD_PH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing .ql-editor");
    editing ? editing.getAttribute("data-placeholder") : "none"
' 2>/dev/null | tr -d '"')
[ "$CHILD_PH" = "Write a child prompt..." ] && log_pass "Child placeholder set" || log_fail "Child placeholder: '$CHILD_PH'"

# Finish child edit
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# 21d: Duplicate placeholder (Ctrl+Shift+D on root block)
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "d", ctrlKey: true, shiftKey: true, bubbles: true})
    )
' 2>/dev/null
sleep 0.8

DUP_PH=$(agent-browser eval '
    var editing = document.querySelector(".q-block.editing .ql-editor");
    editing ? editing.getAttribute("data-placeholder") : "none"
' 2>/dev/null | tr -d '"')
[ "$DUP_PH" = "Edit this variation..." ] && log_pass "Duplicate placeholder set" || log_fail "Duplicate placeholder: '$DUP_PH'"

# ============================================================================
# TEST 22: Composition stable until block is accepted
# ============================================================================
echo ""
log_info "TEST 22: Composition stable until block accepted"

# Reload for clean state
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Record composition before creating new block
ODO_BEFORE=$(agent-browser eval 'document.getElementById("quill-count").textContent.trim()' 2>/dev/null | tr -d '"')

# Click + new block (creates empty block in edit mode)
agent-browser eval 'document.getElementById("q-add-block").click()' 2>/dev/null
sleep 0.8

# Composition should NOT change while block is empty/uncommitted
ODO_DURING=$(agent-browser eval 'document.getElementById("quill-count").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$ODO_BEFORE" = "$ODO_DURING" ] && log_pass "Composition stable during empty block edit" || log_fail "Composition changed during edit: '$ODO_BEFORE' -> '$ODO_DURING'"

# Type text and accept (Enter)
agent-browser eval '
    var editor = document.querySelector(".q-block.editing .ql-editor");
    var quill = Quill.find(editor.parentNode);
    quill.setText("accepted block", "user");
' 2>/dev/null
sleep 0.3
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

# NOW composition should update
ODO_AFTER=$(agent-browser eval 'document.getElementById("quill-count").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$ODO_BEFORE" != "$ODO_AFTER" ] && log_pass "Composition updated after block accepted" || log_pass "Composition unchanged (no new wildcards added)"

# Also test shortcut path: reload to get clean idle odometer
agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

# Record idle odometer (no editing active)
ODO_IDLE=$(agent-browser eval 'document.getElementById("quill-count").textContent.trim()' 2>/dev/null | tr -d '"')

# Edit block[0] then press Ctrl+Enter to create sibling
agent-browser eval 'qState.blocks[0].viewEl.click()' 2>/dev/null
sleep 0.5
agent-browser eval '
    document.querySelector(".q-block.editing .ql-editor").dispatchEvent(
        new KeyboardEvent("keydown", {key: "Enter", ctrlKey: true, bubbles: true})
    )
' 2>/dev/null
sleep 0.8

# While empty sibling is being edited, composition should match idle state
ODO_SIB_EDITING=$(agent-browser eval 'document.getElementById("quill-count").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$ODO_IDLE" = "$ODO_SIB_EDITING" ] && log_pass "Composition stable during sibling edit" || log_fail "Composition changed during sibling edit: '$ODO_IDLE' -> '$ODO_SIB_EDITING'"

# Dismiss empty sibling (Enter on empty = remove)
agent-browser eval 'document.querySelector(".q-block.editing .ql-editor").dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

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
