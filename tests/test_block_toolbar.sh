#!/bin/bash
# ============================================================================
# E2E Test Suite: Block Action Toolbar + Hierarchy Indicators
# ============================================================================
# Tests that:
# - Inline dice button (hover-only)
# - Right-edge pencil + delete (always visible)
# - Path label on divider line (diagram-style, left-aligned)
# - Parent inline connector (──▾) on blocks with children
# - Hierarchy highlighting (yellow) on child hover via :has()
# - Sibling fade on hover
# - Nest button at bottom of block (visible on hover, 28px)
# - No hover background on child blocks
# - All actions work: pencil opens focus, delete confirms
#
# Usage: ./tests/test_block_toolbar.sh [--port 8085]
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

print_header "Block Action Toolbar + Hierarchy Indicators"

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
# SETUP: Navigate to a prompt with nested blocks
# ============================================================================
echo ""
log_info "SETUP: Opening test page"

agent-browser open "${BASE_URL}/?job=hiring-templates&prompt=deep-culture-doc&viz=typewriter" 2>/dev/null
sleep 3

# Verify page loaded
HAS_BLOCKS=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-blocks-container\"]')" 2>/dev/null)
if [ "$HAS_BLOCKS" = "true" ]; then
    log_pass "Blocks container loaded"
else
    log_fail "Blocks container not found"
    print_summary
    exit $?
fi

# ============================================================================
# TEST 1: Inline dice button (inside .pu-inline-actions)
# ============================================================================
echo ""
log_info "TEST 1: Inline dice button"

NO_OLD_TOOLBAR=$(agent-browser eval "!document.querySelector('.pu-block-toolbar')" 2>/dev/null)
[ "$NO_OLD_TOOLBAR" = "true" ] && log_pass "No old absolute toolbar (.pu-block-toolbar removed)" || log_fail "Old .pu-block-toolbar still present"

HAS_DICE=$(agent-browser eval "!!document.querySelector('.pu-inline-dice')" 2>/dev/null)
[ "$HAS_DICE" = "true" ] && log_pass "Dice button is inline (.pu-inline-dice)" || log_skip "Dice not visible (may be text mode)"

DICE_IN_ACTIONS=$(agent-browser eval "!!document.querySelector('.pu-inline-actions .pu-inline-dice')" 2>/dev/null)
[ "$DICE_IN_ACTIONS" = "true" ] && log_pass "Dice inside .pu-inline-actions container" || log_skip "Dice not in inline actions (text mode)"

# ============================================================================
# TEST 2: Right-edge pencil + delete (always visible)
# ============================================================================
echo ""
log_info "TEST 2: Right-edge pencil + delete (always visible)"

HAS_INLINE_EDIT=$(agent-browser eval "!!document.querySelector('.pu-inline-edit')" 2>/dev/null)
[ "$HAS_INLINE_EDIT" = "true" ] && log_pass "Pencil (edit) button found" || log_fail "Pencil button missing"

HAS_INLINE_DELETE=$(agent-browser eval "!!document.querySelector('.pu-inline-delete')" 2>/dev/null)
[ "$HAS_INLINE_DELETE" = "true" ] && log_pass "Delete (trash) button found" || log_fail "Delete button missing"

BOTH_RIGHT_EDGE=$(agent-browser eval "
    const container = document.querySelector('.pu-right-edge-actions');
    container && container.querySelector('.pu-inline-edit') && container.querySelector('.pu-inline-delete') ? true : false
" 2>/dev/null)
[ "$BOTH_RIGHT_EDGE" = "true" ] && log_pass "Pencil and delete in right-edge container" || log_fail "Pencil and delete not in .pu-right-edge-actions"

# Right-edge always visible (opacity > 0 without hover)
EDGE_OPACITY=$(agent-browser eval "
    const edge = document.querySelector('.pu-right-edge-actions');
    edge ? getComputedStyle(edge).opacity : 'not-found'
" 2>/dev/null | tr -d '"')
if [ "$EDGE_OPACITY" = "0.5" ]; then
    log_pass "Right-edge actions visible by default (opacity: 0.5)"
elif [ "$EDGE_OPACITY" != "not-found" ] && [ "$(echo "$EDGE_OPACITY > 0" | bc 2>/dev/null)" = "1" ]; then
    log_pass "Right-edge actions visible by default (opacity: $EDGE_OPACITY)"
else
    log_fail "Right-edge actions hidden (opacity: $EDGE_OPACITY)"
fi

# Dice inline, hidden by default (opacity: 0)
DICE_OPACITY=$(agent-browser eval "
    const actions = document.querySelector('.pu-inline-actions');
    actions ? getComputedStyle(actions).opacity : 'no-dice'
" 2>/dev/null | tr -d '"')
if [ "$DICE_OPACITY" = "0" ]; then
    log_pass "Inline dice hidden by default (opacity: 0)"
elif [ "$DICE_OPACITY" = "no-dice" ]; then
    log_skip "No dice button (text mode)"
else
    log_fail "Inline dice visible by default (opacity: $DICE_OPACITY, expected 0)"
fi

# ============================================================================
# TEST 3: Path label on divider line (diagram-style)
# ============================================================================
echo ""
log_info "TEST 3: Path label on divider line"

# Path divider element exists
HAS_DIVIDER=$(agent-browser eval "!!document.querySelector('.pu-path-divider')" 2>/dev/null)
[ "$HAS_DIVIDER" = "true" ] && log_pass "Path divider element (.pu-path-divider) found" || log_fail "Path divider missing"

# Path label inside divider
LABEL_IN_DIVIDER=$(agent-browser eval "!!document.querySelector('.pu-path-divider .pu-path-label')" 2>/dev/null)
[ "$LABEL_IN_DIVIDER" = "true" ] && log_pass "Path label inside divider (.pu-path-label)" || log_fail "Path label not inside divider"

# Arrow span exists
HAS_ARROW=$(agent-browser eval "!!document.querySelector('.pu-path-label .pu-child-arrow')" 2>/dev/null)
[ "$HAS_ARROW" = "true" ] && log_pass "Arrow span (.pu-child-arrow) in label" || log_fail "Arrow span missing"

# Path divider uses flexbox
DIVIDER_DISPLAY=$(agent-browser eval "
    const d = document.querySelector('.pu-path-divider');
    d ? getComputedStyle(d).display : 'not-found'
" 2>/dev/null | tr -d '"')
[ "$DIVIDER_DISPLAY" = "flex" ] && log_pass "Path divider display: flex" || log_fail "Path divider display: $DIVIDER_DISPLAY (expected flex)"

# Path label has visible opacity
LABEL_OPACITY=$(agent-browser eval "
    const label = document.querySelector('.pu-path-label');
    label ? getComputedStyle(label).opacity : 'not-found'
" 2>/dev/null | tr -d '"')
if [ "$LABEL_OPACITY" = "not-found" ]; then
    log_skip "No path label found"
elif [ "$(echo "$LABEL_OPACITY > 0" | bc 2>/dev/null)" = "1" ]; then
    log_pass "Path label visible (opacity: $LABEL_OPACITY)"
else
    log_fail "Path label hidden (opacity: $LABEL_OPACITY)"
fi

# Path label has badge background
LABEL_BG=$(agent-browser eval "
    const label = document.querySelector('.pu-path-label');
    if (!label) 'not-found';
    else {
        const bg = getComputedStyle(label).backgroundColor;
        bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent' ? 'has-bg' : 'transparent';
    }
" 2>/dev/null | tr -d '"')
if [ "$LABEL_BG" = "has-bg" ]; then
    log_pass "Path label has badge background"
elif [ "$LABEL_BG" = "not-found" ]; then
    log_skip "No path label found"
else
    log_fail "Path label has no background (expected badge)"
fi

# Path divider is OUTSIDE block-body (before it, not inside content)
PATH_OUTSIDE_BODY=$(agent-browser eval "
    const divider = document.querySelector('.pu-path-divider');
    if (!divider) 'not-found';
    else {
        const parent = divider.parentElement;
        parent && parent.classList.contains('pu-block-child') ? 'outside' : 'inside';
    }
" 2>/dev/null | tr -d '"')
[ "$PATH_OUTSIDE_BODY" = "outside" ] && log_pass "Path divider outside block-body (direct child of block-child)" || log_fail "Path divider placement: $PATH_OUTSIDE_BODY"

# ============================================================================
# TEST 4: Parent inline connector (──▾)
# ============================================================================
echo ""
log_info "TEST 4: Parent inline connector"

# Parent connector exists on blocks with children
HAS_CONNECTOR=$(agent-browser eval "!!document.querySelector('.pu-parent-connector')" 2>/dev/null)
[ "$HAS_CONNECTOR" = "true" ] && log_pass "Parent connector (.pu-parent-connector) found" || log_fail "Parent connector missing"

# Connector only on blocks that have children
CONNECTOR_ON_PARENT=$(agent-browser eval "
    const c = document.querySelector('.pu-has-children .pu-parent-connector');
    c ? true : false
" 2>/dev/null)
[ "$CONNECTOR_ON_PARENT" = "true" ] && log_pass "Connector is inside .pu-has-children block" || log_fail "Connector not in parent block"

# No connector on blocks without children
CONNECTOR_ON_LEAF=$(agent-browser eval "
    const blocks = document.querySelectorAll('.pu-block:not(.pu-has-children)');
    let found = false;
    blocks.forEach(b => { if (b.querySelector('.pu-parent-connector')) found = true; });
    found;
" 2>/dev/null)
[ "$CONNECTOR_ON_LEAF" = "false" ] && log_pass "No connector on leaf blocks" || log_fail "Connector found on non-parent block"

# Connector has line + arrow parts
CONNECTOR_PARTS=$(agent-browser eval "
    const c = document.querySelector('.pu-parent-connector');
    c && c.querySelector('.pu-parent-connector-line') && c.querySelector('.pu-parent-connector-arrow') ? true : false
" 2>/dev/null)
[ "$CONNECTOR_PARTS" = "true" ] && log_pass "Connector has line + arrow parts" || log_fail "Connector parts missing"

# .pu-has-children class present
HAS_CHILDREN_CLASS=$(agent-browser eval "!!document.querySelector('.pu-has-children')" 2>/dev/null)
[ "$HAS_CHILDREN_CLASS" = "true" ] && log_pass ".pu-has-children class on parent blocks" || log_fail ".pu-has-children class missing"

# Connector hidden by default (visibility: hidden, preserves layout)
CONNECTOR_VIS=$(agent-browser eval "
    const c = document.querySelector('.pu-parent-connector');
    c ? getComputedStyle(c).visibility : 'not-found'
" 2>/dev/null | tr -d '"')
[ "$CONNECTOR_VIS" = "hidden" ] && log_pass "Connector hidden by default (visibility: hidden)" || log_fail "Connector visibility: $CONNECTOR_VIS (expected hidden)"

# ============================================================================
# TEST 5: Hierarchy highlighting (:has CSS rules)
# ============================================================================
echo ""
log_info "TEST 5: Hierarchy highlighting CSS rules"

# Check :has() rule exists for connector highlighting
HAS_HIGHLIGHT_RULE=$(agent-browser eval "
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.selectorText && rule.selectorText.includes('.pu-has-children:has(') && rule.selectorText.includes('.pu-parent-connector')) {
                    found = true; break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found;
" 2>/dev/null)
[ "$HAS_HIGHLIGHT_RULE" = "true" ] && log_pass ":has() CSS rule for parent connector highlight" || log_fail ":has() connector highlight rule missing"

# Check :has() rule for parent yellow border
HAS_BORDER_RULE=$(agent-browser eval "
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.selectorText && rule.selectorText.includes('.pu-has-children:has(') && rule.style && rule.style.borderLeft) {
                    found = true; break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found;
" 2>/dev/null)
[ "$HAS_BORDER_RULE" = "true" ] && log_pass ":has() CSS rule for parent yellow border" || log_fail ":has() border highlight rule missing"

# :has() rule hides parent actions when child hovered
HAS_HIDE_ACTIONS_RULE=$(agent-browser eval "
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.selectorText && rule.selectorText.includes('.pu-has-children:has(') && rule.selectorText.includes('.pu-right-edge-actions')) {
                    found = true; break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found;
" 2>/dev/null)
[ "$HAS_HIDE_ACTIONS_RULE" = "true" ] && log_pass ":has() CSS rule to hide parent actions on child hover" || log_fail ":has() hide-parent-actions rule missing"

# :has() rule hides parent inline-actions when child hovered (display: none to shift connector)
HAS_HIDE_INLINE_RULE=$(agent-browser eval "
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.selectorText && rule.selectorText.includes('.pu-has-children:has(') && rule.selectorText.includes('.pu-inline-actions') && rule.style && rule.style.display === 'none') {
                    found = true; break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found;
" 2>/dev/null)
[ "$HAS_HIDE_INLINE_RULE" = "true" ] && log_pass ":has() CSS rule to hide parent inline-actions on child hover" || log_fail ":has() hide-inline-actions rule missing"

# No .pu-delete-confirm:hover rule (removed to prevent hover-out style change)
HAS_CONFIRM_HOVER=$(agent-browser eval "
    const sheets = document.styleSheets;
    let found = false;
    for (const sheet of sheets) {
        try {
            for (const rule of sheet.cssRules) {
                if (rule.selectorText && rule.selectorText === '.pu-delete-confirm:hover') {
                    found = true; break;
                }
            }
        } catch(e) {}
        if (found) break;
    }
    found;
" 2>/dev/null)
[ "$HAS_CONFIRM_HOVER" = "false" ] && log_pass "No .pu-delete-confirm:hover rule (hover-out style removed)" || log_fail ".pu-delete-confirm:hover rule still exists"

# Sibling fade still works
SIBLING_FADE=$(agent-browser eval "
    const children = document.querySelectorAll('.pu-block-child');
    if (children.length < 2) 'not-enough';
    else {
        const sheets = document.styleSheets;
        let found = false;
        for (const sheet of sheets) {
            try {
                for (const rule of sheet.cssRules) {
                    if (rule.selectorText && rule.selectorText.includes('.pu-block-children:hover') && rule.selectorText.includes('.pu-block-child')) {
                        found = true; break;
                    }
                }
            } catch(e) {}
            if (found) break;
        }
        found;
    }
" 2>/dev/null | tr -d '"')
if [ "$SIBLING_FADE" = "true" ]; then
    log_pass "Sibling fade CSS rule present"
elif [ "$SIBLING_FADE" = "not-enough" ]; then
    log_skip "Not enough siblings to test fade"
else
    log_fail "Sibling fade CSS rule missing"
fi

# ============================================================================
# TEST 6: Tighter vertical spacing
# ============================================================================
echo ""
log_info "TEST 6: Tighter vertical spacing"

CONTENT_PADDING=$(agent-browser eval "
    const c = document.querySelector('.pu-block-content');
    c ? getComputedStyle(c).paddingTop : 'not-found'
" 2>/dev/null | tr -d '"')
[ "$CONTENT_PADDING" = "8px" ] && log_pass "Root content padding-top: 8px" || log_fail "Root content padding-top: $CONTENT_PADDING (expected 8px)"

CHILD_PADDING=$(agent-browser eval "
    const c = document.querySelector('.pu-block-child .pu-block-content');
    c ? getComputedStyle(c).paddingTop : 'not-found'
" 2>/dev/null | tr -d '"')
[ "$CHILD_PADDING" = "8px" ] && log_pass "Child content padding-top: 8px (equal to root)" || log_fail "Child content padding-top: $CHILD_PADDING (expected 8px)"

# ============================================================================
# TEST 7: Nest button + child block styles
# ============================================================================
echo ""
log_info "TEST 7: Nest button + child block styles"

NEST_WIDTH=$(agent-browser eval "
    const btn = document.querySelector('.pu-nest-btn');
    btn ? getComputedStyle(btn).width : 'not-found'
" 2>/dev/null | tr -d '"')
[ "$NEST_WIDTH" = "28px" ] && log_pass "Nest button width: 28px" || log_fail "Nest button width: $NEST_WIDTH (expected 28px)"

NO_CHILD_BG=$(agent-browser eval "
    const child = document.querySelector('.pu-block-child');
    if (!child) 'no-child';
    else {
        const bg = getComputedStyle(child).backgroundColor;
        bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent' ? 'transparent' : bg;
    }
" 2>/dev/null | tr -d '"')
if [ "$NO_CHILD_BG" = "transparent" ]; then
    log_pass "Child block has transparent background"
elif [ "$NO_CHILD_BG" = "no-child" ]; then
    log_skip "No child block to check"
else
    log_info "Child block background: $NO_CHILD_BG"
fi

# No left border on children container
BORDER_LEFT=$(agent-browser eval "
    const c = document.querySelector('.pu-block-children');
    c ? getComputedStyle(c).borderLeftStyle : 'not-found'
" 2>/dev/null | tr -d '"')
[ "$BORDER_LEFT" = "none" ] || [ "$BORDER_LEFT" = "not-found" ] && log_pass "No left border on children container" || log_fail "Left border: $BORDER_LEFT"

# ============================================================================
# TEST 8: Pencil opens focus overlay
# ============================================================================
echo ""
log_info "TEST 8: Pencil opens focus overlay"

agent-browser eval "
    const btn = document.querySelector('.pu-inline-edit');
    if (btn) btn.click();
" 2>/dev/null
sleep 1

FOCUS_VISIBLE=$(agent-browser eval "
    const overlay = document.querySelector('[data-testid=\"pu-focus-overlay\"]');
    overlay && overlay.style.display !== 'none'
" 2>/dev/null)
[ "$FOCUS_VISIBLE" = "true" ] && log_pass "Pencil opens focus overlay" || log_fail "Focus overlay did not open"

agent-browser eval "
    const closeBtn = document.querySelector('[data-testid=\"pu-focus-close-btn\"]');
    if (closeBtn) closeBtn.click();
" 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 9: Delete shows confirmation state (red bg, yellow CONFIRM? + checkmark)
# ============================================================================
echo ""
log_info "TEST 9: Delete confirmation (inline)"

agent-browser eval "
    const btn = document.querySelector('.pu-inline-delete');
    if (btn) btn.click();
" 2>/dev/null
sleep 0.3

DELETE_CONFIRM=$(agent-browser eval "
    const btn = document.querySelector('.pu-inline-delete');
    btn ? btn.textContent.trim() : 'not-found'
" 2>/dev/null | tr -d '"')

if [ "$DELETE_CONFIRM" = "CONFIRM?" ]; then
    log_pass "Delete shows uppercase CONFIRM? text"
else
    log_fail "Delete confirmation text: '$DELETE_CONFIRM', expected 'CONFIRM?'"
fi

# Check red background and bright yellow text (#ffd54f = rgb(255, 213, 79))
CONFIRM_STYLE=$(agent-browser eval "(() => { const btn = document.querySelector('.pu-delete-confirm'); if (!btn) return 'not-found'; const cs = getComputedStyle(btn); const bg = cs.backgroundColor; const color = cs.color; return bg.includes('224') && color.includes('213') ? 'correct' : bg + '|' + color; })()" 2>/dev/null | tr -d '"')
if [ "$CONFIRM_STYLE" = "correct" ]; then
    log_pass "Confirm has red background + bright yellow text"
elif [ "$CONFIRM_STYLE" = "not-found" ]; then
    log_skip "No confirm element found"
else
    log_fail "Confirm style unexpected: $CONFIRM_STYLE"
fi

# Check checkmark SVG is present
HAS_CHECK=$(agent-browser eval "document.querySelector('.pu-delete-confirm svg polyline') ? 'yes' : 'no'" 2>/dev/null | tr -d '"')
[ "$HAS_CHECK" = "yes" ] && log_pass "Confirm has checkmark icon" || log_fail "Confirm missing checkmark icon"

# Hover-aware revert: confirm stays open while hovered, closes 1s after mouseleave
# Simulate mouseleave to trigger auto-revert timer
agent-browser eval "
    const btn = document.querySelector('.pu-delete-confirm');
    if (btn) btn.dispatchEvent(new MouseEvent('mouseleave', {bubbles: true}));
" 2>/dev/null
sleep 1.5

DELETE_REVERTED=$(agent-browser eval "
    const btn = document.querySelector('.pu-inline-delete');
    btn ? !btn.classList.contains('pu-delete-confirm') : 'not-found'
" 2>/dev/null)
[ "$DELETE_REVERTED" = "true" ] && log_pass "Delete confirm reverted after mouseleave + 1s" || log_info "Delete revert check: $DELETE_REVERTED"

# ============================================================================
# TEST 10: Unified actions for root and child
# ============================================================================
echo ""
log_info "TEST 10: Root vs child action split"

# Root: right-edge has both pencil + delete
ROOT_HAS_DELETE=$(agent-browser eval "
    const root = document.querySelector('.pu-block:not(.pu-block-child)');
    root ? !!root.querySelector('.pu-right-edge-actions .pu-inline-delete') : false
" 2>/dev/null)
[ "$ROOT_HAS_DELETE" = "true" ] && log_pass "Root block has delete in right-edge" || log_fail "Root block missing delete in right-edge"

# Child: right-edge has pencil only (no delete)
CHILD_NO_DELETE=$(agent-browser eval "(() => { const c = document.querySelector('.pu-block-child'); if (!c) return 'no-child'; return c.querySelector('.pu-right-edge-actions .pu-inline-delete') ? 'false' : 'true'; })()" 2>/dev/null | tr -d '"')
if [ "$CHILD_NO_DELETE" = "true" ]; then
    log_pass "Child right-edge has no delete (moved to path)"
elif [ "$CHILD_NO_DELETE" = "no-child" ]; then
    log_skip "No child blocks to test"
else
    log_fail "Child right-edge still has delete button"
fi

# Child: delete button is in path divider
CHILD_PATH_DELETE=$(agent-browser eval "(() => { const c = document.querySelector('.pu-block-child'); if (!c) return 'no-child'; return c.querySelector('.pu-path-divider .pu-path-delete') ? 'true' : 'false'; })()" 2>/dev/null | tr -d '"')
if [ "$CHILD_PATH_DELETE" = "true" ]; then
    log_pass "Child delete button in path divider"
elif [ "$CHILD_PATH_DELETE" = "no-child" ]; then
    log_skip "No child blocks to test"
else
    log_fail "Child delete not found in path divider"
fi

# Child path delete is hidden by default (opacity: 0)
PATH_DEL_OPACITY=$(agent-browser eval "
    const btn = document.querySelector('.pu-path-delete');
    btn ? getComputedStyle(btn).opacity : 'not-found'
" 2>/dev/null | tr -d '"')
if [ "$PATH_DEL_OPACITY" = "0" ]; then
    log_pass "Path delete hidden by default (opacity: 0)"
elif [ "$PATH_DEL_OPACITY" = "not-found" ]; then
    log_skip "No path delete button found"
else
    log_fail "Path delete opacity is $PATH_DEL_OPACITY, expected 0"
fi

# ============================================================================
# TEST 11: Tightened visualizer padding
# ============================================================================
echo ""
log_info "TEST 11: Tightened visualizer padding"

# Page is in typewriter mode — check root visualizer padding
VIZ_PADDING=$(agent-browser eval "
    const el = document.querySelector('.pu-resolved-text.pu-block-visualizer');
    el ? getComputedStyle(el).padding : 'not-found'
" 2>/dev/null | tr -d '"')
if echo "$VIZ_PADDING" | grep -q "12px 24px 24px"; then
    log_pass "Root visualizer padding tightened (12px 24px 24px)"
elif [ "$VIZ_PADDING" = "not-found" ]; then
    log_skip "No visualizer element found"
else
    log_fail "Root visualizer padding is '$VIZ_PADDING', expected 12px 24px 24px"
fi

# ============================================================================
# TEST 12: Right-edge centered within content area (not block-body)
# ============================================================================
echo ""
log_info "TEST 12: Right-edge centered within content area"

# Right-edge should be inside .pu-block-content (not .pu-block-body)
EDGE_IN_CONTENT=$(agent-browser eval "(() => {
    const edge = document.querySelector('.pu-right-edge-actions');
    if (!edge) return 'not-found';
    const parent = edge.parentElement;
    return parent && parent.classList.contains('pu-block-content') ? 'in-content' : 'outside';
})()" 2>/dev/null | tr -d '"')
[ "$EDGE_IN_CONTENT" = "in-content" ] && log_pass "Right-edge inside .pu-block-content (centered with text)" || log_fail "Right-edge placement: $EDGE_IN_CONTENT (expected in-content)"

# Right-edge uses justify-content: center
EDGE_CENTER=$(agent-browser eval "(() => {
    const edge = document.querySelector('.pu-right-edge-actions');
    if (!edge) return 'not-found';
    return getComputedStyle(edge).justifyContent;
})()" 2>/dev/null | tr -d '"')
[ "$EDGE_CENTER" = "center" ] && log_pass "Right-edge justify-content: center" || log_fail "Right-edge justify-content: $EDGE_CENTER (expected center)"

# ============================================================================
# TEST 13: Nest connector on leaf blocks (── + NEST)
# ============================================================================
echo ""
log_info "TEST 13: Nest connector on leaf blocks"

# Switch back to typewriter for this test
agent-browser open "${BASE_URL}/?job=hiring-templates&prompt=deep-culture-doc&viz=typewriter" 2>/dev/null
sleep 3

# Nest connector exists on leaf blocks (blocks without children)
HAS_NEST_CONN=$(agent-browser eval "!!document.querySelector('.pu-nest-connector')" 2>/dev/null)
[ "$HAS_NEST_CONN" = "true" ] && log_pass "Nest connector (.pu-nest-connector) found on page" || log_fail "Nest connector missing"

# Nest connector only on leaf blocks (no children)
NEST_ON_LEAF=$(agent-browser eval "(() => {
    const leafBlocks = document.querySelectorAll('.pu-block:not(.pu-has-children)');
    let found = false;
    leafBlocks.forEach(b => { if (b.querySelector('.pu-nest-connector')) found = true; });
    return found;
})()" 2>/dev/null)
[ "$NEST_ON_LEAF" = "true" ] && log_pass "Nest connector on leaf block (no children)" || log_fail "Nest connector not on leaf block"

# No nest connector on parent blocks (blocks with children)
NEST_ON_PARENT=$(agent-browser eval "(() => {
    const parents = document.querySelectorAll('.pu-has-children');
    let found = false;
    parents.forEach(b => {
        const body = b.querySelector(':scope > .pu-block-body');
        if (body && body.querySelector('.pu-nest-connector')) found = true;
    });
    return found;
})()" 2>/dev/null)
[ "$NEST_ON_PARENT" = "false" ] && log_pass "No nest connector on parent blocks" || log_fail "Nest connector found on parent block"

# Nest connector has correct parts (line, plus, NEST label)
NEST_PARTS=$(agent-browser eval "(() => {
    const nc = document.querySelector('.pu-nest-connector');
    if (!nc) return 'not-found';
    const line = nc.querySelector('.pu-nest-connector-line');
    const plus = nc.querySelector('.pu-nest-connector-plus');
    const label = nc.querySelector('.pu-nest-connector-label');
    return line && plus && label ? 'complete' : 'missing-parts';
})()" 2>/dev/null | tr -d '"')
[ "$NEST_PARTS" = "complete" ] && log_pass "Nest connector has line + plus + NEST label" || log_fail "Nest connector parts: $NEST_PARTS"

# Nest connector label text is "NEST"
NEST_LABEL=$(agent-browser eval "(() => {
    const label = document.querySelector('.pu-nest-connector-label');
    return label ? label.textContent : 'not-found';
})()" 2>/dev/null | tr -d '"')
[ "$NEST_LABEL" = "NEST" ] && log_pass "Nest connector label text: NEST" || log_fail "Nest connector label: $NEST_LABEL (expected NEST)"

# Nest connector hidden by default (opacity: 0)
NEST_OPACITY=$(agent-browser eval "(() => {
    const nc = document.querySelector('.pu-nest-connector');
    return nc ? getComputedStyle(nc).opacity : 'not-found';
})()" 2>/dev/null | tr -d '"')
[ "$NEST_OPACITY" = "0" ] && log_pass "Nest connector hidden by default (opacity: 0)" || log_fail "Nest connector opacity: $NEST_OPACITY (expected 0)"

# Nest connector is a <button> element
NEST_TAG=$(agent-browser eval "(() => {
    const nc = document.querySelector('.pu-nest-connector');
    return nc ? nc.tagName.toLowerCase() : 'not-found';
})()" 2>/dev/null | tr -d '"')
[ "$NEST_TAG" = "button" ] && log_pass "Nest connector is a <button> element" || log_fail "Nest connector tag: $NEST_TAG (expected button)"

# Nest connector has data-testid
NEST_TESTID=$(agent-browser eval "!!document.querySelector('[data-testid^=\"pu-nest-connector-\"]')" 2>/dev/null)
[ "$NEST_TESTID" = "true" ] && log_pass "Nest connector has data-testid" || log_fail "Nest connector missing data-testid"

# ============================================================================
# COMPACT VISUALIZER STYLE TESTS
# ============================================================================
echo ""
log_info "COMPACT VISUALIZER STYLE"

# Switch to compact mode
agent-browser open "${BASE_URL}/?job=hiring-templates&prompt=deep-culture-doc&viz=compact" 2>/dev/null
sleep 3

# Test: Resolved text uses 14px (--pu-font-size-base) font
FONT_SIZE=$(agent-browser eval "
    const el = document.querySelector('.pu-resolved-text');
    el ? getComputedStyle(el).fontSize : 'not-found'
" 2>/dev/null | tr -d '"')
if [ "$FONT_SIZE" = "14px" ]; then
    log_pass "Resolved text uses 14px font (--pu-font-size-base)"
elif [ "$FONT_SIZE" = "not-found" ]; then
    log_skip "No resolved text element found"
else
    log_fail "Resolved text font-size is $FONT_SIZE, expected 14px"
fi

# Test: Wildcard text values use body font (not monospace)
WC_FONT=$(agent-browser eval "(() => { const el = document.querySelector('.pu-wc-text-value'); if (!el) return 'not-found'; const ff = getComputedStyle(el).fontFamily; return ff.includes('monospace') || ff.includes('Mono') ? 'mono' : 'body'; })()" 2>/dev/null | tr -d '"')
if [ "$WC_FONT" = "body" ]; then
    log_pass "Wildcard text uses body font (not monospace)"
elif [ "$WC_FONT" = "not-found" ]; then
    log_skip "No wildcard text value found"
else
    log_fail "Wildcard text uses monospace font, expected body font"
fi

# Test: Wildcard text has dotted underline (not dashed)
WC_BORDER=$(agent-browser eval "(() => { const el = document.querySelector('.pu-wc-text-value'); if (!el) return 'not-found'; return getComputedStyle(el).borderBottomStyle; })()" 2>/dev/null | tr -d '"')
if [ "$WC_BORDER" = "dotted" ]; then
    log_pass "Wildcard text has dotted underline"
elif [ "$WC_BORDER" = "not-found" ]; then
    log_skip "No wildcard text value found"
else
    log_fail "Wildcard underline is '$WC_BORDER', expected 'dotted'"
fi

# Test: No accumulated text shown in compact mode
ACCUM=$(agent-browser eval "
    document.querySelector('.pu-accumulated-text') ? 'found' : 'none'
" 2>/dev/null | tr -d '"')
if [ "$ACCUM" = "none" ]; then
    log_pass "No accumulated text in compact mode"
else
    log_fail "Accumulated text still visible in compact mode"
fi

# Test: Compact mode uses inline path badge (not path divider) for children
HAS_INLINE_HINT=$(agent-browser eval "!!document.querySelector('.pu-child-path-hint')" 2>/dev/null)
if [ "$HAS_INLINE_HINT" = "true" ]; then
    log_pass "Compact mode has inline path badge (.pu-child-path-hint)"
else
    log_fail "Compact mode missing inline path badge"
fi

# Test: Compact mode has NO path divider for children
HAS_PATH_DIVIDER=$(agent-browser eval "!!document.querySelector('.pu-path-divider')" 2>/dev/null)
if [ "$HAS_PATH_DIVIDER" = "false" ]; then
    log_pass "Compact mode has no path divider (uses inline badge)"
else
    log_fail "Compact mode still has path divider (should only have inline badge)"
fi

# Test: Compact mode has NO right-edge actions (uses inline instead)
COMPACT_NO_RIGHT_EDGE=$(agent-browser eval "!document.querySelector('.pu-right-edge-actions')" 2>/dev/null)
[ "$COMPACT_NO_RIGHT_EDGE" = "true" ] && log_pass "Compact mode has no right-edge actions" || log_fail "Compact mode still has right-edge actions"

# Test: Compact mode has inline pencil (edit) after text
COMPACT_INLINE_EDIT=$(agent-browser eval "!!document.querySelector('.pu-compact-actions .pu-inline-edit')" 2>/dev/null)
[ "$COMPACT_INLINE_EDIT" = "true" ] && log_pass "Compact mode has inline pencil in .pu-compact-actions" || log_fail "Compact mode missing inline pencil"

# Test: Compact mode has inline delete after text
COMPACT_INLINE_DELETE=$(agent-browser eval "!!document.querySelector('.pu-compact-actions .pu-inline-delete')" 2>/dev/null)
[ "$COMPACT_INLINE_DELETE" = "true" ] && log_pass "Compact mode has inline delete in .pu-compact-actions" || log_fail "Compact mode missing inline delete"

# Test: Compact mode root block also has inline actions (not just children)
COMPACT_ROOT_INLINE=$(agent-browser eval "(() => { const root = document.querySelector('.pu-block:not(.pu-block-child)'); if (!root) return 'no-root'; return root.querySelector('.pu-compact-actions .pu-inline-edit') ? 'true' : 'false'; })()" 2>/dev/null | tr -d '"')
if [ "$COMPACT_ROOT_INLINE" = "true" ]; then
    log_pass "Compact mode root block has inline pencil+delete"
elif [ "$COMPACT_ROOT_INLINE" = "no-root" ]; then
    log_skip "No root blocks to test"
else
    log_fail "Compact mode root block missing inline actions"
fi

# Test: Compact mode content has no extra padding-right
COMPACT_PAD_RIGHT=$(agent-browser eval "
    const c = document.querySelector('.pu-block-content');
    c ? getComputedStyle(c).paddingRight : 'not-found'
" 2>/dev/null | tr -d '"')
if [ "$COMPACT_PAD_RIGHT" = "16px" ]; then
    log_pass "Compact mode content padding-right: 16px (no right-edge reservation)"
elif [ "$COMPACT_PAD_RIGHT" = "not-found" ]; then
    log_skip "No content element found"
else
    log_fail "Compact mode content padding-right: $COMPACT_PAD_RIGHT (expected 16px, no reservation)"
fi

# Test: data-viz attribute set on blocks container
DATA_VIZ=$(agent-browser eval "document.querySelector('[data-testid=\"pu-blocks-container\"]')?.dataset.viz" 2>/dev/null | tr -d '"')
[ "$DATA_VIZ" = "compact" ] && log_pass "Blocks container data-viz='compact'" || log_fail "data-viz is '$DATA_VIZ', expected 'compact'"

# Test: Inline path badge has mono font and correct size
HINT_FONT=$(agent-browser eval "(() => { const el = document.querySelector('.pu-child-path-hint'); if (!el) return 'not-found'; const cs = getComputedStyle(el); return cs.fontSize + '|' + (cs.fontFamily.includes('Mono') || cs.fontFamily.includes('monospace') ? 'mono' : 'body'); })()" 2>/dev/null | tr -d '"')
if [ "$HINT_FONT" = "10px|mono" ]; then
    log_pass "Inline path badge: 10px monospace font"
elif [ "$HINT_FONT" = "not-found" ]; then
    log_skip "No inline path badge found"
else
    log_fail "Inline path badge font: $HINT_FONT, expected 10px|mono"
fi

# Test: Nest connector present in compact mode
COMPACT_NEST=$(agent-browser eval "!!document.querySelector('.pu-nest-connector')" 2>/dev/null)
[ "$COMPACT_NEST" = "true" ] && log_pass "Compact mode has nest connector on leaf blocks" || log_fail "Compact mode missing nest connector"

# Test: Nest connector not on parent blocks in compact mode
COMPACT_NEST_PARENT=$(agent-browser eval "(() => {
    const parents = document.querySelectorAll('.pu-has-children');
    let found = false;
    parents.forEach(b => {
        const body = b.querySelector(':scope > .pu-block-body');
        if (body && body.querySelector('.pu-nest-connector')) found = true;
    });
    return found;
})()" 2>/dev/null)
[ "$COMPACT_NEST_PARENT" = "false" ] && log_pass "Compact mode: no nest connector on parent blocks" || log_fail "Compact mode: nest connector on parent block"

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
