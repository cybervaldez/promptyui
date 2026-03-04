#!/bin/bash
# ============================================================================
# E2E Test Suite: Demo Page Preview Composition Computation
# ============================================================================
# Tests the Cartesian product preview system during block editing:
# - Committed snapshot correctness
# - Odometer freeze during editing
# - Delta computation (add/remove/revert)
# - Formula display with annotations (base + delta), new terms, plain revert
# - Fingerprint-based DOM skip (no animation re-trigger)
# - Multi-wildcard delta math
# - Negative delta (value removal below committed)
# - Empty block exclusion (leaf count, wildcard removal, delta)
# - Negative delta formula annotation (base − |delta|)
# - Commit transition (odometer rolls, delta clears, fingerprint resets)
#
# Math experts audit:
#   committed = product(wc_i.count) for all i
#   preview_total = product(wc_i.count + delta_i) for all i
#   delta_display = preview_total - committed
#
# Usage: ./tests/test_demo_preview_count.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"
DEMO_URL="$BASE_URL/demo"

setup_cleanup

print_header "Demo Preview Composition Computation"

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

agent-browser open "$DEMO_URL" 2>/dev/null
sleep 2

# ============================================================================
# TEST 1: Committed snapshot is correct
# ============================================================================
echo ""
log_info "TEST 1: OBJECTIVE: Committed state captured correctly on edit entry"

# Read committed total, enter edit, verify snapshot — all in one eval
SNAP_RESULT=$(agent-browser eval '(function() {
    var total = qState.prevOdo;
    // Enter edit
    qState.blocks[0].viewEl.click();
    // Wait a tick for switchToEdit to run
    return total;
})()' 2>/dev/null | tr -d '"')
sleep 1

[ "$SNAP_RESULT" = "48" ] && log_pass "Committed total: 48 (4×4×3)" || log_fail "Committed total: $SNAP_RESULT (expected 48)"

SNAP_CHECK=$(agent-browser eval '(function() {
    var s = qState._committedTotal;
    var wc = qState._committedWcCounts;
    return [s, wc.season || 0, wc.style || 0, wc.detail || 0].join("|");
})()' 2>/dev/null | tr -d '"')

SNAP_T=$(echo "$SNAP_CHECK" | cut -d'|' -f1)
SNAP_S=$(echo "$SNAP_CHECK" | cut -d'|' -f2)
SNAP_ST=$(echo "$SNAP_CHECK" | cut -d'|' -f3)
SNAP_D=$(echo "$SNAP_CHECK" | cut -d'|' -f4)

[ "$SNAP_T" = "48" ] && log_pass "Snapshot total: $SNAP_T" || log_fail "Snapshot total: $SNAP_T (expected 48)"
[ "$SNAP_S" = "4" ] && log_pass "Snapshot season: $SNAP_S" || log_fail "Snapshot season: $SNAP_S (expected 4)"
[ "$SNAP_ST" = "4" ] && log_pass "Snapshot style: $SNAP_ST" || log_fail "Snapshot style: $SNAP_ST (expected 4)"
[ "$SNAP_D" = "3" ] && log_pass "Snapshot detail: $SNAP_D" || log_fail "Snapshot detail: $SNAP_D (expected 3)"

# ============================================================================
# TEST 2: Odometer frozen on edit entry
# ============================================================================
echo ""
log_info "TEST 2: OBJECTIVE: No odometer change, no delta on edit entry"

T2=$(agent-browser eval '(function() {
    var odo = qState.prevOdo;
    var delta = document.getElementById("quill-count-delta").textContent.trim();
    return odo + "|" + delta;
})()' 2>/dev/null | tr -d '"')

T2_ODO=$(echo "$T2" | cut -d'|' -f1)
T2_DELTA=$(echo "$T2" | cut -d'|' -f2)

[ "$T2_ODO" = "48" ] && log_pass "prevOdo unchanged: $T2_ODO" || log_fail "prevOdo: $T2_ODO (expected 48)"
[ -z "$T2_DELTA" ] && log_pass "No delta on edit entry" || log_fail "Unexpected delta: $T2_DELTA"

# ============================================================================
# TEST 3: Add 1 value → season(4+1)×style(4)×detail(3) = 60, delta = +12
# ============================================================================
echo ""
log_info "TEST 3: OBJECTIVE: +1 season value → delta +12, odometer frozen"

T3=$(agent-browser eval '(function() {
    var reg = qState.chipRegistry["season"];
    reg.values.push("test-val-1");
    syncRegistryToBlocks();
    qRecalc();
    var odo = qState.prevOdo;
    var delta = document.getElementById("quill-count-delta").textContent.trim();
    var formula = document.getElementById("quill-formula").textContent;
    var vis = document.getElementById("quill-count-delta").classList.contains("visible");
    return [odo, delta, formula, vis].join("|||");
})()' 2>/dev/null | tr -d '"')
sleep 0.5

T3_ODO=$(echo "$T3" | cut -d'|' -f1)
T3_DELTA=$(echo "$T3" | cut -d'|' -f4)
T3_FORMULA=$(echo "$T3" | cut -d'|' -f7)
T3_VIS=$(echo "$T3" | cut -d'|' -f10)

[ "$T3_ODO" = "48" ] && log_pass "Odometer frozen: $T3_ODO" || log_fail "Odometer moved: $T3_ODO"
[ "$T3_DELTA" = "+ 12" ] && log_pass "Delta: + 12 (5×4×3-48=12)" || log_fail "Delta: '$T3_DELTA'"
echo "$T3_FORMULA" | grep -q "4 + 1" && log_pass "Formula shows (4 + 1)" || log_fail "Formula: '$T3_FORMULA'"
[ "$T3_VIS" = "true" ] && log_pass "Delta .visible class present" || log_fail "Delta .visible missing"

# ============================================================================
# TEST 4: Fade-in CSS properties
# ============================================================================
echo ""
log_info "TEST 4: OBJECTIVE: Delta has opacity transition CSS"

T4=$(agent-browser eval 'getComputedStyle(document.getElementById("quill-count-delta")).transition.includes("opacity")' 2>/dev/null)
[ "$T4" = "true" ] && log_pass "Opacity transition present" || log_fail "Missing opacity transition"

# ============================================================================
# TEST 5: Fingerprint skip — repeated qRecalc does not rebuild DOM
# ============================================================================
echo ""
log_info "TEST 5: OBJECTIVE: Same-state qRecalc skips DOM rebuild (fingerprint)"

T5=$(agent-browser eval '(function() {
    var fp1 = qState._prevFormulaFingerprint;
    qRecalc();
    var fp2 = qState._prevFormulaFingerprint;
    // Check animations are not running
    var terms = document.querySelectorAll("#quill-formula .formula-term");
    var noRunning = true;
    terms.forEach(function(t) {
        var anims = t.getAnimations ? t.getAnimations() : [];
        anims.forEach(function(a) { if (a.playState === "running") noRunning = false; });
    });
    return [fp1 === fp2, noRunning].join("|");
})()' 2>/dev/null | tr -d '"')
sleep 0.3

T5_FP=$(echo "$T5" | cut -d'|' -f1)
T5_ANIM=$(echo "$T5" | cut -d'|' -f2)

[ "$T5_FP" = "true" ] && log_pass "Fingerprint stable on repeat" || log_fail "Fingerprint changed"
[ "$T5_ANIM" = "true" ] && log_pass "No re-triggered animations" || log_fail "Animations running (DOM rebuilt)"

# ============================================================================
# TEST 6: Multi-wildcard delta → season(4+1)×style(4+2)×detail(3) = 90, +42
# ============================================================================
echo ""
log_info "TEST 6: OBJECTIVE: +2 style values → compound delta +42"

T6=$(agent-browser eval '(function() {
    var reg = qState.chipRegistry["style"];
    reg.values.push("test-style-1");
    reg.values.push("test-style-2");
    syncRegistryToBlocks();
    qRecalc();
    var delta = document.getElementById("quill-count-delta").textContent.trim();
    var formula = document.getElementById("quill-formula").textContent;
    return delta + "|||" + formula;
})()' 2>/dev/null | tr -d '"')
sleep 0.5

T6_DELTA=$(echo "$T6" | cut -d'|' -f1)
T6_FORMULA=$(echo "$T6" | cut -d'|' -f4)

[ "$T6_DELTA" = "+ 42" ] && log_pass "Compound delta: + 42 (5×6×3=90, 90-48=42)" || log_fail "Delta: '$T6_DELTA'"
echo "$T6_FORMULA" | grep -q "4 + 2" && log_pass "Style shows (4 + 2)" || log_fail "Style annotation missing: '$T6_FORMULA'"

# ============================================================================
# TEST 7: Partial revert — remove style adds, keep season add → +12
# ============================================================================
echo ""
log_info "TEST 7: OBJECTIVE: Partial revert to season(4+1)×style(4)×detail(3) = 60, +12"

T7=$(agent-browser eval '(function() {
    var reg = qState.chipRegistry["style"];
    var i1 = reg.values.indexOf("test-style-1");
    if (i1 !== -1) reg.values.splice(i1, 1);
    var i2 = reg.values.indexOf("test-style-2");
    if (i2 !== -1) reg.values.splice(i2, 1);
    syncRegistryToBlocks();
    qRecalc();
    var delta = document.getElementById("quill-count-delta").textContent.trim();
    var formula = document.getElementById("quill-formula").textContent;
    return delta + "|||" + formula;
})()' 2>/dev/null | tr -d '"')
sleep 0.5

T7_DELTA=$(echo "$T7" | cut -d'|' -f1)
T7_FORMULA=$(echo "$T7" | cut -d'|' -f4)

[ "$T7_DELTA" = "+ 12" ] && log_pass "Partial revert delta: + 12" || log_fail "Delta: '$T7_DELTA' (expected '+ 12')"
echo "$T7_FORMULA" | grep -q "4 + 1" && log_pass "Season annotation kept" || log_fail "Season annotation lost: '$T7_FORMULA'"
echo "$T7_FORMULA" | grep -qv "4 + 2" && log_pass "Style annotation removed" || log_fail "Style annotation still present"

# ============================================================================
# TEST 8: Full revert — remove all additions → no delta, plain formula
# ============================================================================
echo ""
log_info "TEST 8: OBJECTIVE: Full revert clears all preview"

T8=$(agent-browser eval '(function() {
    var reg = qState.chipRegistry["season"];
    var idx = reg.values.indexOf("test-val-1");
    if (idx !== -1) reg.values.splice(idx, 1);
    syncRegistryToBlocks();
    qRecalc();
    var delta = document.getElementById("quill-count-delta").textContent.trim();
    var vis = document.getElementById("quill-count-delta").classList.contains("visible");
    var hasNew = !!document.querySelector(".formula-term-new");
    var formula = document.getElementById("quill-formula").textContent;
    return [delta, vis, hasNew, formula].join("|||");
})()' 2>/dev/null | tr -d '"')
sleep 0.5

T8_DELTA=$(echo "$T8" | cut -d'|' -f1)
T8_VIS=$(echo "$T8" | cut -d'|' -f4)
T8_NEW=$(echo "$T8" | cut -d'|' -f7)
T8_FORMULA=$(echo "$T8" | cut -d'|' -f10)

[ -z "$T8_DELTA" ] && log_pass "Delta cleared on full revert" || log_fail "Delta still showing: '$T8_DELTA'"
[ "$T8_VIS" = "false" ] && log_pass "Delta .visible removed" || log_fail "Delta .visible still present"
[ "$T8_NEW" = "false" ] && log_pass "No formula-term-new" || log_fail "formula-term-new still present"
echo "$T8_FORMULA" | grep -qv "+" && log_pass "Plain formula: $T8_FORMULA" || log_fail "Formula has annotations: '$T8_FORMULA'"

# ============================================================================
# TEST 9: Negative delta — remove a committed value
# ============================================================================
echo ""
log_info "TEST 9: OBJECTIVE: season(3)×style(4)×detail(3) = 36, delta = -12"

T9=$(agent-browser eval '(function() {
    var reg = qState.chipRegistry["season"];
    reg.values.pop();
    syncRegistryToBlocks();
    qRecalc();
    var delta = document.getElementById("quill-count-delta").textContent.trim();
    // Restore
    reg.values.push("restored-val");
    syncRegistryToBlocks();
    qRecalc();
    return delta;
})()' 2>/dev/null | tr -d '"')
sleep 0.5

echo "$T9" | grep -q "12" && log_pass "Negative delta: $T9 (3×4×3=36, 36-48=-12)" || log_fail "Negative delta wrong: '$T9'"

# ============================================================================
# TEST 10: New wildcard — italic formula-term-new with animation
# ============================================================================
echo ""
log_info "TEST 10: OBJECTIVE: New wildcard shows as italic .formula-term-new"

# Type new wildcard and close popover in one shot
agent-browser eval '(function() {
    var editing = qState.blocks.find(function(b) { return b.lineEl.classList.contains("editing"); });
    if (!editing) return;
    var len = editing.quill.getLength();
    editing.quill.insertText(len - 1, " __mood__", "user");
})()' 2>/dev/null
sleep 1

# Close popover, add values, read state — all in one eval
T10=$(agent-browser eval '(function() {
    // Close popover if open
    var pop = document.getElementById("wc-popover");
    if (pop) pop.style.display = "none";
    _activePopoverWc = null;
    // Add values to new wildcard
    var reg = qState.chipRegistry["mood"];
    if (!reg) return "no-reg|||||||";
    reg.values.push("happy");
    reg.values.push("sad");
    syncRegistryToBlocks();
    qRecalc();
    var hasNew = !!document.querySelector(".formula-term-new");
    var formula = document.getElementById("quill-formula").textContent;
    var delta = document.getElementById("quill-count-delta").textContent.trim();
    var hasAnim = false;
    var el = document.querySelector(".formula-term-new");
    if (el) {
        var anim = getComputedStyle(el).animationName;
        hasAnim = anim && anim !== "none";
    }
    return [hasNew, formula, delta, hasAnim].join("|||");
})()' 2>/dev/null | tr -d '"')
sleep 0.5

T10_NEW=$(echo "$T10" | cut -d'|' -f1)
T10_FORMULA=$(echo "$T10" | cut -d'|' -f4)
T10_DELTA=$(echo "$T10" | cut -d'|' -f7)
T10_ANIM=$(echo "$T10" | cut -d'|' -f10)

[ "$T10_NEW" = "true" ] && log_pass "Has .formula-term-new class" || log_fail "Missing .formula-term-new"
echo "$T10_FORMULA" | grep -q "mood" && log_pass "Formula includes mood: $T10_FORMULA" || log_fail "Formula missing mood: '$T10_FORMULA'"
[ -n "$T10_DELTA" ] && log_pass "Delta shows projected addition: $T10_DELTA" || log_fail "No delta for new wildcard"
[ "$T10_ANIM" = "true" ] && log_pass "New term has formulaFadeIn animation" || log_fail "Missing animation"

# ============================================================================
# TEST 11: Commit transition — blur finishes edit
# ============================================================================
echo ""
log_info "TEST 11: OBJECTIVE: Finishing edit: odometer rolls, delta clears, fingerprint resets"

ODO_PRE=$(agent-browser eval 'qState.prevOdo' 2>/dev/null | tr -d '"')

# Blur to finish editing
agent-browser eval '(function() {
    var editing = qState.blocks.find(function(b) { return b.lineEl.classList.contains("editing"); });
    if (editing) editing.quill.root.blur();
})()' 2>/dev/null
sleep 2

T11=$(agent-browser eval '(function() {
    var isEditing = !!document.querySelector(".q-block.editing");
    var odo = qState.prevOdo;
    var delta = document.getElementById("quill-count-delta").textContent.trim();
    var vis = document.getElementById("quill-count-delta").classList.contains("visible");
    var fp = qState._prevFormulaFingerprint;
    return [isEditing, odo, delta, vis, fp === null].join("|||");
})()' 2>/dev/null | tr -d '"')

T11_EDITING=$(echo "$T11" | cut -d'|' -f1)
T11_ODO=$(echo "$T11" | cut -d'|' -f4)
T11_DELTA=$(echo "$T11" | cut -d'|' -f7)
T11_VIS=$(echo "$T11" | cut -d'|' -f10)
T11_FP=$(echo "$T11" | cut -d'|' -f13)

[ "$T11_EDITING" = "false" ] && log_pass "Edit mode exited" || log_fail "Still in edit mode"
[ "$T11_ODO" != "$ODO_PRE" ] 2>/dev/null && log_pass "Odometer rolled: $ODO_PRE → $T11_ODO" || log_fail "Odometer stuck at $T11_ODO"
[ -z "$T11_DELTA" ] && log_pass "Delta cleared" || log_fail "Delta: '$T11_DELTA'"
[ "$T11_VIS" = "false" ] && log_pass "Delta .visible removed" || log_fail "Delta .visible still present"
[ "$T11_FP" = "true" ] && log_pass "Fingerprint reset to null" || log_fail "Fingerprint not reset"

# ============================================================================
# TEST 12: Delta inline layout — next to odometer
# ============================================================================
echo ""
log_info "TEST 12: OBJECTIVE: Delta positioned inline next to odometer"

T12=$(agent-browser eval '(function() {
    var row = document.querySelector(".quill-count-row");
    if (!row) return "no-row|||";
    var display = getComputedStyle(row).display;
    var siblings = row.contains(document.getElementById("quill-count"))
        && row.contains(document.getElementById("quill-count-delta"));
    return [display, siblings].join("|||");
})()' 2>/dev/null | tr -d '"')

T12_DISPLAY=$(echo "$T12" | cut -d'|' -f1)
T12_SIBLINGS=$(echo "$T12" | cut -d'|' -f4)

[ "$T12_DISPLAY" = "flex" ] && log_pass "Row uses flex layout" || log_fail "Row: '$T12_DISPLAY' (expected flex)"
[ "$T12_SIBLINGS" = "true" ] && log_pass "Count + delta are siblings in row" || log_fail "Not siblings"

# ============================================================================
# TEST 13: Emptying child block reflects compositional changes
# ============================================================================
echo ""
log_info "TEST 13: OBJECTIVE: Emptying child block excludes it from leaf count and drops wildcards"

# Reload for clean state — 2 blocks: root(season,style) + child(detail)
agent-browser open "$DEMO_URL" 2>/dev/null
sleep 2

# Edit the child block (block index 1) and clear it
agent-browser eval '(function() {
    // Click child block to edit
    qState.blocks[1].viewEl.click();
})()' 2>/dev/null
sleep 1

# Verify committed leaves were captured
# Root(depth=0) has 1 child(depth=1) → only child is a leaf → totalLeaves=1
T13_COMMITTED_LEAVES=$(agent-browser eval 'qState._committedLeaves' 2>/dev/null | tr -d '"')
[ "$T13_COMMITTED_LEAVES" = "1" ] && log_pass "Committed leaves: 1 (child is the only leaf)" || log_fail "Committed leaves: $T13_COMMITTED_LEAVES (expected 1)"

# Clear the child block entirely
agent-browser eval '(function() {
    var editing = qState.blocks.find(function(b) { return b.lineEl.classList.contains("editing"); });
    if (editing) {
        editing.quill.setText("", "user");
    }
})()' 2>/dev/null
sleep 0.5

# Trigger recalc
agent-browser eval 'qRecalc()' 2>/dev/null
sleep 0.5

# Read formula and delta — with child emptied:
# Only root block remains as leaf → lines term disappears (1 leaf = no multiplier)
# Child's wildcard (detail) is gone (no chips in empty block)
# Formula should be: season(4) × style(4) = 16
# Delta = 16 - 48 = -32
T13=$(agent-browser eval '(function() {
    var deltaEl = document.getElementById("quill-count-delta");
    var delta = deltaEl ? deltaEl.textContent.trim() : "";
    var formula = document.getElementById("quill-formula").textContent.replace(/\\s+/g, "");
    var hasLines = formula.indexOf("lines") !== -1;
    return [delta, formula, hasLines].join("|||");
})()' 2>/dev/null | tr -d '"')

T13_DELTA=$(echo "$T13" | cut -d'|' -f1)
T13_FORMULA=$(echo "$T13" | cut -d'|' -f4)
T13_HAS_LINES=$(echo "$T13" | cut -d'|' -f7)

[ "$T13_DELTA" = "− 32" ] && log_pass "Delta: − 32 (4×4=16, 16-48=-32)" || log_fail "Delta: '$T13_DELTA' (expected '− 32')"
[ "$T13_HAS_LINES" = "false" ] && log_pass "Lines term removed (1 leaf = no multiplier)" || log_fail "Lines term still present"
echo "$T13_FORMULA" | grep -q "detail" && log_fail "detail wildcard still in formula" || log_pass "detail wildcard removed from formula"

# ============================================================================
# TEST 14: Re-typing content reverts to committed state
# ============================================================================
echo ""
log_info "TEST 14: OBJECTIVE: Re-typing content in emptied block reverts composition"

# Type content back with the detail wildcard
agent-browser eval '(function() {
    var editing = qState.blocks.find(function(b) { return b.lineEl.classList.contains("editing"); });
    if (editing) {
        editing.quill.setText("with __detail__ level", "user");
    }
})()' 2>/dev/null
sleep 0.5

agent-browser eval 'qRecalc()' 2>/dev/null
sleep 0.5

T14=$(agent-browser eval '(function() {
    var deltaEl = document.getElementById("quill-count-delta");
    var delta = deltaEl ? deltaEl.textContent.trim() : "";
    var formula = document.getElementById("quill-formula").textContent.replace(/\\s+/g, "");
    return [delta, formula].join("|||");
})()' 2>/dev/null | tr -d '"')

T14_DELTA=$(echo "$T14" | cut -d'|' -f1)
T14_FORMULA=$(echo "$T14" | cut -d'|' -f4)

[ -z "$T14_DELTA" ] && log_pass "Delta cleared (back to committed)" || log_fail "Delta not cleared: '$T14_DELTA'"
echo "$T14_FORMULA" | grep -q "detail" && log_pass "detail wildcard restored in formula" || log_fail "detail missing from formula: $T14_FORMULA"

# ============================================================================
# TEST 15: Negative delta annotation in formula terms
# ============================================================================
echo ""
log_info "TEST 15: OBJECTIVE: Negative delta shows base − |delta| in formula"

# Reload and edit child block, remove one value from detail (3→2)
agent-browser open "$DEMO_URL" 2>/dev/null
sleep 2

agent-browser eval '(function() {
    qState.blocks[1].viewEl.click();
})()' 2>/dev/null
sleep 1

# Remove a value from detail wildcard via chipRegistry
agent-browser eval '(function() {
    var reg = qState.chipRegistry["detail"];
    if (reg && reg.values.length > 1) {
        reg.values.pop();
        syncRegistryToBlocks();
        qRecalc();
    }
})()' 2>/dev/null
sleep 0.5

T15_FORMULA=$(agent-browser eval 'document.getElementById("quill-formula").textContent.replace(/\\s+/g, "")' 2>/dev/null | tr -d '"')

# Formula should show detail(3 − 1) for negative delta
echo "$T15_FORMULA" | grep -q "3−1\|3 − 1" && log_pass "Negative delta annotation: detail(3 − 1)" || log_fail "Negative annotation missing: $T15_FORMULA"

# ============================================================================
# TEST 16: No JavaScript errors
# ============================================================================
echo ""
log_info "TEST 16: No JavaScript errors"

JS_ERRORS=$(agent-browser errors 2>/dev/null || echo "")
if [ -z "$JS_ERRORS" ] || echo "$JS_ERRORS" | grep -q "^\[\]$"; then
    log_pass "No JS errors"
else
    log_fail "JS errors: $JS_ERRORS"
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
