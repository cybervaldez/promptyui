#!/bin/bash
# ============================================================================
# E2E Test: Copy All inline "Copied to Clipboard" feedback
# ============================================================================
# Verifies that clicking "Copy All" in both the main editor output footer
# and the focus mode overlay replaces the button text with a checkmark +
# "Copied to Clipboard", then reverts after ~2 seconds.
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

# ── Setup: Load a job with outputs ─────────────────────────────────────
log_info "Loading product-content job..."
agent-browser open "$BASE_URL" 2>/dev/null
sleep 2

agent-browser find text "product-content" click 2>/dev/null
sleep 3

# First prompt auto-selects; verify outputs exist
HAS_OUTPUTS=$(agent-browser eval 'document.querySelectorAll("[data-testid=pu-output-list] .pu-output-item-text").length' 2>/dev/null | tr -d '"')
if [ "$HAS_OUTPUTS" -gt 0 ] 2>/dev/null; then
    log_pass "Prompt loaded with $HAS_OUTPUTS output items"
else
    log_fail "Could not load prompt or no outputs (found: $HAS_OUTPUTS)"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

# ============================================================================
# TEST 1: Main editor "Copy All" button shows inline feedback
# ============================================================================
echo ""
log_test "OBJECTIVE: Main editor Copy All shows checkmark + 'Copied to Clipboard'"

# Verify the Copy All button exists in the output footer
COPY_BTN_EXISTS=$(agent-browser eval 'var btn = document.querySelector("[data-testid=pu-output-footer-copy]"); btn ? btn.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
[ "$COPY_BTN_EXISTS" = "Copy All" ] \
    && log_pass "Main editor Copy All button found" \
    || log_fail "Main editor Copy All button not found: $COPY_BTN_EXISTS"

# Click the Copy All button
agent-browser eval 'document.querySelector("[data-testid=pu-output-footer-copy]").click()' 2>/dev/null
sleep 0.3

# Check button now shows "Copied to Clipboard" and has pu-copied class
COPY_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-output-footer-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
echo "$COPY_TEXT" | grep -q "Copied to Clipboard" \
    && log_pass "Button text changed to 'Copied to Clipboard'" \
    || log_fail "Button text should be 'Copied to Clipboard', got: $COPY_TEXT"

COPY_CLASS=$(agent-browser eval 'document.querySelector("[data-testid=pu-output-footer-copy]").classList.contains("pu-copied")' 2>/dev/null)
[ "$COPY_CLASS" = "true" ] \
    && log_pass "Button has pu-copied class" \
    || log_fail "Button should have pu-copied class: $COPY_CLASS"

# Check SVG checkmark is present
HAS_SVG=$(agent-browser eval '!!document.querySelector("[data-testid=pu-output-footer-copy] svg")' 2>/dev/null)
[ "$HAS_SVG" = "true" ] \
    && log_pass "Checkmark SVG present in button" \
    || log_fail "Checkmark SVG missing: $HAS_SVG"

# ============================================================================
# TEST 2: Main editor Copy All reverts after timeout
# ============================================================================
echo ""
log_test "OBJECTIVE: Main editor Copy All reverts to original text after ~2s"

sleep 2.5

REVERTED_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-output-footer-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$REVERTED_TEXT" = "Copy All" ] \
    && log_pass "Button reverted to 'Copy All'" \
    || log_fail "Button should revert to 'Copy All', got: $REVERTED_TEXT"

REVERTED_CLASS=$(agent-browser eval 'document.querySelector("[data-testid=pu-output-footer-copy]").classList.contains("pu-copied")' 2>/dev/null)
[ "$REVERTED_CLASS" = "false" ] \
    && log_pass "pu-copied class removed after revert" \
    || log_fail "pu-copied class should be removed: $REVERTED_CLASS"

# ============================================================================
# TEST 3: Focus mode "Copy All" button shows inline feedback
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
FOCUS_ITEMS=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-output]").querySelectorAll(".pu-output-item-text").length' 2>/dev/null | tr -d '"')
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
# TEST 4: Focus mode Copy All reverts after timeout
# ============================================================================
echo ""
log_test "OBJECTIVE: Focus mode Copy All reverts to original text after ~2s"

sleep 2.5

FOCUS_REVERTED=$(agent-browser eval 'document.querySelector("[data-testid=pu-focus-output-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$FOCUS_REVERTED" = "Copy All" ] \
    && log_pass "Focus button reverted to 'Copy All'" \
    || log_fail "Focus button should revert to 'Copy All', got: $FOCUS_REVERTED"

agent-browser eval 'PU.focus.exit()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 5: Rapid double-click doesn't break the revert
# ============================================================================
echo ""
log_test "OBJECTIVE: Rapid double-click on Copy All doesn't break revert"

# Click main editor Copy All twice quickly
agent-browser eval 'var btn = document.querySelector("[data-testid=pu-output-footer-copy]"); btn.click(); setTimeout(function() { btn.click(); }, 200)' 2>/dev/null
sleep 0.5

RAPID_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-output-footer-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
echo "$RAPID_TEXT" | grep -q "Copied to Clipboard" \
    && log_pass "Button shows feedback after rapid double-click" \
    || log_fail "Button should show feedback after rapid click: $RAPID_TEXT"

sleep 2.5

RAPID_REVERTED=$(agent-browser eval 'document.querySelector("[data-testid=pu-output-footer-copy]").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$RAPID_REVERTED" = "Copy All" ] \
    && log_pass "Button properly reverted after rapid double-click" \
    || log_fail "Button should revert after rapid click: $RAPID_REVERTED"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
