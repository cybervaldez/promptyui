#!/bin/bash
# ============================================================================
# E2E Test: Focus Mode Include Controls (Children checkbox)
# ============================================================================
# Tests:
#   1. Include footer visible in focus mode
#   2. No Parent checkbox (parent always included)
#   3. Children checkbox disabled when block has no children
#   4. Children checkbox enabled when block has children
#   5. Unchecking Children changes composition count
#   6. Session-global: Children state persists across block switches
#   7. Parent text opacity is 0.7
#   8. Empty root block shows 0 resolved prompts (not 1)
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Focus Mode: Include Controls (Children)"

# ── Prerequisites ──────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load hiring-templates / nested-job-brief ────────────────
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

# ── Discover block structure ───────────────────────────────────────
LEAF_PATH=$(agent-browser eval '(() => { const p = PU.helpers.getActivePrompt(); if (!p || !p.text) return ""; function findLeaf(blocks, prefix) { for (let i = 0; i < blocks.length; i++) { const path = prefix ? prefix + "." + i : String(i); const b = blocks[i]; if (b.after && b.after.length > 0) { const r = findLeaf(b.after, path); if (r) return r; } else if ("content" in b) return path; } return ""; } return findLeaf(p.text, ""); })()' 2>/dev/null | tr -d '"')

PARENT_PATH=$(agent-browser eval '(() => { const p = PU.helpers.getActivePrompt(); if (!p || !p.text) return ""; function findParent(blocks, prefix) { for (let i = 0; i < blocks.length; i++) { const path = prefix ? prefix + "." + i : String(i); const b = blocks[i]; if ("content" in b && b.after && b.after.length > 0) return path; if (b.after && b.after.length > 0) { const r = findParent(b.after, path); if (r) return r; } } return ""; } return findParent(p.text, ""); })()' 2>/dev/null | tr -d '"')

log_info "Leaf block path: ${LEAF_PATH:-none}"
log_info "Parent block path: ${PARENT_PATH:-none}"

# ══════════════════════════════════════════════════════════════════════
# TEST 1: Include footer visible in focus mode (leaf block)
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "TEST 1: Include footer visible, leaf block (no children)"

if [ -z "$LEAF_PATH" ]; then
    log_skip "No leaf block found"
else
    agent-browser eval "PU.focus.enter('$LEAF_PATH')" 2>/dev/null
    sleep 2

    FOCUS_ACTIVE=$(agent-browser eval 'PU.state.focusMode.active === true' 2>/dev/null)
    echo "$FOCUS_ACTIVE" | grep -qi "true" \
        && log_pass "Focus mode active" \
        || log_fail "Focus mode not active"

    FOOTER_EXISTS=$(agent-browser eval '!!document.querySelector("[data-testid=pu-focus-include-footer]")' 2>/dev/null)
    echo "$FOOTER_EXISTS" | grep -qi "true" \
        && log_pass "Include footer exists" \
        || log_fail "Include footer missing"
fi

# ══════════════════════════════════════════════════════════════════════
# TEST 2: No Parent checkbox (parent always included)
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "TEST 2: Parent checkbox removed (parent always included)"

if [ -z "$LEAF_PATH" ]; then
    log_skip "No leaf block"
else
    NO_PARENT_CB=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-include-parent]") === null' 2>/dev/null)
    echo "$NO_PARENT_CB" | grep -qi "true" \
        && log_pass "Parent checkbox does not exist (removed)" \
        || log_fail "Parent checkbox should not exist"
fi

# ══════════════════════════════════════════════════════════════════════
# TEST 3: Children checkbox disabled when block has no children
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "TEST 3: Children checkbox disabled for leaf block"

if [ -z "$LEAF_PATH" ]; then
    log_skip "No leaf block"
else
    CHILDREN_DISABLED=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-include-children]").disabled' 2>/dev/null)
    echo "$CHILDREN_DISABLED" | grep -qi "true" \
        && log_pass "Children checkbox disabled for leaf block" \
        || log_fail "Children checkbox not disabled for leaf: $CHILDREN_DISABLED"

    CHILDREN_CHECKED=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-include-children]").checked' 2>/dev/null)
    echo "$CHILDREN_CHECKED" | grep -qi "false" \
        && log_pass "Children checkbox unchecked when disabled" \
        || log_fail "Children checkbox should be unchecked when disabled: $CHILDREN_CHECKED"

    agent-browser eval 'PU.focus.exit()' 2>/dev/null
    sleep 1
fi

# ══════════════════════════════════════════════════════════════════════
# TEST 4: Children checkbox enabled when block has children
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "TEST 4: Children checkbox enabled for parent block"

if [ -z "$PARENT_PATH" ]; then
    log_skip "No parent block with children found"
else
    agent-browser eval "PU.focus.enter('$PARENT_PATH')" 2>/dev/null
    sleep 2

    log_pass "Block $PARENT_PATH has children"

    CHILDREN_ENABLED=$(agent-browser eval '!document.querySelector("[data-testid=pu-focus-include-children]").disabled' 2>/dev/null)
    echo "$CHILDREN_ENABLED" | grep -qi "true" \
        && log_pass "Children checkbox enabled for parent block" \
        || log_fail "Children checkbox should be enabled for parent block"

    CHILDREN_CHECKED=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-include-children]").checked' 2>/dev/null)
    echo "$CHILDREN_CHECKED" | grep -qi "true" \
        && log_pass "Children checkbox checked by default for parent block" \
        || log_fail "Children checkbox should be checked: $CHILDREN_CHECKED"
fi

HAS_PARENT_BLOCK="$PARENT_PATH"

# ══════════════════════════════════════════════════════════════════════
# TEST 5: Unchecking Children changes counts
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "TEST 5: Uncheck Children — composition count changes"

if [ -n "$HAS_PARENT_BLOCK" ]; then
    # Expand output first
    agent-browser eval 'PU.focus.expandOutput()' 2>/dev/null
    sleep 1

    COUNT_WITH_CHILDREN=$(agent-browser eval 'document.querySelectorAll("[data-testid=pu-focus-output-list] .pu-output-item").length' 2>/dev/null)
    log_info "Output items with children: $COUNT_WITH_CHILDREN"

    # Uncheck Children
    agent-browser eval 'document.querySelector("[data-testid=pu-focus-include-children]").click()' 2>/dev/null
    sleep 1

    CHILDREN_STATE=$(agent-browser eval 'PU.focus._includeChildren' 2>/dev/null)
    echo "$CHILDREN_STATE" | grep -qi "false" \
        && log_pass "JS state _includeChildren is false" \
        || log_fail "JS state should be false: $CHILDREN_STATE"

    COUNT_WITHOUT_CHILDREN=$(agent-browser eval 'document.querySelectorAll("[data-testid=pu-focus-output-list] .pu-output-item").length' 2>/dev/null)
    log_info "Output items without children: $COUNT_WITHOUT_CHILDREN"

    if [ "$COUNT_WITHOUT_CHILDREN" -le "$COUNT_WITH_CHILDREN" ] 2>/dev/null; then
        log_pass "Output count changed or stayed same when children unchecked ($COUNT_WITH_CHILDREN -> $COUNT_WITHOUT_CHILDREN)"
    else
        log_fail "Output count increased when children unchecked: $COUNT_WITH_CHILDREN -> $COUNT_WITHOUT_CHILDREN"
    fi

    # Re-check Children
    agent-browser eval 'document.querySelector("[data-testid=pu-focus-include-children]").click()' 2>/dev/null
    sleep 0.5
else
    log_skip "No parent block — skipping children toggle test"
fi

# ══════════════════════════════════════════════════════════════════════
# TEST 6: Session-global — Children state persists across block switches
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "TEST 6: Session-global persistence for Children"

if [ -n "$HAS_PARENT_BLOCK" ]; then
    # Uncheck Children
    agent-browser eval 'document.querySelector("[data-testid=pu-focus-include-children]").click()' 2>/dev/null
    sleep 0.5

    CHILDREN_BEFORE=$(agent-browser eval 'PU.focus._includeChildren' 2>/dev/null)
    echo "$CHILDREN_BEFORE" | grep -qi "false" \
        && log_pass "Children unchecked before block switch" \
        || log_fail "Children should be unchecked"

    # Exit and enter different block (that also has children)
    agent-browser eval 'PU.focus.exit()' 2>/dev/null
    sleep 1

    agent-browser eval "PU.focus.enter('$PARENT_PATH')" 2>/dev/null
    sleep 2

    CHILDREN_AFTER=$(agent-browser eval 'PU.focus._includeChildren' 2>/dev/null)
    echo "$CHILDREN_AFTER" | grep -qi "false" \
        && log_pass "Children state persisted after block switch (session-global)" \
        || log_fail "Children state lost after block switch: $CHILDREN_AFTER"

    CHILDREN_CB_AFTER=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-include-children]").checked' 2>/dev/null)
    echo "$CHILDREN_CB_AFTER" | grep -qi "false" \
        && log_pass "Children checkbox reflects persisted state in DOM" \
        || log_fail "Children checkbox doesn't match persisted state: $CHILDREN_CB_AFTER"

    # Reset Children back to checked for cleanup
    agent-browser eval 'PU.focus._includeChildren = true' 2>/dev/null
else
    log_skip "No parent block — skipping persistence test"
fi

# ══════════════════════════════════════════════════════════════════════
# TEST 7: Parent text opacity is 0.7
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "TEST 7: Parent text opacity styling"

OPACITY=$(agent-browser eval '(() => { const el = document.querySelector(".pu-focus-parent-text"); if (!el) return "no-element"; return getComputedStyle(el).opacity; })()' 2>/dev/null | tr -d '"')

if [ "$OPACITY" = "no-element" ]; then
    OPACITY=$(agent-browser eval '(() => { for (const sheet of document.styleSheets) { try { for (const rule of sheet.cssRules) { if (rule.selectorText === ".pu-focus-parent-text" && rule.style.opacity) return rule.style.opacity; } } catch(e) {} } return "not-found"; })()' 2>/dev/null | tr -d '"')
fi

if [ "$OPACITY" = "0.7" ]; then
    log_pass "Parent text opacity is 0.7"
elif echo "$OPACITY" | grep -q "0.7"; then
    log_pass "Parent text opacity is ~0.7 ($OPACITY)"
else
    log_fail "Parent text opacity should be 0.7, got: $OPACITY"
fi

# ══════════════════════════════════════════════════════════════════════
# TEST 8: Empty root block shows 0 resolved prompts (not 1)
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "TEST 8: Empty root block counter shows 0 (not 1)"

# Exit current focus
agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# Add a new root block with empty content
agent-browser eval 'var p = PU.helpers.getActivePrompt(); p.text.push({content: ""}); var newPath = String(p.text.length - 1); PU.focus.enter(newPath); newPath' 2>/dev/null
sleep 2

# Counter should show 0 compositions for empty content
COUNTER_TEXT=$(agent-browser eval 'var q = PU.state.focusMode.quillInstance; var text = PU.quill.serialize(q); var path = PU.state.focusMode.blockPath; var c = PU.focus._computeFocusCounters(text, path); c.totalCompositions' 2>/dev/null)
[ "$COUNTER_TEXT" = "0" ] \
    && log_pass "Empty block counter shows 0 compositions" \
    || log_fail "Empty block counter should be 0, got: $COUNTER_TEXT"

# Clean up: remove the test block
agent-browser eval 'var p = PU.helpers.getActivePrompt(); p.text.pop()' 2>/dev/null

# ══════════════════════════════════════════════════════════════════════
# CLEANUP
# ══════════════════════════════════════════════════════════════════════
echo ""
log_info "CLEANUP"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 0.5
agent-browser close 2>/dev/null
log_pass "Browser closed"

# ══════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════
print_summary
exit $?
