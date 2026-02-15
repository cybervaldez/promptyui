#!/bin/bash
# ============================================================================
# E2E Test Suite: Focus Mode URL Persistence
# ============================================================================
# Tests deep linking, page refresh persistence, and URL sync for focus mode.
#
# Covers:
#   1-3. Deep link with ?focus=X / ?modal=focus opens focus mode
#   4-5. URL updates with modal=focus&focus=X when entering/exiting
#   6. Invalid focus path cleaned from URL
#   7. Focus param without job/prompt handled gracefully
#   8. Nested block deep link with parent context
#   9. Page refresh preserves focus mode
#   10. Focus param validation rejects non-numeric paths
#   11. Switching prompts exits focus and clears URL
#   12. modal=focus without focus param defaults to block 0
#   13. modal=focus with explicit focus param uses that path
#
# Usage: ./tests/test_focus_url_persistence.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$1" == "--port" ]] && PORT="$2"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Focus Mode: URL Persistence & Deep Linking"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_pass "Server is running"
else
    log_fail "Server not running on port $PORT"
    exit 1
fi

# ============================================================================
# TEST 1: Deep link with focus param opens focus mode
# ============================================================================
echo ""
log_info "TEST 1: Deep link with ?focus=0 opens focus mode"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=outreach-email&composition=99&focus=0" 2>/dev/null
sleep 4

FOCUS_ACTIVE=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if echo "$FOCUS_ACTIVE" | grep -qi "true"; then
    log_pass "Focus mode active after deep link"
else
    log_fail "Focus mode not active after deep link: $FOCUS_ACTIVE"
fi

BLOCK_PATH=$(agent-browser eval 'PU.state.focusMode.blockPath' 2>/dev/null | tr -d '"')
if [ "$BLOCK_PATH" = "0" ]; then
    log_pass "Focus mode on correct block path: $BLOCK_PATH"
else
    log_fail "Wrong block path: expected '0', got '$BLOCK_PATH'"
fi

# Check overlay is fully rendered (not just state)
RENDER_STATE=$(agent-browser eval 'JSON.stringify({display: document.querySelector("[data-testid=pu-focus-overlay]").style.display, visible: document.querySelector("[data-testid=pu-focus-overlay]").classList.contains("pu-focus-visible"), height: document.querySelector("[data-testid=pu-focus-overlay]").offsetHeight})' 2>/dev/null)
if echo "$RENDER_STATE" | grep -q 'display.*flex' && echo "$RENDER_STATE" | grep -q 'visible.*true'; then
    log_pass "Focus overlay rendered: display=flex, visible class applied"
else
    log_fail "Focus overlay not fully rendered: $RENDER_STATE"
fi

# ============================================================================
# TEST 2: URL contains modal=focus and focus=X while in focus mode
# ============================================================================
echo ""
log_info "TEST 2: URL reflects focus state with modal=focus param"

CURRENT_URL=$(agent-browser get url 2>/dev/null)
if echo "$CURRENT_URL" | grep -q "modal=focus"; then
    log_pass "URL contains modal=focus param"
else
    log_fail "URL missing modal=focus: $CURRENT_URL"
fi

if echo "$CURRENT_URL" | grep -q "focus=0"; then
    log_pass "URL contains focus=0 param"
else
    log_fail "URL missing focus=0: $CURRENT_URL"
fi

if echo "$CURRENT_URL" | grep -q "job=hiring-templates"; then
    log_pass "URL preserves job param"
else
    log_fail "URL lost job param: $CURRENT_URL"
fi

if echo "$CURRENT_URL" | grep -q "prompt=outreach-email"; then
    log_pass "URL preserves prompt param"
else
    log_fail "URL lost prompt param: $CURRENT_URL"
fi

# ============================================================================
# TEST 3: Exiting focus mode removes modal=focus and focus param from URL
# ============================================================================
echo ""
log_info "TEST 3: Exit focus mode clears modal=focus and focus from URL"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

FOCUS_AFTER_EXIT=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if echo "$FOCUS_AFTER_EXIT" | grep -qi "false"; then
    log_pass "Focus mode deactivated"
else
    log_fail "Focus mode still active after exit: $FOCUS_AFTER_EXIT"
fi

URL_AFTER_EXIT=$(agent-browser get url 2>/dev/null)
if echo "$URL_AFTER_EXIT" | grep -q "focus="; then
    log_fail "URL still has focus param after exit: $URL_AFTER_EXIT"
else
    log_pass "URL focus param cleared after exit"
fi

if echo "$URL_AFTER_EXIT" | grep -q "modal=focus"; then
    log_fail "URL still has modal=focus after exit: $URL_AFTER_EXIT"
else
    log_pass "URL modal=focus param cleared after exit"
fi

if echo "$URL_AFTER_EXIT" | grep -q "job=hiring-templates" && echo "$URL_AFTER_EXIT" | grep -q "prompt=outreach-email"; then
    log_pass "URL preserves job and prompt after focus exit"
else
    log_fail "URL lost other params after focus exit: $URL_AFTER_EXIT"
fi

# ============================================================================
# TEST 4: Enter focus mode via JS updates URL with modal=focus
# ============================================================================
echo ""
log_info "TEST 4: Entering focus mode programmatically updates URL"

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1

URL_AFTER_ENTER=$(agent-browser get url 2>/dev/null)
if echo "$URL_AFTER_ENTER" | grep -q "modal=focus" && echo "$URL_AFTER_ENTER" | grep -q "focus=0"; then
    log_pass "URL updated with modal=focus&focus=0 on enter"
else
    log_fail "URL not updated correctly after focus enter: $URL_AFTER_ENTER"
fi

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 5: Invalid focus path is cleaned from URL
# ============================================================================
echo ""
log_info "TEST 5: Invalid focus path (non-existent block) cleaned from URL"

agent-browser close 2>/dev/null || true
sleep 0.5

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=outreach-email&composition=99&focus=99" 2>/dev/null
sleep 4

FOCUS_INVALID=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if echo "$FOCUS_INVALID" | grep -qi "false"; then
    log_pass "Focus mode not activated for invalid path"
else
    log_fail "Focus mode activated for invalid path: $FOCUS_INVALID"
fi

URL_INVALID=$(agent-browser get url 2>/dev/null)
if echo "$URL_INVALID" | grep -q "focus="; then
    log_fail "URL still has stale focus param for invalid path: $URL_INVALID"
else
    log_pass "Stale focus param cleaned from URL"
fi

if echo "$URL_INVALID" | grep -q "modal=focus"; then
    log_fail "URL still has stale modal=focus for invalid path: $URL_INVALID"
else
    log_pass "Stale modal=focus param cleaned from URL"
fi

# ============================================================================
# TEST 6: Focus param with missing prompt is handled gracefully
# ============================================================================
echo ""
log_info "TEST 6: Focus param without prompt is handled gracefully"

agent-browser close 2>/dev/null || true
sleep 0.5

agent-browser open "$BASE_URL/?job=hiring-templates&focus=0" 2>/dev/null
sleep 4

FOCUS_NO_PROMPT=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if echo "$FOCUS_NO_PROMPT" | grep -qi "false"; then
    log_pass "Focus mode not activated without prompt param"
else
    AUTO_PROMPT=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
    if [ -n "$AUTO_PROMPT" ] && [ "$AUTO_PROMPT" != "null" ]; then
        if echo "$FOCUS_NO_PROMPT" | grep -qi "true"; then
            log_pass "Focus mode active — prompt auto-selected: $AUTO_PROMPT"
        else
            log_fail "Unexpected state: focus=$FOCUS_NO_PROMPT, prompt=$AUTO_PROMPT"
        fi
    else
        log_fail "Focus mode active without prompt: $FOCUS_NO_PROMPT"
    fi
fi

# ============================================================================
# TEST 7: Deep link with nested block path
# ============================================================================
echo ""
log_info "TEST 7: Deep link with nested block path (dot notation)"

agent-browser close 2>/dev/null || true
sleep 0.5

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=nested-job-brief&composition=99&focus=1.0" 2>/dev/null
sleep 4

FOCUS_NESTED=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
NESTED_PATH=$(agent-browser eval 'PU.state.focusMode.blockPath' 2>/dev/null | tr -d '"')

if echo "$FOCUS_NESTED" | grep -qi "true" && [ "$NESTED_PATH" = "1.0" ]; then
    log_pass "Deep link opened focus mode on nested block 1.0"
else
    log_fail "Nested deep link failed: active=$FOCUS_NESTED, path=$NESTED_PATH"
fi

URL_NESTED=$(agent-browser get url 2>/dev/null)
if echo "$URL_NESTED" | grep -q "focus=1.0"; then
    log_pass "URL shows nested focus path: focus=1.0"
else
    log_fail "URL wrong for nested path: $URL_NESTED"
fi

HAS_PARENT_CTX=$(agent-browser eval '!!document.querySelector(".ql-parent-context")' 2>/dev/null)
if echo "$HAS_PARENT_CTX" | grep -qi "true"; then
    log_pass "Parent context blot present for nested block deep link"
else
    log_fail "Parent context blot missing for nested deep link"
fi

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 8: Page refresh preserves focus mode
# ============================================================================
echo ""
log_info "TEST 8: Page refresh while in focus mode re-enters focus"

agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 1

URL_BEFORE_REFRESH=$(agent-browser get url 2>/dev/null)
if echo "$URL_BEFORE_REFRESH" | grep -q "modal=focus" && echo "$URL_BEFORE_REFRESH" | grep -q "focus=0"; then
    log_pass "URL has modal=focus&focus=0 before refresh"
else
    log_fail "URL incorrect before refresh: $URL_BEFORE_REFRESH"
fi

agent-browser reload 2>/dev/null
sleep 4

FOCUS_AFTER_REFRESH=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if echo "$FOCUS_AFTER_REFRESH" | grep -qi "true"; then
    log_pass "Focus mode re-activated after page refresh"
else
    log_fail "Focus mode not restored after refresh: $FOCUS_AFTER_REFRESH"
fi

PATH_AFTER_REFRESH=$(agent-browser eval 'PU.state.focusMode.blockPath' 2>/dev/null | tr -d '"')
if [ "$PATH_AFTER_REFRESH" = "0" ]; then
    log_pass "Correct block path restored after refresh: $PATH_AFTER_REFRESH"
else
    log_fail "Wrong block path after refresh: expected '0', got '$PATH_AFTER_REFRESH'"
fi

URL_AFTER_REFRESH=$(agent-browser get url 2>/dev/null)
if echo "$URL_AFTER_REFRESH" | grep -q "modal=focus" && echo "$URL_AFTER_REFRESH" | grep -q "focus=0"; then
    log_pass "URL preserved modal=focus&focus params after refresh"
else
    log_fail "URL lost params after refresh: $URL_AFTER_REFRESH"
fi

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 9: Focus param validation rejects non-numeric paths
# ============================================================================
echo ""
log_info "TEST 9: Focus param validation rejects non-numeric paths"

agent-browser close 2>/dev/null || true
sleep 0.5

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=outreach-email&composition=99&focus=abc" 2>/dev/null
sleep 4

FOCUS_ALPHA=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if echo "$FOCUS_ALPHA" | grep -qi "false"; then
    log_pass "Alphabetic focus path rejected"
else
    log_fail "Alphabetic focus path accepted: $FOCUS_ALPHA"
fi

agent-browser close 2>/dev/null || true
sleep 0.5

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=outreach-email&focus=0%3Balert(1)" 2>/dev/null
sleep 4

FOCUS_INJECTION=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if echo "$FOCUS_INJECTION" | grep -qi "false"; then
    log_pass "Injection attempt in focus param rejected"
else
    log_fail "Injection attempt in focus param not rejected: $FOCUS_INJECTION"
fi

# ============================================================================
# TEST 10: Switching prompts exits focus and clears URL
# ============================================================================
echo ""
log_info "TEST 10: Switching prompts exits focus mode and updates URL"

agent-browser close 2>/dev/null || true
sleep 0.5

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=outreach-email&composition=99&focus=0" 2>/dev/null
sleep 4

FOCUS_BEFORE_SWITCH=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if ! echo "$FOCUS_BEFORE_SWITCH" | grep -qi "true"; then
    log_skip "Could not enter focus mode for prompt switch test"
else
    agent-browser eval 'PU.actions.selectPrompt("hiring-templates", "nested-job-brief")' 2>/dev/null
    sleep 2

    FOCUS_AFTER_SWITCH=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
    if echo "$FOCUS_AFTER_SWITCH" | grep -qi "false"; then
        log_pass "Focus mode exited on prompt switch"
    else
        log_fail "Focus mode still active after prompt switch: $FOCUS_AFTER_SWITCH"
    fi

    URL_AFTER_SWITCH=$(agent-browser get url 2>/dev/null)
    if echo "$URL_AFTER_SWITCH" | grep -q "focus="; then
        log_fail "URL still has focus param after prompt switch: $URL_AFTER_SWITCH"
    else
        log_pass "Focus param cleared from URL after prompt switch"
    fi

    if echo "$URL_AFTER_SWITCH" | grep -q "modal=focus"; then
        log_fail "URL still has modal=focus after prompt switch: $URL_AFTER_SWITCH"
    else
        log_pass "modal=focus cleared from URL after prompt switch"
    fi

    if echo "$URL_AFTER_SWITCH" | grep -q "prompt=nested-job-brief"; then
        log_pass "URL updated to new prompt after switch"
    else
        log_fail "URL doesn't reflect new prompt: $URL_AFTER_SWITCH"
    fi
fi

# ============================================================================
# TEST 11: Deep link with ?modal=focus (no explicit focus param) defaults to block 0
# ============================================================================
echo ""
log_info "TEST 11: Deep link with ?modal=focus defaults to block 0"

agent-browser close 2>/dev/null || true
sleep 0.5

# Use modal=focus without explicit focus param — should default to block "0"
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=outreach-email&composition=99&modal=focus" 2>/dev/null
sleep 4

FOCUS_MODAL=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
if echo "$FOCUS_MODAL" | grep -qi "true"; then
    log_pass "modal=focus activated focus mode"
else
    log_fail "modal=focus did not activate focus mode: $FOCUS_MODAL"
fi

MODAL_PATH=$(agent-browser eval 'PU.state.focusMode.blockPath' 2>/dev/null | tr -d '"')
if [ "$MODAL_PATH" = "0" ]; then
    log_pass "modal=focus defaulted to block 0"
else
    log_fail "modal=focus wrong path: expected '0', got '$MODAL_PATH'"
fi

# Verify overlay is rendered
MODAL_OVERLAY=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-overlay]").classList.contains("pu-focus-visible")' 2>/dev/null)
if echo "$MODAL_OVERLAY" | grep -qi "true"; then
    log_pass "Focus overlay visually rendered via modal=focus"
else
    log_fail "Focus overlay not rendered via modal=focus"
fi

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 12: Deep link with ?modal=focus&focus=1.0 uses explicit path
# ============================================================================
echo ""
log_info "TEST 12: Deep link with ?modal=focus&focus=1.0 uses explicit path"

agent-browser close 2>/dev/null || true
sleep 0.5

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=nested-job-brief&composition=99&modal=focus&focus=1.0" 2>/dev/null
sleep 4

FOCUS_EXPLICIT=$(agent-browser eval 'PU.state.focusMode.active' 2>/dev/null)
EXPLICIT_PATH=$(agent-browser eval 'PU.state.focusMode.blockPath' 2>/dev/null | tr -d '"')

if echo "$FOCUS_EXPLICIT" | grep -qi "true" && [ "$EXPLICIT_PATH" = "1.0" ]; then
    log_pass "modal=focus&focus=1.0 opened nested block correctly"
else
    log_fail "modal=focus&focus=1.0 failed: active=$FOCUS_EXPLICIT, path=$EXPLICIT_PATH"
fi

# Verify parent context (nested block)
HAS_CTX=$(agent-browser eval '!!document.querySelector(".ql-parent-context")' 2>/dev/null)
if echo "$HAS_CTX" | grep -qi "true"; then
    log_pass "Parent context blot present via modal=focus deep link"
else
    log_fail "Parent context blot missing via modal=focus deep link"
fi

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null || true
log_pass "Browser closed"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
