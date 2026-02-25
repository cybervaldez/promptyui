#!/bin/bash
# ============================================================================
# E2E Test Suite: Universal Annotations (_comment)
# ============================================================================
# Verifies the universal annotations registry, _comment rendering (inline on
# block card + textarea in editor), badge count exclusion, and the "+ Comment"
# shortcut button.
#
# Usage: ./tests/test_universal_annotations.sh [--port 8085]
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
    sed 's/^"//;s/"$//' | sed 's/\\\\/\\/g' | sed 's/\\"/"/g'
}

print_header "Universal Annotations (_comment)"

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

# ============================================================================
# TEST 1: Universal registry exists in JS
# ============================================================================
echo ""
log_info "TEST 1: Universal annotations registry exists"

agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 4

HAS_REGISTRY=$(agent-browser eval '!!PU.annotations._universals' 2>/dev/null | tr -d '"')
[ "$HAS_REGISTRY" = "true" ] \
    && log_pass "PU.annotations._universals exists" \
    || log_fail "PU.annotations._universals missing: $HAS_REGISTRY"

# ============================================================================
# TEST 2: _comment is registered as universal
# ============================================================================
echo ""
log_info "TEST 2: _comment registered in universals"

HAS_COMMENT=$(agent-browser eval '!!PU.annotations._universals["_comment"]' 2>/dev/null | tr -d '"')
[ "$HAS_COMMENT" = "true" ] \
    && log_pass "_comment is in universals registry" \
    || log_fail "_comment missing from universals: $HAS_COMMENT"

WIDGET=$(agent-browser eval 'PU.annotations._universals["_comment"].widget' 2>/dev/null | tr -d '"')
[ "$WIDGET" = "textarea" ] \
    && log_pass "_comment widget is textarea" \
    || log_fail "_comment widget: $WIDGET (expected textarea)"

SHOW_ON_CARD=$(agent-browser eval 'PU.annotations._universals["_comment"].showOnCard' 2>/dev/null | tr -d '"')
[ "$SHOW_ON_CARD" = "true" ] \
    && log_pass "_comment showOnCard is true" \
    || log_fail "_comment showOnCard: $SHOW_ON_CARD"

# ============================================================================
# TEST 3: isUniversal() API works
# ============================================================================
echo ""
log_info "TEST 3: isUniversal() API"

IS_U_COMMENT=$(agent-browser eval 'PU.annotations.isUniversal("_comment")' 2>/dev/null | tr -d '"')
[ "$IS_U_COMMENT" = "true" ] \
    && log_pass "isUniversal('_comment') returns true" \
    || log_fail "isUniversal('_comment'): $IS_U_COMMENT"

IS_U_REGULAR=$(agent-browser eval 'PU.annotations.isUniversal("audience")' 2>/dev/null | tr -d '"')
[ "$IS_U_REGULAR" = "false" ] \
    && log_pass "isUniversal('audience') returns false" \
    || log_fail "isUniversal('audience'): $IS_U_REGULAR"

# ============================================================================
# TEST 4: defineUniversal() API works
# ============================================================================
echo ""
log_info "TEST 4: defineUniversal() API"

agent-browser eval 'PU.annotations.defineUniversal("_test_flag", { widget: "toggle", label: "Test" })' 2>/dev/null
IS_DEFINED=$(agent-browser eval '!!PU.annotations._universals["_test_flag"]' 2>/dev/null | tr -d '"')
[ "$IS_DEFINED" = "true" ] \
    && log_pass "defineUniversal() registers new universal" \
    || log_fail "defineUniversal() failed: $IS_DEFINED"

# Cleanup
agent-browser eval 'delete PU.annotations._universals["_test_flag"]' 2>/dev/null

# ============================================================================
# TEST 5: Inline _comment renders on block card
# ============================================================================
echo ""
log_info "TEST 5: Inline _comment on block card"

# Root block (path "0") has _comment: "Sets the overall tone context for children"
HAS_INLINE_COMMENT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-comment-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_INLINE_COMMENT" = "true" ] \
    && log_pass "Inline comment element exists on block 0" \
    || log_fail "Inline comment element missing on block 0"

COMMENT_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-block-comment-0\"]")?.textContent?.trim()' 2>/dev/null | tr -d '"')
echo "$COMMENT_TEXT" | grep -q "Sets the overall tone" \
    && log_pass "Comment text matches: $COMMENT_TEXT" \
    || log_fail "Comment text wrong: $COMMENT_TEXT"

# ============================================================================
# TEST 6: Badge count excludes _comment (showOnCard)
# ============================================================================
echo ""
log_info "TEST 6: Badge count excludes _comment"

# Block 0 has: quality: null, tone: conversational, _comment: "..."
# Inherited: audience (from prompt). Computed without _comment: audience, tone = 2
# _comment should NOT be counted in badge
BADGE_COUNT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-ann-badge-0\"] .pu-ann-count")?.textContent?.trim()' 2>/dev/null | tr -d '"')

# computedCount should exclude _comment
COUNT_OBJ=$(agent-browser eval 'JSON.stringify(PU.annotations.computedCount("0"))' 2>/dev/null | decode_json)
echo "$COUNT_OBJ" | grep -q '"count":2' \
    && log_pass "computedCount excludes _comment (count=2)" \
    || log_fail "computedCount includes _comment: $COUNT_OBJ"

# ============================================================================
# TEST 7: Children don't show parent's _comment inline
# ============================================================================
echo ""
log_info "TEST 7: Children don't inherit inline _comment"

# Child A (path "0.0") has no own _comment
HAS_CHILD_COMMENT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-comment-0-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_CHILD_COMMENT" = "false" ] \
    && log_pass "Child A has no inline comment (correct)" \
    || log_fail "Child A unexpectedly has inline comment"

# ============================================================================
# TEST 8: Editor shows _comment as textarea widget
# ============================================================================
echo ""
log_info "TEST 8: Editor textarea widget for _comment"

# Open annotation editor for block 0
agent-browser eval 'PU.annotations.openEditor("0")' 2>/dev/null
sleep 0.5

HAS_TEXTAREA=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-comment-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_TEXTAREA" = "true" ] \
    && log_pass "Comment textarea exists in editor" \
    || log_fail "Comment textarea missing in editor"

# Check textarea has correct value
TEXTAREA_VAL=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-ann-comment-0\"]")?.value?.trim()' 2>/dev/null | tr -d '"')
echo "$TEXTAREA_VAL" | grep -q "Sets the overall tone" \
    && log_pass "Textarea has correct value" \
    || log_fail "Textarea value wrong: $TEXTAREA_VAL"

# Check the row has pu-ann-universal class
HAS_UNIVERSAL_CLASS=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-comment-0\"]")?.closest(".pu-ann-universal")' 2>/dev/null | tr -d '"')
[ "$HAS_UNIVERSAL_CLASS" = "true" ] \
    && log_pass "Comment row has pu-ann-universal class" \
    || log_fail "Comment row missing pu-ann-universal class"

# Close editor
agent-browser eval 'PU.annotations.closeEditor("0")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 9: data-ann-key attribute on rows
# ============================================================================
echo ""
log_info "TEST 9: data-ann-key attributes on rows"

# Open editor again
agent-browser eval 'PU.annotations.openEditor("0")' 2>/dev/null
sleep 0.5

HAS_ANN_KEY=$(agent-browser eval '!!document.querySelector("[data-ann-key=\"_comment\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_ANN_KEY" = "true" ] \
    && log_pass "data-ann-key=\"_comment\" exists on row" \
    || log_fail "data-ann-key attribute missing"

# Check standard annotation also has data-ann-key
HAS_TONE_KEY=$(agent-browser eval '!!document.querySelector("[data-ann-key=\"tone\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_TONE_KEY" = "true" ] \
    && log_pass "data-ann-key=\"tone\" exists on standard row" \
    || log_fail "data-ann-key=\"tone\" missing"

agent-browser eval 'PU.annotations.closeEditor("0")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 10: "+ Comment" button appears when no _comment
# ============================================================================
echo ""
log_info "TEST 10: + Comment shortcut button"

# Child A (path 0.0) has no _comment — should show "+ Comment" button
agent-browser eval 'PU.annotations.openEditor("0.0")' 2>/dev/null
sleep 0.5

HAS_COMMENT_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-add-comment-0-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_COMMENT_BTN" = "true" ] \
    && log_pass "+ Comment button shown for block without _comment" \
    || log_fail "+ Comment button missing for block 0.0"

agent-browser eval 'PU.annotations.closeEditor("0.0")' 2>/dev/null
sleep 0.3

# Block 0 HAS _comment — should NOT show "+ Comment" button
agent-browser eval 'PU.annotations.openEditor("0")' 2>/dev/null
sleep 0.5

NO_COMMENT_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-ann-add-comment-0\"]")' 2>/dev/null | tr -d '"')
[ "$NO_COMMENT_BTN" = "false" ] \
    && log_pass "+ Comment button hidden when _comment already exists" \
    || log_fail "+ Comment button unexpectedly shown on block 0"

agent-browser eval 'PU.annotations.closeEditor("0")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 11: _comment in tooltip is skipped (showOnCard)
# ============================================================================
echo ""
log_info "TEST 11: Tooltip skips _comment"

# Build tooltip content for block 0 via resolve
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
    && log_fail "Tooltip would include _comment (should be skipped)" \
    || log_pass "Tooltip correctly skips _comment"

# ============================================================================
# TEST 12: _addUniversal creates _comment on a block
# ============================================================================
echo ""
log_info "TEST 12: _addUniversal creates _comment"

# Add _comment to Child A (path 0.0)
agent-browser eval 'PU.annotations._addUniversal("0.0", "_comment")' 2>/dev/null
sleep 0.3

CHILD_HAS_COMMENT=$(agent-browser eval '
(function() {
    var p = PU.helpers.getActivePrompt();
    var block = PU.blocks.findBlockByPath(p.text, "0.0");
    return block && block.annotations && block.annotations.hasOwnProperty("_comment");
})()
' 2>/dev/null | tr -d '"')
[ "$CHILD_HAS_COMMENT" = "true" ] \
    && log_pass "_addUniversal created _comment on block 0.0" \
    || log_fail "_addUniversal failed: $CHILD_HAS_COMMENT"

# ============================================================================
# TEST 13: Hiring-templates _comment in API response
# ============================================================================
echo ""
log_info "TEST 13: Hiring-templates _comment in API"

api_call GET "$BASE_URL/api/pu/job/hiring-templates"
[ "$HTTP_CODE" = "200" ] \
    && log_pass "API returns hiring-templates (HTTP 200)" \
    || log_fail "API failed: HTTP $HTTP_CODE"

# Check ext-sourcing-strategy first block has _comment
FIRST_BLOCK_COMMENT=$(echo "$BODY" | ./venv/bin/python -c "
import json,sys
d=json.load(sys.stdin)
for p in d.get('prompts',[]):
    if p['id']=='ext-sourcing-strategy':
        for t in p.get('text',[]):
            if isinstance(t,dict) and 'content' in t:
                ann = t.get('annotations',{})
                print(ann.get('_comment',''))
                break
        break
" 2>/dev/null)

echo "$FIRST_BLOCK_COMMENT" | grep -q "Root context block" \
    && log_pass "API has _comment on first block" \
    || log_fail "API _comment missing: $FIRST_BLOCK_COMMENT"

# ============================================================================
# TEST 14: Navigate to hiring-templates and check inline comment
# ============================================================================
echo ""
log_info "TEST 14: Hiring-templates inline comment in browser"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=ext-sourcing-strategy" 2>/dev/null
sleep 4

HAS_HT_COMMENT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-block-comment-0\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_HT_COMMENT" = "true" ] \
    && log_pass "Hiring-templates block 0 has inline comment" \
    || log_fail "Hiring-templates inline comment missing"

HT_COMMENT_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-block-comment-0\"]")?.textContent?.trim()' 2>/dev/null | tr -d '"')
echo "$HT_COMMENT_TEXT" | grep -q "Root context block" \
    && log_pass "Comment text correct: $HT_COMMENT_TEXT" \
    || log_fail "Comment text wrong: $HT_COMMENT_TEXT"

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
