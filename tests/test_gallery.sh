#!/bin/bash
# ============================================================================
# E2E Test Suite: Sampler Gallery
# ============================================================================
# Tests the Sampler Gallery modal — grid of sampled compositions with wildcard
# labels, card click navigation, resample, and regression checks.
#
# Usage: ./tests/test_gallery.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

setup_cleanup

print_header "Sampler Gallery"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server; then
    log_pass "Server is running"
else
    log_fail "Server not running at $BASE_URL"
    exit 1
fi

# Load test-fixtures job with nested-blocks prompt (has 1 wildcard, 2 values)
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: Gallery modal exists in DOM
# ============================================================================
echo ""
log_info "TEST 1: Gallery modal exists in DOM"

HAS_MODAL=$(agent-browser eval '!!document.querySelector("[data-testid=pu-gallery-modal]")' 2>/dev/null)
[ "$HAS_MODAL" = "true" ] \
    && log_pass "Gallery modal element exists" \
    || log_fail "Gallery modal element missing"

# ============================================================================
# TEST 2: Dropdown has Sampler Gallery item
# ============================================================================
echo ""
log_info "TEST 2: Dropdown has Sampler Gallery item"

HAS_GALLERY_ITEM=$(agent-browser eval '!!document.querySelector("[data-testid=pu-build-menu-gallery]")' 2>/dev/null)
[ "$HAS_GALLERY_ITEM" = "true" ] \
    && log_pass "Sampler Gallery menu item exists" \
    || log_fail "Sampler Gallery menu item missing"

GALLERY_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-menu-gallery]").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$GALLERY_TEXT" = "Sampler Gallery" ] \
    && log_pass "Sampler Gallery label correct" \
    || log_fail "Sampler Gallery label: '$GALLERY_TEXT'"

# ============================================================================
# TEST 3: Gallery modal is hidden by default
# ============================================================================
echo ""
log_info "TEST 3: Gallery modal hidden by default"

MODAL_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=pu-gallery-modal]").style.display' 2>/dev/null | tr -d '"')
[ "$MODAL_DISPLAY" = "none" ] \
    && log_pass "Gallery modal hidden by default" \
    || log_fail "Gallery modal not hidden: display=$MODAL_DISPLAY"

# ============================================================================
# TEST 4: PU.gallery.open() shows modal
# ============================================================================
echo ""
log_info "TEST 4: PU.gallery.open() shows modal"

agent-browser eval 'PU.gallery.open()' 2>/dev/null
sleep 2

MODAL_VISIBLE=$(agent-browser eval 'document.querySelector("[data-testid=pu-gallery-modal]").style.display' 2>/dev/null | tr -d '"')
[ "$MODAL_VISIBLE" = "flex" ] \
    && log_pass "Gallery modal opens" \
    || log_fail "Gallery modal not visible: display=$MODAL_VISIBLE"

# ============================================================================
# TEST 5: Gallery renders grid
# ============================================================================
echo ""
log_info "TEST 5: Gallery renders grid"

HAS_GRID=$(agent-browser eval '!!document.querySelector("[data-testid=pu-gallery-grid]")' 2>/dev/null)
[ "$HAS_GRID" = "true" ] \
    && log_pass "Gallery grid container exists" \
    || log_fail "Gallery grid container missing"

# ============================================================================
# TEST 6: Grid has cards
# ============================================================================
echo ""
log_info "TEST 6: Grid has cards"

CARD_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-gallery-card").length' 2>/dev/null | tr -d '"')
[ "$CARD_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Gallery cards rendered: $CARD_COUNT" \
    || log_fail "No gallery cards found: $CARD_COUNT"

# ============================================================================
# TEST 7: Cards have text content
# ============================================================================
echo ""
log_info "TEST 7: Cards have text content"

CARD_TEXT=$(agent-browser eval 'var el = document.querySelector("[data-testid=pu-gallery-card-text-0]"); el ? el.textContent.trim().length > 0 : false' 2>/dev/null)
[ "$CARD_TEXT" = "true" ] \
    && log_pass "First card has text content" \
    || log_fail "First card text content empty"

# ============================================================================
# TEST 8: Cards have wildcard labels
# ============================================================================
echo ""
log_info "TEST 8: Cards have wildcard labels"

WC_TAG_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-gallery-wc-tag").length' 2>/dev/null | tr -d '"')
[ "$WC_TAG_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Wildcard tags rendered: $WC_TAG_COUNT" \
    || log_fail "No wildcard tags found: $WC_TAG_COUNT"

# ============================================================================
# TEST 9: Status shows count
# ============================================================================
echo ""
log_info "TEST 9: Status shows composition count"

STATUS_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-gallery-status]").textContent.trim()' 2>/dev/null | tr -d '"')
echo "$STATUS_TEXT" | grep -qE '[0-9]+ of [0-9,]+ compositions' \
    && log_pass "Status shows count: $STATUS_TEXT" \
    || log_fail "Status text unexpected: '$STATUS_TEXT'"

# ============================================================================
# TEST 10: Resample button works
# ============================================================================
echo ""
log_info "TEST 10: Resample button works"

# Get current card count, click refresh, verify grid still has cards
agent-browser eval 'document.querySelector("[data-testid=pu-gallery-refresh-btn]").click()' 2>/dev/null
sleep 2

CARD_COUNT_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-gallery-card").length' 2>/dev/null | tr -d '"')
[ "$CARD_COUNT_AFTER" -gt 0 ] 2>/dev/null \
    && log_pass "Resample re-rendered cards: $CARD_COUNT_AFTER" \
    || log_fail "Resample failed, no cards: $CARD_COUNT_AFTER"

# ============================================================================
# TEST 11: Close works
# ============================================================================
echo ""
log_info "TEST 11: Close works"

agent-browser eval 'PU.gallery.close()' 2>/dev/null
sleep 0.5

MODAL_CLOSED=$(agent-browser eval 'document.querySelector("[data-testid=pu-gallery-modal]").style.display' 2>/dev/null | tr -d '"')
[ "$MODAL_CLOSED" = "none" ] \
    && log_pass "Gallery modal closes" \
    || log_fail "Gallery modal still visible: display=$MODAL_CLOSED"

# ============================================================================
# TEST 12: Pipeline modal still works (regression)
# ============================================================================
echo ""
log_info "TEST 12: Pipeline modal still works (regression)"

agent-browser eval 'PU.pipeline.open()' 2>/dev/null
sleep 1

PIPELINE_VISIBLE=$(agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-modal]").style.display' 2>/dev/null | tr -d '"')
[ "$PIPELINE_VISIBLE" = "flex" ] \
    && log_pass "Pipeline modal still opens" \
    || log_fail "Pipeline modal broken: display=$PIPELINE_VISIBLE"

HAS_TREE=$(agent-browser eval '!!document.querySelector("[data-testid=pu-pipeline-tree]")' 2>/dev/null)
[ "$HAS_TREE" = "true" ] \
    && log_pass "Pipeline tree renders" \
    || log_fail "Pipeline tree missing"

agent-browser eval 'PU.pipeline.close()' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 13: Build panel still works (regression)
# ============================================================================
echo ""
log_info "TEST 13: Build panel still works (regression)"

agent-browser eval 'PU.buildComposition.open()' 2>/dev/null
sleep 1

PANEL_OPEN=$(agent-browser eval 'var p = document.querySelector("[data-testid=pu-build-panel]"); p && p.classList.contains("open")' 2>/dev/null)
[ "$PANEL_OPEN" = "true" ] \
    && log_pass "Build panel still opens" \
    || log_fail "Build panel broken"

agent-browser eval 'PU.buildComposition.close()' 2>/dev/null
sleep 0.5

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
