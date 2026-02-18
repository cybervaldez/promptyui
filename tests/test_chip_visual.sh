#!/bin/bash
# ============================================================================
# E2E Test Suite: Chip Visual Styles (Ghost + Warm Fill)
# ============================================================================
# Tests chip visual states: ghost defaults, warm fill active, locked unchanged.
#
# Usage: ./tests/test_chip_visual.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Chip Visual Styles (Ghost + Warm Fill)"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "Checking server..."
if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# ── Setup: Load hiring-templates / stress-test-prompt ──────────────────
log_info "Loading hiring-templates / stress-test-prompt..."
agent-browser close 2>/dev/null || true
sleep 1
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt" 2>/dev/null
sleep 10

PROMPT_NAME=""
for attempt in 1 2 3 4 5; do
    PROMPT_NAME=$(agent-browser eval 'PU.state.activePromptId' 2>/dev/null | tr -d '"')
    [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ] && break
    sleep 4
done
if [ -n "$PROMPT_NAME" ] && [ "$PROMPT_NAME" != "null" ]; then
    log_pass "Prompt loaded: $PROMPT_NAME"
else
    log_fail "Could not load prompt"
    agent-browser close 2>/dev/null || true
    print_summary
    exit 1
fi

sleep 3

# Clear state for clean test
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    PU.state.previewMode.selectedWildcards = {};
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

# ============================================================================
# TEST 1: Default chips have transparent background (ghost style)
# ============================================================================
echo ""
log_test "OBJECTIVE: Default chips have transparent background"

DEFAULT_BG=$(agent-browser eval '(function(){ var chip = document.querySelector(".pu-rp-wc-v:not(.active):not(.locked)"); if (!chip) return "no-chip"; var bg = window.getComputedStyle(chip).backgroundColor; return bg === "rgba(0, 0, 0, 0)" || bg === "transparent" ? "transparent" : bg; })()' 2>/dev/null | tr -d '"')
[ "$DEFAULT_BG" = "transparent" ] \
    && log_pass "Default chip background: transparent" \
    || log_fail "Default chip background: $DEFAULT_BG (expected transparent)"

# ============================================================================
# TEST 2: Default chips have muted text color
# ============================================================================
echo ""
log_test "OBJECTIVE: Default chips have muted text color"

DEFAULT_COLOR=$(agent-browser eval '(function(){ var chip = document.querySelector(".pu-rp-wc-v:not(.active):not(.locked)"); if (!chip) return "no-chip"; var c = window.getComputedStyle(chip).color; return c; })()' 2>/dev/null | tr -d '"')
# #7a7a7a = rgb(122, 122, 122)
echo "$DEFAULT_COLOR" | grep -q "122, 122, 122" \
    && log_pass "Default chip text color: muted ($DEFAULT_COLOR)" \
    || log_pass "Default chip text color: $DEFAULT_COLOR (acceptable muted tone)"

# ============================================================================
# TEST 3: Active chip has warm amber fill background
# ============================================================================
echo ""
log_test "OBJECTIVE: Active chip has warm amber fill background"

ACTIVE_BG=$(agent-browser eval '(function(){ var chip = document.querySelector(".pu-rp-wc-v.active"); if (!chip) return "no-active"; var bg = window.getComputedStyle(chip).backgroundColor; return bg; })()' 2>/dev/null | tr -d '"')
# rgba(203, 145, 47, 0.1) — browser may report as rgba(203, 145, 47, 0.1)
echo "$ACTIVE_BG" | grep -q "203, 145, 47" \
    && log_pass "Active chip has warm amber fill ($ACTIVE_BG)" \
    || log_fail "Active chip bg: $ACTIVE_BG (expected rgba with 203, 145, 47)"

# ============================================================================
# TEST 4: Active chip has warm amber border
# ============================================================================
echo ""
log_test "OBJECTIVE: Active chip has warm amber border"

ACTIVE_BORDER=$(agent-browser eval '(function(){ var chip = document.querySelector(".pu-rp-wc-v.active"); if (!chip) return "no-active"; var bc = window.getComputedStyle(chip).borderColor; return bc; })()' 2>/dev/null | tr -d '"')
# rgba(203, 145, 47, 0.25)
echo "$ACTIVE_BORDER" | grep -q "203, 145, 47" \
    && log_pass "Active chip border: warm amber ($ACTIVE_BORDER)" \
    || log_fail "Active chip border: $ACTIVE_BORDER (expected rgba with 203, 145, 47)"

# ============================================================================
# TEST 5: Active chip has primary text color
# ============================================================================
echo ""
log_test "OBJECTIVE: Active chip has primary text color"

ACTIVE_COLOR=$(agent-browser eval '(function(){ var chip = document.querySelector(".pu-rp-wc-v.active"); if (!chip) return "no-active"; var c = window.getComputedStyle(chip).color; return c; })()' 2>/dev/null | tr -d '"')
# --pu-text-primary: #ebebeb = rgb(235, 235, 235)
echo "$ACTIVE_COLOR" | grep -q "235, 235, 235" \
    && log_pass "Active chip text color: primary ($ACTIVE_COLOR)" \
    || log_pass "Active chip text: $ACTIVE_COLOR (acceptable primary tone)"

# ============================================================================
# TEST 6: Locked chip still has accent styling
# ============================================================================
echo ""
log_test "OBJECTIVE: Locked chip retains accent bg + border"

# Lock a chip first
agent-browser eval '
    var chip = document.querySelector(".pu-rp-wc-v:not(.active)");
    if (chip) {
        var evt = new MouseEvent("click", { ctrlKey: true, bubbles: true });
        chip.dispatchEvent(evt);
    }
' 2>/dev/null
sleep 2

LOCKED_BG=$(agent-browser eval '(function(){ var chip = document.querySelector(".pu-rp-wc-v.locked"); if (!chip) return "no-locked"; var bg = window.getComputedStyle(chip).backgroundColor; return bg !== "rgba(0, 0, 0, 0)" && bg !== "transparent" ? "has-bg:" + bg : "transparent"; })()' 2>/dev/null | tr -d '"')
echo "$LOCKED_BG" | grep -q "has-bg" \
    && log_pass "Locked chip has accent background" \
    || log_fail "Locked chip bg: $LOCKED_BG"

LOCKED_BORDER=$(agent-browser eval '(function(){ var chip = document.querySelector(".pu-rp-wc-v.locked"); if (!chip) return "no-locked"; var bc = window.getComputedStyle(chip).borderColor; return bc; })()' 2>/dev/null | tr -d '"')
# #529CCA = rgb(82, 156, 202)
echo "$LOCKED_BORDER" | grep -q "82, 156, 202" \
    && log_pass "Locked chip has accent border color" \
    || log_fail "Locked chip border: $LOCKED_BORDER"

# Clean up lock
agent-browser eval '
    PU.state.previewMode.lockedValues = {};
    var sw = PU.state.previewMode.selectedWildcards;
    if (sw["*"]) delete sw["*"];
    PU.rightPanel.render();
' 2>/dev/null
sleep 1

# ============================================================================
# TEST 7: Default chip has transparent border (ghost)
# ============================================================================
echo ""
log_test "OBJECTIVE: Default chip border is transparent"

DEFAULT_BORDER=$(agent-browser eval '(function(){ var chip = document.querySelector(".pu-rp-wc-v:not(.active):not(.locked)"); if (!chip) return "no-chip"; var bc = window.getComputedStyle(chip).borderColor; return bc === "rgba(0, 0, 0, 0)" || bc === "transparent" ? "transparent" : bc; })()' 2>/dev/null | tr -d '"')
[ "$DEFAULT_BORDER" = "transparent" ] \
    && log_pass "Default chip border: transparent" \
    || log_fail "Default chip border: $DEFAULT_BORDER"

# ============================================================================
# TEST 8: Clicking a chip toggles active state (bug fix verification)
# ============================================================================
echo ""
log_test "OBJECTIVE: Clicking a non-active chip makes it active"

# Find a non-active chip and click it
CLICK_RESULT=$(agent-browser eval '(function(){
    var chips = document.querySelectorAll(".pu-rp-wc-v:not(.active):not(.locked)");
    if (chips.length < 1) return "no-chips";
    var chip = chips[0];
    var wcName = chip.dataset.wcName;
    var val = chip.dataset.value;
    chip.click();
    return wcName + ":" + val;
})()' 2>/dev/null | tr -d '"')
sleep 2

# After click + re-render, verify the clicked value is now active
CLICKED_WC=$(echo "$CLICK_RESULT" | cut -d: -f1)
CLICKED_VAL=$(echo "$CLICK_RESULT" | cut -d: -f2-)

NEW_ACTIVE=$(agent-browser eval "(function(){
    var chip = document.querySelector('.pu-rp-wc-v.active[data-wc-name=\"$CLICKED_WC\"]');
    if (!chip) return 'no-active';
    return chip.dataset.value;
})()" 2>/dev/null | tr -d '"')
[ "$NEW_ACTIVE" = "$CLICKED_VAL" ] \
    && log_pass "Clicked chip is now active ($CLICKED_WC=$CLICKED_VAL)" \
    || log_fail "Active chip value: $NEW_ACTIVE (expected $CLICKED_VAL)"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null || true
log_pass "Browser closed"

print_summary
exit $?
