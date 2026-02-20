#!/bin/bash
# ============================================================================
# E2E Test Suite: Landing Page Interactive Demo
# ============================================================================
# Tests the scrollable landing page with hero animation and interactive demo
# section. Verifies wildcard editing, add child, and live formula updates.
#
# Usage: ./tests/test_landing_demo.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"
LANDING_URL="$BASE_URL/previews/preview-landing-single-viewport.html"

setup_cleanup

print_header "Landing Page Interactive Demo"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server "$BASE_URL/"; then
    log_pass "Server is running"
else
    log_fail "Server not running"
    exit 1
fi

# ============================================================================
# TEST 1: Page loads with both sections
# ============================================================================
echo ""
log_info "TEST 1: Page loads with both sections"

agent-browser open "$LANDING_URL" 2>/dev/null
sleep 2

SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)

echo "$SNAPSHOT" | grep -qi "cabin in the forest" && log_pass "Hero prompt text visible" || log_fail "Hero prompt text missing"
echo "$SNAPSHOT" | grep -qi "try it yourself" && log_pass "Demo section title visible" || log_fail "Demo section title missing"
echo "$SNAPSHOT" | grep -qi "Add Child" && log_pass "Add Child button visible" || log_fail "Add Child button missing"
echo "$SNAPSHOT" | grep -qi "Add Wildcard" && log_pass "Add Wildcard button visible" || log_fail "Add Wildcard button missing"
echo "$SNAPSHOT" | grep -qi "Start Building" && log_pass "CTA button visible" || log_fail "CTA button missing"

# ============================================================================
# TEST 2: Demo section has pre-filled wildcards
# ============================================================================
echo ""
log_info "TEST 2: Demo has pre-filled wildcards"

HAS_SEASON=$(agent-browser eval '!!document.querySelector("#demo-lines [data-testid=\"demo-reel-season\"]")' 2>/dev/null)
[ "$HAS_SEASON" = "true" ] && log_pass "Season reel exists in demo" || log_fail "Season reel missing"

HAS_STYLE=$(agent-browser eval '!!document.querySelector("#demo-lines [data-testid=\"demo-reel-style\"]")' 2>/dev/null)
[ "$HAS_STYLE" = "true" ] && log_pass "Style reel exists in demo" || log_fail "Style reel missing"

HAS_DETAIL=$(agent-browser eval '!!document.querySelector("#demo-lines [data-testid=\"demo-reel-detail\"]")' 2>/dev/null)
[ "$HAS_DETAIL" = "true" ] && log_pass "Detail reel exists in demo" || log_fail "Detail reel missing"

# ============================================================================
# TEST 3: Initial formula is correct (4 x 4 x 3 = 48)
# ============================================================================
echo ""
log_info "TEST 3: Initial formula is correct"

DEMO_FORMULA=$(agent-browser eval 'document.getElementById("demo-formula").textContent.replace(/\s+/g, " ").trim()' 2>/dev/null | tr -d '"')
echo "$DEMO_FORMULA" | grep -q "season" && log_pass "Formula has season term" || log_fail "Formula missing season: $DEMO_FORMULA"
echo "$DEMO_FORMULA" | grep -q "style" && log_pass "Formula has style term" || log_fail "Formula missing style: $DEMO_FORMULA"
echo "$DEMO_FORMULA" | grep -q "detail" && log_pass "Formula has detail term" || log_fail "Formula missing detail: $DEMO_FORMULA"

# Check odometer shows 48
DEMO_COUNT=$(agent-browser eval 'demoState.prevOdo' 2>/dev/null | tr -d '"')
[ "$DEMO_COUNT" = "48" ] && log_pass "Demo count is 48" || log_fail "Demo count expected 48, got: $DEMO_COUNT"

# ============================================================================
# TEST 4: Click wildcard opens popover
# ============================================================================
echo ""
log_info "TEST 4: Click wildcard opens popover"

agent-browser eval 'document.querySelector("#demo-lines [data-testid=\"demo-reel-season\"]").click()' 2>/dev/null
sleep 0.5

POPOVER_VISIBLE=$(agent-browser eval 'document.getElementById("wc-popover").style.display !== "none"' 2>/dev/null)
[ "$POPOVER_VISIBLE" = "true" ] && log_pass "Popover opens on reel click" || log_fail "Popover did not open"

POPOVER_NAME=$(agent-browser eval 'document.querySelector(".wc-popover-name").textContent' 2>/dev/null | tr -d '"')
[ "$POPOVER_NAME" = "season" ] && log_pass "Popover shows 'season' name" || log_fail "Popover name: $POPOVER_NAME"

PILL_COUNT=$(agent-browser eval 'document.querySelectorAll(".wc-popover-pills .wc-pill").length' 2>/dev/null)
[ "$PILL_COUNT" = "4" ] && log_pass "Season has 4 value pills" || log_fail "Season pill count: $PILL_COUNT"

# ============================================================================
# TEST 5: Add values via popover input
# ============================================================================
echo ""
log_info "TEST 5: Add values via popover"

# Type new values and press Enter
agent-browser eval 'var inp = document.querySelector("[data-testid=\"wc-popover-input\"]"); inp.value = "rainy, foggy"; inp.dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

NEW_PILL_COUNT=$(agent-browser eval 'document.querySelectorAll(".wc-popover-pills .wc-pill").length' 2>/dev/null)
[ "$NEW_PILL_COUNT" = "6" ] && log_pass "Added 2 values (now 6 pills)" || log_fail "Expected 6 pills, got: $NEW_PILL_COUNT"

# Check count updated: 6 x 4 x 3 = 72
NEW_COUNT=$(agent-browser eval 'demoState.prevOdo' 2>/dev/null | tr -d '"')
[ "$NEW_COUNT" = "72" ] && log_pass "Count updated to 72" || log_fail "Count expected 72, got: $NEW_COUNT"

# ============================================================================
# TEST 6: Remove value via pill × button
# ============================================================================
echo ""
log_info "TEST 6: Remove value via pill"

agent-browser eval 'document.querySelector(".wc-pill-remove[data-idx=\"0\"]").click()' 2>/dev/null
sleep 0.5

AFTER_REMOVE=$(agent-browser eval 'document.querySelectorAll(".wc-popover-pills .wc-pill").length' 2>/dev/null)
[ "$AFTER_REMOVE" = "5" ] && log_pass "Removed 1 value (now 5 pills)" || log_fail "Expected 5 pills, got: $AFTER_REMOVE"

REMOVE_COUNT=$(agent-browser eval 'demoState.prevOdo' 2>/dev/null | tr -d '"')
[ "$REMOVE_COUNT" = "60" ] && log_pass "Count updated to 60" || log_fail "Count expected 60, got: $REMOVE_COUNT"

# Close popover
agent-browser eval 'document.body.click()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 7: Add Child creates new line
# ============================================================================
echo ""
log_info "TEST 7: Add Child button"

LINES_BEFORE=$(agent-browser eval 'document.querySelectorAll("#demo-lines .editor-line").length' 2>/dev/null)

agent-browser eval 'document.querySelector("[data-testid=\"btn-add-child\"]").click()' 2>/dev/null
sleep 0.5

HAS_INPUT=$(agent-browser eval '!!document.querySelector("[data-testid=\"demo-child-input\"]")' 2>/dev/null)
[ "$HAS_INPUT" = "true" ] && log_pass "Child input appeared" || log_fail "Child input missing"

LINES_AFTER=$(agent-browser eval 'document.querySelectorAll("#demo-lines .editor-line").length' 2>/dev/null)
[ "$LINES_AFTER" -gt "$LINES_BEFORE" ] && log_pass "New line added ($LINES_BEFORE -> $LINES_AFTER)" || log_fail "No new line"

# ============================================================================
# TEST 8: Type text with [bracket] wildcard in child
# ============================================================================
echo ""
log_info "TEST 8: Bracket wildcard detection"

# Type text with a bracket wildcard
agent-browser eval 'var inp = document.querySelector("[data-testid=\"demo-child-input\"]"); inp.textContent = "at [time] of day"; inp.dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}))' 2>/dev/null
sleep 0.5

HAS_TIME_REEL=$(agent-browser eval '!!document.querySelector("#demo-lines [data-testid=\"demo-reel-time\"]")' 2>/dev/null)
[ "$HAS_TIME_REEL" = "true" ] && log_pass "Bracket [time] created reel" || log_fail "Time reel not created"

# Check formula has time term
FINAL_FORMULA=$(agent-browser eval 'document.getElementById("demo-formula").textContent' 2>/dev/null | tr -d '"')
echo "$FINAL_FORMULA" | grep -q "time" && log_pass "Formula includes time term" || log_fail "Formula missing time: $FINAL_FORMULA"

# ============================================================================
# TEST 9: Tree connectors update correctly
# ============================================================================
echo ""
log_info "TEST 9: Tree connectors"

CONNECTORS=$(agent-browser eval 'Array.from(document.querySelectorAll("#demo-lines .tree-connector")).map(c => c.textContent.trim()).join("|")' 2>/dev/null | tr -d '"')
echo "$CONNECTORS" | grep -q "├" && log_pass "Has ├ connector (non-last)" || log_fail "Missing ├ connector: $CONNECTORS"
echo "$CONNECTORS" | grep -q "└" && log_pass "Has └ connector (last)" || log_fail "Missing └ connector: $CONNECTORS"

# ============================================================================
# TEST 10: Page is scrollable
# ============================================================================
echo ""
log_info "TEST 10: Page is scrollable"

IS_SCROLLABLE=$(agent-browser eval 'document.documentElement.scrollHeight > window.innerHeight' 2>/dev/null)
[ "$IS_SCROLLABLE" = "true" ] && log_pass "Page is scrollable" || log_fail "Page is not scrollable"

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
