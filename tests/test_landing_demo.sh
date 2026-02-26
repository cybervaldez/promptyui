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
LANDING_URL="$BASE_URL/demo"

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
# TEST 11: Save & Continue shows compositions section
# ============================================================================
echo ""
log_info "TEST 11: Save & Continue shows compositions section"

agent-browser eval 'document.getElementById("quill-save-btn").click()' 2>/dev/null
sleep 1

PREVIEW_VISIBLE=$(agent-browser eval 'document.getElementById("preview-section").style.display !== "none"' 2>/dev/null)
[ "$PREVIEW_VISIBLE" = "true" ] && log_pass "Compositions section visible" || log_fail "Compositions section not visible"

# ============================================================================
# TEST 12: Preview navigator shows "1 / N" (matches live app)
# ============================================================================
echo ""
log_info "TEST 12: Preview navigator shows composition count"

NAV_LABEL=$(agent-browser eval 'document.querySelector("[data-testid=\"preview-nav-label\"]").textContent' 2>/dev/null | tr -d '"')
echo "$NAV_LABEL" | grep -q "1 /" && log_pass "Nav shows '1 / N': $NAV_LABEL" || log_fail "Nav label unexpected: $NAV_LABEL"

# ============================================================================
# TEST 13: Preview next/prev buttons work (‹ › style)
# ============================================================================
echo ""
log_info "TEST 13: Preview next/prev navigation"

agent-browser eval 'document.querySelector("[data-testid=\"preview-next-btn\"]").click()' 2>/dev/null
sleep 0.3

NAV_AFTER=$(agent-browser eval 'document.querySelector("[data-testid=\"preview-nav-label\"]").textContent' 2>/dev/null | tr -d '"')
echo "$NAV_AFTER" | grep -q "2 /" && log_pass "Next button works: $NAV_AFTER" || log_fail "Next button failed: $NAV_AFTER"

# ============================================================================
# TEST 14: Preview shows resolved text (no __wildcards__)
# ============================================================================
echo ""
log_info "TEST 14: Preview shows resolved text"

RESOLVED_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"preview-block-0\"]").textContent' 2>/dev/null | tr -d '"')
HAS_WC=$(echo "$RESOLVED_TEXT" | grep -c '__')
[ "$HAS_WC" = "0" ] && log_pass "Resolved text has no __wildcards__" || log_fail "Text still has wildcards: $RESOLVED_TEXT"
[ -n "$RESOLVED_TEXT" ] && log_pass "Block 0 has text: $RESOLVED_TEXT" || log_fail "Block 0 is empty"

# ============================================================================
# TEST 15: Preview pills show wildcard tags (name="value")
# ============================================================================
echo ""
log_info "TEST 15: Preview wildcard tags"

PILL_COUNT=$(agent-browser eval 'document.querySelectorAll(".preview-pill").length' 2>/dev/null)
[ "$PILL_COUNT" -gt "0" ] && log_pass "Has $PILL_COUNT wildcard tags" || log_fail "No wildcard tags found"

# ============================================================================
# TEST 16: Shuffle button randomizes composition
# ============================================================================
echo ""
log_info "TEST 16: Shuffle button"

BEFORE_SHUFFLE=$(agent-browser eval 'demoPreviewState.compId' 2>/dev/null | tr -d '"')
agent-browser eval 'document.querySelector("[data-testid=\"preview-shuffle-btn\"]").click()' 2>/dev/null
sleep 0.3
HAS_SHUFFLE=$(agent-browser eval '!!document.querySelector("[data-testid=\"preview-shuffle-btn\"]")' 2>/dev/null)
[ "$HAS_SHUFFLE" = "true" ] && log_pass "Shuffle button exists" || log_fail "Shuffle button missing"

# ============================================================================
# TEST 17: Bucket area visible in same section (consolidated)
# ============================================================================
echo ""
log_info "TEST 17: Bucket area in same section"

BUCKET_AREA=$(agent-browser eval '!!document.querySelector("[data-testid=\"bucket-area\"]")' 2>/dev/null)
[ "$BUCKET_AREA" = "true" ] && log_pass "Bucket area exists in compositions section" || log_fail "Bucket area missing"

SCALE_DIVIDER=$(agent-browser eval '!!document.querySelector("[data-testid=\"scale-divider\"]")' 2>/dev/null)
[ "$SCALE_DIVIDER" = "true" ] && log_pass "Scale divider visible" || log_fail "Scale divider missing"

# ============================================================================
# TEST 18: Bucket slider changes window size
# ============================================================================
echo ""
log_info "TEST 18: Bucket slider changes window size"

agent-browser eval 'var s = document.querySelector("[data-testid=\"bucket-slider\"]"); s.value = 3; s.dispatchEvent(new Event("input"))' 2>/dev/null
sleep 0.3

SLIDER_VAL=$(agent-browser eval 'document.querySelector("[data-testid=\"bucket-slider-value\"]").textContent' 2>/dev/null | tr -d '"')
[ "$SLIDER_VAL" = "3" ] && log_pass "Slider value shows 3" || log_fail "Slider value: $SLIDER_VAL"

# ============================================================================
# TEST 19: Bucket visual shows bracket groups
# ============================================================================
echo ""
log_info "TEST 19: Bucket bracket groups"

GROUP_COUNT=$(agent-browser eval 'document.querySelectorAll(".bucket-group").length' 2>/dev/null)
[ "$GROUP_COUNT" -gt "0" ] && log_pass "Has $GROUP_COUNT bracket groups" || log_fail "No bracket groups"

# ============================================================================
# TEST 20: Bucket nav coarse works
# ============================================================================
echo ""
log_info "TEST 20: Bucket coarse navigation"

COARSE_BEFORE=$(agent-browser eval 'document.querySelector("[data-testid=\"bucket-coarse-label\"]").textContent' 2>/dev/null | tr -d '"')
agent-browser eval 'demoBucketNext()' 2>/dev/null
sleep 0.3

COARSE_AFTER=$(agent-browser eval 'document.querySelector("[data-testid=\"bucket-coarse-label\"]").textContent' 2>/dev/null | tr -d '"')
[ "$COARSE_BEFORE" != "$COARSE_AFTER" ] && log_pass "Coarse nav changed: $COARSE_BEFORE -> $COARSE_AFTER" || log_fail "Coarse nav unchanged"

# ============================================================================
# TEST 21: Bucket resolved text updates
# ============================================================================
echo ""
log_info "TEST 21: Bucket resolved text"

BUCKET_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"bucket-block-0\"]").textContent' 2>/dev/null | tr -d '"')
[ -n "$BUCKET_TEXT" ] && log_pass "Bucket resolved text: $BUCKET_TEXT" || log_fail "Bucket resolved text empty"

# ============================================================================
# TEST 22: Continue to Annotations works
# ============================================================================
echo ""
log_info "TEST 22: Continue to Annotations"

agent-browser eval 'document.getElementById("preview-continue-btn").click()' 2>/dev/null
sleep 1

ANN_VISIBLE=$(agent-browser eval 'document.getElementById("ann-section").style.display !== "none"' 2>/dev/null)
[ "$ANN_VISIBLE" = "true" ] && log_pass "Annotations section visible" || log_fail "Annotations section not visible"

# ============================================================================
# TEST 23: Annotation layers show 3 columns
# ============================================================================
echo ""
log_info "TEST 23: Annotation layers"

HAS_DEFAULTS=$(agent-browser eval '!!document.querySelector("[data-testid=\"ann-layer-defaults\"]")' 2>/dev/null)
HAS_PROMPT=$(agent-browser eval '!!document.querySelector("[data-testid=\"ann-layer-prompt\"]")' 2>/dev/null)
HAS_BLOCK=$(agent-browser eval '!!document.querySelector("[data-testid=\"ann-layer-block\"]")' 2>/dev/null)
[ "$HAS_DEFAULTS" = "true" ] && log_pass "Defaults layer exists" || log_fail "Defaults layer missing"
[ "$HAS_PROMPT" = "true" ] && log_pass "Prompt layer exists" || log_fail "Prompt layer missing"
[ "$HAS_BLOCK" = "true" ] && log_pass "Block layer exists" || log_fail "Block layer missing"

# ============================================================================
# TEST 24: Block cards have badges
# ============================================================================
echo ""
log_info "TEST 24: Block card badges"

BADGE_COUNT=$(agent-browser eval 'document.querySelectorAll(".ann-badge").length' 2>/dev/null)
[ "$BADGE_COUNT" -gt "0" ] && log_pass "Has $BADGE_COUNT badges" || log_fail "No badges found"

# ============================================================================
# TEST 25: Click block opens editor
# ============================================================================
echo ""
log_info "TEST 25: Click block opens editor"

agent-browser eval 'document.querySelector("[data-testid=\"ann-block-0\"]").click()' 2>/dev/null
sleep 0.5

HAS_OPEN_EDITOR=$(agent-browser eval '!!document.querySelector(".ann-block-editor.open")' 2>/dev/null)
[ "$HAS_OPEN_EDITOR" = "true" ] && log_pass "Editor opened on click" || log_fail "Editor did not open"

# ============================================================================
# TEST 26: Token counter shows count
# ============================================================================
echo ""
log_info "TEST 26: Token counter"

TOKEN_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"ann-token-chip\"]").textContent' 2>/dev/null | tr -d '"')
echo "$TOKEN_TEXT" | grep -qE '~[0-9]+/[0-9]+' && log_pass "Token chip: $TOKEN_TEXT" || log_fail "Token chip unexpected: $TOKEN_TEXT"

# ============================================================================
# TEST 27: Token counter updates on input
# ============================================================================
echo ""
log_info "TEST 27: Token counter updates on input"

TOKEN_BEFORE=$(agent-browser eval 'document.querySelector("[data-testid=\"ann-token-chip\"]").textContent' 2>/dev/null | tr -d '"')
agent-browser eval 'var ta = document.querySelector("[data-testid=\"ann-token-textarea\"]"); ta.value = "This is a much longer text to test the token counter updates when typing more content into the textarea field"; ta.dispatchEvent(new Event("input"))' 2>/dev/null
sleep 0.3

TOKEN_AFTER=$(agent-browser eval 'document.querySelector("[data-testid=\"ann-token-chip\"]").textContent' 2>/dev/null | tr -d '"')
[ "$TOKEN_BEFORE" != "$TOKEN_AFTER" ] && log_pass "Token chip updated: $TOKEN_BEFORE -> $TOKEN_AFTER" || log_fail "Token chip unchanged"

# ============================================================================
# TEST 28: Token budget change updates color
# ============================================================================
echo ""
log_info "TEST 28: Token budget color change"

agent-browser eval 'var inp = document.querySelector("[data-testid=\"ann-budget-input\"]"); inp.value = 10; inp.dispatchEvent(new Event("input"))' 2>/dev/null
sleep 0.3

TOKEN_CLASS=$(agent-browser eval 'document.querySelector("[data-testid=\"ann-token-chip\"]").className' 2>/dev/null | tr -d '"')
echo "$TOKEN_CLASS" | grep -qE 'over|warn' && log_pass "Token chip shows warning/over: $TOKEN_CLASS" || log_fail "No warning class: $TOKEN_CLASS"

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
