#!/bin/bash
# ============================================================================
# E2E Test Suite: Filter Tree in Output Footer
# ============================================================================
# Verifies the filter tree panel replaces group-by dropdown and provides
# dimension filtering for resolved outputs.
#
# Usage: ./tests/test_filter_tree.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Output footer was removed — filter tree migrated to Build Composition panel.
# This test is now obsolete.
print_header "Filter Tree in Output Footer (SKIPPED)"
log_skip "Output footer removed — filter tree migrated to Build Composition panel"
print_summary
exit 0

PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

setup_cleanup

print_header "Filter Tree in Output Footer"

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

# Find a job with wildcards to test with
JOBS_JSON=$(curl -sf "$BASE_URL/api/pu/jobs" 2>/dev/null)
FIRST_JOB=$(echo "$JOBS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); jobs=d.get('jobs',d); keys=list(jobs.keys()) if isinstance(jobs,dict) else []; print(keys[0] if keys else '')" 2>/dev/null)
if [ -z "$FIRST_JOB" ]; then
    log_skip "No jobs available to test filter tree"
    print_summary
    exit $?
fi
log_pass "Found test job: $FIRST_JOB"

# ============================================================================
# TEST 1: Page loads and output footer exists
# ============================================================================
echo ""
log_info "TEST 1: Output footer structure"

agent-browser open "$BASE_URL/?job=$FIRST_JOB" 2>/dev/null
sleep 3

HAS_FOOTER=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-output-footer\"]')" 2>/dev/null)
[ "$HAS_FOOTER" = "true" ] && log_pass "Output footer exists" || log_fail "Output footer missing"

HAS_TREE=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-filter-tree\"]')" 2>/dev/null)
[ "$HAS_TREE" = "true" ] && log_pass "Filter tree element exists" || log_fail "Filter tree element missing"

HAS_LIST=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-output-list\"]')" 2>/dev/null)
[ "$HAS_LIST" = "true" ] && log_pass "Output list element exists" || log_fail "Output list element missing"

# ============================================================================
# TEST 2: Group-by dropdown is removed
# ============================================================================
echo ""
log_info "TEST 2: Group-by dropdown removed"

HAS_GROUPBY=$(agent-browser eval "!!document.querySelector('[data-testid=\"pu-output-groupby-wrapper\"]')" 2>/dev/null)
[ "$HAS_GROUPBY" = "false" ] && log_pass "Group-by dropdown wrapper removed" || log_fail "Group-by dropdown wrapper still present"

# ============================================================================
# TEST 3: Filter tree shows dimensions when outputs have wildcards
# ============================================================================
echo ""
log_info "TEST 3: Filter tree with wildcards"

# Check if filter tree is visible (has dimensions rendered)
TREE_VISIBLE=$(agent-browser eval "document.querySelector('[data-testid=\"pu-filter-tree\"]').style.display" 2>/dev/null | tr -d '"')
DIM_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-filter-dim').length" 2>/dev/null)

if [ "$TREE_VISIBLE" = "flex" ] && [ "$DIM_COUNT" -gt 0 ] 2>/dev/null; then
    log_pass "Filter tree visible with $DIM_COUNT dimensions"
elif [ "$TREE_VISIBLE" = "none" ] || [ "$DIM_COUNT" = "0" ] 2>/dev/null; then
    log_skip "No free wildcards in this prompt — filter tree hidden (expected)"
else
    log_skip "Could not determine filter tree state"
fi

# ============================================================================
# TEST 4: Filter tree dot indicators and bar tracks
# ============================================================================
echo ""
log_info "TEST 4: Filter tree UI elements"

DOT_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-filter-dot').length" 2>/dev/null)
BAR_COUNT=$(agent-browser eval "document.querySelectorAll('.pu-filter-value-bar-track').length" 2>/dev/null)

if [ "$DOT_COUNT" -gt 0 ] 2>/dev/null; then
    log_pass "Dot indicators present ($DOT_COUNT dots)"
else
    log_skip "No dot indicators (no free wildcards in prompt)"
fi

if [ "$BAR_COUNT" -gt 0 ] 2>/dev/null; then
    log_pass "Bar tracks present ($BAR_COUNT bars)"
else
    log_skip "No bar tracks (no free wildcards in prompt)"
fi

# ============================================================================
# TEST 5: Reset button hidden when no filters
# ============================================================================
echo ""
log_info "TEST 5: Reset button state"

RESET_DISPLAY=$(agent-browser eval "document.querySelector('[data-testid=\"pu-filter-reset-btn\"]').style.display" 2>/dev/null | tr -d '"')
[ "$RESET_DISPLAY" = "none" ] && log_pass "Reset button hidden when no filters active" || log_fail "Reset button visible with no filters: '$RESET_DISPLAY'"

# ============================================================================
# TEST 6: Filter badge hidden when no filters
# ============================================================================
echo ""
log_info "TEST 6: Filter badge state"

BADGE_DISPLAY=$(agent-browser eval "document.querySelector('[data-testid=\"pu-output-filter-badge\"]').style.display" 2>/dev/null | tr -d '"')
[ "$BADGE_DISPLAY" = "none" ] && log_pass "Filter badge hidden when no filters" || log_fail "Filter badge visible with no filters: '$BADGE_DISPLAY'"

# ============================================================================
# TEST 7: Clicking a filter value toggles it
# ============================================================================
echo ""
log_info "TEST 7: Filter toggle interaction"

FIRST_FILTER=$(agent-browser eval "document.querySelector('.pu-filter-value') ? document.querySelector('.pu-filter-value').getAttribute('data-testid') : ''" 2>/dev/null | tr -d '"')

if [ -n "$FIRST_FILTER" ] && [ "$FIRST_FILTER" != "" ]; then
    # Click the filter value
    agent-browser eval "document.querySelector('[data-testid=\"$FIRST_FILTER\"]').click()" 2>/dev/null
    sleep 0.5

    # Check if it became active
    IS_ACTIVE=$(agent-browser eval "document.querySelector('[data-testid=\"$FIRST_FILTER\"]') && document.querySelector('[data-testid=\"$FIRST_FILTER\"]').classList.contains('active')" 2>/dev/null)
    [ "$IS_ACTIVE" = "true" ] && log_pass "Filter value becomes active on click" || log_fail "Filter value not active after click"

    # Check reset button is now visible
    RESET_NOW=$(agent-browser eval "document.querySelector('[data-testid=\"pu-filter-reset-btn\"]').style.display" 2>/dev/null | tr -d '"')
    [ "$RESET_NOW" = "flex" ] && log_pass "Reset button visible after filter" || log_fail "Reset button not visible after filter: '$RESET_NOW'"

    # Check filter badge is visible
    BADGE_NOW=$(agent-browser eval "document.querySelector('[data-testid=\"pu-output-filter-badge\"]').style.display" 2>/dev/null | tr -d '"')
    [ "$BADGE_NOW" != "none" ] && log_pass "Filter badge visible after filter" || log_fail "Filter badge hidden after filter"

    # Click reset
    agent-browser eval "document.querySelector('[data-testid=\"pu-filter-reset-btn\"]').click()" 2>/dev/null
    sleep 0.5

    # Verify reset clears filters
    IS_ACTIVE_AFTER=$(agent-browser eval "document.querySelectorAll('.pu-filter-value.active').length" 2>/dev/null)
    [ "$IS_ACTIVE_AFTER" = "0" ] && log_pass "Reset clears all filters" || log_fail "Filters not cleared after reset: $IS_ACTIVE_AFTER active"
else
    log_skip "No filter values to test interaction"
fi

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
