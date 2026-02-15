#!/bin/bash
# E2E Test: Focus mode parent context blot protection + wildcard conversion
# Tests:
#   1. Parent context blot renders inline in focus mode for nested blocks
#   2. Parent context blot cannot be deleted (backspace/delete protection)
#   3. Cursor cannot be positioned before the blot
#   4. Ctrl+A selects only child content (not the blot)
#   5. __name__ wildcard patterns convert to chips correctly
#   6. Serialization excludes parent context blot
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Focus Mode: Parent Context Blot & Wildcard Conversion"

# Prerequisites
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load a job with nested blocks ────────────────────────────

log_info "Loading hiring-templates job with nested blocks..."
agent-browser open "$BASE_URL" 2>/dev/null
sleep 2

# Select hiring-templates job
agent-browser find text "hiring-templates" click 2>/dev/null
sleep 1

# Select the nested-job-brief prompt (has nested content blocks)
agent-browser find text "nested-job-brief" click 2>/dev/null
sleep 2

# Verify prompt loaded
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
if echo "$SNAPSHOT" | grep -q "nested-job-brief"; then
    log_pass "nested-job-brief prompt loaded"
else
    log_fail "Could not load nested-job-brief prompt"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

# ── Test 1: ParentContextBlot registered ─────────────────────────────

log_test "OBJECTIVE: ParentContextBlot is registered with Quill"
BLOT_REGISTERED=$(agent-browser eval 'try { !!Quill.import("formats/parentContext") } catch(e) { false }' 2>/dev/null)
echo "$BLOT_REGISTERED" | grep -qi "true" \
    && log_pass "ParentContextBlot registered with Quill" \
    || log_fail "ParentContextBlot not registered: $BLOT_REGISTERED"

# ── Test 2: Focus mode on nested block shows parent context blot ─────

log_test "OBJECTIVE: Nested block focus mode renders parent context inline"

# Enter focus mode on the nested child block (path 1.0)
agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

# Check that focus overlay is visible
OVERLAY_VISIBLE=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-overlay]").style.display !== "none"' 2>/dev/null)
echo "$OVERLAY_VISIBLE" | grep -qi "true" \
    && log_pass "Focus mode overlay opened" \
    || log_fail "Focus mode overlay not visible"

# Check parent context blot exists in the Quill editor
HAS_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$HAS_BLOT" | grep -qi "true" \
    && log_pass "Parent context blot rendered in Quill editor" \
    || log_fail "Parent context blot missing from Quill editor"

# Check that blot is contenteditable=false
BLOT_CE=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context")?.getAttribute("contenteditable")' 2>/dev/null)
echo "$BLOT_CE" | grep -qi "false" \
    && log_pass "Parent context blot is non-editable (contenteditable=false)" \
    || log_fail "Parent context blot contenteditable: $BLOT_CE"

# ── Test 3: _hasParentContext flag is set ─────────────────────────────

log_test "OBJECTIVE: State flag _hasParentContext is true for nested block"
HAS_FLAG=$(agent-browser eval 'PU.state.focusMode._hasParentContext === true' 2>/dev/null)
echo "$HAS_FLAG" | grep -qi "true" \
    && log_pass "_hasParentContext flag is true" \
    || log_fail "_hasParentContext flag is not true: $HAS_FLAG"

# ── Test 4: Cursor positioned after blot (not at end) ────────────────

log_test "OBJECTIVE: Cursor is at position >= 1 (not before blot)"
# Allow extra time for requestAnimationFrame autofocus
sleep 0.5
CURSOR_POS=$(agent-browser eval 'var s = PU.state.focusMode.quillInstance?.getSelection(); s ? s.index : -1' 2>/dev/null)
if [ -n "$CURSOR_POS" ] && [ "$CURSOR_POS" -ge 1 ] 2>/dev/null; then
    log_pass "Cursor at position $CURSOR_POS (>= 1, after blot)"
else
    log_fail "Cursor at position $CURSOR_POS (expected >= 1)"
fi

# ── Test 5: Backspace at position 1 does NOT delete blot ─────────────

log_test "OBJECTIVE: Backspace at blot boundary does not delete parent context"

# Position cursor at 1 and press Backspace
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.focus(); q.setSelection(1, 0)' 2>/dev/null
sleep 0.3

agent-browser press Backspace 2>/dev/null
sleep 0.5

BLOT_AFTER_BS=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$BLOT_AFTER_BS" | grep -qi "true" \
    && log_pass "Parent context blot survives Backspace" \
    || log_fail "Parent context blot deleted by Backspace"

# ── Test 6: Delete key at position 0/1 does NOT delete blot ──────────

log_test "OBJECTIVE: Delete key does not remove parent context"

agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.focus(); q.setSelection(1, 0)' 2>/dev/null
sleep 0.3

agent-browser press Delete 2>/dev/null
sleep 0.5

BLOT_AFTER_DEL=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$BLOT_AFTER_DEL" | grep -qi "true" \
    && log_pass "Parent context blot survives Delete key" \
    || log_fail "Parent context blot deleted by Delete key"

# ── Test 7: Cursor cannot land at position 0 ─────────────────────────

log_test "OBJECTIVE: Cursor snaps from position 0 to >= 1"
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.setSelection(0, 0, Quill.sources.USER)' 2>/dev/null
sleep 0.5
SNAP_POS=$(agent-browser eval 'var s = PU.state.focusMode.quillInstance?.getSelection(); s ? s.index : -1' 2>/dev/null)
if [ -n "$SNAP_POS" ] && [ "$SNAP_POS" -ge 1 ] 2>/dev/null; then
    log_pass "Cursor snapped to $SNAP_POS (>= 1)"
else
    log_fail "Cursor at position $SNAP_POS (expected >= 1)"
fi

# ── Test 8: Ctrl+A selects child content only ─────────────────────────

log_test "OBJECTIVE: Ctrl+A handler selects from position 1 (excludes blot)"
CTRL_A_IDX=$(agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.setSelection(1, q.getLength() - 2); var s = q.getSelection(); s ? s.index : -1' 2>/dev/null)
if [ "$CTRL_A_IDX" = "1" ]; then
    log_pass "Ctrl+A selection starts at position 1 (excludes blot)"
else
    log_fail "Ctrl+A selection starts at $CTRL_A_IDX (expected 1)"
fi

# ── Test 9: Serialization excludes parent context ─────────────────────

log_test "OBJECTIVE: serialize() returns only child content, not parent context"
EXCLUDES_PARENT=$(agent-browser eval 'var s = PU.quill.serialize(PU.state.focusMode.quillInstance); !s.includes("Draft a job brief")' 2>/dev/null)
echo "$EXCLUDES_PARENT" | grep -qi "true" \
    && log_pass "Serialization excludes parent context text" \
    || log_fail "Serialization includes parent text"

SERIAL_CONTENT=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance).substring(0, 60)' 2>/dev/null)
log_info "Serialized content: $SERIAL_CONTENT"

# ── Test 10: Exit and verify state reset ──────────────────────────────

log_test "OBJECTIVE: Exit focus mode resets _hasParentContext"
agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

FLAG_RESET=$(agent-browser eval 'PU.state.focusMode._hasParentContext === false && PU.state.focusMode.active === false' 2>/dev/null)
echo "$FLAG_RESET" | grep -qi "true" \
    && log_pass "_hasParentContext reset to false on exit" \
    || log_fail "_hasParentContext not reset on exit: $FLAG_RESET"

# ── Test 11: Root block has NO parent context ─────────────────────────

log_test "OBJECTIVE: Root block (path 0) shows no parent context in focus mode"
agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

ROOT_HAS_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
ROOT_FLAG=$(agent-browser eval 'PU.state.focusMode._hasParentContext' 2>/dev/null)
echo "$ROOT_HAS_BLOT" | grep -qi "false" \
    && log_pass "Root block has no parent context blot" \
    || log_fail "Root block has unexpected parent context blot: $ROOT_HAS_BLOT"

# ── Test 12: convertWildcardsInline converts __name__ to chip ─────────

log_test "OBJECTIVE: convertWildcardsInline converts __name__ pattern to chip"

# Clear content and insert test text, then convert
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.deleteText(0, q.getLength()-1, Quill.sources.SILENT); q.insertText(0, "Hello __testrole__ world", Quill.sources.SILENT); PU.quill.convertWildcardsInline(q)' 2>/dev/null
sleep 0.5

CHIP_FOUND=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=testrole]") !== null' 2>/dev/null)
echo "$CHIP_FOUND" | grep -qi "true" \
    && log_pass "Wildcard __testrole__ converted to chip" \
    || log_fail "Wildcard __testrole__ NOT converted to chip"

# Verify serialization roundtrip
ROUNDTRIP=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance)' 2>/dev/null)
if echo "$ROUNDTRIP" | grep -q "Hello __testrole__ world"; then
    log_pass "Serialization roundtrip: Hello __testrole__ world"
else
    log_fail "Serialization roundtrip wrong: $ROUNDTRIP"
fi

# ── Test 13: handleTextChange converts complete __name__ pattern ──────

log_test "OBJECTIVE: handleTextChange detects complete __name__ (not trapped by autocomplete)"

# Clear, insert text, set cursor, call handleTextChange
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.deleteText(0, q.getLength()-1, Quill.sources.SILENT); q.insertText(0, "Test __newwc__", Quill.sources.SILENT); q.setSelection(14, 0, Quill.sources.SILENT); PU.focus.handleTextChange("0", q)' 2>/dev/null
sleep 0.5

CHIP_FOUND2=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=newwc]") !== null' 2>/dev/null)
AC_OPEN=$(agent-browser eval 'PU.quill._autocompleteOpen' 2>/dev/null)

echo "$CHIP_FOUND2" | grep -qi "true" \
    && log_pass "handleTextChange converts __newwc__ to chip" \
    || log_fail "handleTextChange did not convert __newwc__: chip=$CHIP_FOUND2"

echo "$AC_OPEN" | grep -qi "false" \
    && log_pass "Autocomplete closed after complete wildcard" \
    || log_fail "Autocomplete still open: $AC_OPEN"

# ── Test 14: Wildcard conversion with parent context blot present ──────

log_test "OBJECTIVE: __test__ conversion preserves parent context blot (regression)"

# Exit current and enter nested block focus (has parent context)
agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1
agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

# Verify parent context blot is present
PRE_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$PRE_BLOT" | grep -qi "true" \
    && log_pass "Parent context blot present before wildcard conversion" \
    || log_fail "Parent context blot missing before test"

# Type __test__ after the existing content and trigger conversion
agent-browser eval 'var q = PU.state.focusMode.quillInstance; var len = q.getLength(); q.insertText(len - 1, " __testwc__", Quill.sources.SILENT); q.setSelection(len + 10, 0, Quill.sources.SILENT); PU.quill.convertWildcardsInline(q)' 2>/dev/null
sleep 0.5

# The parent context blot must STILL exist
POST_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$POST_BLOT" | grep -qi "true" \
    && log_pass "Parent context blot survives wildcard conversion" \
    || log_fail "Parent context blot DESTROYED by wildcard conversion"

# The wildcard chip must exist
WC_CHIP=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=testwc]") !== null' 2>/dev/null)
echo "$WC_CHIP" | grep -qi "true" \
    && log_pass "Wildcard chip __testwc__ created alongside parent context" \
    || log_fail "Wildcard chip __testwc__ not created"

# ── Test 15: No JS errors throughout ──────────────────────────────────

log_test "OBJECTIVE: No JavaScript errors during focus mode operations"
JS_ERRORS=$(agent-browser errors 2>/dev/null || echo "")
if [ -z "$JS_ERRORS" ] || echo "$JS_ERRORS" | grep -q "^\[\]$"; then
    log_pass "No JS errors"
else
    log_fail "JS errors detected: $JS_ERRORS"
fi

# ── Cleanup ───────────────────────────────────────────────────────────

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 0.5
agent-browser close 2>/dev/null || true

print_summary
exit $?
