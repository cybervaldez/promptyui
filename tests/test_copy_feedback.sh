#!/bin/bash
# ============================================================================
# E2E Test: Copy All inline "Copied to Clipboard" feedback
# ============================================================================
# Verifies that clicking "Copy All" in the focus mode overlay replaces the
# button text with a checkmark + "Copied to Clipboard", then reverts after
# ~2 seconds.
#
# Note: The main editor output footer was removed (migrated to Build panel).
# This test now only covers focus mode copy feedback.
#
# Usage: ./tests/test_copy_feedback.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Copy All: Inline Feedback"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load a job ─────────────────────────────────────────────────
log_info "Loading product-content job..."
agent-browser open "$BASE_URL" 2>/dev/null
sleep 3

agent-browser find text "product-content" click 2>/dev/null
sleep 3

# Verify prompt loaded
PROMPT_NAME=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
if [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ]; then
    log_pass "Prompt loaded: $PROMPT_NAME"
else
    log_fail "Could not load prompt (activePromptId: $PROMPT_NAME)"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

# ============================================================================
# TEST 1: Focus mode "Copy All" button shows inline feedback
# ============================================================================
echo ""
log_test "OBJECTIVE: Focus mode Copy All shows checkmark + 'Copied to Clipboard'"

# Open focus mode on block 0
agent-browser eval 'PU.focus.enter("0")' 2>/dev/null
sleep 2

# Expand the output panel if collapsed
agent-browser eval 'var toggle = document.querySelector("[data-testid=pu-focus-output-toggle]"); if (toggle) toggle.click()' 2>/dev/null
sleep 2

# Verify focus mode has output items
FOCUS_ITEMS=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-focus-output]"); el ? el.querySelectorAll(".pu-output-item-text").length : 0' 2>/dev/null | tr -d '"')
log_info "Focus mode has $FOCUS_ITEMS output items"

# Check focus mode Copy All button exists
FOCUS_COPY_EXISTS=$(agent-browser eval 'var btn = document.querySelector("[data-testid=pu-focus-output-copy]"); btn ? btn.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
[ "$FOCUS_COPY_EXISTS" = "Copy All" ] \
    && log_pass "Focus mode Copy All button found" \
    || log_fail "Focus mode Copy All button not found: $FOCUS_COPY_EXISTS"

# Click the focus mode Copy All button
agent-browser eval 'document.querySelector("[data-testid=pu-focus-output-copy]").click()' 2>/dev/null
sleep 0.3

# Check button now shows "Copied to Clipboard"
FOCUS_COPY_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-output-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
echo "$FOCUS_COPY_TEXT" | grep -q "Copied to Clipboard" \
    && log_pass "Focus Copy All text changed to 'Copied to Clipboard'" \
    || log_fail "Focus Copy All text should be 'Copied to Clipboard', got: $FOCUS_COPY_TEXT"

FOCUS_COPY_CLASS=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-output-copy]").classList.contains("pu-copied")' 2>/dev/null)
[ "$FOCUS_COPY_CLASS" = "true" ] \
    && log_pass "Focus button has pu-copied class" \
    || log_fail "Focus button should have pu-copied class: $FOCUS_COPY_CLASS"

# ============================================================================
# TEST 2: Focus mode Copy All reverts after timeout
# ============================================================================
echo ""
log_test "OBJECTIVE: Focus mode Copy All reverts to original text after ~2s"

sleep 2.5

FOCUS_REVERTED=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-output-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$FOCUS_REVERTED" = "Copy All" ] \
    && log_pass "Focus button reverted to 'Copy All'" \
    || log_fail "Focus button should revert to 'Copy All', got: $FOCUS_REVERTED"

FOCUS_REVERTED_CLASS=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-output-copy]").classList.contains("pu-copied")' 2>/dev/null)
[ "$FOCUS_REVERTED_CLASS" = "false" ] \
    && log_pass "pu-copied class removed after revert" \
    || log_fail "pu-copied class should be removed: $FOCUS_REVERTED_CLASS"

# ============================================================================
# TEST 3: Rapid double-click doesn't break the revert
# ============================================================================
echo ""
log_test "OBJECTIVE: Rapid double-click on focus Copy All doesn't break revert"

# Click focus mode Copy All twice quickly
agent-browser eval 'var btn = document.querySelector("[data-testid=pu-focus-output-copy]"); btn.click(); setTimeout(function() { btn.click(); }, 200)' 2>/dev/null
sleep 0.5

RAPID_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-output-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
echo "$RAPID_TEXT" | grep -q "Copied to Clipboard" \
    && log_pass "Button shows feedback after rapid double-click" \
    || log_fail "Button should show feedback after rapid click: $RAPID_TEXT"

sleep 2.5

RAPID_REVERTED=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-output-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$RAPID_REVERTED" = "Copy All" ] \
    && log_pass "Button properly reverted after rapid double-click" \
    || log_fail "Button should revert after rapid click: $RAPID_REVERTED"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
