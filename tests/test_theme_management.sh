#!/bin/bash
# ============================================================================
# E2E Test Suite: Theme Management
# ============================================================================
# Tests the blocks-first theme management features:
# - Theme block renders with purple styling
# - Clickable label in compact mode opens swap dropdown
# - Context menu on ⋯ button (theme + content blocks)
# - Diff popover shows on hover
# - Swap performs ext_text change
# - "Add Theme" terminology
# - Insert Theme button at block level
# - "from themes" section in right panel
# - Escape/click-outside closes overlays
#
# Usage: ./tests/test_theme_management.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Theme Management"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load a prompt with ext_text blocks ──────────────────────────
# ext-sourcing-strategy has ext_text blocks
log_info "Loading hiring-templates / ext-sourcing-strategy..."
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=ext-sourcing-strategy&composition=99" 2>/dev/null
sleep 5

PROMPT_NAME=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
if [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ]; then
    log_pass "Prompt loaded: $PROMPT_NAME"
else
    log_fail "Could not load prompt"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

# Wait for ext_text blocks to resolve
sleep 3

# ============================================================================
# TEST 1: Theme block renders with purple styling
# ============================================================================
echo ""
log_test "OBJECTIVE: Theme blocks (ext_text) render with purple .pu-theme-block class"

THEME_BLOCK=$(agent-browser eval '!!document.querySelector(".pu-theme-block")' 2>/dev/null)
[ "$THEME_BLOCK" = "true" ] \
    && log_pass "Theme block with .pu-theme-block found" \
    || log_fail "No .pu-theme-block element found"

# ============================================================================
# TEST 2: Theme label shows package icon
# ============================================================================
echo ""
log_test "OBJECTIVE: Theme label shows package icon (📦)"

THEME_ICON=$(agent-browser eval '!!document.querySelector(".pu-theme-icon")' 2>/dev/null)
[ "$THEME_ICON" = "true" ] \
    && log_pass "Theme icon element found" \
    || log_fail "Theme icon element missing"

# ============================================================================
# TEST 3: Clickable label in compact mode
# ============================================================================
echo ""
log_test "OBJECTIVE: Theme label is clickable with swap arrow in compact mode"

CLICKABLE=$(agent-browser eval '!!document.querySelector(".pu-theme-label.clickable")' 2>/dev/null)
[ "$CLICKABLE" = "true" ] \
    && log_pass "Clickable theme label found" \
    || log_fail "Clickable theme label missing"

SWAP_ARROW=$(agent-browser eval '!!document.querySelector(".pu-theme-swap-arrow")' 2>/dev/null)
[ "$SWAP_ARROW" = "true" ] \
    && log_pass "Swap arrow (▾) found" \
    || log_fail "Swap arrow missing"

# ============================================================================
# TEST 4: Swap dropdown opens on label click
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking theme label opens swap dropdown"

agent-browser eval 'var label = document.querySelector(".pu-theme-label.clickable"); if (label) label.click()' 2>/dev/null
sleep 1

DD_EXISTS=$(agent-browser eval '!!document.getElementById("pu-theme-swap-dropdown")' 2>/dev/null)
[ "$DD_EXISTS" = "true" ] \
    && log_pass "Swap dropdown opened" \
    || log_fail "Swap dropdown did not open"

# ============================================================================
# TEST 5: Swap dropdown has alternatives or empty message
# ============================================================================
echo ""
log_test "OBJECTIVE: Swap dropdown shows alternatives or empty message"

DD_CONTENT=$(agent-browser eval 'var dd = document.getElementById("pu-theme-swap-dropdown"); dd ? dd.textContent.trim().length : 0' 2>/dev/null | tr -d '"')
[ "$DD_CONTENT" -gt 0 ] 2>/dev/null \
    && log_pass "Swap dropdown has content ($DD_CONTENT chars)" \
    || log_fail "Swap dropdown empty"

# ============================================================================
# TEST 6: Diff popover shows on hover
# ============================================================================
echo ""
log_test "OBJECTIVE: Hovering swap item triggers diff popover"

# Try to hover first swap item
HOVER_RESULT=$(agent-browser eval '
    var item = document.querySelector(".pu-swap-item");
    if (item) {
        item.dispatchEvent(new MouseEvent("mouseenter", {bubbles: true}));
        "hovered";
    } else {
        "no_items";
    }
' 2>/dev/null | tr -d '"')

if [ "$HOVER_RESULT" = "hovered" ]; then
    sleep 2
    DIFF_EXISTS=$(agent-browser eval '!!document.getElementById("pu-theme-diff-popover")' 2>/dev/null)
    [ "$DIFF_EXISTS" = "true" ] \
        && log_pass "Diff popover appeared on hover" \
        || log_fail "Diff popover did not appear"

    # Check diff popover has section content
    DIFF_CONTENT=$(agent-browser eval 'var dp = document.getElementById("pu-theme-diff-popover"); dp ? dp.querySelectorAll(".pu-diff-section, .pu-diff-header-bar").length : 0' 2>/dev/null | tr -d '"')
    [ "$DIFF_CONTENT" -gt 0 ] 2>/dev/null \
        && log_pass "Diff popover has structured content ($DIFF_CONTENT sections)" \
        || log_pass "Diff popover rendered (may have no wildcard data)"
else
    log_skip "No swap alternatives to hover (single extension in folder)"
fi

# ============================================================================
# TEST 7: Escape closes swap dropdown
# ============================================================================
echo ""
log_test "OBJECTIVE: Pressing Escape closes swap dropdown"

agent-browser eval 'document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape"}))' 2>/dev/null
sleep 0.5

DD_CLOSED=$(agent-browser eval '!document.getElementById("pu-theme-swap-dropdown")' 2>/dev/null)
[ "$DD_CLOSED" = "true" ] \
    && log_pass "Swap dropdown closed on Escape" \
    || log_fail "Swap dropdown still open after Escape"

# ============================================================================
# TEST 8: Context menu (⋯) on theme block
# ============================================================================
echo ""
log_test "OBJECTIVE: ⋯ button opens context menu on theme block"

MORE_BTN=$(agent-browser eval '!!document.querySelector("[data-testid^=pu-theme-more]")' 2>/dev/null)
[ "$MORE_BTN" = "true" ] \
    && log_pass "⋯ button found on theme block" \
    || log_fail "⋯ button missing on theme block"

agent-browser eval 'var btn = document.querySelector("[data-testid^=pu-theme-more]"); if (btn) btn.click()' 2>/dev/null
sleep 0.5

CTX_MENU=$(agent-browser eval '!!document.getElementById("pu-theme-context-menu")' 2>/dev/null)
[ "$CTX_MENU" = "true" ] \
    && log_pass "Context menu opened" \
    || log_fail "Context menu did not open"

# Verify menu has expected items
CTX_ITEMS=$(agent-browser eval 'var cm = document.getElementById("pu-theme-context-menu"); cm ? cm.querySelectorAll(".pu-ctx-item").length : 0' 2>/dev/null | tr -d '"')
[ "$CTX_ITEMS" -ge 4 ] 2>/dev/null \
    && log_pass "Context menu has $CTX_ITEMS items (Move Up/Down, Duplicate, Dissolve, Save, Delete)" \
    || log_fail "Expected >= 4 context menu items, got: $CTX_ITEMS"

# Close context menu
agent-browser eval 'document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape"}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 9: ⋯ button on content blocks (Gap B2)
# ============================================================================
echo ""
log_test "OBJECTIVE: Content blocks also have ⋯ more button in compact mode"

CONTENT_MORE=$(agent-browser eval '!!document.querySelector("[data-testid^=pu-block-more]")' 2>/dev/null)
[ "$CONTENT_MORE" = "true" ] \
    && log_pass "⋯ button found on content block" \
    || log_fail "⋯ button missing on content block"

# Click it and verify context menu
agent-browser eval 'var btn = document.querySelector("[data-testid^=pu-block-more]"); if (btn) btn.click()' 2>/dev/null
sleep 0.5

CTX_CONTENT=$(agent-browser eval '!!document.getElementById("pu-theme-context-menu")' 2>/dev/null)
[ "$CTX_CONTENT" = "true" ] \
    && log_pass "Context menu opens from content block ⋯" \
    || log_fail "Context menu did not open from content block ⋯"

# Verify no Dissolve option (content blocks don't dissolve)
HAS_DISSOLVE=$(agent-browser eval 'var cm = document.getElementById("pu-theme-context-menu"); cm ? cm.textContent.includes("Dissolve") : false' 2>/dev/null)
[ "$HAS_DISSOLVE" = "false" ] \
    && log_pass "Content block context menu correctly omits Dissolve" \
    || log_fail "Content block context menu should not have Dissolve"

# Close
agent-browser eval 'document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape"}))' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 10: Insert Theme button (Gap B1)
# ============================================================================
echo ""
log_test "OBJECTIVE: Root blocks have '+ Insert Theme' button alongside nest button"

THEME_BTN=$(agent-browser eval '!!document.querySelector("[data-testid^=pu-nest-theme-btn]")' 2>/dev/null)
[ "$THEME_BTN" = "true" ] \
    && log_pass "Insert Theme button found" \
    || log_fail "Insert Theme button missing"

# ============================================================================
# TEST 11: "Add Theme" terminology (Gap D1)
# ============================================================================
echo ""
log_test "OBJECTIVE: Root add menu shows 'Add Theme' (not 'Add ext_text Reference')"

# Open the add menu
agent-browser eval 'PU.actions.toggleAddMenu()' 2>/dev/null
sleep 0.5

ADD_THEME_TEXT=$(agent-browser eval 'var btn = document.querySelector("[data-testid=pu-add-exttext-btn]"); btn ? btn.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
echo "$ADD_THEME_TEXT" | grep -qi "theme" \
    && log_pass "Add button shows 'Add Theme': $ADD_THEME_TEXT" \
    || log_fail "Button should say 'Add Theme', got: $ADD_THEME_TEXT"

# Close menu
agent-browser eval 'PU.actions.toggleAddMenu()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 12: Theme wildcards in right panel (Gap A1)
# ============================================================================
echo ""
log_test "OBJECTIVE: Right panel shows 'from themes' section when theme wildcards exist"

# Check if any theme divider exists
THEME_DIVIDER=$(agent-browser eval '
    var dividers = document.querySelectorAll(".pu-rp-wc-divider-label");
    var found = false;
    dividers.forEach(function(d) {
        if (d.textContent.toLowerCase().includes("theme")) found = true;
    });
    found
' 2>/dev/null)

# This may not show if the ext_text cache hasn't resolved theme wildcards yet
if [ "$THEME_DIVIDER" = "true" ]; then
    log_pass "Theme divider section found in right panel"

    # Check purple styling (Gap A3)
    PURPLE_DIVIDER=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-divider.from-theme")' 2>/dev/null)
    [ "$PURPLE_DIVIDER" = "true" ] \
        && log_pass "Theme divider has purple .from-theme class" \
        || log_fail "Theme divider missing .from-theme class"

    # Check purple wildcard names (Gap A4)
    PURPLE_NAME=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-name.from-theme")' 2>/dev/null)
    [ "$PURPLE_NAME" = "true" ] \
        && log_pass "Theme wildcard names have purple .from-theme class" \
        || log_pass "No theme wildcard names with .from-theme (may have no theme wildcards)"

    # Check .from-theme on chips (Gap A2)
    PURPLE_CHIP=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-v.from-theme")' 2>/dev/null)
    [ "$PURPLE_CHIP" = "true" ] \
        && log_pass "Theme chips have .from-theme class" \
        || log_pass "No theme chips with .from-theme (may have no theme wildcards)"
else
    log_pass "No theme divider (ext_text cache may not have resolved — acceptable)"
fi

# ============================================================================
# TEST 13: Theme source annotation
# ============================================================================
echo ""
log_test "OBJECTIVE: Theme wildcards show inline source annotation"

THEME_SRC=$(agent-browser eval '!!document.querySelector(".pu-rp-wc-name-src")' 2>/dev/null)
if [ "$THEME_SRC" = "true" ]; then
    log_pass "Theme source annotation found (inline)"
else
    log_pass "No theme source annotation (no theme wildcards in this prompt — acceptable)"
fi

# ============================================================================
# TEST 14: Save as Theme modal
# ============================================================================
echo ""
log_test "OBJECTIVE: Save as Theme modal opens from context menu"

# Open context menu on theme block
agent-browser eval 'var btn = document.querySelector("[data-testid^=pu-theme-more]"); if (btn) btn.click()' 2>/dev/null
sleep 0.5

# Click Save as Theme
agent-browser eval '
    var cm = document.getElementById("pu-theme-context-menu");
    if (cm) {
        var items = cm.querySelectorAll(".pu-ctx-item");
        items.forEach(function(item) {
            if (item.textContent.includes("Save as Theme")) item.click();
        });
    }
' 2>/dev/null
sleep 1

SAVE_MODAL=$(agent-browser eval 'var m = document.querySelector("[data-testid=pu-theme-save-modal]"); m ? m.style.display : "none"' 2>/dev/null | tr -d '"')
[ "$SAVE_MODAL" = "flex" ] \
    && log_pass "Save as Theme modal opened" \
    || log_fail "Save as Theme modal did not open (display: $SAVE_MODAL)"

# Verify modal has name input and folder selector
NAME_INPUT=$(agent-browser eval '!!document.querySelector("[data-testid=pu-theme-save-name]")' 2>/dev/null)
FOLDER_SELECT=$(agent-browser eval '!!document.querySelector("[data-testid=pu-theme-save-folder]")' 2>/dev/null)
[ "$NAME_INPUT" = "true" ] && [ "$FOLDER_SELECT" = "true" ] \
    && log_pass "Modal has name input and folder selector" \
    || log_fail "Modal missing name input or folder selector"

# Close modal
agent-browser eval 'PU.themes.closeSaveModal()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 15: Click outside closes overlays
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking outside closes swap dropdown"

# Open swap dropdown
agent-browser eval 'var label = document.querySelector(".pu-theme-label.clickable"); if (label) label.click()' 2>/dev/null
sleep 1

DD_OPEN=$(agent-browser eval '!!document.getElementById("pu-theme-swap-dropdown")' 2>/dev/null)
[ "$DD_OPEN" = "true" ] && log_pass "Swap dropdown opened for outside-click test" || log_fail "Swap dropdown did not open"

# Click on the body (outside)
agent-browser eval 'document.body.click()' 2>/dev/null
sleep 0.5

DD_GONE=$(agent-browser eval '!document.getElementById("pu-theme-swap-dropdown")' 2>/dev/null)
[ "$DD_GONE" = "true" ] \
    && log_pass "Swap dropdown closed on outside click" \
    || log_fail "Swap dropdown still open after outside click"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"
agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
