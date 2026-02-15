#!/bin/bash
# E2E Test: Focus overlay interaction fixes
# Tests:
#   1. Click outside overlay does NOT close it (refocuses editor instead)
#   2. Wildcard click in parent context blot refocuses Quill editor
#   3. Popover shows when cursor is at left edge of wildcard chip (offset 0)
#   4. Popover shows when cursor is at right edge of wildcard chip (offset -1)
#   5. Popover does NOT show when cursor is one position before chip
#   6. Popover does NOT show when cursor is one position after chip
#   7. Editor remains focused after parent context wildcard click (even when empty)
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Focus Overlay: Click-Outside, Wildcard Refocus & Popover Adjacency"

# Prerequisites
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load hiring-templates / nested-job-brief ─────────────────

log_info "Loading hiring-templates job..."
agent-browser open "$BASE_URL" 2>/dev/null
sleep 2

agent-browser find text "hiring-templates" click 2>/dev/null
sleep 1
agent-browser find text "nested-job-brief" click 2>/dev/null
sleep 2

SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
if echo "$SNAPSHOT" | grep -q "nested-job-brief"; then
    log_pass "nested-job-brief prompt loaded"
else
    log_fail "Could not load nested-job-brief prompt"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════
# SECTION A: Click-outside does NOT close overlay
# ══════════════════════════════════════════════════════════════════════

log_test "OBJECTIVE: Click on overlay background does NOT close focus mode"

# Enter focus mode on root block
agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

# Verify overlay is visible
OVERLAY_VIS=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-overlay]").classList.contains("pu-focus-visible")' 2>/dev/null)
echo "$OVERLAY_VIS" | grep -qi "true" \
    && log_pass "Focus overlay is visible" \
    || log_fail "Focus overlay not visible"

# Simulate click on the overlay background (calls handleOverlayClick)
agent-browser eval 'PU.focus.handleOverlayClick({ target: document.querySelector("[data-testid=pu-focus-overlay]") })' 2>/dev/null
sleep 0.5

# Overlay should STILL be visible (not closed)
STILL_ACTIVE=$(agent-browser eval 'PU.state.focusMode.active === true' 2>/dev/null)
echo "$STILL_ACTIVE" | grep -qi "true" \
    && log_pass "Focus mode still active after overlay click" \
    || log_fail "Focus mode closed after overlay click"

# Editor should be focused
HAS_SEL=$(agent-browser eval 'PU.state.focusMode.quillInstance?.getSelection() !== null' 2>/dev/null)
echo "$HAS_SEL" | grep -qi "true" \
    && log_pass "Quill editor has selection after overlay click" \
    || log_fail "Quill editor lost selection after overlay click"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ══════════════════════════════════════════════════════════════════════
# SECTION B: Wildcard click in parent context blot refocuses editor
# ══════════════════════════════════════════════════════════════════════

log_test "OBJECTIVE: Clicking wildcard in parent context blot refocuses Quill editor"

# Enter focus on nested block (has parent context)
agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

# Verify parent context blot exists with wildcard values
HAS_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$HAS_BLOT" | grep -qi "true" \
    && log_pass "Parent context blot present in nested block" \
    || log_fail "Parent context blot missing"

HAS_WC_VALUES=$(agent-browser eval 'document.querySelectorAll(".pu-focus-quill .ql-parent-context .pu-wc-text-value").length > 0' 2>/dev/null)
echo "$HAS_WC_VALUES" | grep -qi "true" \
    && log_pass "Parent context blot contains wildcard values" \
    || log_fail "No wildcard values in parent context blot"

# Simulate clicking a wildcard value in the parent context blot
# This triggers the click handler which should cycle value + refocus editor
agent-browser eval '
    var wcEl = document.querySelector(".pu-focus-quill .ql-parent-context .pu-wc-text-value");
    if (wcEl) {
        var evt = new MouseEvent("click", { bubbles: true, cancelable: true });
        wcEl.dispatchEvent(evt);
    }
' 2>/dev/null
sleep 0.5

# After click, editor should still have focus with valid cursor position
REFOCUSED=$(agent-browser eval '
    var q = PU.state.focusMode.quillInstance;
    var sel = q ? q.getSelection() : null;
    sel !== null && sel.index >= 1
' 2>/dev/null)
echo "$REFOCUSED" | grep -qi "true" \
    && log_pass "Quill editor refocused after parent context wildcard click" \
    || log_fail "Quill editor lost focus after parent context wildcard click"

# Verify cursor is at valid position (>= 1, after parent context blot)
CURSOR_POS=$(agent-browser eval 'var s = PU.state.focusMode.quillInstance?.getSelection(); s ? s.index : -1' 2>/dev/null)
if [ -n "$CURSOR_POS" ] && [ "$CURSOR_POS" -ge 1 ] 2>/dev/null; then
    log_pass "Cursor at position $CURSOR_POS after wildcard click (>= 1)"
else
    log_fail "Cursor at invalid position $CURSOR_POS after wildcard click"
fi

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test: Refocus works even when editor content is empty ──────────

log_test "OBJECTIVE: Wildcard click refocuses editor even when content is empty"

agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

# Clear all child content (leave only parent context blot)
agent-browser eval '
    var q = PU.state.focusMode.quillInstance;
    if (q) {
        var len = q.getLength();
        // Delete from pos 1 (after blot) to end, keeping the blot at pos 0
        if (len > 2) q.deleteText(1, len - 2, Quill.sources.SILENT);
    }
' 2>/dev/null
sleep 0.3

# Click a wildcard in parent context when editor body is empty
agent-browser eval '
    var wcEl = document.querySelector(".pu-focus-quill .ql-parent-context .pu-wc-text-value");
    if (wcEl) wcEl.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
' 2>/dev/null
sleep 0.5

REFOCUSED_EMPTY=$(agent-browser eval '
    var q = PU.state.focusMode.quillInstance;
    var sel = q ? q.getSelection() : null;
    sel !== null
' 2>/dev/null)
echo "$REFOCUSED_EMPTY" | grep -qi "true" \
    && log_pass "Quill editor refocused with empty content after wildcard click" \
    || log_fail "Quill editor not focused with empty content"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ══════════════════════════════════════════════════════════════════════
# SECTION C: Popover adjacency — only at chip boundaries
# ══════════════════════════════════════════════════════════════════════

log_test "OBJECTIVE: Popover appears ONLY at wildcard chip boundaries (left/right edge)"

# Set up a block with known content: "Hello __tone__ world"
agent-browser eval "
    var p = PU.helpers.getActivePrompt();
    var b = PU.blocks.findBlockByPath(p.text, '0');
    if (b) b.content = 'Hello __tone__ world';
" 2>/dev/null
sleep 0.3

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

# Close any existing popover
agent-browser eval 'if (PU.wildcardPopover?._open) PU.wildcardPopover.close()' 2>/dev/null
sleep 0.3

# Find the wildcard chip position in the Quill document
# Content: "Hello " (6 chars) + [wildcard embed at pos 6] + " world" (7 chars)
# So chip is at index 6
CHIP_INDEX=$(agent-browser eval '
    var q = PU.state.focusMode.quillInstance;
    var delta = q.getContents();
    var pos = 0;
    for (var i = 0; i < delta.ops.length; i++) {
        var op = delta.ops[i];
        if (op.insert && op.insert.wildcard && op.insert.wildcard.name === "tone") {
            break;
        }
        if (typeof op.insert === "string") pos += op.insert.length;
        else pos += 1;
    }
    pos;
' 2>/dev/null)
log_info "Wildcard chip 'tone' at document index: $CHIP_INDEX"

# ── Test C1: Cursor at left edge of chip (offset 0) → popover shows ──

log_test "OBJECTIVE: Cursor at left edge of chip triggers popover"

agent-browser eval "
    if (PU.wildcardPopover?._open) PU.wildcardPopover.close();
    var q = PU.state.focusMode.quillInstance;
    q.setSelection($CHIP_INDEX, 0, Quill.sources.USER);
" 2>/dev/null
sleep 0.8

LEFT_EDGE_WC=$(agent-browser eval 'PU.quill.getAdjacentWildcardName(PU.state.focusMode.quillInstance)' 2>/dev/null)
echo "$LEFT_EDGE_WC" | grep -q "tone" \
    && log_pass "Left edge (index $CHIP_INDEX): detected wildcard 'tone'" \
    || log_fail "Left edge (index $CHIP_INDEX): no wildcard detected, got: $LEFT_EDGE_WC"

LEFT_POPOVER=$(agent-browser eval 'PU.wildcardPopover?._open === true' 2>/dev/null)
echo "$LEFT_POPOVER" | grep -qi "true" \
    && log_pass "Popover opened at left edge of chip" \
    || log_fail "Popover NOT opened at left edge of chip"

# ── Test C2: Cursor at right edge of chip (offset -1) → popover shows ──

log_test "OBJECTIVE: Cursor at right edge of chip triggers popover"

agent-browser eval "
    if (PU.wildcardPopover?._open) PU.wildcardPopover.close();
    var q = PU.state.focusMode.quillInstance;
    q.setSelection($CHIP_INDEX + 1, 0, Quill.sources.USER);
" 2>/dev/null
sleep 0.8

RIGHT_EDGE_WC=$(agent-browser eval 'PU.quill.getAdjacentWildcardName(PU.state.focusMode.quillInstance)' 2>/dev/null)
echo "$RIGHT_EDGE_WC" | grep -q "tone" \
    && log_pass "Right edge (index $(($CHIP_INDEX + 1))): detected wildcard 'tone'" \
    || log_fail "Right edge (index $(($CHIP_INDEX + 1))): no wildcard detected, got: $RIGHT_EDGE_WC"

RIGHT_POPOVER=$(agent-browser eval 'PU.wildcardPopover?._open === true' 2>/dev/null)
echo "$RIGHT_POPOVER" | grep -qi "true" \
    && log_pass "Popover opened at right edge of chip" \
    || log_fail "Popover NOT opened at right edge of chip"

# ── Test C3: Cursor one position BEFORE chip → NO popover ─────────────

log_test "OBJECTIVE: Cursor one position before chip does NOT trigger popover"

agent-browser eval "
    if (PU.wildcardPopover?._open) PU.wildcardPopover.close();
    var q = PU.state.focusMode.quillInstance;
    q.setSelection($CHIP_INDEX - 1, 0, Quill.sources.USER);
" 2>/dev/null
sleep 0.8

BEFORE_WC=$(agent-browser eval 'PU.quill.getAdjacentWildcardName(PU.state.focusMode.quillInstance)' 2>/dev/null)
BEFORE_POPOVER=$(agent-browser eval 'PU.wildcardPopover?._open === true' 2>/dev/null)

if echo "$BEFORE_WC" | grep -qi "null\|undefined\|^$"; then
    log_pass "One before chip (index $(($CHIP_INDEX - 1))): no wildcard detected"
else
    log_fail "One before chip (index $(($CHIP_INDEX - 1))): falsely detected '$BEFORE_WC'"
fi

echo "$BEFORE_POPOVER" | grep -qi "false\|undefined" \
    && log_pass "Popover NOT opened one position before chip" \
    || log_fail "Popover incorrectly opened one position before chip"

# ── Test C4: Cursor one position AFTER chip → NO popover ──────────────

log_test "OBJECTIVE: Cursor one position after right edge does NOT trigger popover"

agent-browser eval "
    if (PU.wildcardPopover?._open) PU.wildcardPopover.close();
    var q = PU.state.focusMode.quillInstance;
    q.setSelection($CHIP_INDEX + 2, 0, Quill.sources.USER);
" 2>/dev/null
sleep 0.8

AFTER_WC=$(agent-browser eval 'PU.quill.getAdjacentWildcardName(PU.state.focusMode.quillInstance)' 2>/dev/null)
AFTER_POPOVER=$(agent-browser eval 'PU.wildcardPopover?._open === true' 2>/dev/null)

if echo "$AFTER_WC" | grep -qi "null\|undefined\|^$"; then
    log_pass "One after chip (index $(($CHIP_INDEX + 2))): no wildcard detected"
else
    log_fail "One after chip (index $(($CHIP_INDEX + 2))): falsely detected '$AFTER_WC'"
fi

echo "$AFTER_POPOVER" | grep -qi "false\|undefined" \
    && log_pass "Popover NOT opened one position after chip" \
    || log_fail "Popover incorrectly opened one position after chip"

# ── Test C5: Cursor far from chip → NO popover ──────────────────────

log_test "OBJECTIVE: Cursor far from chip (position 0) does NOT trigger popover"

agent-browser eval '
    if (PU.wildcardPopover?._open) PU.wildcardPopover.close();
    var q = PU.state.focusMode.quillInstance;
    q.setSelection(0, 0, Quill.sources.USER);
' 2>/dev/null
sleep 0.8

FAR_WC=$(agent-browser eval 'PU.quill.getAdjacentWildcardName(PU.state.focusMode.quillInstance)' 2>/dev/null)
if echo "$FAR_WC" | grep -qi "null\|undefined\|^$"; then
    log_pass "Far from chip (position 0): no wildcard detected"
else
    log_fail "Far from chip (position 0): falsely detected '$FAR_WC'"
fi

# ── Test C6: getAdjacentWildcardChipEl matches getAdjacentWildcardName ──

log_test "OBJECTIVE: getAdjacentWildcardChipEl returns element only at chip boundaries"

# At chip left edge — should return element
CHIP_EL_LEFT=$(agent-browser eval "
    var q = PU.state.focusMode.quillInstance;
    q.setSelection($CHIP_INDEX, 0, Quill.sources.SILENT);
    PU.quill.getAdjacentWildcardChipEl(q) !== null;
" 2>/dev/null)
echo "$CHIP_EL_LEFT" | grep -qi "true" \
    && log_pass "getAdjacentWildcardChipEl returns element at left edge" \
    || log_fail "getAdjacentWildcardChipEl returns null at left edge"

# At chip right edge — should return element
CHIP_EL_RIGHT=$(agent-browser eval "
    var q = PU.state.focusMode.quillInstance;
    q.setSelection($CHIP_INDEX + 1, 0, Quill.sources.SILENT);
    PU.quill.getAdjacentWildcardChipEl(q) !== null;
" 2>/dev/null)
echo "$CHIP_EL_RIGHT" | grep -qi "true" \
    && log_pass "getAdjacentWildcardChipEl returns element at right edge" \
    || log_fail "getAdjacentWildcardChipEl returns null at right edge"

# One position before — should NOT return element
CHIP_EL_BEFORE=$(agent-browser eval "
    var q = PU.state.focusMode.quillInstance;
    q.setSelection($CHIP_INDEX - 1, 0, Quill.sources.SILENT);
    PU.quill.getAdjacentWildcardChipEl(q) === null;
" 2>/dev/null)
echo "$CHIP_EL_BEFORE" | grep -qi "true" \
    && log_pass "getAdjacentWildcardChipEl returns null one before chip" \
    || log_fail "getAdjacentWildcardChipEl falsely returns element one before chip"

# One position after — should NOT return element
CHIP_EL_AFTER=$(agent-browser eval "
    var q = PU.state.focusMode.quillInstance;
    q.setSelection($CHIP_INDEX + 2, 0, Quill.sources.SILENT);
    PU.quill.getAdjacentWildcardChipEl(q) === null;
" 2>/dev/null)
echo "$CHIP_EL_AFTER" | grep -qi "true" \
    && log_pass "getAdjacentWildcardChipEl returns null one after chip" \
    || log_fail "getAdjacentWildcardChipEl falsely returns element one after chip"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test: No JS errors throughout ─────────────────────────────────

log_test "OBJECTIVE: No JavaScript errors during all operations"
JS_ERRORS=$(agent-browser errors 2>/dev/null || echo "")
if [ -z "$JS_ERRORS" ] || echo "$JS_ERRORS" | grep -q "^\[\]$"; then
    log_pass "No JS errors"
else
    log_fail "JS errors detected: $JS_ERRORS"
fi

# ── Cleanup ───────────────────────────────────────────────────────

# Restore block 0 content
agent-browser eval "
    var p = PU.helpers.getActivePrompt();
    var b = PU.blocks.findBlockByPath(p.text, '0');
    if (b) b.content = 'You are a __tone__ HR consultant for a __company_size__ company';
" 2>/dev/null
sleep 0.3

agent-browser close 2>/dev/null || true

print_summary
exit $?
