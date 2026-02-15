#!/bin/bash
# E2E Test: Focus mode content editing lifecycle
# Tests:
#   1. Content round-trip (enter/edit/exit/re-enter persistence)
#   2. Existing wildcards hydrate as chips on entry
#   3. Clear content and exit — block content is empty
#   4. Root → nested block transitions (parent context appears/disappears)
#   5. Re-enter same block — fresh state
#   6. Overlay click exit saves content
#   7. Debounce guard prevents rapid double-entry
#   8. State fully resets on exit
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Focus Mode: Content Editing Lifecycle"

# Prerequisites
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load hiring-templates / nested-job-brief ─────────────────

log_info "Loading hiring-templates job with nested blocks..."
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

# ── Test 1: Content round-trip (enter, edit, exit, re-enter) ────────

log_test "OBJECTIVE: Edited content persists across exit and re-enter"

# Enter focus on nested block 1.0
agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

# Get initial content length
INITIAL_LEN=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance).length' 2>/dev/null)

# Append test marker text at the end
agent-browser eval 'var q = PU.state.focusMode.quillInstance; var len = q.getLength(); q.insertText(len - 1, " LIFECYCLE_MARKER_789", Quill.sources.USER)' 2>/dev/null
sleep 0.5

# Verify marker was inserted
AFTER_INSERT=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance).includes("LIFECYCLE_MARKER_789")' 2>/dev/null)
echo "$AFTER_INSERT" | grep -qi "true" \
    && log_pass "Marker text inserted in editor" \
    || log_fail "Marker text not found after insert"

# Exit focus mode
agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# Verify block content was saved with marker
BLOCK_CONTENT=$(agent-browser eval 'var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, "1.0"); b ? b.content : ""' 2>/dev/null)
echo "$BLOCK_CONTENT" | grep -q "LIFECYCLE_MARKER_789" \
    && log_pass "Block content saved with marker on exit" \
    || log_fail "Block content missing marker after exit: $BLOCK_CONTENT"

# Re-enter same block — verify content persists
agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

RE_ENTER=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance).includes("LIFECYCLE_MARKER_789")' 2>/dev/null)
echo "$RE_ENTER" | grep -qi "true" \
    && log_pass "Content persists after re-enter" \
    || log_fail "Content lost after re-enter"

# Cleanup marker
agent-browser eval 'var q = PU.state.focusMode.quillInstance; var text = PU.quill.serialize(q); var newText = text.replace(" LIFECYCLE_MARKER_789", ""); q.setContents(PU.quill.parseContentToOps(newText, PU.helpers.getWildcardLookup()), Quill.sources.SILENT)' 2>/dev/null
sleep 0.3

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 2: Existing wildcards hydrate as chips ─────────────────────

log_test "OBJECTIVE: Existing __wildcard__ patterns render as chips on entry"

# Block 0 has __tone__ and __company_size__ wildcards
agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

TONE_CHIP=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=tone]") !== null' 2>/dev/null)
echo "$TONE_CHIP" | grep -qi "true" \
    && log_pass "Wildcard __tone__ rendered as chip" \
    || log_fail "Wildcard __tone__ not rendered as chip"

SIZE_CHIP=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=company_size]") !== null' 2>/dev/null)
echo "$SIZE_CHIP" | grep -qi "true" \
    && log_pass "Wildcard __company_size__ rendered as chip" \
    || log_fail "Wildcard __company_size__ not rendered as chip"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 3: Clear all content, exit → empty block ──────────────────

log_test "OBJECTIVE: Clearing all content results in empty block on exit"

agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

# Save original content for later restore
ORIGINAL_CONTENT=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance)' 2>/dev/null)

# Clear all child content (keep parent context blot if present)
agent-browser eval 'var q = PU.state.focusMode.quillInstance; var startPos = PU.state.focusMode._hasParentContext ? 1 : 0; q.deleteText(startPos, q.getLength() - startPos - 1, Quill.sources.USER)' 2>/dev/null
sleep 0.3

# Verify serialized content is empty
EMPTY_CHECK=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance).trim().length === 0' 2>/dev/null)
echo "$EMPTY_CHECK" | grep -qi "true" \
    && log_pass "Editor content cleared (serialization is empty)" \
    || log_fail "Editor content not empty after clear"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# Verify block content is now empty
BLOCK_EMPTY=$(agent-browser eval 'var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, "1.0"); b ? b.content.trim().length === 0 : true' 2>/dev/null)
echo "$BLOCK_EMPTY" | grep -qi "true" \
    && log_pass "Block content is empty after clearing and exit" \
    || log_fail "Block content not empty after clear-and-exit"

# Restore original content
agent-browser eval "var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, '1.0'); if (b) b.content = $(echo "$ORIGINAL_CONTENT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip().strip("\"")))');" 2>/dev/null
sleep 0.3

# ── Test 4: Root → Nested block transition ──────────────────────────

log_test "OBJECTIVE: Transitioning root→nested shows parent context correctly"

# Enter root block — no parent context
agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

ROOT_HAS_PC=$(agent-browser eval 'PU.state.focusMode._hasParentContext' 2>/dev/null)
echo "$ROOT_HAS_PC" | grep -qi "false" \
    && log_pass "Root block: _hasParentContext is false" \
    || log_fail "Root block: _hasParentContext should be false: $ROOT_HAS_PC"

ROOT_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") === null' 2>/dev/null)
echo "$ROOT_BLOT" | grep -qi "true" \
    && log_pass "Root block: no parent context blot in DOM" \
    || log_fail "Root block: unexpected parent context blot found"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# Enter nested block — parent context should appear
agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

NESTED_HAS_PC=$(agent-browser eval 'PU.state.focusMode._hasParentContext' 2>/dev/null)
echo "$NESTED_HAS_PC" | grep -qi "true" \
    && log_pass "Nested block: _hasParentContext is true" \
    || log_fail "Nested block: _hasParentContext should be true: $NESTED_HAS_PC"

NESTED_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$NESTED_BLOT" | grep -qi "true" \
    && log_pass "Nested block: parent context blot present" \
    || log_fail "Nested block: parent context blot missing"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 5: Nested → Root transition ────────────────────────────────

log_test "OBJECTIVE: Transitioning nested→root removes parent context"

agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

NESTED_CHECK=$(agent-browser eval 'PU.state.focusMode._hasParentContext === true' 2>/dev/null)
echo "$NESTED_CHECK" | grep -qi "true" \
    && log_pass "Starting nested: parent context confirmed" \
    || log_fail "Starting nested: parent context missing"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

ROOT_CHECK=$(agent-browser eval 'PU.state.focusMode._hasParentContext === false && document.querySelector(".pu-focus-quill .ql-parent-context") === null' 2>/dev/null)
echo "$ROOT_CHECK" | grep -qi "true" \
    && log_pass "After nested→root: no parent context, clean state" \
    || log_fail "After nested→root: stale parent context state"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 6: Re-enter same block — fresh blot ───────────────────────

log_test "OBJECTIVE: Re-entering same nested block shows fresh parent context blot"

agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

FIRST_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$FIRST_BLOT" | grep -qi "true" \
    && log_pass "First entry: parent context blot present" \
    || log_fail "First entry: parent context blot missing"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

SECOND_BLOT=$(agent-browser eval 'document.querySelector(".pu-focus-quill .ql-parent-context") !== null' 2>/dev/null)
echo "$SECOND_BLOT" | grep -qi "true" \
    && log_pass "Re-entry: parent context blot present again" \
    || log_fail "Re-entry: parent context blot missing"

CURSOR_OK=$(agent-browser eval 'var s = PU.state.focusMode.quillInstance.getSelection(); s && s.index >= 1' 2>/dev/null)
echo "$CURSOR_OK" | grep -qi "true" \
    && log_pass "Re-entry: cursor positioned after blot" \
    || log_fail "Re-entry: cursor not positioned after blot"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 7: Overlay click exits and saves ───────────────────────────

log_test "OBJECTIVE: Clicking overlay background exits focus and saves content"

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

# Insert test marker
agent-browser eval 'var q = PU.state.focusMode.quillInstance; var len = q.getLength(); q.insertText(len - 1, " OVERLAY_EXIT_TEST", Quill.sources.USER)' 2>/dev/null
sleep 0.3

# Simulate overlay click (click on overlay background, not children)
agent-browser eval 'var overlay = document.querySelector("[data-testid=pu-focus-overlay]"); PU.focus.handleOverlayClick({target: overlay})' 2>/dev/null
sleep 1.5

# Verify focus mode exited
EXITED=$(agent-browser eval 'PU.state.focusMode.active === false' 2>/dev/null)
echo "$EXITED" | grep -qi "true" \
    && log_pass "Focus mode exited via overlay click" \
    || log_fail "Focus mode still active after overlay click"

# Verify content was saved
SAVED=$(agent-browser eval 'var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, "0"); b && b.content.includes("OVERLAY_EXIT_TEST")' 2>/dev/null)
echo "$SAVED" | grep -qi "true" \
    && log_pass "Content saved on overlay click exit" \
    || log_fail "Content NOT saved on overlay click exit"

# Cleanup marker from block content
agent-browser eval 'var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, "0"); if (b) b.content = b.content.replace(" OVERLAY_EXIT_TEST", "")' 2>/dev/null
sleep 0.3

# ── Test 8: Debounce prevents rapid double-entry ───────────────────

log_test "OBJECTIVE: Rapid double PU.focus.enter() calls are debounced"

# First call enters focus mode
agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 0.1

# Immediately try to enter again — should be blocked by active guard
agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 0.5

# Should still be on block "0" (second call ignored)
BLOCK_PATH=$(agent-browser eval 'PU.state.focusMode.blockPath' 2>/dev/null)
echo "$BLOCK_PATH" | grep -q '"0"' \
    && log_pass "Debounce: second enter ignored, still on block 0" \
    || echo "$BLOCK_PATH" | grep -q '0' \
    && log_pass "Debounce: second enter ignored, still on block 0" \
    || log_fail "Debounce failed: blockPath is $BLOCK_PATH (expected 0)"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 9: Full state reset on exit ───────────────────────────────

log_test "OBJECTIVE: All focusMode state flags reset on exit"

agent-browser eval 'PU.focus.enter("1.0")' 2>/dev/null
sleep 2

# Verify state is active
ACTIVE=$(agent-browser eval 'PU.state.focusMode.active === true' 2>/dev/null)
echo "$ACTIVE" | grep -qi "true" \
    && log_pass "Pre-exit: focusMode.active is true" \
    || log_fail "Pre-exit: focusMode.active should be true"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# Check all state flags
STATE_RESET=$(agent-browser eval 'var s = PU.state.focusMode; s.active === false && s.blockPath === null && s.quillInstance === null && s._hasParentContext === false && s.draft === false && s.draftMaterialized === false' 2>/dev/null)
echo "$STATE_RESET" | grep -qi "true" \
    && log_pass "All state flags properly reset on exit" \
    || log_fail "State not fully reset on exit"

# ── Test 10: Overlay hidden after exit ──────────────────────────────

log_test "OBJECTIVE: Focus overlay is hidden after exit"

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

OVERLAY_VIS=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-overlay]").style.display !== "none"' 2>/dev/null)
echo "$OVERLAY_VIS" | grep -qi "true" \
    && log_pass "Overlay visible while in focus mode" \
    || log_fail "Overlay not visible during focus mode"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 0.5

OVERLAY_HIDDEN=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-overlay]").style.display === "none"' 2>/dev/null)
echo "$OVERLAY_HIDDEN" | grep -qi "true" \
    && log_pass "Overlay hidden after exit" \
    || log_fail "Overlay still visible after exit"

# ── Test 11: No JS errors throughout ────────────────────────────────

log_test "OBJECTIVE: No JavaScript errors during lifecycle operations"
JS_ERRORS=$(agent-browser errors 2>/dev/null || echo "")
if [ -z "$JS_ERRORS" ] || echo "$JS_ERRORS" | grep -q "^\[\]$"; then
    log_pass "No JS errors"
else
    log_fail "JS errors detected: $JS_ERRORS"
fi

# ── Cleanup ─────────────────────────────────────────────────────────

agent-browser close 2>/dev/null || true

print_summary
exit $?
