#!/bin/bash
# ============================================================================
# E2E Test Suite: Annotation Persistence Phase 2
# ============================================================================
# Tests: (A) Defaults popover in header, (B) Prompt annotations bar in right
# panel, (C) Badge hover tooltip, (D) Live propagation.
#
# Usage: ./tests/test_annotation_phase2.sh [--port 8085]
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

# Helper: decode agent-browser eval JSON string output
decode_json() {
    sed 's/^"//;s/"$//' | sed 's/\\"/"/g'
}

print_header "Annotation Persistence (Phase 2)"

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

# Load test-fixtures job with nested-blocks prompt
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: Gear icon exists in header
# ============================================================================
echo ""
log_info "TEST 1: Gear icon in header"

HAS_GEAR=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-header-defaults-btn\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_GEAR" = "true" ] \
    && log_pass "Gear icon button exists in header" \
    || log_fail "Gear icon missing: $HAS_GEAR"

# ============================================================================
# TEST 2: Defaults popover hidden by default
# ============================================================================
echo ""
log_info "TEST 2: Popover hidden by default"

POPOVER_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-defaults-popover\"]").style.display' 2>/dev/null | tr -d '"')
[ "$POPOVER_DISPLAY" = "none" ] \
    && log_pass "Defaults popover hidden by default" \
    || log_fail "Popover display: $POPOVER_DISPLAY"

# ============================================================================
# TEST 3: Clicking gear opens popover
# ============================================================================
echo ""
log_info "TEST 3: Gear click opens popover"

agent-browser eval 'PU.rightPanel.toggleDefaultsPopover(); "opened"' 2>/dev/null
sleep 0.5

POPOVER_VISIBLE=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-defaults-popover\"]").style.display !== "none"' 2>/dev/null | tr -d '"')
[ "$POPOVER_VISIBLE" = "true" ] \
    && log_pass "Popover opens on gear click" \
    || log_fail "Popover not visible: $POPOVER_VISIBLE"

# ============================================================================
# TEST 4: Popover shows defaults annotations
# ============================================================================
echo ""
log_info "TEST 4: Popover shows defaults annotations"

ANN_SECTION=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-defaults-popover-ann\"]")' 2>/dev/null | tr -d '"')
[ "$ANN_SECTION" = "true" ] \
    && log_pass "Annotations section exists in popover" \
    || log_fail "No annotations section: $ANN_SECTION"

# Check annotation rows
ANN_COUNT=$(agent-browser eval 'document.querySelectorAll("[data-testid=\"pu-defaults-popover-ann\"] .pu-defaults-popover-ann-row").length' 2>/dev/null | tr -d '"')
[ "$ANN_COUNT" -ge 2 ] 2>/dev/null \
    && log_pass "Defaults annotations rendered: $ANN_COUNT rows" \
    || log_fail "Expected 2+ annotation rows: $ANN_COUNT"

# ============================================================================
# TEST 5: Popover shows info defaults
# ============================================================================
echo ""
log_info "TEST 5: Popover shows numeric defaults"

POPOVER_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-defaults-popover\"]").textContent' 2>/dev/null | decode_json)
echo "$POPOVER_TEXT" | grep -q "wildcards_max" \
    && log_pass "Shows wildcards_max" \
    || log_fail "Missing wildcards_max in popover"

# Close popover
agent-browser eval 'PU.rightPanel.hideDefaultsPopover(); "closed"' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 6: Prompt annotations bar exists
# ============================================================================
echo ""
log_info "TEST 6: Prompt annotations bar"

HAS_BAR=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-prompt-ann\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_BAR" = "true" ] \
    && log_pass "Prompt annotations bar exists" \
    || log_fail "Prompt annotations bar missing: $HAS_BAR"

# ============================================================================
# TEST 7: Prompt bar collapsed by default
# ============================================================================
echo ""
log_info "TEST 7: Prompt bar collapsed by default"

IS_COLLAPSED=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-prompt-ann\"]").classList.contains("collapsed")' 2>/dev/null | tr -d '"')
[ "$IS_COLLAPSED" = "true" ] \
    && log_pass "Prompt bar collapsed by default" \
    || log_fail "Not collapsed: $IS_COLLAPSED"

# ============================================================================
# TEST 8: Prompt bar shows count badge
# ============================================================================
echo ""
log_info "TEST 8: Prompt bar count badge"

COUNT_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-prompt-ann-count\"]").textContent' 2>/dev/null | tr -d '"')
[ "$COUNT_TEXT" = "(1)" ] \
    && log_pass "Count badge shows (1)" \
    || log_fail "Count badge wrong: $COUNT_TEXT"

# ============================================================================
# TEST 9: Expanding prompt bar shows annotations
# ============================================================================
echo ""
log_info "TEST 9: Expand prompt bar"

agent-browser eval 'PU.rightPanel.togglePromptAnnotations(); "toggled"' 2>/dev/null
sleep 0.5

PROMPT_ROWS=$(agent-browser eval 'document.querySelectorAll("[data-testid=\"pu-rp-prompt-ann-body\"] .pu-defaults-popover-ann-row").length' 2>/dev/null | tr -d '"')
[ "$PROMPT_ROWS" -ge 1 ] 2>/dev/null \
    && log_pass "Prompt annotation rows visible: $PROMPT_ROWS" \
    || log_fail "No prompt annotation rows: $PROMPT_ROWS"

# Collapse it back
agent-browser eval 'PU.rightPanel.togglePromptAnnotations(); "collapsed"' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 10: Badge hover tooltip
# ============================================================================
echo ""
log_info "TEST 10: Badge hover tooltip"

# Trigger tooltip via JS
agent-browser eval 'var b = document.querySelector(".pu-annotation-badge"); if (b) { PU.annotations.showTooltip("0", b); "shown"; } else "no badge"' 2>/dev/null
sleep 0.3

TOOLTIP_VISIBLE=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-ann-tooltip\"]").style.display !== "none"' 2>/dev/null | tr -d '"')
[ "$TOOLTIP_VISIBLE" = "true" ] \
    && log_pass "Tooltip visible on hover" \
    || log_fail "Tooltip not visible: $TOOLTIP_VISIBLE"

# Check tooltip content
TOOLTIP_TEXT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-ann-tooltip\"]").textContent' 2>/dev/null | decode_json)
echo "$TOOLTIP_TEXT" | grep -q "audience" \
    && log_pass "Tooltip shows audience annotation" \
    || log_fail "Tooltip missing audience: $TOOLTIP_TEXT"

echo "$TOOLTIP_TEXT" | grep -q "prompt" \
    && log_pass "Tooltip shows source label" \
    || log_fail "Tooltip missing source: $TOOLTIP_TEXT"

# Hide tooltip
agent-browser eval 'PU.annotations.hideTooltip(); "hidden"' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 11: Tooltip shows removed annotations
# ============================================================================
echo ""
log_info "TEST 11: Tooltip shows removed annotations"

agent-browser eval 'var b = document.querySelector(".pu-annotation-badge"); if (b) { PU.annotations.showTooltip("0", b); "shown"; }' 2>/dev/null
sleep 0.3

TOOLTIP_HTML=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-ann-tooltip\"]").innerHTML' 2>/dev/null | decode_json)
echo "$TOOLTIP_HTML" | grep -q "removed" \
    && log_pass "Tooltip shows removed annotation" \
    || log_fail "Tooltip missing removed: $TOOLTIP_HTML"

agent-browser eval 'PU.annotations.hideTooltip(); "hidden"' 2>/dev/null

# ============================================================================
# TEST 12: Live propagation - edit defaults annotation
# ============================================================================
echo ""
log_info "TEST 12: Live propagation from defaults"

# Get initial badge count
INITIAL_COUNT=$(agent-browser eval 'PU.annotations.computedCount("0").count' 2>/dev/null | tr -d '"')

# Add a new defaults annotation via JS
agent-browser eval 'var j = PU.rightPanel._ensureModifiedJob(); if (!j.defaults) j.defaults = {}; if (!j.defaults.annotations) j.defaults.annotations = {}; j.defaults.annotations.priority = "high"; PU.annotations.propagateFromParent(); "done"' 2>/dev/null
sleep 0.5

NEW_COUNT=$(agent-browser eval 'PU.annotations.computedCount("0").count' 2>/dev/null | tr -d '"')
[ "$NEW_COUNT" -gt "$INITIAL_COUNT" ] 2>/dev/null \
    && log_pass "Badge count increased after defaults change ($INITIAL_COUNT -> $NEW_COUNT)" \
    || log_fail "Count did not increase: $INITIAL_COUNT -> $NEW_COUNT"

# Verify in resolve
RESOLVED=$(agent-browser eval 'JSON.stringify(PU.annotations.resolve("0").computed)' 2>/dev/null | decode_json)
echo "$RESOLVED" | grep -q '"priority":"high"' \
    && log_pass "New defaults annotation visible in resolve" \
    || log_fail "priority not in resolve: $RESOLVED"

# Clean up
agent-browser eval 'var j = PU.rightPanel._ensureModifiedJob(); delete j.defaults.annotations.priority; PU.annotations.propagateFromParent(); "cleaned"' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 13: Live propagation - edit prompt annotation
# ============================================================================
echo ""
log_info "TEST 13: Live propagation from prompt"

agent-browser eval 'var p = PU.editor.getModifiedPrompt(); if (!p.annotations) p.annotations = {}; p.annotations.format = "markdown"; PU.annotations.propagateFromParent(); "done"' 2>/dev/null
sleep 0.5

RESOLVED2=$(agent-browser eval 'JSON.stringify(PU.annotations.resolve("0").computed)' 2>/dev/null | decode_json)
echo "$RESOLVED2" | grep -q '"format":"markdown"' \
    && log_pass "Prompt annotation propagated to block resolve" \
    || log_fail "format not in resolve: $RESOLVED2"

# Clean up
agent-browser eval 'var p = PU.editor.getModifiedPrompt(); delete p.annotations.format; PU.annotations.propagateFromParent(); "cleaned"' 2>/dev/null

# ============================================================================
# TEST 14: Old defaults section removed from right panel
# ============================================================================
echo ""
log_info "TEST 14: Old defaults section removed"

HAS_OLD_DEFAULTS=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-defaults\"]")' 2>/dev/null | tr -d '"')
[ "$HAS_OLD_DEFAULTS" = "false" ] \
    && log_pass "Old defaults section removed from right panel" \
    || log_fail "Old defaults section still present: $HAS_OLD_DEFAULTS"

# ============================================================================
# TEST 15: Phase 1 still works (regression)
# ============================================================================
echo ""
log_info "TEST 15: Phase 1 regression"

HAS_RESOLVE=$(agent-browser eval 'typeof PU.annotations.resolve' 2>/dev/null | tr -d '"')
[ "$HAS_RESOLVE" = "function" ] \
    && log_pass "resolve() still exists" \
    || log_fail "resolve() missing: $HAS_RESOLVE"

BADGE=$(agent-browser eval '!!document.querySelector(".pu-annotation-badge")' 2>/dev/null | tr -d '"')
[ "$BADGE" = "true" ] \
    && log_pass "Block annotation badges still render" \
    || log_fail "No annotation badges: $BADGE"

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
