#!/bin/bash
# ============================================================================
# E2E Test Suite: Visualizer Modes
# ============================================================================
# Tests centered block visualizer for animated modes (typewriter, reel,
# stack, ticker), prototype-matching font sizes, dice/play buttons,
# and that text mode remains compact/left-aligned.
#
# Usage: ./tests/test_visualizer_modes.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

# Helper: eval JS and strip quotes
beval() {
    agent-browser eval "$1" 2>/dev/null | tr -d '"'
}

setup_cleanup
print_header "Visualizer Modes"

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
# TEST 1: Text mode stays compact (no visualizer class)
# ============================================================================
echo ""
log_info "TEST 1: Text mode stays compact"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=outreach-email&composition=3395&viz=text" 2>/dev/null
sleep 4

HAS_PRES=$(beval "document.querySelector('.pu-resolved-text')?.classList.contains('pu-block-visualizer') ? 'true' : 'false'")
FONT_SIZE=$(beval "getComputedStyle(document.querySelector('.pu-resolved-text')).fontSize")

[ "$HAS_PRES" = "false" ] && log_pass "Text mode: no visualizer class" || log_fail "Text mode has visualizer class: $HAS_PRES"
[ "$FONT_SIZE" = "13px" ] && log_pass "Text mode: 13px font" || log_fail "Text mode font: $FONT_SIZE"

# ============================================================================
# TEST 2: Typewriter mode - centered, 19px, placeholders, dice button
# ============================================================================
echo ""
log_info "TEST 2: Typewriter mode"

beval "PU.editor.handleVisualizerChange('typewriter')" > /dev/null
sleep 2

# Check visualizer class applied
PRES_CLASS=$(beval "document.querySelector('.pu-resolved-text')?.classList.contains('pu-block-visualizer') ? 'true' : 'false'")
[ "$PRES_CLASS" = "true" ] && log_pass "Typewriter: visualizer class applied" || log_fail "Typewriter: no visualizer class ($PRES_CLASS)"

# Check centered 19px
FONT=$(beval "getComputedStyle(document.querySelector('.pu-resolved-text')).fontSize")
[ "$FONT" = "19px" ] && log_pass "Typewriter: 19px font" || log_fail "Typewriter: font is $FONT"

ALIGN=$(beval "getComputedStyle(document.querySelector('.pu-resolved-text')).textAlign")
[ "$ALIGN" = "center" ] && log_pass "Typewriter: centered text" || log_fail "Typewriter: text-align is $ALIGN"

# Check typewriter widget font-size (17px)
TW_FONT=$(beval "var tw = document.querySelector('.pu-wc-typewriter'); tw ? getComputedStyle(tw).fontSize : 'none'")
[ "$TW_FONT" = "17px" ] && log_pass "Typewriter: widget 17px" || log_fail "Typewriter: widget font is $TW_FONT"

# Check last placeholder visible during intro delay (1400ms before typing starts)
LAST_PH=$(beval "var phs = document.querySelectorAll('.pu-wc-tw-placeholder'); phs.length > 1 ? (phs[phs.length-1].classList.contains('hidden') ? 'hidden' : 'visible') : 'only-one'")
[ "$LAST_PH" = "visible" ] && log_pass "Typewriter: last placeholder visible during intro" || log_fail "Typewriter: last placeholder state is $LAST_PH"

# Check dice button exists but disabled during intro
DICE=$(beval "document.querySelector('[data-testid=\"pu-viz-dice-btn\"]') ? 'found' : 'missing'")
[ "$DICE" = "found" ] && log_pass "Typewriter: dice button present" || log_fail "Typewriter: dice button $DICE"

DICE_DIS=$(beval "document.querySelector('[data-testid=\"pu-viz-dice-btn\"]').disabled ? 'true' : 'false'")
[ "$DICE_DIS" = "true" ] && log_pass "Typewriter: dice disabled during animation" || log_fail "Typewriter: dice not disabled during animation ($DICE_DIS)"

# Wait for fill to complete (1400ms intro + ~70ms/char * ~30 chars + pauses)
sleep 10

# After fill: all settled, clickable, cursor on last
SETTLED=$(beval "var r=true; document.querySelectorAll('.pu-wc-typewriter').forEach(function(tw){if(!tw.classList.contains('settled'))r=false}); r ? 'true' : 'false'")
[ "$SETTLED" = "true" ] && log_pass "Typewriter: all wildcards settled after fill" || log_fail "Typewriter: not all settled ($SETTLED)"

CLICKABLE=$(beval "var r=true; document.querySelectorAll('.pu-wc-typewriter').forEach(function(tw){if(!tw.classList.contains('clickable'))r=false}); r ? 'true' : 'false'")
[ "$CLICKABLE" = "true" ] && log_pass "Typewriter: all wildcards clickable after fill" || log_fail "Typewriter: not all clickable ($CLICKABLE)"

ACTIVE_LAST=$(beval "var tws = document.querySelectorAll('.pu-wc-typewriter'); tws[tws.length-1].classList.contains('active') ? 'true' : 'false'")
[ "$ACTIVE_LAST" = "true" ] && log_pass "Typewriter: cursor on last wildcard" || log_fail "Typewriter: cursor not on last ($ACTIVE_LAST)"

DICE_ENABLED=$(beval "document.querySelector('[data-testid=\"pu-viz-dice-btn\"]').disabled ? 'true' : 'false'")
[ "$DICE_ENABLED" = "false" ] && log_pass "Typewriter: dice enabled after fill" || log_fail "Typewriter: dice still disabled ($DICE_ENABLED)"

# Test dice re-roll (animated erase + retype)
BEFORE=$(beval "var tws = document.querySelectorAll('.pu-wc-typewriter'); var r=[]; tws.forEach(function(tw){r.push(tw.querySelector('.pu-wc-tw-text').textContent)}); r.join('|')")

beval "document.querySelector('[data-testid=\"pu-viz-dice-btn\"]').click()" > /dev/null
sleep 15

AFTER=$(beval "var tws = document.querySelectorAll('.pu-wc-typewriter'); var r=[]; tws.forEach(function(tw){r.push(tw.querySelector('.pu-wc-tw-text').textContent)}); r.join('|')")

[ "$BEFORE" != "$AFTER" ] && log_pass "Typewriter: dice re-roll changed values" || log_fail "Typewriter: dice did not change values (before=$BEFORE after=$AFTER)"

# Verify settled after re-roll
SETTLED2=$(beval "var r=true; document.querySelectorAll('.pu-wc-typewriter').forEach(function(tw){if(!tw.classList.contains('settled'))r=false}); r ? 'true' : 'false'")
[ "$SETTLED2" = "true" ] && log_pass "Typewriter: all settled after re-roll" || log_fail "Typewriter: not settled after re-roll ($SETTLED2)"

# ============================================================================
# TEST 3: Stack mode - centered, 14px/16px font
# ============================================================================
echo ""
log_info "TEST 3: Stack mode"

beval "PU.editor.handleVisualizerChange('stack')" > /dev/null
sleep 2

PRES_CLASS=$(beval "document.querySelector('.pu-resolved-text')?.classList.contains('pu-block-visualizer') ? 'true' : 'false'")
[ "$PRES_CLASS" = "true" ] && log_pass "Stack: visualizer class applied" || log_fail "Stack: no visualizer class ($PRES_CLASS)"

# Check center item font-size (16px)
CENTER_FONT=$(beval "var c = document.querySelector('.pu-wc-stack-item.center'); c ? getComputedStyle(c).fontSize : 'none'")
[ "$CENTER_FONT" = "16px" ] && log_pass "Stack: center item 16px" || log_fail "Stack: center font is $CENTER_FONT"

# Check far item font-size (14px)
FAR_FONT=$(beval "var f = document.querySelector('.pu-wc-stack-item.far'); f ? getComputedStyle(f).fontSize : 'none'")
[ "$FAR_FONT" = "14px" ] && log_pass "Stack: far item 14px" || log_fail "Stack: far font is $FAR_FONT"

# ============================================================================
# TEST 4: Ticker mode - centered, 16px font
# ============================================================================
echo ""
log_info "TEST 4: Ticker mode"

beval "PU.editor.handleVisualizerChange('ticker')" > /dev/null
sleep 2

PRES_CLASS=$(beval "document.querySelector('.pu-resolved-text')?.classList.contains('pu-block-visualizer') ? 'true' : 'false'")
[ "$PRES_CLASS" = "true" ] && log_pass "Ticker: visualizer class applied" || log_fail "Ticker: no visualizer class ($PRES_CLASS)"

TK_FONT=$(beval "var t = document.querySelector('.pu-wc-ticker-item'); t ? getComputedStyle(t).fontSize : 'none'")
[ "$TK_FONT" = "16px" ] && log_pass "Ticker: 16px items" || log_fail "Ticker: item font is $TK_FONT"

# ============================================================================
# TEST 5: Reel mode - centered, 16px font, play/stop button
# ============================================================================
echo ""
log_info "TEST 5: Reel mode"

beval "PU.editor.handleVisualizerChange('reel')" > /dev/null
sleep 4

PRES_CLASS=$(beval "document.querySelector('.pu-resolved-text')?.classList.contains('pu-block-visualizer') ? 'true' : 'false'")
[ "$PRES_CLASS" = "true" ] && log_pass "Reel: visualizer class applied" || log_fail "Reel: no visualizer class ($PRES_CLASS)"

RL_FONT=$(beval "var r = document.querySelector('.pu-wc-reel-item'); r ? getComputedStyle(r).fontSize : 'none'")
[ "$RL_FONT" = "16px" ] && log_pass "Reel: 16px items" || log_fail "Reel: item font is $RL_FONT"

# Check play/stop button
PLAY_BTN=$(beval "document.querySelector('[data-testid=\"pu-viz-play-btn\"]') ? 'found' : 'missing'")
[ "$PLAY_BTN" = "found" ] && log_pass "Reel: play/stop button present" || log_fail "Reel: play/stop button $PLAY_BTN"

# Check initial state is playing (stop icon visible means display is empty string, not 'none')
STOP_DISPLAY=$(beval "var btn = document.querySelector('[data-testid=\"pu-viz-play-btn\"]'); var icon = btn && btn.querySelector('.pu-viz-stop-icon'); icon ? (icon.style.display === 'none' ? 'hidden' : 'visible') : 'missing'")
[ "$STOP_DISPLAY" = "visible" ] && log_pass "Reel: initially playing (stop icon shown)" || log_fail "Reel: stop icon state=$STOP_DISPLAY"

# Click to pause
beval "document.querySelector('[data-testid=\"pu-viz-play-btn\"]').click()" > /dev/null
sleep 0.5

PLAY_DISPLAY=$(beval "var btn = document.querySelector('[data-testid=\"pu-viz-play-btn\"]'); var icon = btn && btn.querySelector('.pu-viz-play-icon'); icon ? (icon.style.display === 'none' ? 'hidden' : 'visible') : 'missing'")
[ "$PLAY_DISPLAY" = "visible" ] && log_pass "Reel: paused (play icon shown)" || log_fail "Reel: play icon state=$PLAY_DISPLAY"

# Click to resume
beval "document.querySelector('[data-testid=\"pu-viz-play-btn\"]').click()" > /dev/null
sleep 0.5

STOP_DISPLAY2=$(beval "var btn = document.querySelector('[data-testid=\"pu-viz-play-btn\"]'); var icon = btn && btn.querySelector('.pu-viz-stop-icon'); icon ? (icon.style.display === 'none' ? 'hidden' : 'visible') : 'missing'")
[ "$STOP_DISPLAY2" = "visible" ] && log_pass "Reel: resumed (stop icon shown)" || log_fail "Reel: stop icon state=$STOP_DISPLAY2"

# ============================================================================
# TEST 6: URL persistence
# ============================================================================
echo ""
log_info "TEST 6: URL persistence"

CURRENT_URL=$(agent-browser get url 2>/dev/null)
echo "$CURRENT_URL" | grep -q "viz=reel" && log_pass "URL has viz=reel" || log_fail "URL missing viz param: $CURRENT_URL"

beval "PU.editor.handleVisualizerChange('text')" > /dev/null
sleep 1
TEXT_URL=$(agent-browser get url 2>/dev/null)
echo "$TEXT_URL" | grep -q "viz=" && log_fail "Text mode URL has viz param: $TEXT_URL" || log_pass "Text mode URL omits viz param"

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
