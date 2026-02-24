#!/bin/bash
# ============================================================================
# E2E Test Suite: Integrated Path+Source Selector
# ============================================================================
# Tests the integrated source suffix inside path badges (pu-block-path,
# pu-path-label, pu-child-path-hint) with dropdown for switching block source.
#
# Usage: ./tests/test_source_pill.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Integrated Path+Source Selector"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load hiring-templates / ext-sourcing-strategy ───────────────
# This prompt has both content blocks (text.0) and ext_text blocks (text.1)
log_info "Loading hiring-templates / ext-sourcing-strategy..."
agent-browser close 2>/dev/null || true
sleep 1
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=ext-sourcing-strategy" 2>/dev/null
sleep 10

# Verify prompt loaded
PROMPT_NAME=""
for attempt in 1 2 3 4 5; do
    PROMPT_NAME=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
    [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ] && break
    sleep 4
done
if [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ]; then
    log_pass "Prompt loaded: $PROMPT_NAME"
else
    log_fail "Could not load prompt (activePromptId: $PROMPT_NAME)"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

sleep 3

# ============================================================================
# TEST 1: Source suffix renders in content root block path (shows "content")
# ============================================================================
echo ""
log_test "OBJECTIVE: Source suffix in content root block path badge"

CONTENT_PATH=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    el ? el.textContent.trim() : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

if echo "$CONTENT_PATH" | grep -q "content"; then
    log_pass "Content root path badge contains source suffix: $CONTENT_PATH"
else
    log_fail "Expected path badge with 'content' source, got: $CONTENT_PATH"
fi

# ============================================================================
# TEST 2: Source suffix renders in ext_text root block path (shows theme name)
# ============================================================================
echo ""
log_test "OBJECTIVE: Source suffix in ext_text root block path badge"

THEME_PATH=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-1]");
    el ? el.textContent.trim() : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

if echo "$THEME_PATH" | grep -q "roles"; then
    log_pass "ext_text root path badge contains theme name: $THEME_PATH"
else
    log_fail "Expected path badge with theme name (roles), got: $THEME_PATH"
fi

# ============================================================================
# TEST 3: Path badge has data-has-source and data-source-type attributes
# ============================================================================
echo ""
log_test "OBJECTIVE: Path badges have source data attributes"

HAS_SOURCE=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    el ? el.hasAttribute("data-has-source") : false
' 2>/dev/null)

SOURCE_TYPE=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    el ? el.getAttribute("data-source-type") : "NONE"
' 2>/dev/null | tr -d '"')

[ "$HAS_SOURCE" = "true" ] \
    && log_pass "Path badge has data-has-source attribute" \
    || log_fail "Path badge missing data-has-source"

[ "$SOURCE_TYPE" = "content" ] \
    && log_pass "Content block has data-source-type=content" \
    || log_fail "Expected source-type=content, got: $SOURCE_TYPE"

THEME_SOURCE_TYPE=$(agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-1]");
    el ? el.getAttribute("data-source-type") : "NONE"
' 2>/dev/null | tr -d '"')

[ "$THEME_SOURCE_TYPE" = "theme" ] \
    && log_pass "ext_text block has data-source-type=theme" \
    || log_fail "Expected source-type=theme, got: $THEME_SOURCE_TYPE"

# ============================================================================
# TEST 4: Clicking path badge opens #pu-source-dropdown
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking path badge opens source dropdown"

agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    if (el) el.click();
' 2>/dev/null
sleep 1

DROPDOWN_EXISTS=$(agent-browser eval '!!document.querySelector("#pu-source-dropdown")' 2>/dev/null)
[ "$DROPDOWN_EXISTS" = "true" ] \
    && log_pass "Source dropdown opened" \
    || log_fail "Source dropdown did not open"

# ============================================================================
# TEST 5: Dropdown shows "content" option and theme options with badges
# ============================================================================
echo ""
log_test "OBJECTIVE: Dropdown shows content + theme options"

CONTENT_ITEM=$(agent-browser eval '
    var item = document.querySelector("[data-testid=pu-source-item-content]");
    item ? item.textContent.trim() : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

THEME_ITEMS=$(agent-browser eval '
    document.querySelectorAll("#pu-source-dropdown .pu-source-item").length
' 2>/dev/null | tr -d '"')

BADGE_COUNT=$(agent-browser eval '
    document.querySelectorAll("#pu-source-dropdown .pu-source-badge").length
' 2>/dev/null | tr -d '"')

if echo "$CONTENT_ITEM" | grep -q "content"; then
    log_pass "Dropdown has content option"
else
    log_fail "Expected content option, got: $CONTENT_ITEM"
fi

if [ "$THEME_ITEMS" -gt 1 ] 2>/dev/null; then
    log_pass "Dropdown has $THEME_ITEMS items (content + themes)"
else
    log_fail "Expected >1 dropdown items, got: $THEME_ITEMS"
fi

if [ "$BADGE_COUNT" -gt 0 ] 2>/dev/null; then
    log_pass "Dropdown has $BADGE_COUNT text count badges"
else
    log_fail "Expected text count badges, got: $BADGE_COUNT"
fi

# ============================================================================
# TEST 6: Active source has .active class
# ============================================================================
echo ""
log_test "OBJECTIVE: Active source has .active class"

ACTIVE_ITEM=$(agent-browser eval '
    var active = document.querySelector("#pu-source-dropdown .pu-source-item.active");
    active ? active.textContent.trim() : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

if echo "$ACTIVE_ITEM" | grep -q "content"; then
    log_pass "Content item marked as active: $ACTIVE_ITEM"
else
    log_fail "Expected content item to be active, got: $ACTIVE_ITEM"
fi

# Close dropdown before next test
agent-browser eval 'PU.overlay.dismissAll()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 7: Select theme on content block -> block switches to ext_text
# ============================================================================
echo ""
log_test "OBJECTIVE: Selecting theme on content block switches to ext_text"

# Open dropdown on content block (path 0)
agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    if (el) el.click();
' 2>/dev/null
sleep 1

# Select "roles" theme
agent-browser eval '
    var item = document.querySelector("[data-testid=pu-source-item-roles]");
    if (item) item.click();
' 2>/dev/null
sleep 2

# Check block type changed
BLOCK_TYPE=$(agent-browser eval '
    var prompt = PU.helpers.getActivePrompt();
    var block = prompt && prompt.text ? prompt.text[0] : null;
    block ? (("ext_text" in block) ? block.ext_text : "content") : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

if echo "$BLOCK_TYPE" | grep -q "roles"; then
    log_pass "Content block switched to ext_text: $BLOCK_TYPE"
else
    log_fail "Expected ext_text with roles, got: $BLOCK_TYPE"
fi

# ============================================================================
# TEST 8: Select "content" on ext_text block -> block switches to content
# ============================================================================
echo ""
log_test "OBJECTIVE: Selecting 'content' on ext_text block switches to content"

# Block 0 is now ext_text — open its dropdown via the path badge
agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    if (el) el.click();
' 2>/dev/null
sleep 1

# Select content
agent-browser eval '
    var item = document.querySelector("[data-testid=pu-source-item-content]");
    if (item) item.click();
' 2>/dev/null
sleep 2

BLOCK_TYPE2=$(agent-browser eval '
    var prompt = PU.helpers.getActivePrompt();
    var block = prompt && prompt.text ? prompt.text[0] : null;
    block ? (("content" in block) ? "content" : "ext_text") : "NOT_FOUND"
' 2>/dev/null | tr -d '"')

[ "$BLOCK_TYPE2" = "content" ] \
    && log_pass "ext_text block switched back to content" \
    || log_fail "Expected content, got: $BLOCK_TYPE2"

# ============================================================================
# TEST 9: Overlay backdrop visible when dropdown open
# ============================================================================
echo ""
log_test "OBJECTIVE: Overlay backdrop visible when dropdown open"

agent-browser eval '
    var el = document.querySelector("[data-testid=pu-block-path-0]");
    if (el) el.click();
' 2>/dev/null
sleep 1

OVERLAY_VISIBLE=$(agent-browser eval '
    var ov = document.querySelector("[data-testid=pu-popup-overlay]");
    ov ? ov.classList.contains("visible") : false
' 2>/dev/null)

[ "$OVERLAY_VISIBLE" = "true" ] \
    && log_pass "Overlay backdrop is visible" \
    || log_fail "Overlay backdrop not visible"

# ============================================================================
# TEST 10: Click outside closes dropdown
# ============================================================================
echo ""
log_test "OBJECTIVE: Click outside closes dropdown"

agent-browser eval 'PU.overlay.dismissAll()' 2>/dev/null
sleep 1

DROPDOWN_GONE=$(agent-browser eval '!document.querySelector("#pu-source-dropdown")' 2>/dev/null)
[ "$DROPDOWN_GONE" = "true" ] \
    && log_pass "Dropdown closed after dismissAll" \
    || log_fail "Dropdown still present after dismissAll"

# ============================================================================
# TEST 11: Source integrated in animated child path divider
# ============================================================================
echo ""
log_test "OBJECTIVE: Source suffix in animated child path divider"

# Switch to typewriter mode to get animated child dividers
agent-browser eval 'PU.state.previewMode.visualizer = "typewriter"; PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId)' 2>/dev/null
sleep 3

# Load stress-test-prompt which has nested children
agent-browser eval '
    PU.state.activePromptId = "stress-test-prompt";
    PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
' 2>/dev/null
sleep 4

# Check for source suffix inside a path-label in a path-divider
DIVIDER_SOURCE=$(agent-browser eval '
    var label = document.querySelector(".pu-path-divider .pu-path-label[data-has-source]");
    if (label) {
        var src = label.querySelector(".pu-path-source");
        src ? src.textContent.trim() : "NO_SOURCE_SPAN";
    } else {
        "NO_LABEL_WITH_SOURCE";
    }
' 2>/dev/null | tr -d '"')

if [ "$DIVIDER_SOURCE" != "NO_LABEL_WITH_SOURCE" ] && [ "$DIVIDER_SOURCE" != "NO_SOURCE_SPAN" ] && [ -n "$DIVIDER_SOURCE" ]; then
    log_pass "Source suffix in animated child divider label: $DIVIDER_SOURCE"
else
    log_fail "No source suffix found in animated child path divider: $DIVIDER_SOURCE"
fi

# ============================================================================
# TEST 12: Source integrated in compact child inline
# ============================================================================
echo ""
log_test "OBJECTIVE: Source suffix in compact child path hint"

# Switch to compact mode
agent-browser eval 'PU.state.previewMode.visualizer = "compact"; PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId)' 2>/dev/null
sleep 3

COMPACT_SOURCE=$(agent-browser eval '
    var hint = document.querySelector(".pu-child-path-hint[data-has-source]");
    if (hint) {
        var src = hint.querySelector(".pu-path-source");
        src ? src.textContent.trim() : "NO_SOURCE_SPAN";
    } else {
        "NO_HINT_WITH_SOURCE";
    }
' 2>/dev/null | tr -d '"')

if [ "$COMPACT_SOURCE" != "NO_HINT_WITH_SOURCE" ] && [ "$COMPACT_SOURCE" != "NO_SOURCE_SPAN" ] && [ -n "$COMPACT_SOURCE" ]; then
    log_pass "Source suffix in compact child path hint: $COMPACT_SOURCE"
else
    log_fail "No source suffix in compact child path hint: $COMPACT_SOURCE"
fi

# ============================================================================
# TEST 13: No .pu-source-pill or .pu-theme-badge elements (old patterns removed)
# ============================================================================
echo ""
log_test "OBJECTIVE: No old .pu-source-pill or .pu-theme-badge elements"

OLD_PILL_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-source-pill").length
' 2>/dev/null | tr -d '"')

OLD_BADGE_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-theme-badge").length
' 2>/dev/null | tr -d '"')

[ "$OLD_PILL_COUNT" = "0" ] \
    && log_pass "No .pu-source-pill elements found (integrated into path)" \
    || log_fail "Found $OLD_PILL_COUNT .pu-source-pill elements (should be 0)"

[ "$OLD_BADGE_COUNT" = "0" ] \
    && log_pass "No .pu-theme-badge elements found (cleaned up)" \
    || log_fail "Found $OLD_BADGE_COUNT .pu-theme-badge elements (should be 0)"

# ── Cleanup ────────────────────────────────────────────────────────────
agent-browser close 2>/dev/null || true

print_summary
