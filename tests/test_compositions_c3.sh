#!/bin/bash
# ============================================================================
# E2E Test Suite: C3 Compositions Panel
# ============================================================================
# Tests the C3 view modes, breadcrumb navigation, grouped structure,
# smart sticky headers, and URL persistence.
#
# Usage: ./tests/test_compositions_c3.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"

setup_cleanup

print_header "C3 Compositions Panel"

# ============================================================================
# PREREQ
# ============================================================================
log_info "PREREQUISITES"

if wait_for_server; then
    log_pass "Server is running"
else
    log_fail "Server not running"
    exit 1
fi

# Open stress-test-prompt in preview mode (auto-generates compositions)
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt&composition=0&editorMode=preview" 2>/dev/null
sleep 5

# Preview mode now shows compositions as main view (no mode switch needed)

TOTAL_ITEMS=$(agent-browser eval 'PU.state.previewMode.compositions.length' 2>/dev/null | tr -d '"')
[ "$TOTAL_ITEMS" -gt "0" ] 2>/dev/null && log_pass "Compositions populated: $TOTAL_ITEMS items" || log_fail "No compositions: $TOTAL_ITEMS"

# ============================================================================
# TEST 1: C3 Group Structure
# ============================================================================
echo ""
log_info "TEST 1: C3 Group structure"

GROUP_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-compositions-group").length' 2>/dev/null | tr -d '"')
[ "$GROUP_COUNT" -gt "0" ] 2>/dev/null && log_pass "Groups rendered: $GROUP_COUNT" || log_fail "No groups rendered"

HEADER_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-compositions-header-row[data-header-path]").length' 2>/dev/null | tr -d '"')
[ "$HEADER_COUNT" -gt "0" ] 2>/dev/null && log_pass "Header rows with path: $HEADER_COUNT" || log_fail "No header rows"

# Check depth attribute
DEPTH_ATTRS=$(agent-browser eval 'document.querySelectorAll(".pu-compositions-group[data-depth]").length' 2>/dev/null | tr -d '"')
[ "$DEPTH_ATTRS" -gt "0" ] 2>/dev/null && log_pass "Groups have data-depth: $DEPTH_ATTRS" || log_fail "No data-depth"

# ============================================================================
# TEST 2: Breadcrumb bar always visible
# ============================================================================
echo ""
log_info "TEST 2: Breadcrumb bar"

BREADCRUMB_EXISTS=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-compositions-breadcrumb\"]")' 2>/dev/null)
[ "$BREADCRUMB_EXISTS" = "true" ] && log_pass "Breadcrumb bar exists" || log_fail "No breadcrumb bar"

# Check "All" crumb present (when not magnified, it's the current crumb)
ALL_CRUMB=$(agent-browser eval 'document.querySelector(".pu-compositions-crumb-current")?.textContent' 2>/dev/null | tr -d '"')
[ "$ALL_CRUMB" = "All" ] && log_pass "All crumb present" || log_fail "All crumb text: $ALL_CRUMB"

# ============================================================================
# TEST 3: View mode segmented control
# ============================================================================
echo ""
log_info "TEST 3: View mode segmented control"

VIEW_SEG=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-compositions-view-seg\"]")' 2>/dev/null)
[ "$VIEW_SEG" = "true" ] && log_pass "View segment control exists" || log_fail "No view segment control"

# Default is 'full'
DEFAULT_MODE=$(agent-browser eval 'PU.state.previewMode.compositionsViewMode' 2>/dev/null | tr -d '"')
[ "$DEFAULT_MODE" = "full" ] && log_pass "Default view mode is full" || log_fail "Default mode: $DEFAULT_MODE"

# Switch to leaf mode
agent-browser eval 'PU.compositions.setViewMode("leaf")' 2>/dev/null
sleep 0.3

LEAF_CLASS=$(agent-browser eval 'document.querySelector(".pu-compositions-panel").classList.contains("pu-compositions-view-leaf")' 2>/dev/null)
[ "$LEAF_CLASS" = "true" ] && log_pass "Leaf mode class applied" || log_fail "Leaf class not applied"

LEAF_STATE=$(agent-browser eval 'PU.state.previewMode.compositionsViewMode' 2>/dev/null | tr -d '"')
[ "$LEAF_STATE" = "leaf" ] && log_pass "State updated to leaf" || log_fail "State: $LEAF_STATE"

# Switch to flat mode
agent-browser eval 'PU.compositions.setViewMode("flat")' 2>/dev/null
sleep 0.3

FLAT_CLASS=$(agent-browser eval 'document.querySelector(".pu-compositions-panel").classList.contains("pu-compositions-view-flat")' 2>/dev/null)
[ "$FLAT_CLASS" = "true" ] && log_pass "Flat mode class applied" || log_fail "Flat class not applied"

# Flat mode allows paths toggle
agent-browser eval 'PU.state.previewMode.compositionsShowPaths = true; PU.compositions.setViewMode("flat")' 2>/dev/null
sleep 0.3
agent-browser eval 'PU.compositions.toggleShowPaths()' 2>/dev/null
sleep 0.3
FLAT_PATHS_OFF=$(agent-browser eval '!PU.state.previewMode.compositionsShowPaths' 2>/dev/null)
[ "$FLAT_PATHS_OFF" = "true" ] && log_pass "Flat mode allows paths toggle off" || log_fail "Paths toggle stuck in flat mode"

# Switch back to full
agent-browser eval 'PU.compositions.setViewMode("full")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 4: Paths toggle
# ============================================================================
echo ""
log_info "TEST 4: Paths toggle (#)"

PATHS_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-compositions-paths-btn\"]")' 2>/dev/null)
[ "$PATHS_BTN" = "true" ] && log_pass "Paths button exists" || log_fail "No paths button"

# Ensure paths are off first (flat mode may have left them on)
agent-browser eval 'PU.state.previewMode.compositionsShowPaths = false; PU.compositions.render()' 2>/dev/null
sleep 0.3

# Toggle paths on
agent-browser eval 'PU.compositions.toggleShowPaths()' 2>/dev/null
sleep 0.3

PATHS_ON=$(agent-browser eval 'document.querySelector(".pu-compositions-panel").classList.contains("pu-compositions-show-paths")' 2>/dev/null)
[ "$PATHS_ON" = "true" ] && log_pass "Paths class applied on toggle" || log_fail "Paths class not applied"

# Toggle off
agent-browser eval 'PU.compositions.toggleShowPaths()' 2>/dev/null
sleep 0.3

PATHS_OFF=$(agent-browser eval '!document.querySelector(".pu-compositions-panel").classList.contains("pu-compositions-show-paths")' 2>/dev/null)
[ "$PATHS_OFF" = "true" ] && log_pass "Paths class removed on toggle" || log_fail "Paths class still present"

# ============================================================================
# TEST 5: Magnify with deeper breadcrumb tracking
# ============================================================================
echo ""
log_info "TEST 5: Togglable breadcrumb navigation"

# Find a nested path (depth > 1)
DEEP_PATH=$(agent-browser eval '
    const items = document.querySelectorAll(".pu-compositions-item[data-block-path]");
    let deepest = "";
    items.forEach(i => {
        const bp = i.dataset.blockPath;
        if (bp.split(".").length > deepest.split(".").length) deepest = bp;
    });
    deepest;
' 2>/dev/null | tr -d '"')

if [ -n "$DEEP_PATH" ] && [ "$DEEP_PATH" != "" ]; then
    # Magnify to deep path
    agent-browser eval "PU.compositions.magnify('${DEEP_PATH}')" 2>/dev/null
    sleep 0.5

    DEEP_STORED=$(agent-browser eval 'PU.state.previewMode.deepestMagnifiedPath' 2>/dev/null | tr -d '"')
    [ "$DEEP_STORED" = "$DEEP_PATH" ] && log_pass "Deepest path stored: $DEEP_STORED" || log_fail "Deepest path: $DEEP_STORED vs $DEEP_PATH"

    # Navigate up to parent
    PARENT_PATH=$(echo "$DEEP_PATH" | sed 's/\.[0-9]*$//')
    if [ "$PARENT_PATH" != "$DEEP_PATH" ]; then
        agent-browser eval "PU.compositions.magnify('${PARENT_PATH}')" 2>/dev/null
        sleep 0.5

        # Deeper crumbs should be visible
        DEEPER_CRUMBS=$(agent-browser eval 'document.querySelectorAll(".pu-compositions-crumb-deeper").length' 2>/dev/null | tr -d '"')
        [ "$DEEPER_CRUMBS" -gt "0" ] 2>/dev/null && log_pass "Deeper crumbs visible after nav up: $DEEPER_CRUMBS" || log_fail "No deeper crumbs after nav up"

        # Click deeper crumb should navigate back
        agent-browser eval "PU.compositions.magnify('${DEEP_PATH}')" 2>/dev/null
        sleep 0.3
        BACK_TO_DEEP=$(agent-browser eval 'PU.state.previewMode.magnifiedPath' 2>/dev/null | tr -d '"')
        [ "$BACK_TO_DEEP" = "$DEEP_PATH" ] && log_pass "Navigated back to deep path" || log_fail "Failed nav back: $BACK_TO_DEEP"
    else
        log_skip "Only single-level path, skip parent nav"
    fi

    # Clear
    agent-browser eval 'PU.compositions.clearMagnify()' 2>/dev/null
    sleep 0.3
    CLEARED=$(agent-browser eval '!PU.state.previewMode.magnifiedPath && !PU.state.previewMode.deepestMagnifiedPath' 2>/dev/null)
    [ "$CLEARED" = "true" ] && log_pass "Both magnified and deepest paths cleared" || log_fail "Paths not fully cleared"
else
    log_skip "No nested items to test breadcrumb navigation"
fi

# ============================================================================
# TEST 6: URL persistence for view mode
# ============================================================================
echo ""
log_info "TEST 6: URL persistence"

# Set leaf mode and check URL
agent-browser eval 'PU.compositions.setViewMode("leaf")' 2>/dev/null
sleep 0.5
agent-browser eval 'PU.actions.updateUrl()' 2>/dev/null
sleep 0.3

URL_MODE=$(agent-browser eval 'new URL(location.href).searchParams.get("compView")' 2>/dev/null | tr -d '"')
[ "$URL_MODE" = "leaf" ] && log_pass "View mode in URL: $URL_MODE" || log_fail "URL view mode: $URL_MODE"

# Turn paths on and check URL
agent-browser eval 'PU.state.previewMode.compositionsShowPaths = false; PU.compositions.toggleShowPaths()' 2>/dev/null
sleep 0.3
agent-browser eval 'PU.actions.updateUrl()' 2>/dev/null
sleep 0.3

URL_PATHS=$(agent-browser eval 'new URL(location.href).searchParams.get("compPaths")' 2>/dev/null | tr -d '"')
[ "$URL_PATHS" = "1" ] && log_pass "Paths toggle in URL" || log_fail "URL paths: $URL_PATHS"

# Reset
agent-browser eval 'PU.compositions.setViewMode("full")' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 7: Consolidation — preview body hidden, compositions is main
# ============================================================================
echo ""
log_info "TEST 7: Consolidation layout"

# Already in preview mode — consolidation CSS targets body[data-editor-mode="preview"]

PV_HIDDEN=$(agent-browser eval 'window.getComputedStyle(document.querySelector(".pu-preview-body")).display' 2>/dev/null | tr -d '"')
[ "$PV_HIDDEN" = "none" ] && log_pass "Preview body hidden in preview mode" || log_fail "Preview body visible: $PV_HIDDEN"

COMP_FLEX=$(agent-browser eval 'window.getComputedStyle(document.querySelector(".pu-compositions-panel")).flex' 2>/dev/null | tr -d '"')
echo "$COMP_FLEX" | grep -q "1" && log_pass "Compositions panel flex: $COMP_FLEX" || log_fail "Panel not flex: $COMP_FLEX"

HEADER_HIDDEN=$(agent-browser eval 'window.getComputedStyle(document.querySelector(".pu-compositions-header")).display' 2>/dev/null | tr -d '"')
[ "$HEADER_HIDDEN" = "none" ] && log_pass "Compositions toggle header hidden" || log_fail "Header visible: $HEADER_HIDDEN"

COMP_H=$(agent-browser eval 'document.querySelector(".pu-compositions-panel")?.offsetHeight' 2>/dev/null | tr -d '"')
[ "$COMP_H" -gt "300" ] 2>/dev/null && log_pass "Compositions panel expanded: ${COMP_H}px" || log_fail "Panel too small: ${COMP_H}px"

# ============================================================================
# TEST 8: No depth stepper (removed)
# ============================================================================
echo ""
log_info "TEST 9: Lock strip"

LOCK_STRIP_EL=$(agent-browser eval 'document.querySelectorAll("[data-testid=\"pu-compositions-lock-strip\"]").length' 2>/dev/null | tr -d '"')
[ "$LOCK_STRIP_EL" = "1" ] && log_pass "Lock strip element exists" || log_fail "No lock strip element"

# Expand a wildcard to get multi-value lock
agent-browser eval '
    const lookup = PU.preview.getFullWildcardLookup();
    const names = Object.keys(lookup).sort();
    const first = names[0];
    const vals = lookup[first];
    if (vals && vals.length >= 2) {
        PU.state.previewMode.lockedValues[first] = [vals[0], vals[1]];
        PU.editorMode.renderPreview();
    }
' 2>/dev/null
sleep 2

LOCK_CHIPS=$(agent-browser eval 'document.querySelectorAll(".pu-compositions-lock-chip").length' 2>/dev/null | tr -d '"')
[ "$LOCK_CHIPS" -gt "0" ] 2>/dev/null && log_pass "Lock chips rendered: $LOCK_CHIPS" || log_fail "No lock chips"

# Reset locks
agent-browser eval 'PU.editorMode.clearAllLocks()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 10: Sidebar wildcards-only (no block tree)
# ============================================================================
echo ""
log_info "TEST 10: Sidebar wildcards-only"

NO_BLOCK_TREE=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-bt-title\"]") === null' 2>/dev/null)
[ "$NO_BLOCK_TREE" = "true" ] && log_pass "Block tree removed from sidebar" || log_fail "Block tree still present"

WC_ENTRIES=$(agent-browser eval 'document.querySelectorAll(".pu-rp-wc-entry").length' 2>/dev/null | tr -d '"')
[ "$WC_ENTRIES" -gt "0" ] 2>/dev/null && log_pass "Wildcard entries in sidebar: $WC_ENTRIES" || log_fail "No wildcard entries"

WC_TITLE=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-bt-wc-title\"]")?.textContent' 2>/dev/null | tr -d '"')
[ "$WC_TITLE" = "WILDCARDS" ] && log_pass "Wildcards title present" || log_fail "Title: $WC_TITLE"

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
