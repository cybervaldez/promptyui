#!/bin/bash
# E2E Test: Focus mode wildcard popover + force-values behavior
# Tests:
#   1. Type __newwc__ → popover auto-opens with _forceValues
#   2. Close popover without values → chip removed
#   3. Type __newwc__ → add values → close → chip preserved
#   4. Existing defined wildcard → passive popover (hint, no input), no force-values
#   5. Autocomplete select undefined → active popover (input focused), force-values
#   6. Colon shortcut __name: → popover opens with force-values
#   7. Value addition updates chip preview
#   8. _forceValues flag resets on close
#   9. Chip removal syncs block content
#  10. Main editor filter tree footer hidden when no filters
#  11. Main editor filter tree footer visible when filters active
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Focus Mode: Wildcard Popover & Force-Values"

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

# Save original block 0 content for later restoration
ORIG_BLOCK0=$(agent-browser eval 'var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, "0"); b ? b.content : ""' 2>/dev/null)

# ── Test 1: Type __newwc__ → popover auto-opens ─────────────────────

log_test "OBJECTIVE: Complete wildcard __newwc__ triggers popover auto-open"

# Enter focus on root block (no parent context — simpler)
agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

# Clear content and insert text with new undefined wildcard
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.deleteText(0, q.getLength()-1, Quill.sources.SILENT); q.insertText(0, "Hello __poptest1__", Quill.sources.SILENT); q.setSelection(18, 0, Quill.sources.SILENT); PU.focus.handleTextChange("0", q)' 2>/dev/null
sleep 1

# Check popover is open
POPOVER_OPEN=$(agent-browser eval 'PU.wildcardPopover._open === true' 2>/dev/null)
echo "$POPOVER_OPEN" | grep -qi "true" \
    && log_pass "Popover auto-opened after __poptest1__" \
    || log_fail "Popover not open after __poptest1__"

# Check _forceValues is set
FORCE_FLAG=$(agent-browser eval 'PU.wildcardPopover._forceValues === true' 2>/dev/null)
echo "$FORCE_FLAG" | grep -qi "true" \
    && log_pass "_forceValues is true for new wildcard" \
    || log_fail "_forceValues not set: $FORCE_FLAG"

# Check the popover is for the right wildcard
POPOVER_WC=$(agent-browser eval 'PU.wildcardPopover._wildcardName' 2>/dev/null)
echo "$POPOVER_WC" | grep -q "poptest1" \
    && log_pass "Popover targets correct wildcard: poptest1" \
    || log_fail "Popover targets wrong wildcard: $POPOVER_WC"

# ── Test 2: Close without values → chip removed ─────────────────────

log_test "OBJECTIVE: Closing force-values popover without adding values removes chip"

# Chip exists before close
PRE_CHIP=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=poptest1]") !== null' 2>/dev/null)
echo "$PRE_CHIP" | grep -qi "true" \
    && log_pass "Chip exists before popover close" \
    || log_fail "Chip missing before popover close"

# Close popover without adding values
agent-browser eval 'PU.wildcardPopover.close()' 2>/dev/null
sleep 0.5

# Chip should be removed
POST_CHIP=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=poptest1]") !== null' 2>/dev/null)
echo "$POST_CHIP" | grep -qi "false" \
    && log_pass "Chip removed after close without values" \
    || log_fail "Chip still present after close without values"

# Serialized content should not contain __poptest1__
SERIAL=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance)' 2>/dev/null)
echo "$SERIAL" | grep -qv "poptest1" \
    && log_pass "Serialized content has no __poptest1__" \
    || log_fail "Serialized content still has poptest1: $SERIAL"

# ── Test 3: _forceValues resets after close ──────────────────────────

log_test "OBJECTIVE: _forceValues flag resets to false after close"

FORCE_RESET=$(agent-browser eval 'PU.wildcardPopover._forceValues === false' 2>/dev/null)
echo "$FORCE_RESET" | grep -qi "true" \
    && log_pass "_forceValues reset to false after close" \
    || log_fail "_forceValues still true after close"

# ── Test 4: Add values then close → chip preserved ──────────────────

log_test "OBJECTIVE: Adding values before close preserves the chip"

# Insert a new wildcard and trigger conversion
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.deleteText(0, q.getLength()-1, Quill.sources.SILENT); q.insertText(0, "Test __poptest2__", Quill.sources.SILENT); q.setSelection(17, 0, Quill.sources.SILENT); PU.focus.handleTextChange("0", q)' 2>/dev/null
sleep 1

# Verify popover opened
POP_OPEN2=$(agent-browser eval 'PU.wildcardPopover._open === true && PU.wildcardPopover._forceValues === true' 2>/dev/null)
echo "$POP_OPEN2" | grep -qi "true" \
    && log_pass "Popover opened with force-values for poptest2" \
    || log_fail "Popover not correctly opened for poptest2"

# Add values via the popover API
agent-browser eval 'PU.wildcardPopover.addValues("value_a, value_b")' 2>/dev/null
sleep 0.5

# Close the popover
agent-browser eval 'PU.wildcardPopover.close()' 2>/dev/null
sleep 0.5

# Chip should still exist (values were added)
CHIP_PRESERVED=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=poptest2]") !== null' 2>/dev/null)
echo "$CHIP_PRESERVED" | grep -qi "true" \
    && log_pass "Chip preserved after adding values and closing" \
    || log_fail "Chip removed even though values were added"

# Chip should no longer be marked undefined
CHIP_DEFINED=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=poptest2]").classList.contains("ql-wc-undefined") === false' 2>/dev/null)
echo "$CHIP_DEFINED" | grep -qi "true" \
    && log_pass "Chip no longer marked undefined after values added" \
    || log_fail "Chip still marked undefined"

# ── Test 5: Chip preview shows values ────────────────────────────────

log_test "OBJECTIVE: Chip preview text shows the added values"

PREVIEW_TEXT=$(agent-browser eval 'var chip = PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=poptest2] .ql-wc-preview"); chip ? chip.textContent : ""' 2>/dev/null)
echo "$PREVIEW_TEXT" | grep -q "value_a" \
    && log_pass "Chip preview contains value_a" \
    || log_fail "Chip preview missing value_a: $PREVIEW_TEXT"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# Cleanup: remove test wildcard from prompt data
agent-browser eval 'var p = PU.editor.getModifiedPrompt(); if (p && p.wildcards) p.wildcards = p.wildcards.filter(w => w.name !== "poptest2")' 2>/dev/null
sleep 0.3

# ── Test 6: Existing defined wildcard → passive popover, no force ───

log_test "OBJECTIVE: Defined wildcard opens passive popover without force-values"

# Restore original block 0 content (earlier tests modified it)
agent-browser eval "var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, '0'); if (b) b.content = 'You are a __tone__ HR consultant for a __company_size__ company'" 2>/dev/null
sleep 0.3

# Enter root block which has __tone__ (defined with values)
agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

# Position cursor at the tone wildcard chip to trigger passive popover
agent-browser eval 'PU.quill.positionCursorAtWildcard(PU.state.focusMode.quillInstance, "tone")' 2>/dev/null
sleep 1

# Check popover is open in passive mode
PASSIVE_OPEN=$(agent-browser eval 'PU.wildcardPopover._open === true && PU.wildcardPopover._passive === true' 2>/dev/null)
echo "$PASSIVE_OPEN" | grep -qi "true" \
    && log_pass "Passive popover opened for defined wildcard __tone__" \
    || log_fail "Passive popover not opened for __tone__"

# Check _forceValues is NOT set
NO_FORCE=$(agent-browser eval 'PU.wildcardPopover._forceValues === false' 2>/dev/null)
echo "$NO_FORCE" | grep -qi "true" \
    && log_pass "No force-values for defined wildcard" \
    || log_fail "_forceValues incorrectly set for defined wildcard"

# Check passive mode shows hint (not input)
PASSIVE_HINT=$(agent-browser eval 'PU.wildcardPopover._el && PU.wildcardPopover._el.querySelector(".pu-wc-inline-hint") ? "hint" : PU.wildcardPopover._el && PU.wildcardPopover._el.querySelector(".pu-wc-inline-input") ? "input" : "none"' 2>/dev/null | tr -d '"')
[ "$PASSIVE_HINT" = "hint" ] \
    && log_pass "Passive popover shows hint (not input)" \
    || log_fail "Passive popover should show hint, got: $PASSIVE_HINT"

# Close it
agent-browser eval 'PU.wildcardPopover.close()' 2>/dev/null
sleep 0.3

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 7: Autocomplete select undefined → force-values popover ────

log_test "OBJECTIVE: Selecting undefined wildcard from autocomplete opens force-values popover"

# Restore block 0 content before modifying
agent-browser eval "var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, '0'); if (b) b.content = 'You are a __tone__ HR consultant for a __company_size__ company'" 2>/dev/null
sleep 0.3

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

# Clear and set up for autocomplete selection
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.deleteText(0, q.getLength()-1, Quill.sources.SILENT); q.insertText(0, "Test text", Quill.sources.SILENT)' 2>/dev/null
sleep 0.3

# Directly call selectAutocompleteItem with an undefined wildcard name
# First set up autocomplete state so selectAutocompleteItem works
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.insertText(9, " __", Quill.sources.SILENT); q.setSelection(12, 0, Quill.sources.SILENT); PU.quill._autocompleteOpen = true; PU.quill._autocompleteQuill = q; PU.quill._autocompletePath = "0"; PU.quill._autocompleteTriggerIndex = 10; PU.quill._autocompleteQuery = "actest"; PU.quill.selectAutocompleteItem("actest")' 2>/dev/null
sleep 1

# Check popover opened with force-values
AC_POPOVER=$(agent-browser eval 'PU.wildcardPopover._open === true' 2>/dev/null)
echo "$AC_POPOVER" | grep -qi "true" \
    && log_pass "Popover opened after autocomplete selection" \
    || log_fail "Popover not opened after autocomplete selection"

AC_FORCE=$(agent-browser eval 'PU.wildcardPopover._forceValues === true' 2>/dev/null)
echo "$AC_FORCE" | grep -qi "true" \
    && log_pass "Force-values set via autocomplete path" \
    || log_fail "Force-values not set via autocomplete path"

# Check popover is ACTIVE (not passive) for undefined wildcard
AC_ACTIVE=$(agent-browser eval 'PU.wildcardPopover._passive === false' 2>/dev/null)
echo "$AC_ACTIVE" | grep -qi "true" \
    && log_pass "Popover is active (not passive) for undefined wildcard" \
    || log_fail "Popover should be active for undefined wildcard"

# Close without values — chip should be removed
agent-browser eval 'PU.wildcardPopover.close()' 2>/dev/null
sleep 0.5

AC_CHIP_GONE=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=actest]") === null' 2>/dev/null)
echo "$AC_CHIP_GONE" | grep -qi "true" \
    && log_pass "Autocomplete chip removed after close without values" \
    || log_fail "Autocomplete chip still present"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 8: Colon shortcut → force-values popover ───────────────────

log_test "OBJECTIVE: Colon shortcut __name: creates chip and opens force-values popover"

agent-browser eval "var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, '0'); if (b) b.content = 'You are a __tone__ HR consultant for a __company_size__ company'" 2>/dev/null
sleep 0.3

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

# Clear and insert text with colon shortcut pattern, then trigger handleTextChange
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.deleteText(0, q.getLength()-1, Quill.sources.SILENT); q.insertText(0, "Test __colonwc:", Quill.sources.SILENT); q.setSelection(16, 0, Quill.sources.SILENT); PU.focus.handleTextChange("0", q)' 2>/dev/null
sleep 1

# Check chip was created
COLON_CHIP=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=colonwc]") !== null' 2>/dev/null)
echo "$COLON_CHIP" | grep -qi "true" \
    && log_pass "Colon shortcut created chip for __colonwc__" \
    || log_fail "Colon shortcut did not create chip"

# Check popover opened with force-values
COLON_POP=$(agent-browser eval 'PU.wildcardPopover._open === true' 2>/dev/null)
echo "$COLON_POP" | grep -qi "true" \
    && log_pass "Popover opened via colon shortcut" \
    || log_fail "Popover not opened via colon shortcut"

COLON_FORCE=$(agent-browser eval 'PU.wildcardPopover._forceValues === true' 2>/dev/null)
echo "$COLON_FORCE" | grep -qi "true" \
    && log_pass "Force-values set via colon shortcut" \
    || log_fail "Force-values not set via colon shortcut"

# Close and verify removal
agent-browser eval 'PU.wildcardPopover.close()' 2>/dev/null
sleep 0.5

COLON_REMOVED=$(agent-browser eval 'PU.state.focusMode.quillInstance.root.querySelector(".ql-wildcard-chip[data-wildcard-name=colonwc]") === null' 2>/dev/null)
echo "$COLON_REMOVED" | grep -qi "true" \
    && log_pass "Colon shortcut chip removed after close without values" \
    || log_fail "Colon shortcut chip still present"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 9: Block content syncs after chip removal ──────────────────

log_test "OBJECTIVE: Block content does not contain removed wildcard pattern"

agent-browser eval "var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, '0'); if (b) b.content = 'You are a __tone__ HR consultant for a __company_size__ company'" 2>/dev/null
sleep 0.3

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

# Insert wildcard, trigger conversion, then close without values (removal)
agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.deleteText(0, q.getLength()-1, Quill.sources.SILENT); q.insertText(0, "Keep this __synctest__", Quill.sources.SILENT); q.setSelection(22, 0, Quill.sources.SILENT); PU.focus.handleTextChange("0", q)' 2>/dev/null
sleep 1

# Close popover — chip removed
agent-browser eval 'PU.wildcardPopover.close()' 2>/dev/null
sleep 0.5

# Check block content via serialization
SYNC_SERIAL=$(agent-browser eval 'PU.quill.serialize(PU.state.focusMode.quillInstance)' 2>/dev/null)
echo "$SYNC_SERIAL" | grep -q "Keep this" \
    && log_pass "Base text preserved after chip removal" \
    || log_fail "Base text lost: $SYNC_SERIAL"

echo "$SYNC_SERIAL" | grep -qv "synctest" \
    && log_pass "Wildcard pattern removed from serialized content" \
    || log_fail "Wildcard pattern still in serialized content: $SYNC_SERIAL"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 10: Popover element visible when open ──────────────────────

log_test "OBJECTIVE: Popover DOM element is visible when open"

agent-browser eval "var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, '0'); if (b) b.content = 'You are a __tone__ HR consultant for a __company_size__ company'" 2>/dev/null
sleep 0.3

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1.5

agent-browser eval 'var q = PU.state.focusMode.quillInstance; q.deleteText(0, q.getLength()-1, Quill.sources.SILENT); q.insertText(0, "Vis __vistest__", Quill.sources.SILENT); q.setSelection(15, 0, Quill.sources.SILENT); PU.focus.handleTextChange("0", q)' 2>/dev/null
sleep 1

POP_VISIBLE=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-wc-inline]"); el && el.style.display !== "none"' 2>/dev/null)
echo "$POP_VISIBLE" | grep -qi "true" \
    && log_pass "Popover element visible in DOM" \
    || log_fail "Popover element not visible"

# Check it has the wildcard name label
POP_LABEL=$(agent-browser eval 'document.querySelector("[data-testid=pu-wc-inline] .pu-wc-inline-label")?.textContent' 2>/dev/null)
echo "$POP_LABEL" | grep -q "vistest" \
    && log_pass "Popover shows correct wildcard label: vistest" \
    || log_fail "Popover label incorrect: $POP_LABEL"

agent-browser eval 'PU.wildcardPopover.close()' 2>/dev/null
sleep 0.3
agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ── Test 11: Main editor filter tree footer hidden when no filters ──

log_test "OBJECTIVE: Main editor filter tree footer hidden when no active filters"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 0.5
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt&composition=99" 2>/dev/null
sleep 4

FOOTER_HT=$(agent-browser eval 'var ft=document.querySelector("[data-testid=pu-output-footer] .pu-filter-tree-footer");ft?ft.offsetHeight:-1' 2>/dev/null)
[ "$FOOTER_HT" = "0" ] \
    && log_pass "Main editor filter footer 0px when no filters" \
    || log_fail "Footer should be 0px, got: ${FOOTER_HT}px"

FOOTER_CLS=$(agent-browser eval 'var ft=document.querySelector("[data-testid=pu-output-footer] .pu-filter-tree-footer");ft?ft.className:"none"' 2>/dev/null | tr -d '"')
echo "$FOOTER_CLS" | grep -q "pu-hidden" \
    && log_pass "Footer has pu-hidden class" \
    || log_fail "Footer missing pu-hidden: $FOOTER_CLS"

# ── Test 12: Main editor filter footer visible with active filters ──

log_test "OBJECTIVE: Main editor filter tree footer visible with active filters"

agent-browser eval 'var item=document.querySelector("[data-testid=pu-output-footer] [data-testid^=pu-filter-value-]");item&&item.click();true' 2>/dev/null
sleep 0.5

FOOTER_HT_ACT=$(agent-browser eval 'var ft=document.querySelector("[data-testid=pu-output-footer] .pu-filter-tree-footer");ft?ft.offsetHeight:-1' 2>/dev/null)
if [ "$FOOTER_HT_ACT" -gt 0 ] 2>/dev/null; then
    log_pass "Footer visible with active filter (${FOOTER_HT_ACT}px)"
else
    log_fail "Footer should be visible, got: ${FOOTER_HT_ACT}px"
fi

FOOTER_CLS_ACT=$(agent-browser eval 'var ft=document.querySelector("[data-testid=pu-output-footer] .pu-filter-tree-footer");ft?ft.className:"none"' 2>/dev/null | tr -d '"')
echo "$FOOTER_CLS_ACT" | grep -qv "pu-hidden" \
    && log_pass "Footer pu-hidden removed with active filter" \
    || log_fail "Footer should not have pu-hidden: $FOOTER_CLS_ACT"

# ── Test 13: No JS errors throughout ────────────────────────────────

log_test "OBJECTIVE: No JavaScript errors during wildcard popover operations"
JS_ERRORS=$(agent-browser errors 2>/dev/null || echo "")
if [ -z "$JS_ERRORS" ] || echo "$JS_ERRORS" | grep -q "^\[\]$"; then
    log_pass "No JS errors"
else
    log_fail "JS errors detected: $JS_ERRORS"
fi

# ── Cleanup ─────────────────────────────────────────────────────────

# Remove any test wildcards from prompt data
agent-browser eval 'var p = PU.editor.getModifiedPrompt(); if (p && p.wildcards) p.wildcards = p.wildcards.filter(w => !["poptest1","poptest2","actest","colonwc","synctest","vistest"].includes(w.name))' 2>/dev/null
sleep 0.3

agent-browser close 2>/dev/null || true

print_summary
exit $?
