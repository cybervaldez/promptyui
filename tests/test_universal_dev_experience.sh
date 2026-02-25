#!/bin/bash
# ============================================================================
# E2E Test Suite: Universal Annotations Developer Experience (Steps 1-4)
# ============================================================================
# Tests: defineUniversal validation, _priority select widget, _draft toggle
# widget, generic showOnCard inline display, dynamic shortcut buttons,
# hot-reload verification, badge count exclusion.
#
# Usage: ./tests/test_universal_dev_experience.sh [--port 8085]
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

# Helper: decode agent-browser eval JSON string output
decode_json() {
    sed 's/^"//;s/"$//' | sed 's/\\\\\\\\/\\\\/g' | sed 's/\\\\\"/\"/g'
}

print_header "Universal Annotations Dev Experience (Steps 1-4)"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server; then
    log_pass "Server is running"
else
    log_fail "Server not running at $BASE_URL"
    exit 1
fi

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 4

# ============================================================================
# TEST 1: defineUniversal() validation — missing widget
# ============================================================================
echo ""
log_info "TEST 1: defineUniversal() validation — missing widget"

WARN_MISSING=$(agent-browser eval '
(function() {
    var warns = [];
    var origWarn = console.warn;
    console.warn = function() { warns.push(Array.from(arguments).join(" ")); origWarn.apply(console, arguments); };
    PU.annotations.defineUniversal("_test_no_widget", { label: "Test" });
    console.warn = origWarn;
    delete PU.annotations._universals["_test_no_widget"];
    return warns.join("|");
})()
' 2>/dev/null | tr -d '"')

echo "$WARN_MISSING" | grep -q 'missing required field' \
    && log_pass "Warns on missing widget field" \
    || log_fail "No warning for missing widget: $WARN_MISSING"

# ============================================================================
# TEST 2: defineUniversal() validation — unknown widget type
# ============================================================================
echo ""
log_info "TEST 2: defineUniversal() validation — unknown widget type"

WARN_UNKNOWN=$(agent-browser eval '
(function() {
    var warns = [];
    var origWarn = console.warn;
    console.warn = function() { warns.push(Array.from(arguments).join(" ")); origWarn.apply(console, arguments); };
    PU.annotations.defineUniversal("_test_bad_widget", { widget: "textaera" });
    console.warn = origWarn;
    delete PU.annotations._universals["_test_bad_widget"];
    return warns.join("|");
})()
' 2>/dev/null | tr -d '"')

echo "$WARN_UNKNOWN" | grep -q 'unknown widget type' \
    && log_pass "Warns on unknown widget type" \
    || log_fail "No warning for unknown widget: $WARN_UNKNOWN"

# ============================================================================
# TEST 3: defineUniversal() validation — select without options
# ============================================================================
echo ""
log_info "TEST 3: defineUniversal() validation — select without options"

WARN_SELECT=$(agent-browser eval '
(function() {
    var warns = [];
    var origWarn = console.warn;
    console.warn = function() { warns.push(Array.from(arguments).join(" ")); origWarn.apply(console, arguments); };
    PU.annotations.defineUniversal("_test_no_opts", { widget: "select" });
    console.warn = origWarn;
    delete PU.annotations._universals["_test_no_opts"];
    return warns.join("|");
})()
' 2>/dev/null | tr -d '"')

echo "$WARN_SELECT" | grep -q 'requires non-empty' \
    && log_pass "Warns on select without options" \
    || log_fail "No warning for select without options: $WARN_SELECT"

# ============================================================================
# TEST 4: defineUniversal() validation — key without _ prefix
# ============================================================================
echo ""
log_info "TEST 4: defineUniversal() validation — key without _ prefix"

WARN_PREFIX=$(agent-browser eval '
(function() {
    var warns = [];
    var origWarn = console.warn;
    console.warn = function() { warns.push(Array.from(arguments).join(" ")); origWarn.apply(console, arguments); };
    PU.annotations.defineUniversal("nounderscore", { widget: "textarea" });
    console.warn = origWarn;
    delete PU.annotations._universals["nounderscore"];
    return warns.join("|");
})()
' 2>/dev/null | tr -d '"')

echo "$WARN_PREFIX" | grep -q 'key should start with' \
    && log_pass "Warns on key without _ prefix" \
    || log_fail "No warning for key prefix: $WARN_PREFIX"

# ============================================================================
# TEST 5: defineUniversal() validation — valid definition produces no warnings
# ============================================================================
echo ""
log_info "TEST 5: defineUniversal() validation — valid definition no warnings"

WARN_VALID=$(agent-browser eval '
(function() {
    var warns = [];
    var origWarn = console.warn;
    console.warn = function() { warns.push(Array.from(arguments).join(" ")); origWarn.apply(console, arguments); };
    PU.annotations.defineUniversal("_test_valid", { widget: "textarea", label: "Valid" });
    console.warn = origWarn;
    delete PU.annotations._universals["_test_valid"];
    return warns.length;
})()
' 2>/dev/null | tr -d '"')

[ "$WARN_VALID" = "0" ] \
    && log_pass "Valid definition produces no warnings" \
    || log_fail "Valid definition produced $WARN_VALID warnings"

# ============================================================================
# TEST 6: _priority registered as select universal
# ============================================================================
echo ""
log_info "TEST 6: _priority registered as select universal"

PRIORITY_WIDGET=$(agent-browser eval 'PU.annotations._universals["_priority"].widget' 2>/dev/null | tr -d '"')
[ "$PRIORITY_WIDGET" = "select" ] \
    && log_pass "_priority widget is select" \
    || log_fail "_priority widget: $PRIORITY_WIDGET (expected select)"

PRIORITY_OPTS=$(agent-browser eval 'JSON.stringify(PU.annotations._universals["_priority"].options)' 2>/dev/null | tr -d '"')
echo "$PRIORITY_OPTS" | grep -q 'high' \
    && log_pass "_priority has options including 'high'" \
    || log_fail "_priority options: $PRIORITY_OPTS"

PRIORITY_DEFAULT=$(agent-browser eval 'PU.annotations._universals["_priority"].defaultValue' 2>/dev/null | tr -d '"')
[ "$PRIORITY_DEFAULT" = "medium" ] \
    && log_pass "_priority defaultValue is 'medium'" \
    || log_fail "_priority defaultValue: $PRIORITY_DEFAULT"

# ============================================================================
# TEST 7: _draft registered as toggle universal
# ============================================================================
echo ""
log_info "TEST 7: _draft registered as toggle universal"

DRAFT_WIDGET=$(agent-browser eval 'PU.annotations._universals["_draft"].widget' 2>/dev/null | tr -d '"')
[ "$DRAFT_WIDGET" = "toggle" ] \
    && log_pass "_draft widget is toggle" \
    || log_fail "_draft widget: $DRAFT_WIDGET (expected toggle)"

DRAFT_DESC=$(agent-browser eval 'PU.annotations._universals["_draft"].description' 2>/dev/null | tr -d '"')
[ "$DRAFT_DESC" = "Mark as draft" ] \
    && log_pass "_draft description correct" \
    || log_fail "_draft description: $DRAFT_DESC"

# ============================================================================
# TEST 8: Inline showOnCard rendering — _comment as italic text
# ============================================================================
echo ""
log_info "TEST 8: Inline showOnCard rendering — _comment"

HAS_COMMENT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-comment-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_COMMENT" = "true" ] \
    && log_pass "Inline comment element exists on block 0" \
    || log_fail "Inline comment missing on block 0"

COMMENT_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-block-comment-0\"]")?.textContent?.trim()' 2>/dev/null | tr -d '"')
echo "$COMMENT_TEXT" | grep -q "Sets the overall tone" \
    && log_pass "Comment text matches" \
    || log_fail "Comment text: $COMMENT_TEXT"

# ============================================================================
# TEST 9: Inline showOnCard rendering — _priority as pill
# ============================================================================
echo ""
log_info "TEST 9: Inline showOnCard rendering — _priority pill"

HAS_PRIORITY_PILL=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-pill-priority-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_PRIORITY_PILL" = "true" ] \
    && log_pass "Priority pill exists on block 0" \
    || log_fail "Priority pill missing on block 0"

PILL_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-block-pill-priority-0\"]")?.textContent?.trim()' 2>/dev/null | tr -d '"')
echo "$PILL_TEXT" | grep -q "high" \
    && log_pass "Priority pill shows 'high'" \
    || log_fail "Priority pill text: $PILL_TEXT"

# ============================================================================
# TEST 10: Inline showOnCard rendering — _draft as toggle pill
# ============================================================================
echo ""
log_info "TEST 10: Inline showOnCard rendering — _draft toggle pill"

HAS_DRAFT_PILL=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-pill-draft-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_DRAFT_PILL" = "true" ] \
    && log_pass "Draft pill exists on block 0" \
    || log_fail "Draft pill missing on block 0"

DRAFT_PILL_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-block-pill-draft-0\"]")?.textContent?.trim()' 2>/dev/null | tr -d '"')
echo "$DRAFT_PILL_TEXT" | grep -qi "draft" \
    && log_pass "Draft pill shows 'Draft' label" \
    || log_fail "Draft pill text: $DRAFT_PILL_TEXT"

# ============================================================================
# TEST 11: Pills container exists
# ============================================================================
echo ""
log_info "TEST 11: Pills container exists"

HAS_PILLS=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-pills-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_PILLS" = "true" ] \
    && log_pass "Pills container exists on block 0" \
    || log_fail "Pills container missing on block 0"

# ============================================================================
# TEST 12: Children don't show parent's showOnCard universals
# ============================================================================
echo ""
log_info "TEST 12: Children don't show parent's inline universals"

HAS_CHILD_PILLS=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-pills-0-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_CHILD_PILLS" = "false" ] \
    && log_pass "Child A has no pills (correct — block-own only)" \
    || log_fail "Child A unexpectedly has pills"

HAS_CHILD_COMMENT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-comment-0-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_CHILD_COMMENT" = "false" ] \
    && log_pass "Child A has no inline comment (correct)" \
    || log_fail "Child A unexpectedly has inline comment"

# ============================================================================
# TEST 13: Badge count excludes all showOnCard universals
# ============================================================================
echo ""
log_info "TEST 13: Badge count excludes showOnCard universals"

COUNT_OBJ=$(agent-browser eval 'JSON.stringify(PU.annotations.computedCount("0"))' 2>/dev/null | decode_json)
echo "$COUNT_OBJ" | grep -q 'count.*:2' \
    && log_pass "computedCount excludes showOnCard universals (count=2)" \
    || log_fail "computedCount wrong: $COUNT_OBJ"

# ============================================================================
# TEST 14: Editor — _priority renders as select dropdown
# ============================================================================
echo ""
log_info "TEST 14: Editor — _priority select widget"

agent-browser eval 'PU.annotations.openEditor("0")' 2>/dev/null
sleep 0.5

HAS_SELECT=$(agent-browser eval '!!document.querySelector("[data-ann-key=\"_priority\"] select")' 2>/dev/null | tr -d '"')
[ "$HAS_SELECT" = "true" ] \
    && log_pass "Priority select widget exists in editor" \
    || log_fail "Priority select widget missing in editor"

SELECT_VAL=$(agent-browser eval 'document.querySelector("[data-ann-key=\"_priority\"] select")?.value' 2>/dev/null | tr -d '"')
[ "$SELECT_VAL" = "high" ] \
    && log_pass "Priority select has correct value: high" \
    || log_fail "Priority select value: $SELECT_VAL"

# ============================================================================
# TEST 15: Editor — _draft renders as toggle checkbox
# ============================================================================
echo ""
log_info "TEST 15: Editor — _draft toggle widget"

HAS_TOGGLE=$(agent-browser eval '!!document.querySelector("[data-ann-key=\"_draft\"] input[type=\"checkbox\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_TOGGLE" = "true" ] \
    && log_pass "Draft toggle checkbox exists in editor" \
    || log_fail "Draft toggle checkbox missing in editor"

TOGGLE_CHECKED=$(agent-browser eval 'document.querySelector("[data-ann-key=\"_draft\"] input[type=\"checkbox\"]")?.checked' 2>/dev/null | tr -d '"')
[ "$TOGGLE_CHECKED" = "true" ] \
    && log_pass "Draft toggle is checked (correct — _draft: true)" \
    || log_fail "Draft toggle checked: $TOGGLE_CHECKED"

# ============================================================================
# TEST 16: Editor — _comment textarea still works
# ============================================================================
echo ""
log_info "TEST 16: Editor — _comment textarea still works"

HAS_TEXTAREA=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-comment-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_TEXTAREA" = "true" ] \
    && log_pass "Comment textarea exists in editor" \
    || log_fail "Comment textarea missing in editor"

agent-browser eval 'PU.annotations.closeEditor("0")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 17: Dynamic shortcut buttons — child has all 3 universal buttons
# ============================================================================
echo ""
log_info "TEST 17: Dynamic shortcut buttons on child block"

agent-browser eval 'PU.annotations.openEditor("0.0")' 2>/dev/null
sleep 0.5

HAS_COMMENT_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-add-comment-0-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_COMMENT_BTN" = "true" ] \
    && log_pass "+ Comment button shown for block without _comment" \
    || log_fail "+ Comment button missing"

HAS_PRIORITY_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-add-priority-0-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_PRIORITY_BTN" = "true" ] \
    && log_pass "+ Priority button shown for block without _priority" \
    || log_fail "+ Priority button missing"

HAS_DRAFT_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-add-draft-0-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_DRAFT_BTN" = "true" ] \
    && log_pass "+ Draft button shown for block without _draft" \
    || log_fail "+ Draft button missing"

agent-browser eval 'PU.annotations.closeEditor("0.0")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 18: Block 0 should NOT show shortcut buttons for existing universals
# ============================================================================
echo ""
log_info "TEST 18: Block 0 hides buttons for existing universals"

agent-browser eval 'PU.annotations.openEditor("0")' 2>/dev/null
sleep 0.5

NO_COMMENT_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-add-comment-0\"]")' 2>/dev/null | tr -d '"')
[ "$NO_COMMENT_BTN" = "false" ] \
    && log_pass "+ Comment hidden when _comment exists" \
    || log_fail "+ Comment button unexpectedly shown on block 0"

NO_PRIORITY_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-add-priority-0\"]")' 2>/dev/null | tr -d '"')
[ "$NO_PRIORITY_BTN" = "false" ] \
    && log_pass "+ Priority hidden when _priority exists" \
    || log_fail "+ Priority button unexpectedly shown on block 0"

NO_DRAFT_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-add-draft-0\"]")' 2>/dev/null | tr -d '"')
[ "$NO_DRAFT_BTN" = "false" ] \
    && log_pass "+ Draft hidden when _draft exists" \
    || log_fail "+ Draft button unexpectedly shown on block 0"

agent-browser eval 'PU.annotations.closeEditor("0")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 19: _addUniversal uses defaultValue
# ============================================================================
echo ""
log_info "TEST 19: _addUniversal uses defaultValue"

agent-browser eval 'PU.annotations._addUniversal("0.0", "_priority")' 2>/dev/null
sleep 0.3

CHILD_PRIORITY=$(agent-browser eval '
(function() {
    var p = PU.helpers.getActivePrompt();
    var block = PU.blocks.findBlockByPath(p.text, "0.0");
    return block && block.annotations && block.annotations._priority;
})()
' 2>/dev/null | tr -d '"')
[ "$CHILD_PRIORITY" = "medium" ] \
    && log_pass "_addUniversal set _priority to defaultValue 'medium'" \
    || log_fail "_addUniversal _priority value: $CHILD_PRIORITY (expected medium)"

# ============================================================================
# TEST 20: Hot-reload — defineUniversal at runtime
# ============================================================================
echo ""
log_info "TEST 20: Hot-reload — defineUniversal at runtime"

# Define a new universal at runtime
agent-browser eval '
PU.annotations.defineUniversal("_urgency", {
    widget: "select",
    label: "Urgency",
    options: ["critical", "normal", "backlog"],
    showOnCard: true,
    defaultValue: "normal"
})
' 2>/dev/null

# Add it to a block
agent-browser eval 'PU.annotations._addUniversal("0.0", "_urgency")' 2>/dev/null
sleep 0.3

# Open editor and verify the select widget renders
agent-browser eval 'PU.annotations.openEditor("0.0")' 2>/dev/null
sleep 0.5

HAS_URGENCY_SELECT=$(agent-browser eval '!!document.querySelector("[data-ann-key=\"_urgency\"] select")' 2>/dev/null | tr -d '"')
[ "$HAS_URGENCY_SELECT" = "true" ] \
    && log_pass "Hot-reload: _urgency select widget renders in editor" \
    || log_fail "Hot-reload: _urgency select widget missing"

# Verify inline pill appears
HAS_URGENCY_PILL=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-pill-urgency-0-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_URGENCY_PILL" = "true" ] \
    && log_pass "Hot-reload: _urgency pill appears on card" \
    || log_fail "Hot-reload: _urgency pill missing on card"

# Cleanup: remove runtime universal
agent-browser eval '
(function() {
    var p = PU.helpers.getActivePrompt();
    var block = PU.blocks.findBlockByPath(p.text, "0.0");
    if (block && block.annotations) { delete block.annotations._urgency; }
    delete PU.annotations._universals["_urgency"];
})()
' 2>/dev/null

agent-browser eval 'PU.annotations.closeEditor("0.0")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 21: _validWidgets list includes all expected types
# ============================================================================
echo ""
log_info "TEST 21: _validWidgets list"

VALID_WIDGETS=$(agent-browser eval 'JSON.stringify(PU.annotations._validWidgets)' 2>/dev/null | tr -d '"')
echo "$VALID_WIDGETS" | grep -q 'textarea' && echo "$VALID_WIDGETS" | grep -q 'select' && echo "$VALID_WIDGETS" | grep -q 'toggle' && echo "$VALID_WIDGETS" | grep -q 'async' \
    && log_pass "_validWidgets includes all 4 types: $VALID_WIDGETS" \
    || log_fail "_validWidgets: $VALID_WIDGETS"

# ============================================================================
# TEST 22: isUniversal for new universals
# ============================================================================
echo ""
log_info "TEST 22: isUniversal for _priority and _draft"

IS_PRIORITY=$(agent-browser eval 'PU.annotations.isUniversal("_priority")' 2>/dev/null | tr -d '"')
[ "$IS_PRIORITY" = "true" ] \
    && log_pass "isUniversal('_priority') returns true" \
    || log_fail "isUniversal('_priority'): $IS_PRIORITY"

IS_DRAFT=$(agent-browser eval 'PU.annotations.isUniversal("_draft")' 2>/dev/null | tr -d '"')
[ "$IS_DRAFT" = "true" ] \
    && log_pass "isUniversal('_draft') returns true" \
    || log_fail "isUniversal('_draft'): $IS_DRAFT"

# ============================================================================
# TEST 23: Tooltip skips all showOnCard universals
# ============================================================================
echo ""
log_info "TEST 23: Tooltip skips all showOnCard universals"

TOOLTIP_KEYS=$(agent-browser eval '
(function() {
    var r = PU.annotations.resolve("0");
    var keys = [];
    for (var k in r.computed) {
        var desc = PU.annotations._universals[k];
        if (desc && desc.showOnCard) continue;
        keys.push(k);
    }
    return JSON.stringify(keys);
})()
' 2>/dev/null | decode_json)

echo "$TOOLTIP_KEYS" | grep -q '_comment' \
    && log_fail "Tooltip includes _comment (should be skipped)" \
    || log_pass "Tooltip skips _comment"

echo "$TOOLTIP_KEYS" | grep -q '_priority' \
    && log_fail "Tooltip includes _priority (should be skipped)" \
    || log_pass "Tooltip skips _priority"

echo "$TOOLTIP_KEYS" | grep -q '_draft' \
    && log_fail "Tooltip includes _draft (should be skipped)" \
    || log_pass "Tooltip skips _draft"

# ============================================================================
# TEST 24: data-universal-key attributes on inline elements
# ============================================================================
echo ""
log_info "TEST 24: data-universal-key attributes"

COMMENT_KEY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-block-comment-0\"]")?.getAttribute("data-universal-key")' 2>/dev/null | tr -d '"')
[ "$COMMENT_KEY" = "_comment" ] \
    && log_pass "Comment has data-universal-key=\"_comment\"" \
    || log_fail "Comment data-universal-key: $COMMENT_KEY"

PILL_KEY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-block-pill-priority-0\"]")?.getAttribute("data-universal-key")' 2>/dev/null | tr -d '"')
[ "$PILL_KEY" = "_priority" ] \
    && log_pass "Priority pill has data-universal-key=\"_priority\"" \
    || log_fail "Priority pill data-universal-key: $PILL_KEY"

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
