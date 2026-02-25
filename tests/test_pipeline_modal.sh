#!/bin/bash
# ============================================================================
# E2E Test Suite: Split Button + Pipeline View Modal
# ============================================================================
# Tests the Build split button dropdown and Pipeline View modal.
# Verifies: split button renders, dropdown opens/closes, pipeline modal
# opens with block tree, wildcard pills, and composition counts.
#
# Usage: ./tests/test_pipeline_modal.sh [--port 8085]
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

print_header "Split Button + Pipeline View Modal"

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

# Load a job with prompts (hiring-templates has nested blocks + wildcards)
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=interview-questions" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: Split button group renders in header
# ============================================================================
echo ""
log_info "TEST 1: Split button group renders"

HAS_GROUP=$(agent-browser eval '!!document.querySelector("[data-testid=pu-header-build-group]")' 2>/dev/null)
[ "$HAS_GROUP" = "true" ] \
    && log_pass "Build button group exists" \
    || log_fail "Build button group missing"

HAS_BUILD=$(agent-browser eval '!!document.querySelector("[data-testid=pu-header-build-btn]")' 2>/dev/null)
[ "$HAS_BUILD" = "true" ] \
    && log_pass "Build main button exists" \
    || log_fail "Build main button missing"

HAS_CARET=$(agent-browser eval '!!document.querySelector("[data-testid=pu-header-build-menu-btn]")' 2>/dev/null)
[ "$HAS_CARET" = "true" ] \
    && log_pass "Caret dropdown button exists" \
    || log_fail "Caret dropdown button missing"

# ============================================================================
# TEST 2: Dropdown is hidden by default
# ============================================================================
echo ""
log_info "TEST 2: Dropdown hidden by default"

MENU_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-menu]").style.display' 2>/dev/null | tr -d '"')
[ "$MENU_DISPLAY" = "none" ] \
    && log_pass "Dropdown hidden by default" \
    || log_fail "Dropdown not hidden: display=$MENU_DISPLAY"

# ============================================================================
# TEST 3: Clicking caret opens dropdown
# ============================================================================
echo ""
log_info "TEST 3: Caret opens dropdown"

agent-browser eval 'document.querySelector("[data-testid=pu-header-build-menu-btn]").click()' 2>/dev/null
sleep 0.5

MENU_VISIBLE=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-menu]").style.display' 2>/dev/null | tr -d '"')
[ "$MENU_VISIBLE" = "block" ] \
    && log_pass "Dropdown opens on caret click" \
    || log_fail "Dropdown not visible: display=$MENU_VISIBLE"

# ============================================================================
# TEST 4: Dropdown has Pipeline View and Quick Build items
# ============================================================================
echo ""
log_info "TEST 4: Dropdown menu items"

HAS_PIPELINE=$(agent-browser eval '!!document.querySelector("[data-testid=pu-build-menu-pipeline]")' 2>/dev/null)
[ "$HAS_PIPELINE" = "true" ] \
    && log_pass "Pipeline View menu item exists" \
    || log_fail "Pipeline View menu item missing"

HAS_QUICK=$(agent-browser eval '!!document.querySelector("[data-testid=pu-build-menu-panel]")' 2>/dev/null)
[ "$HAS_QUICK" = "true" ] \
    && log_pass "Quick Build menu item exists" \
    || log_fail "Quick Build menu item missing"

PIPELINE_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-build-menu-pipeline]").textContent.trim()' 2>/dev/null | tr -d '"')
[ "$PIPELINE_TEXT" = "Pipeline View" ] \
    && log_pass "Pipeline View label correct" \
    || log_fail "Pipeline View label: '$PIPELINE_TEXT'"

# Close dropdown before next test
agent-browser eval 'PU.buildMenu.close()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 5: Pipeline modal opens from dropdown
# ============================================================================
echo ""
log_info "TEST 5: Pipeline modal opens"

# Open via dropdown
agent-browser eval 'document.querySelector("[data-testid=pu-build-menu-pipeline]").click()' 2>/dev/null
sleep 1

MODAL_VISIBLE=$(agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-modal]").style.display' 2>/dev/null | tr -d '"')
[ "$MODAL_VISIBLE" = "flex" ] \
    && log_pass "Pipeline modal opens" \
    || log_fail "Pipeline modal not visible: display=$MODAL_VISIBLE"

# ============================================================================
# TEST 6: Pipeline modal has block tree
# ============================================================================
echo ""
log_info "TEST 6: Block tree renders"

HAS_TREE=$(agent-browser eval '!!document.querySelector("[data-testid=pu-pipeline-tree]")' 2>/dev/null)
[ "$HAS_TREE" = "true" ] \
    && log_pass "Block tree container exists" \
    || log_fail "Block tree container missing"

# Count block nodes
NODE_COUNT=$(agent-browser eval 'document.querySelectorAll("[data-testid^=pu-pipeline-node-]").length' 2>/dev/null | tr -d '"')
[ "$NODE_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Block nodes rendered: $NODE_COUNT" \
    || log_fail "No block nodes found: $NODE_COUNT"

# ============================================================================
# TEST 7: Wildcard dimension pills render
# ============================================================================
echo ""
log_info "TEST 7: Dimension pills"

HAS_DIMS=$(agent-browser eval '!!document.querySelector("[data-testid=pu-pipeline-dims]")' 2>/dev/null)
[ "$HAS_DIMS" = "true" ] \
    && log_pass "Dimensions container exists" \
    || log_fail "Dimensions container missing"

PILL_COUNT=$(agent-browser eval 'document.querySelectorAll("[data-testid^=pu-pipeline-pill-]").length' 2>/dev/null | tr -d '"')
[ "$PILL_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Wildcard pills rendered: $PILL_COUNT" \
    || log_fail "No wildcard pills found: $PILL_COUNT"

# ============================================================================
# TEST 8: Pipeline info shows prompt name and stats
# ============================================================================
echo ""
log_info "TEST 8: Pipeline info header"

HAS_INFO=$(agent-browser eval '!!document.querySelector("[data-testid=pu-pipeline-info]")' 2>/dev/null)
[ "$HAS_INFO" = "true" ] \
    && log_pass "Pipeline info header exists" \
    || log_fail "Pipeline info header missing"

PROMPT_NAME=$(agent-browser eval 'var el = document.querySelector(".pu-pipeline-prompt-name"); el ? el.textContent.trim() : "MISSING"' 2>/dev/null | tr -d '"')
[ "$PROMPT_NAME" = "interview-questions" ] \
    && log_pass "Prompt name displayed: $PROMPT_NAME" \
    || log_fail "Prompt name wrong: '$PROMPT_NAME'"

# ============================================================================
# TEST 9: Block nodes have data-run-state attribute (Phase 2 foundation)
# ============================================================================
echo ""
log_info "TEST 9: Block nodes have run state"

RUN_STATE=$(agent-browser eval 'var n = document.querySelector("[data-testid^=pu-pipeline-node-]"); n ? n.dataset.runState : "MISSING"' 2>/dev/null | tr -d '"')
[ "$RUN_STATE" = "idle" ] \
    && log_pass "Block nodes have data-run-state=idle" \
    || log_fail "Block run state: '$RUN_STATE'"

# ============================================================================
# TEST 10: Pipeline modal closes
# ============================================================================
echo ""
log_info "TEST 10: Pipeline modal closes"

agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-close-btn]").click()' 2>/dev/null
sleep 0.5

MODAL_CLOSED=$(agent-browser eval 'document.querySelector("[data-testid=pu-pipeline-modal]").style.display' 2>/dev/null | tr -d '"')
[ "$MODAL_CLOSED" = "none" ] \
    && log_pass "Pipeline modal closes" \
    || log_fail "Pipeline modal still visible: display=$MODAL_CLOSED"

# ============================================================================
# TEST 11: Build button still opens Build panel (backward compat)
# ============================================================================
echo ""
log_info "TEST 11: Build button backward compatibility"

agent-browser eval 'document.querySelector("[data-testid=pu-header-build-btn]").click()' 2>/dev/null
sleep 1

PANEL_OPEN=$(agent-browser eval 'var p = document.querySelector("[data-testid=pu-build-panel]"); p && p.classList.contains("open")' 2>/dev/null)
[ "$PANEL_OPEN" = "true" ] \
    && log_pass "Build button still opens Build panel" \
    || log_fail "Build panel did not open"

# Close build panel
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
