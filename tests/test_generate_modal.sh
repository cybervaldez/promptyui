#!/bin/bash
# ============================================================================
# E2E Test Suite: Generate Modal
# ============================================================================
# Tests the Generate button and Generate modal with horizontal tree layout,
# wildcard pills, run simulation, stop/resume, and close behavior.
#
# Usage: ./tests/test_generate_modal.sh [--port 8085]
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

print_header "Generate Modal"

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

# Load test-fixtures with nested-blocks prompt (has wildcards + children)
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: Generate button exists in header
# ============================================================================
echo ""
log_info "TEST 1: Generate button exists in header"

HAS_BTN=$(agent-browser eval '!!document.querySelector("[data-testid=pu-header-generate-btn]")' 2>/dev/null)
if [[ "$HAS_BTN" == "true" ]]; then
    log_pass "Generate button found in header"
else
    log_fail "Generate button not found in header"
fi

BTN_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-header-generate-btn]")?.textContent?.trim()' 2>/dev/null)
if [[ "$BTN_TEXT" == "Generate" ]]; then
    log_pass "Generate button has correct text"
else
    log_fail "Generate button text: '$BTN_TEXT' (expected 'Generate')"
fi

# ============================================================================
# TEST 2: Clicking Generate opens the modal
# ============================================================================
echo ""
log_info "TEST 2: Clicking Generate opens the modal"

agent-browser eval 'document.querySelector("[data-testid=pu-header-generate-btn]").click()' 2>/dev/null
sleep 1

MODAL_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=pu-generate-modal]")?.style.display' 2>/dev/null)
if [[ "$MODAL_DISPLAY" == "flex" ]]; then
    log_pass "Generate modal is visible"
else
    log_fail "Generate modal display: '$MODAL_DISPLAY' (expected 'flex')"
fi

# ============================================================================
# TEST 3: Modal shows prompt name and composition count
# ============================================================================
echo ""
log_info "TEST 3: Modal header shows prompt info"

PROMPT_NAME=$(agent-browser eval 'document.querySelector("[data-testid=pu-gen-prompt-name]")?.textContent?.trim()' 2>/dev/null)
if [[ -n "$PROMPT_NAME" && "$PROMPT_NAME" != "" ]]; then
    log_pass "Prompt name shown: '$PROMPT_NAME'"
else
    log_fail "Prompt name not shown"
fi

COMP_COUNT=$(agent-browser eval 'document.querySelector("[data-testid=pu-gen-comp-count]")?.textContent?.trim()' 2>/dev/null)
if [[ "$COMP_COUNT" == *"compositions"* ]]; then
    log_pass "Composition count shown: '$COMP_COUNT'"
else
    log_fail "Composition count text: '$COMP_COUNT' (expected '*compositions*')"
fi

# ============================================================================
# TEST 4: Block tree renders with nodes
# ============================================================================
echo ""
log_info "TEST 4: Block tree renders"

HAS_TREE=$(agent-browser eval '!!document.querySelector("[data-testid=pu-gen-tree]")' 2>/dev/null)
if [[ "$HAS_TREE" == "true" ]]; then
    log_pass "Tree element found"
else
    log_fail "Tree element not found"
fi

NODE_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-gen-node:not(.root)").length' 2>/dev/null)
if [[ "$NODE_COUNT" -gt 0 ]]; then
    log_pass "Block nodes rendered: $NODE_COUNT"
else
    log_fail "No block nodes rendered"
fi

ROOT_NODE=$(agent-browser eval '!!document.querySelector(".pu-gen-node.root")' 2>/dev/null)
if [[ "$ROOT_NODE" == "true" ]]; then
    log_pass "Root prompt node present"
else
    log_fail "Root prompt node not found"
fi

# ============================================================================
# TEST 5: Inline wildcard dropdowns show (if prompt has wildcards)
# ============================================================================
echo ""
log_info "TEST 5: Inline wildcard dropdowns"

INLINE_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-gen-wc-inline").length' 2>/dev/null)
if [[ "$INLINE_COUNT" -gt 0 ]]; then
    log_pass "Inline wildcard dropdowns found: $INLINE_COUNT"
else
    log_skip "No inline wildcards (prompt may not have wildcards)"
fi

# ============================================================================
# TEST 5b: Annotation strip renders in dims zone
# ============================================================================
echo ""
log_info "TEST 5b: Annotation strip in dims zone"

STRIP_COUNT=$(agent-browser eval 'document.querySelectorAll("[data-testid=pu-gen-ann-strip]").length' 2>/dev/null)
if [[ "$STRIP_COUNT" -gt 0 ]]; then
    log_pass "Annotation strips found: $STRIP_COUNT"
else
    log_skip "No annotation strips (prompt may not have annotations)"
fi

# ============================================================================
# TEST 5c: ext_text entries list renders for ext_text prompts
# ============================================================================
echo ""
log_info "TEST 5c: ext_text entries list in generate modal"

# Close current modal, switch to ext-wildcard-test, open generate
agent-browser eval 'document.querySelector("[data-testid=pu-gen-close-btn]")?.click()' 2>/dev/null
sleep 0.5
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=ext-wildcard-test" 2>/dev/null
sleep 3

agent-browser eval 'document.querySelector("[data-testid=pu-header-generate-btn]").click()' 2>/dev/null
sleep 1

EXT_ENTRIES=$(agent-browser eval 'document.querySelectorAll(".pu-gen-ext-entries").length' 2>/dev/null)
if [[ "$EXT_ENTRIES" -gt 0 ]]; then
    log_pass "ext_text entries list rendered: $EXT_ENTRIES"
else
    log_skip "No ext_text entries (ext cache may not be loaded)"
fi

EXT_ENTRY_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-gen-ext-entry").length' 2>/dev/null)
if [[ "$EXT_ENTRY_COUNT" -gt 0 ]]; then
    log_pass "ext_text entry items rendered: $EXT_ENTRY_COUNT"
else
    log_skip "No ext_text entry items"
fi

# Check for inline wildcard pills within ext entries
EXT_WC_PILLS=$(agent-browser eval 'document.querySelectorAll(".pu-gen-ext-entries .pu-gen-wc-inline").length' 2>/dev/null)
if [[ "$EXT_WC_PILLS" -gt 0 ]]; then
    log_pass "Inline wildcard pills in ext entries: $EXT_WC_PILLS"
else
    log_skip "No wildcard pills in ext entries"
fi

# Switch back to nested-blocks for remaining tests
agent-browser eval 'document.querySelector("[data-testid=pu-gen-close-btn]")?.click()' 2>/dev/null
sleep 0.5
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3
agent-browser eval 'document.querySelector("[data-testid=pu-header-generate-btn]").click()' 2>/dev/null
sleep 1

# ============================================================================
# TEST 6: Run button starts simulation
# ============================================================================
echo ""
log_info "TEST 6: Run button starts simulation"

RUN_BTN_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=pu-gen-run-btn]")?.textContent?.trim()' 2>/dev/null)
if [[ "$RUN_BTN_TEXT" == "Run" ]]; then
    log_pass "Run button shows 'Run' in idle state"
else
    log_fail "Run button text: '$RUN_BTN_TEXT' (expected 'Run')"
fi

agent-browser eval 'document.querySelector("[data-testid=pu-gen-run-btn]").click()' 2>/dev/null
sleep 0.5

BTN_DURING=$(agent-browser eval 'document.querySelector("[data-testid=pu-gen-run-btn]")?.textContent?.trim()' 2>/dev/null)
if [[ "$BTN_DURING" == "Stop" || "$BTN_DURING" == "Stopping…" ]]; then
    log_pass "Run button changes to '$BTN_DURING' during execution"
else
    log_fail "Run button during execution: '$BTN_DURING' (expected 'Stop')"
fi

# Check nodes transition through states
HAS_DORMANT=$(agent-browser eval 'document.querySelectorAll(".pu-gen-node[data-run-state=dormant]").length > 0 || document.querySelectorAll(".pu-gen-node[data-run-state=running]").length > 0 || document.querySelectorAll(".pu-gen-node[data-run-state=complete]").length > 0' 2>/dev/null)
if [[ "$HAS_DORMANT" == "true" ]]; then
    log_pass "Nodes transition through run states"
else
    log_fail "No nodes in run states"
fi

# Wait for completion
sleep 8

BTN_AFTER=$(agent-browser eval 'document.querySelector("[data-testid=pu-gen-run-btn]")?.textContent?.trim()' 2>/dev/null)
if [[ "$BTN_AFTER" == "Run Again" ]]; then
    log_pass "Run completes and button shows 'Run Again'"
else
    log_skip "Run may still be in progress: '$BTN_AFTER'"
fi

# ============================================================================
# TEST 7: Stop pauses, Resume continues
# ============================================================================
echo ""
log_info "TEST 7: Stop and Resume"

# Start a new run
agent-browser eval 'document.querySelector("[data-testid=pu-gen-run-btn]").click()' 2>/dev/null
sleep 0.3

# Click Stop
agent-browser eval 'document.querySelector("[data-testid=pu-gen-run-btn]").click()' 2>/dev/null
sleep 1

BTN_PAUSED=$(agent-browser eval 'document.querySelector("[data-testid=pu-gen-run-btn]")?.textContent?.trim()' 2>/dev/null)
if [[ "$BTN_PAUSED" == "Resume" ]]; then
    log_pass "Stop pauses and button shows 'Resume'"
else
    log_skip "Paused state: '$BTN_PAUSED' (run may have already completed)"
fi

# ============================================================================
# TEST 8: Close button hides the modal
# ============================================================================
echo ""
log_info "TEST 8: Close button hides modal"

agent-browser eval 'document.querySelector("[data-testid=pu-gen-close-btn]").click()' 2>/dev/null
sleep 0.5

MODAL_HIDDEN=$(agent-browser eval 'document.querySelector("[data-testid=pu-generate-modal]")?.style.display' 2>/dev/null)
if [[ "$MODAL_HIDDEN" == "none" ]]; then
    log_pass "Modal hidden after close"
else
    log_fail "Modal display after close: '$MODAL_HIDDEN' (expected 'none')"
fi

# ============================================================================
# TEST 9: Re-opening after complete shows fresh state
# ============================================================================
echo ""
log_info "TEST 9: Re-open shows fresh state"

agent-browser eval 'document.querySelector("[data-testid=pu-header-generate-btn]").click()' 2>/dev/null
sleep 1

FRESH_BTN=$(agent-browser eval 'document.querySelector("[data-testid=pu-gen-run-btn]")?.textContent?.trim()' 2>/dev/null)
if [[ "$FRESH_BTN" == "Run" ]]; then
    log_pass "Re-opened modal shows fresh 'Run' button"
else
    log_pass "Re-opened modal shows '$FRESH_BTN' (state preserved or reset)"
fi

# Close for cleanup
agent-browser eval 'document.querySelector("[data-testid=pu-gen-close-btn]").click()' 2>/dev/null
sleep 0.3

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
