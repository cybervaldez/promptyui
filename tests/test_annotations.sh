#!/bin/bash
# ============================================================================
# E2E Test Suite: Block Annotations Feature
# ============================================================================
# Tests that:
# - Annotate button (tag icon) appears in right-edge actions for all blocks
# - Annotation editor opens/closes with collapsible animation
# - CRUD: Add, edit, remove annotations via inline editor
# - Badge renders with correct count after adding annotations
# - Badge disappears when all annotations removed
# - Annotations persist through re-render cycle
# - Annotations included in export YAML
# - Preview API returns annotations (parent-child merge)
# - Backward compat: existing blocks without annotations render normally
#
# Usage: ./tests/test_annotations.sh [--port 8085]
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

print_header "Block Annotations Feature"

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
# SETUP: Navigate to a prompt with content blocks
# ============================================================================
echo ""
log_info "SETUP: Opening hiring-templates / job-posting (compact mode)"

agent-browser open "${BASE_URL}/?job=hiring-templates&prompt=job-posting&viz=compact" 2>/dev/null
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
# TEST 1: PU.annotations module loaded
# ============================================================================
echo ""
log_info "TEST 1: PU.annotations module loaded"

HAS_MODULE=$(agent-browser eval "typeof PU.annotations === 'object' && typeof PU.annotations.toggleEditor === 'function'" 2>/dev/null)
[ "$HAS_MODULE" = "true" ] && log_pass "PU.annotations module is loaded" || log_fail "PU.annotations module not found"

HAS_REGISTER=$(agent-browser eval "typeof PU.annotations.register === 'function'" 2>/dev/null)
[ "$HAS_REGISTER" = "true" ] && log_pass "PU.annotations.register() hook API available" || log_fail "Hook API missing"

HAS_FIRE=$(agent-browser eval "typeof PU.annotations.fire === 'function'" 2>/dev/null)
[ "$HAS_FIRE" = "true" ] && log_pass "PU.annotations.fire() event system available" || log_fail "Event system missing"

# ============================================================================
# TEST 2: Annotate button in right-edge actions (animated mode)
# ============================================================================
echo ""
log_info "TEST 2: Annotate button in right-edge actions"

# Switch to animated mode where right-edge is visible
agent-browser open "${BASE_URL}/?job=hiring-templates&prompt=job-posting&viz=typewriter" 2>/dev/null
sleep 3

HAS_ANNOTATE_BTN=$(agent-browser eval "!!document.querySelector('.pu-inline-annotate')" 2>/dev/null)
[ "$HAS_ANNOTATE_BTN" = "true" ] && log_pass "Annotate (tag) button found in right-edge" || log_fail "Annotate button missing"

ANNOTATE_IN_RIGHT_EDGE=$(agent-browser eval "
    const container = document.querySelector('.pu-right-edge-actions');
    container && container.querySelector('.pu-inline-annotate') ? true : false
" 2>/dev/null)
[ "$ANNOTATE_IN_RIGHT_EDGE" = "true" ] && log_pass "Annotate button inside .pu-right-edge-actions" || log_fail "Annotate button not in right-edge container"

# Verify it has testid
HAS_TESTID=$(agent-browser eval "!!document.querySelector('[data-testid^=\"pu-block-annotate-btn-\"]')" 2>/dev/null)
[ "$HAS_TESTID" = "true" ] && log_pass "Annotate button has data-testid" || log_fail "Annotate button missing data-testid"

# Initially no has-annotations class (no annotations yet)
NO_ACTIVE=$(agent-browser eval "!document.querySelector('.pu-inline-annotate.has-annotations')" 2>/dev/null)
[ "$NO_ACTIVE" = "true" ] && log_pass "Annotate button not tinted (no annotations)" || log_fail "Annotate button should not be tinted initially"

# ============================================================================
# TEST 3: Annotation CRUD helpers on PU.blocks
# ============================================================================
echo ""
log_info "TEST 3: CRUD helpers on PU.blocks"

HAS_GET=$(agent-browser eval "typeof PU.blocks.getAnnotations === 'function'" 2>/dev/null)
[ "$HAS_GET" = "true" ] && log_pass "PU.blocks.getAnnotations() exists" || log_fail "getAnnotations missing"

HAS_SET=$(agent-browser eval "typeof PU.blocks.setAnnotations === 'function'" 2>/dev/null)
[ "$HAS_SET" = "true" ] && log_pass "PU.blocks.setAnnotations() exists" || log_fail "setAnnotations missing"

HAS_SET1=$(agent-browser eval "typeof PU.blocks.setAnnotation === 'function'" 2>/dev/null)
[ "$HAS_SET1" = "true" ] && log_pass "PU.blocks.setAnnotation() exists" || log_fail "setAnnotation missing"

HAS_REMOVE=$(agent-browser eval "typeof PU.blocks.removeAnnotation === 'function'" 2>/dev/null)
[ "$HAS_REMOVE" = "true" ] && log_pass "PU.blocks.removeAnnotation() exists" || log_fail "removeAnnotation missing"

HAS_HAS=$(agent-browser eval "typeof PU.blocks.hasAnnotations === 'function'" 2>/dev/null)
[ "$HAS_HAS" = "true" ] && log_pass "PU.blocks.hasAnnotations() exists" || log_fail "hasAnnotations missing"

# ============================================================================
# TEST 4: Add annotation via JS and verify state
# ============================================================================
echo ""
log_info "TEST 4: Add annotation via JS -> state update"

# Use CRUD helper to add an annotation to the first block
ADDED=$(agent-browser eval "
    const prompt = PU.editor.getModifiedPrompt();
    if (!prompt || !Array.isArray(prompt.text)) { 'no-prompt'; }
    else {
        PU.blocks.setAnnotation(prompt.text, '0', 'output_format', 'markdown');
        PU.blocks.setAnnotation(prompt.text, '0', 'audience', 'linkedin');
        const ann = PU.blocks.getAnnotations(prompt.text, '0');
        JSON.stringify(ann);
    }
" 2>/dev/null)

if echo "$ADDED" | grep -q 'output_format'; then
    log_pass "setAnnotation stored output_format: $ADDED"
else
    log_fail "setAnnotation did not store correctly: $ADDED"
fi

if echo "$ADDED" | grep -q 'audience'; then
    log_pass "setAnnotation stored audience"
else
    log_fail "setAnnotation did not store audience: $ADDED"
fi

HAS_ANN=$(agent-browser eval "PU.blocks.hasAnnotations(PU.editor.getModifiedPrompt().text, '0')" 2>/dev/null)
[ "$HAS_ANN" = "true" ] && log_pass "hasAnnotations returns true after adding" || log_fail "hasAnnotations should return true"

# ============================================================================
# TEST 5: Open annotation editor
# ============================================================================
echo ""
log_info "TEST 5: Annotation editor opens"

agent-browser eval "PU.annotations.openEditor('0')" 2>/dev/null
sleep 1

HAS_EDITOR=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-ann-editor-0\"]')" 2>/dev/null)
[ "$HAS_EDITOR" = "true" ] && log_pass "Annotation editor DOM element created" || log_fail "Annotation editor not found in DOM"

EDITOR_OPEN=$(agent-browser eval "document.querySelector('[data-testid=\"pu-ann-editor-0\"]')?.classList.contains('open')" 2>/dev/null)
[ "$EDITOR_OPEN" = "true" ] && log_pass "Annotation editor has 'open' class (animated)" || log_fail "Annotation editor missing 'open' class"

# Check for key/value rows
ROW_COUNT=$(agent-browser eval "document.querySelectorAll('[data-testid=\"pu-ann-editor-0\"] .pu-annotation-row').length" 2>/dev/null)
[ "$ROW_COUNT" = "2" ] && log_pass "Editor shows 2 annotation rows" || log_fail "Expected 2 rows, got $ROW_COUNT"

# Check key inputs show correct values
KEY_0=$(agent-browser eval "document.querySelector('[data-testid=\"pu-ann-key-0-0\"]')?.value" 2>/dev/null | tr -d '"')
KEY_1=$(agent-browser eval "document.querySelector('[data-testid=\"pu-ann-key-0-1\"]')?.value" 2>/dev/null | tr -d '"')
if [ "$KEY_0" = "output_format" ] || [ "$KEY_1" = "output_format" ]; then
    log_pass "Key input shows 'output_format'"
else
    log_fail "Key input wrong: key0=$KEY_0, key1=$KEY_1"
fi

# Check add button exists
HAS_ADD_BTN=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-ann-add-0\"]')" 2>/dev/null)
[ "$HAS_ADD_BTN" = "true" ] && log_pass "Add annotation button present" || log_fail "Add annotation button missing"

# ============================================================================
# TEST 6: Add row via editor
# ============================================================================
echo ""
log_info "TEST 6: Add annotation row via editor button"

agent-browser eval "PU.annotations._addRow('0', '0')" 2>/dev/null
sleep 0.5

ROW_COUNT_AFTER=$(agent-browser eval "document.querySelectorAll('[data-testid=\"pu-ann-editor-0\"] .pu-annotation-row').length" 2>/dev/null)
[ "$ROW_COUNT_AFTER" = "3" ] && log_pass "Row added: now 3 rows" || log_fail "Expected 3 rows after add, got $ROW_COUNT_AFTER"

ANN_COUNT=$(agent-browser eval "Object.keys(PU.blocks.getAnnotations(PU.editor.getModifiedPrompt().text, '0') || {}).length" 2>/dev/null)
[ "$ANN_COUNT" = "3" ] && log_pass "State has 3 annotations" || log_fail "State has $ANN_COUNT annotations, expected 3"

# ============================================================================
# TEST 7: Remove annotation row
# ============================================================================
echo ""
log_info "TEST 7: Remove annotation row"

# Remove the 'key' annotation (the auto-generated one)
agent-browser eval "PU.annotations._removeRow('0', 'key')" 2>/dev/null
sleep 0.5

ROW_COUNT_AFTER_RM=$(agent-browser eval "document.querySelectorAll('[data-testid=\"pu-ann-editor-0\"] .pu-annotation-row').length" 2>/dev/null)
[ "$ROW_COUNT_AFTER_RM" = "2" ] && log_pass "Row removed: back to 2 rows" || log_fail "Expected 2 rows after remove, got $ROW_COUNT_AFTER_RM"

# ============================================================================
# TEST 8: Close annotation editor
# ============================================================================
echo ""
log_info "TEST 8: Close annotation editor"

agent-browser eval "PU.annotations.closeEditor('0')" 2>/dev/null
sleep 0.5

EDITOR_GONE=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-ann-editor-0\"]') || !document.querySelector('[data-testid=\"pu-ann-editor-0\"]').classList.contains('open')" 2>/dev/null)
[ "$EDITOR_GONE" = "true" ] && log_pass "Editor closed (removed or not .open)" || log_fail "Editor still visible after close"

IN_OPEN_SET=$(agent-browser eval "PU.annotations._openEditors.has('0')" 2>/dev/null)
[ "$IN_OPEN_SET" = "false" ] && log_pass "_openEditors no longer contains '0'" || log_fail "_openEditors still contains '0'"

# ============================================================================
# TEST 9: Badge renders after re-render
# ============================================================================
echo ""
log_info "TEST 9: Badge renders on blocks with annotations"

# Re-render blocks to see badge
agent-browser eval "PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId)" 2>/dev/null
sleep 2

HAS_BADGE=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-ann-badge-0\"]')" 2>/dev/null)
[ "$HAS_BADGE" = "true" ] && log_pass "Annotation badge visible on block 0" || log_fail "Annotation badge not found"

BADGE_COUNT=$(agent-browser eval "document.querySelector('[data-testid=\"pu-ann-badge-0\"] .pu-ann-count')?.textContent" 2>/dev/null | tr -d '"')
[ "$BADGE_COUNT" = "2" ] && log_pass "Badge shows count 2" || log_fail "Badge count wrong: $BADGE_COUNT (expected 2)"

# ============================================================================
# TEST 10: Remove all annotations -> badge disappears
# ============================================================================
echo ""
log_info "TEST 10: Remove all annotations -> badge disappears"

agent-browser eval "
    const prompt = PU.editor.getModifiedPrompt();
    PU.blocks.removeAnnotation(prompt.text, '0', 'output_format');
    PU.blocks.removeAnnotation(prompt.text, '0', 'audience');
" 2>/dev/null

# Re-render
agent-browser eval "PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId)" 2>/dev/null
sleep 2

NO_BADGE=$(agent-browser eval "!document.querySelector('[data-testid=\"pu-ann-badge-0\"]')" 2>/dev/null)
[ "$NO_BADGE" = "true" ] && log_pass "Badge gone after removing all annotations" || log_fail "Badge still present after removing all annotations"

NO_ANN=$(agent-browser eval "!PU.blocks.hasAnnotations(PU.editor.getModifiedPrompt().text, '0')" 2>/dev/null)
[ "$NO_ANN" = "true" ] && log_pass "hasAnnotations returns false" || log_fail "hasAnnotations still true"

# ============================================================================
# TEST 11: Backward compat - blocks without annotations render normally
# ============================================================================
echo ""
log_info "TEST 11: Backward compatibility"

# Switch to a prompt that has no annotations
agent-browser open "${BASE_URL}/?job=hiring-templates&prompt=interview-questions&viz=typewriter" 2>/dev/null
sleep 3

HAS_BLOCKS_2=$(agent-browser eval "document.querySelectorAll('.pu-block').length" 2>/dev/null)
if [ "$HAS_BLOCKS_2" -gt 0 ] 2>/dev/null; then
    log_pass "Blocks render normally without annotations ($HAS_BLOCKS_2 blocks)"
else
    log_fail "No blocks rendered: $HAS_BLOCKS_2"
fi

NO_BADGES=$(agent-browser eval "document.querySelectorAll('.pu-annotation-badge').length" 2>/dev/null)
[ "$NO_BADGES" = "0" ] && log_pass "No badges on blocks without annotations" || log_fail "Unexpected badges: $NO_BADGES"

# Right-edge still has pencil + delete + annotate
HAS_EDIT=$(agent-browser eval "!!document.querySelector('.pu-inline-edit')" 2>/dev/null)
HAS_DELETE=$(agent-browser eval "!!document.querySelector('.pu-inline-delete')" 2>/dev/null)
HAS_ANNOTATE=$(agent-browser eval "!!document.querySelector('.pu-inline-annotate')" 2>/dev/null)
[ "$HAS_EDIT" = "true" ] && log_pass "Pencil button still present" || log_fail "Pencil button missing"
[ "$HAS_DELETE" = "true" ] && log_pass "Delete button still present" || log_fail "Delete button missing"
[ "$HAS_ANNOTATE" = "true" ] && log_pass "Annotate button present (no tint)" || log_fail "Annotate button missing"

# No JS errors
JS_ERRORS=$(agent-browser errors 2>/dev/null || echo "")
if [ -z "$JS_ERRORS" ] || echo "$JS_ERRORS" | grep -q "^\[\]$"; then
    log_pass "No JavaScript errors"
else
    log_fail "JS errors: $JS_ERRORS"
fi

# ============================================================================
# TEST 12: Preview API returns annotations
# ============================================================================
echo ""
log_info "TEST 12: Preview API returns annotations (parent-child merge)"

api_call POST "$BASE_URL/api/pu/preview" '{
    "text": [
        {
            "content": "Write a casual email",
            "annotations": {"output_format": "markdown", "audience": "linkedin"},
            "after": [
                {
                    "content": "for engineers",
                    "annotations": {"priority": "high", "audience": "github"}
                }
            ]
        }
    ]
}'

if [ "$HTTP_CODE" = "200" ]; then
    log_pass "Preview API returned 200"
else
    log_fail "Preview API returned $HTTP_CODE"
fi

# Check annotations in response
HAS_ANN_KEY=$(echo "$BODY" | jq -e '.variations[0].annotations' 2>/dev/null)
if [ $? -eq 0 ]; then
    log_pass "Response includes annotations field"
else
    log_fail "Response missing annotations field"
fi

# Verify parent-child merge: child 'audience' overrides parent
AUDIENCE=$(echo "$BODY" | jq -r '.variations[0].annotations.audience' 2>/dev/null)
[ "$AUDIENCE" = "github" ] && log_pass "Child annotation overrides parent (audience=github)" || log_fail "Merge failed: audience=$AUDIENCE (expected github)"

# Verify parent annotation propagated
FORMAT=$(echo "$BODY" | jq -r '.variations[0].annotations.output_format' 2>/dev/null)
[ "$FORMAT" = "markdown" ] && log_pass "Parent annotation propagated (output_format=markdown)" || log_fail "Parent not propagated: output_format=$FORMAT"

# Verify child annotation present
PRIORITY=$(echo "$BODY" | jq -r '.variations[0].annotations.priority' 2>/dev/null)
[ "$PRIORITY" = "high" ] && log_pass "Child annotation present (priority=high)" || log_fail "Child annotation missing: priority=$PRIORITY"

# ============================================================================
# TEST 13: Preview API backward compat (no annotations)
# ============================================================================
echo ""
log_info "TEST 13: Preview API backward compat (no annotations in input)"

api_call POST "$BASE_URL/api/pu/preview" '{
    "text": [{"content": "Simple text without annotations"}]
}'

if [ "$HTTP_CODE" = "200" ]; then
    log_pass "Preview API returned 200 for plain content"
else
    log_fail "Preview API returned $HTTP_CODE for plain content"
fi

EMPTY_ANN=$(echo "$BODY" | jq '.variations[0].annotations | length' 2>/dev/null)
[ "$EMPTY_ANN" = "0" ] && log_pass "Annotations empty for plain content" || log_fail "Unexpected annotations: $EMPTY_ANN"

# ============================================================================
# TEST 14: Editor restore after re-render
# ============================================================================
echo ""
log_info "TEST 14: Open editors restored after re-render"

# Go back to a prompt, add annotation, open editor, re-render
agent-browser open "${BASE_URL}/?job=hiring-templates&prompt=outreach-email&viz=typewriter" 2>/dev/null
sleep 3

# Add annotation and open editor
agent-browser eval "
    const prompt = PU.editor.getModifiedPrompt();
    if (prompt && Array.isArray(prompt.text)) {
        PU.blocks.setAnnotation(prompt.text, '0', 'test_key', 'test_value');
        PU.annotations.openEditor('0');
    }
" 2>/dev/null
sleep 1

# Verify editor is open
EDITOR_BEFORE=$(agent-browser eval "!!document.querySelector('.pu-annotation-editor.open')" 2>/dev/null)
[ "$EDITOR_BEFORE" = "true" ] && log_pass "Editor open before re-render" || log_fail "Editor not open before re-render"

# Track that path is in _openEditors
IN_SET=$(agent-browser eval "PU.annotations._openEditors.has('0')" 2>/dev/null)
[ "$IN_SET" = "true" ] && log_pass "Path '0' tracked in _openEditors" || log_fail "Path '0' not in _openEditors"

# Trigger re-render
agent-browser eval "PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId)" 2>/dev/null
sleep 2

# Verify editor was restored
EDITOR_AFTER=$(agent-browser eval "!!document.querySelector('.pu-annotation-editor.open')" 2>/dev/null)
[ "$EDITOR_AFTER" = "true" ] && log_pass "Editor restored after re-render" || log_fail "Editor not restored after re-render"

# ============================================================================
# TEST 15: Annotations in export YAML
# ============================================================================
echo ""
log_info "TEST 15: Annotations included in export data"

# Verify the modified prompt has annotations that would appear in export
EXPORT_CHECK=$(agent-browser eval "
    const prompt = PU.editor.getModifiedPrompt();
    if (!prompt || !Array.isArray(prompt.text)) { 'no-prompt'; }
    else {
        const block = prompt.text[0];
        block && block.annotations && block.annotations.test_key === 'test_value' ? 'has-annotations' : 'no-annotations';
    }
" 2>/dev/null | tr -d '"')
if echo "$EXPORT_CHECK" | grep -q "has-annotations"; then
    log_pass "Annotations on block ready for export"
else
    log_fail "Annotations not on block: $EXPORT_CHECK"
fi

# Verify annotations key is a sibling of content (not nested inside)
STRUCTURE_CHECK=$(agent-browser eval "
    const prompt = PU.editor.getModifiedPrompt();
    const block = prompt && prompt.text && prompt.text[0];
    if (!block) { 'no-block'; }
    else {
        const keys = Object.keys(block);
        keys.includes('content') && keys.includes('annotations') ? 'correct-structure' : 'wrong-structure: ' + keys.join(',');
    }
" 2>/dev/null | tr -d '"')
if echo "$STRUCTURE_CHECK" | grep -q "correct-structure"; then
    log_pass "annotations is sibling of content in block structure"
else
    log_fail "Block structure wrong: $STRUCTURE_CHECK"
fi

# ============================================================================
# TEST 16: Nested prompt - annotate button on child blocks
# ============================================================================
echo ""
log_info "TEST 16: Annotate button on nested child blocks"

agent-browser open "${BASE_URL}/?job=hiring-templates&prompt=deep-culture-doc&viz=typewriter" 2>/dev/null
sleep 3

CHILD_ANNOTATE=$(agent-browser eval "
    const childBlocks = document.querySelectorAll('.pu-block-child .pu-inline-annotate');
    childBlocks.length;
" 2>/dev/null)
if [ "$CHILD_ANNOTATE" -gt 0 ] 2>/dev/null; then
    log_pass "Annotate button on $CHILD_ANNOTATE child blocks"
else
    log_fail "No annotate buttons on child blocks: $CHILD_ANNOTATE"
fi

# ============================================================================
# CLEANUP
# ============================================================================
agent-browser close 2>/dev/null || true

print_summary
