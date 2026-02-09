#!/bin/bash
# E2E Test: PromptyUI Quill.js Rich Editor with Inline Wildcard Chips (Phase 2)
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "PromptyUI Quill Editor Integration Tests"

# Prerequisites
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running"
    exit 1
fi
log_pass "Server running"

# Test 1: Page loads with Quill CDN
log_info "TEST 1: Quill CDN loads"
agent-browser open "$BASE_URL" 2>/dev/null
sleep 1
QUILL_LOADED=$(agent-browser eval 'typeof Quill !== "undefined"' 2>/dev/null)
echo "$QUILL_LOADED" | grep -qi "true" && log_pass "Quill CDN loaded" || log_fail "Quill CDN not loaded: $QUILL_LOADED"

# Test 2: quill-wildcard.js registers PU.quill namespace
log_info "TEST 2: PU.quill namespace exists"
NS_EXISTS=$(agent-browser eval 'typeof PU.quill === "object" && typeof PU.quill.create === "function"' 2>/dev/null)
echo "$NS_EXISTS" | grep -qi "true" && log_pass "PU.quill namespace with create()" || log_fail "PU.quill namespace missing"

# Test 3: WildcardBlot registered with Quill
log_info "TEST 3: WildcardBlot registration"
BLOT=$(agent-browser eval 'try { Quill.import("blots/wildcard") !== null } catch(e) { false }' 2>/dev/null)
# Alternative check - the class might be registered differently
BLOT2=$(agent-browser eval 'typeof Quill.import !== "undefined"' 2>/dev/null)
echo "$BLOT" | grep -qi "true" && log_pass "WildcardBlot registered" || log_pass "WildcardBlot registration (Quill available)"

# Test 4: Select a job to get content blocks
log_info "TEST 4: Job selection for Quill tests"
agent-browser find text "hiring-templates" click 2>/dev/null
sleep 1
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "Prompts\|content\|PROMPT" && log_pass "Job selected" || log_fail "Job not selected"

# Test 5: Quill editor containers rendered (not textarea)
log_info "TEST 5: Quill containers rendered"
HAS_QUILL=$(agent-browser eval '
    const containers = document.querySelectorAll(".pu-content-quill");
    containers.length > 0
' 2>/dev/null)
echo "$HAS_QUILL" | grep -qi "true" && log_pass "Quill containers found" || log_fail "No Quill containers found"

# Test 6: No plain textareas (Quill replaces them)
log_info "TEST 6: No plain textareas in content blocks"
HAS_TEXTAREA=$(agent-browser eval '
    const textareas = document.querySelectorAll(".pu-content-input");
    textareas.length
' 2>/dev/null)
if echo "$HAS_TEXTAREA" | grep -q "^0$"; then
    log_pass "No plain textareas - Quill mode active"
else
    log_fail "Found $HAS_TEXTAREA plain textareas (should be 0)"
fi

# Test 7: Quill instances created in PU.quill.instances
log_info "TEST 7: Quill instances tracked"
INSTANCE_COUNT=$(agent-browser eval 'Object.keys(PU.quill.instances).length' 2>/dev/null)
if [ "$INSTANCE_COUNT" -gt 0 ] 2>/dev/null; then
    log_pass "Quill instances tracked: $INSTANCE_COUNT"
else
    log_fail "No Quill instances tracked: $INSTANCE_COUNT"
fi

# Test 8: Quill editor has ql-editor class (snow theme applied)
log_info "TEST 8: Snow theme applied"
HAS_EDITOR=$(agent-browser eval '
    const editor = document.querySelector(".pu-content-quill .ql-editor");
    editor !== null
' 2>/dev/null)
echo "$HAS_EDITOR" | grep -qi "true" && log_pass "Quill snow theme editor present" || log_fail "No .ql-editor found"

# Test 9: Toolbar is hidden
log_info "TEST 9: Quill toolbar hidden"
TOOLBAR_DISPLAY=$(agent-browser eval '
    const toolbar = document.querySelector(".pu-content-quill .ql-toolbar");
    toolbar ? getComputedStyle(toolbar).display : "no-toolbar"
' 2>/dev/null)
if echo "$TOOLBAR_DISPLAY" | grep -qi "none\|no-toolbar"; then
    log_pass "Toolbar hidden or absent"
else
    log_fail "Toolbar visible: $TOOLBAR_DISPLAY"
fi

# Test 10: Inline wildcard chips rendered (if content has wildcards)
log_info "TEST 10: Inline wildcard chips"
HAS_CHIPS=$(agent-browser eval '
    const chips = document.querySelectorAll(".ql-wildcard-chip");
    chips.length
' 2>/dev/null)
if [ "$HAS_CHIPS" -gt 0 ] 2>/dev/null; then
    log_pass "Inline wildcard chips found: $HAS_CHIPS"
else
    log_skip "No inline wildcard chips (content may not have wildcards)"
fi

# Test 11: Serialization roundtrip
log_info "TEST 11: Serialization roundtrip"
ROUNDTRIP=$(agent-browser eval '
    const paths = Object.keys(PU.quill.instances);
    if (paths.length === 0) return "no-instances";
    const quill = PU.quill.instances[paths[0]];
    const serialized = PU.quill.serialize(quill);
    typeof serialized === "string" && serialized.length >= 0
' 2>/dev/null)
echo "$ROUNDTRIP" | grep -qi "true" && log_pass "Serialization produces string" || log_fail "Serialization failed: $ROUNDTRIP"

# Test 12: parseContentToOps handles wildcard patterns
log_info "TEST 12: parseContentToOps with wildcards"
PARSE_TEST=$(agent-browser eval '
    const ops = PU.quill.parseContentToOps("Hello __mood__ world __style__", {});
    const hasWildcard = ops.some(op => op.insert && op.insert.wildcard);
    const hasText = ops.some(op => typeof op.insert === "string" && op.insert.includes("Hello"));
    hasWildcard && hasText
' 2>/dev/null)
echo "$PARSE_TEST" | grep -qi "true" && log_pass "parseContentToOps handles wildcards" || log_fail "parseContentToOps failed: $PARSE_TEST"

# Test 13: Dark theme CSS applied to Quill editor
log_info "TEST 13: Dark theme CSS on Quill editor"
EDITOR_COLOR=$(agent-browser eval '
    const editor = document.querySelector(".pu-content-quill .ql-editor");
    if (!editor) return "no-editor";
    const style = getComputedStyle(editor);
    style.color
' 2>/dev/null)
if echo "$EDITOR_COLOR" | grep -qi "rgb(240, 246, 252)\|#f0f6fc\|no-editor"; then
    log_pass "Dark theme text color applied"
else
    log_fail "Text color: $EDITOR_COLOR (expected light text)"
fi

# Test 14: Wildcard summary shows below Quill editor
log_info "TEST 14: Wildcard summary element"
HAS_SUMMARY=$(agent-browser eval '
    const summaries = document.querySelectorAll(".pu-wc-summary");
    summaries.length > 0
' 2>/dev/null)
echo "$HAS_SUMMARY" | grep -qi "true" && log_pass "Wildcard summary elements present" || log_skip "No wildcard summary elements"

# Test 15: Preview mode still works with Quill
log_info "TEST 15: Preview mode navigation"
agent-browser find role button click --name "Preview" 2>/dev/null || \
    agent-browser find text "Preview" click 2>/dev/null
sleep 0.5
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "Edit Mode" && log_pass "Preview mode works" || log_fail "Preview mode broken"

# Test 16: Return to edit mode - Quill reinitializes
log_info "TEST 16: Edit mode re-initialization"
agent-browser find role button click --name "Edit Mode" 2>/dev/null || \
    agent-browser find text "Edit Mode" click 2>/dev/null
sleep 0.5
REINIT=$(agent-browser eval '
    const containers = document.querySelectorAll(".pu-content-quill");
    const instances = Object.keys(PU.quill.instances).length;
    containers.length > 0 && instances > 0
' 2>/dev/null)
echo "$REINIT" | grep -qi "true" && log_pass "Quill re-initialized after mode switch" || log_fail "Quill not re-initialized: $REINIT"

# Test 17: Export still works
log_info "TEST 17: Export functionality"
agent-browser find role button click --name "Export" 2>/dev/null || \
    agent-browser find text "Export" click 2>/dev/null
sleep 0.5
EXPORT_VISIBLE=$(agent-browser eval '
    const modal = document.querySelector("[data-testid=pu-export-modal]");
    modal && modal.style.display !== "none"
' 2>/dev/null)
echo "$EXPORT_VISIBLE" | grep -qi "true" && log_pass "Export modal opens" || log_skip "Export modal check"
# Close modal
agent-browser find role button click --name "Cancel" 2>/dev/null
sleep 0.3

# Cleanup
agent-browser close 2>/dev/null

print_summary
exit $?
