#!/bin/bash
# ============================================================================
# E2E Test Suite: Shortlist (Ancestor Expansion)
# ============================================================================
# Tests the shortlist feature: clicking a leaf auto-adds ancestors as
# separate entries. Each entry has { text, sources: [{blockPath, comboKey}] }.
#
# Usage: ./tests/test_shortlist.sh [--port 8085]
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

print_header "Shortlist Tests (Sources Model)"

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

# ============================================================================
# TEST 1: Shortlist starts empty
# ============================================================================
echo ""
log_info "TEST 1: Shortlist starts empty in preview mode"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=stress-test-prompt&composition=0&editorMode=preview" 2>/dev/null
sleep 3

# Clear any stale session data from previous runs
agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

SL_COUNT=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$SL_COUNT" = "0" ] && log_pass "Shortlist starts empty" || log_fail "Shortlist not empty: $SL_COUNT"

PANEL_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-shortlist-panel\"]")?.style.display' 2>/dev/null | tr -d '"')
[ "$PANEL_DISPLAY" = "none" ] && log_pass "Shortlist panel hidden when empty" || log_fail "Panel display: $PANEL_DISPLAY"

# ============================================================================
# TEST 2: Variations are clickable with data attributes
# ============================================================================
echo ""
log_info "TEST 2: Variations are clickable with data attributes"

HAS_CLICKABLE=$(agent-browser eval 'document.querySelectorAll("[data-testid=\"pu-shortlist-var\"]").length' 2>/dev/null)
[ "$HAS_CLICKABLE" -ge 1 ] 2>/dev/null && log_pass "Clickable variations present ($HAS_CLICKABLE)" || log_fail "No clickable variations: $HAS_CLICKABLE"

HAS_DATA=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-shortlist-var\"][data-block-path]")' 2>/dev/null)
[ "$HAS_DATA" = "true" ] && log_pass "Variations have data-block-path attribute" || log_fail "Missing data-block-path"

HAS_COMBO=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-shortlist-var\"][data-combo-key]")' 2>/dev/null)
[ "$HAS_COMBO" = "true" ] && log_pass "Variations have data-combo-key attribute" || log_fail "Missing data-combo-key"

# ============================================================================
# TEST 3: Click variation to add to shortlist
# ============================================================================
echo ""
log_info "TEST 3: Click variation to add — entry has text + sources"

agent-browser eval 'document.querySelector("[data-testid=\"pu-shortlist-var\"]")?.click()' 2>/dev/null
sleep 1

SL_COUNT=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$SL_COUNT" = "1" ] && log_pass "Shortlist has 1 entry after add" || log_fail "Shortlist count: $SL_COUNT"

# Verify new data model: entry has text and sources
HAS_TEXT=$(agent-browser eval 'typeof PU.state.previewMode.shortlist[0].text === "string" && PU.state.previewMode.shortlist[0].text.length > 0' 2>/dev/null)
[ "$HAS_TEXT" = "true" ] && log_pass "Entry has resolved text" || log_fail "Missing text field"

HAS_SOURCES=$(agent-browser eval 'Array.isArray(PU.state.previewMode.shortlist[0].sources) && PU.state.previewMode.shortlist[0].sources.length >= 1' 2>/dev/null)
[ "$HAS_SOURCES" = "true" ] && log_pass "Entry has sources array" || log_fail "Missing sources"

# Each source has blockPath and comboKey
SRC_VALID=$(agent-browser eval 'PU.state.previewMode.shortlist[0].sources.every(s => typeof s.blockPath === "string" && typeof s.comboKey === "string")' 2>/dev/null)
[ "$SRC_VALID" = "true" ] && log_pass "Sources have blockPath + comboKey" || log_fail "Invalid source structure"

# ============================================================================
# TEST 4: Footer panel visible with correct count
# ============================================================================
echo ""
log_info "TEST 4: Footer panel visible after add"

PANEL_DISPLAY=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-shortlist-panel\"]")?.style.display' 2>/dev/null | tr -d '"')
[ "$PANEL_DISPLAY" != "none" ] && log_pass "Shortlist panel visible" || log_fail "Panel hidden: $PANEL_DISPLAY"

FOOTER_COUNT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-shortlist-count\"]")?.textContent' 2>/dev/null | tr -d '"')
[ "$FOOTER_COUNT" = "1" ] && log_pass "Footer shows count = 1" || log_fail "Footer count: $FOOTER_COUNT"

# ============================================================================
# TEST 5: Shortlisted variation has green highlight + click toggle
# ============================================================================
echo ""
log_info "TEST 5: Shortlisted variation visual state and toggle"

HAS_SHORTLISTED=$(agent-browser eval 'document.querySelectorAll(".pu-preview-variation.pu-shortlisted").length' 2>/dev/null)
[ "$HAS_SHORTLISTED" -ge 1 ] 2>/dev/null && log_pass "Shortlisted variation has green highlight ($HAS_SHORTLISTED)" || log_fail "No shortlisted class: $HAS_SHORTLISTED"

# Click again to toggle off
agent-browser eval 'document.querySelector(".pu-preview-variation.pu-shortlisted")?.click()' 2>/dev/null
sleep 1

REMOVED=$(agent-browser eval 'document.querySelectorAll(".pu-preview-variation.pu-shortlisted").length' 2>/dev/null)
[ "$REMOVED" = "0" ] && log_pass "Click toggle removes shortlisted state" || log_fail "Still shortlisted: $REMOVED"

# ============================================================================
# TEST 6: Auto-ancestor expansion — separate entries per block
# ============================================================================
echo ""
log_info "TEST 6: Auto-ancestor expansion — separate entries per block"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "data-driven"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# Should have 2 entries: one for block 0 (auto-expanded), one for leaf 0.0
TOTAL=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$TOTAL" = "2" ] && log_pass "2 entries (ancestor + leaf)" || log_fail "Total: $TOTAL"

# Each entry has exactly 1 source
SRC_0=$(agent-browser eval 'PU.state.previewMode.shortlist[0].sources.length' 2>/dev/null)
SRC_1=$(agent-browser eval 'PU.state.previewMode.shortlist[1].sources.length' 2>/dev/null)
[ "$SRC_0" = "1" ] && [ "$SRC_1" = "1" ] && log_pass "Each entry has 1 source" || log_fail "Sources: $SRC_0, $SRC_1"

# First entry is block 0, second is block 0.0
FIRST_BP=$(agent-browser eval 'PU.state.previewMode.shortlist[0].sources[0].blockPath' 2>/dev/null | tr -d '"')
[ "$FIRST_BP" = "0" ] && log_pass "First entry is block '0'" || log_fail "First: $FIRST_BP"

LAST_BP=$(agent-browser eval 'PU.state.previewMode.shortlist[1].sources[0].blockPath' 2>/dev/null | tr -d '"')
[ "$LAST_BP" = "0.0" ] && log_pass "Second entry is block '0.0'" || log_fail "Second: $LAST_BP"

# ============================================================================
# TEST 7: Grandchild — 3 separate entries (one per block in chain)
# ============================================================================
echo ""
log_info "TEST 7: Grandchild — 3 separate entries"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

agent-browser eval '
    PU.shortlist.add("0.0.0", [{name: "hook", value: "statistic"}]);
' 2>/dev/null
sleep 0.5

TOTAL=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$TOTAL" = "3" ] && log_pass "3 entries (block 0 + 0.0 + 0.0.0)" || log_fail "Total: $TOTAL"

# Verify all three block paths
PATHS=$(agent-browser eval 'PU.state.previewMode.shortlist.map(e => e.sources[0].blockPath).join(",")' 2>/dev/null | tr -d '"')
[ "$PATHS" = "0,0.0,0.0.0" ] && log_pass "Entries: 0, 0.0, 0.0.0" || log_fail "Paths: $PATHS"

# Each entry has exactly 1 source
ALL_SINGLE=$(agent-browser eval 'PU.state.previewMode.shortlist.every(e => e.sources.length === 1)' 2>/dev/null)
[ "$ALL_SINGLE" = "true" ] && log_pass "Each entry has 1 source" || log_fail "Not all single-source"

# Each entry has non-trivial text
ALL_TEXT=$(agent-browser eval 'PU.state.previewMode.shortlist.every(e => e.text.length > 5)' 2>/dev/null)
[ "$ALL_TEXT" = "true" ] && log_pass "Each entry has resolved text" || log_fail "Missing text"

# ============================================================================
# TEST 8: Remove leaf entry without cascade
# ============================================================================
echo ""
log_info "TEST 8: Remove leaf entry"

# Already have 3 entries from test 7 (block 0, 0.0, 0.0.0)
BEFORE=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$BEFORE" = "3" ] && log_pass "3 entries from test 7" || log_fail "Count before: $BEFORE"

# Remove the leaf (0.0.0) — no descendants, no cascade prompt
agent-browser eval '
    const leaf = PU.state.previewMode.shortlist.find(e => e.sources[0].blockPath === "0.0.0");
    if (leaf) PU.shortlist.remove(leaf.sources[0].blockPath, leaf.sources[0].comboKey);
' 2>/dev/null
sleep 0.3

AFTER=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$AFTER" = "2" ] && log_pass "Leaf removed (2 remaining)" || log_fail "Count after: $AFTER"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 9: Footer shows resolved text in tree view
# ============================================================================
echo ""
log_info "TEST 9: Footer shows stored resolved text in tree groups"

agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# Check tree group for block 0 exists
HAS_GROUP_0=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-shortlist-group-0\"]")' 2>/dev/null)
[ "$HAS_GROUP_0" = "true" ] && log_pass "Tree group for block 0 exists" || log_fail "Group 0 missing"

# Check tree group for block 0.0 exists
HAS_GROUP_00=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-shortlist-group-0.0\"]")' 2>/dev/null)
[ "$HAS_GROUP_00" = "true" ] && log_pass "Tree group for block 0.0 exists" || log_fail "Group 0.0 missing"

# Check item entries exist (at least 2: one in group 0, one in group 0.0)
HAS_ITEMS=$(agent-browser eval 'document.querySelectorAll("[data-testid=\"pu-shortlist-resolved\"]").length' 2>/dev/null)
[ "$HAS_ITEMS" -ge 2 ] 2>/dev/null && log_pass "Resolved prompt texts rendered ($HAS_ITEMS)" || log_fail "Resolved texts: $HAS_ITEMS"

# Check that ANY resolved text contains the pick value 'urgent' (it's the 0.0 entry)
ALL_TEXT=$(agent-browser eval '[...document.querySelectorAll("[data-testid=\"pu-shortlist-resolved\"]")].map(el => el.textContent).join(" ")' 2>/dev/null | tr -d '"')
echo "$ALL_TEXT" | grep -qi "urgent" && log_pass "Resolved text contains pick value 'urgent'" || log_fail "Missing pick value in: $ALL_TEXT"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 10: Write mode hides shortlist
# ============================================================================
echo ""
log_info "TEST 10: Shortlist UI hidden in write mode"

agent-browser eval '
    PU.shortlist.add("0", [{name: "persona", value: "CEO"}, {name: "format", value: "memo"}, {name: "topic", value: "retention"}]);
' 2>/dev/null
sleep 0.3

agent-browser eval "PU.editorMode.setPreset('write')" 2>/dev/null
sleep 1

PANEL_HIDDEN=$(agent-browser eval '
    const panel = document.querySelector("[data-testid=\"pu-shortlist-panel\"]");
    panel ? getComputedStyle(panel).display : "missing"
' 2>/dev/null | tr -d '"')
[ "$PANEL_HIDDEN" = "none" ] && log_pass "Shortlist panel hidden in write mode" || log_fail "Panel display in write: $PANEL_HIDDEN"

agent-browser eval "PU.editorMode.setPreset('preview')" 2>/dev/null
sleep 1

# ============================================================================
# TEST 11: Clear all
# ============================================================================
echo ""
log_info "TEST 11: Clear all shortlist entries"

agent-browser eval '
    if (PU.state.previewMode.shortlist.length === 0) {
        PU.shortlist.add("0", [{name: "persona", value: "CEO"}, {name: "format", value: "memo"}, {name: "topic", value: "retention"}]);
    }
' 2>/dev/null
sleep 0.3

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.5

AFTER_CLEAR=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$AFTER_CLEAR" = "0" ] && log_pass "Clear all: shortlist empty" || log_fail "After clear: $AFTER_CLEAR"

# ============================================================================
# TEST 12: Combo key determinism
# ============================================================================
echo ""
log_info "TEST 12: Combo key is deterministic (sorted by name)"

KEY1=$(agent-browser eval 'PU.shortlist.comboToKey([{name:"z", value:"1"}, {name:"a", value:"2"}])' 2>/dev/null | tr -d '"')
KEY2=$(agent-browser eval 'PU.shortlist.comboToKey([{name:"a", value:"2"}, {name:"z", value:"1"}])' 2>/dev/null | tr -d '"')
[ "$KEY1" = "$KEY2" ] && log_pass "Combo key deterministic: $KEY1" || log_fail "Keys differ: $KEY1 vs $KEY2"

# ============================================================================
# TEST 13: 100-item limit
# ============================================================================
echo ""
log_info "TEST 13: 100-item limit enforced"

agent-browser eval '
    PU.shortlist.clearAll();
    for (let i = 0; i < 100; i++) {
        PU.state.previewMode.shortlist.push({ text: "prompt " + i, sources: [{blockPath: "0", comboKey: "idx=" + i}] });
    }
    PU.shortlist._lookupSet = null;
' 2>/dev/null
sleep 0.3

COUNT=$(agent-browser eval 'PU.shortlist.count()' 2>/dev/null)
[ "$COUNT" = "100" ] && log_pass "100 entries added" || log_fail "Count: $COUNT"

agent-browser eval 'PU.shortlist.add("1", [{name: "x", value: "overflow"}])' 2>/dev/null
sleep 0.3

COUNT_AFTER=$(agent-browser eval 'PU.shortlist.count()' 2>/dev/null)
[ "$COUNT_AFTER" = "100" ] && log_pass "101st entry rejected (still 100)" || log_fail "Count after overflow: $COUNT_AFTER"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 14: Session persistence with separate entries
# ============================================================================
echo ""
log_info "TEST 14: Session persistence round-trip (text + sources)"

# add("0") → 1 entry. add("0.0") → block 0 exists, skip → just 0.0 entry. Total: 2
agent-browser eval '
    PU.shortlist.add("0", [{name: "persona", value: "CEO"}, {name: "format", value: "memo"}, {name: "topic", value: "retention"}]);
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# Verify session data has text + sources (each entry has 1 source)
SESSION_VALID=$(agent-browser eval '
    const data = PU.shortlist.getSessionData();
    data.length >= 2 && data.every(i => typeof i.text === "string" && Array.isArray(i.sources) && i.sources.length === 1)
' 2>/dev/null)
[ "$SESSION_VALID" = "true" ] && log_pass "Session data: 2 entries, each 1 source" || log_fail "Invalid session format"

# Save session
agent-browser eval 'PU.rightPanel.saveSession().then(() => window._slSaved = true)' 2>/dev/null
sleep 2

SAVED=$(agent-browser eval 'window._slSaved === true' 2>/dev/null)
[ "$SAVED" = "true" ] && log_pass "Session save completed" || log_fail "Session save may not have completed"

# Verify via API
api_call GET "$BASE_URL/api/pu/job/hiring-templates/session"
echo "$BODY" | grep -q "shortlist" && log_pass "Shortlist saved to session.yaml" || log_fail "No shortlist in session"

# Clear and hydrate
agent-browser eval '
    const saved = PU.shortlist.getSessionData();
    PU.state.previewMode.shortlist = [];
    PU.shortlist._lookupSet = null;
    window._savedSl = saved;
' 2>/dev/null

agent-browser eval 'PU.shortlist.hydrateFromSession(window._savedSl)' 2>/dev/null
sleep 0.3

SL_AFTER=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$SL_AFTER" = "2" ] && log_pass "Shortlist hydrated from session ($SL_AFTER entries)" || log_fail "Hydration failed: $SL_AFTER"

# Verify hydrated entries have text + sources
HYDRATED_OK=$(agent-browser eval 'PU.state.previewMode.shortlist.every(e => typeof e.text === "string" && Array.isArray(e.sources))' 2>/dev/null)
[ "$HYDRATED_OK" = "true" ] && log_pass "Hydrated entries have text + sources" || log_fail "Invalid hydrated structure"

# Clean up
agent-browser eval '
    PU.shortlist.clearAll();
    PU.rightPanel.saveSession();
' 2>/dev/null
sleep 1

# ============================================================================
# TEST 15: Duplicate add is ignored
# ============================================================================
echo ""
log_info "TEST 15: Duplicate add is ignored"

agent-browser eval '
    PU.shortlist.add("0", [{name: "persona", value: "CEO"}, {name: "format", value: "memo"}, {name: "topic", value: "retention"}]);
    PU.shortlist.add("0", [{name: "persona", value: "CEO"}, {name: "format", value: "memo"}, {name: "topic", value: "retention"}]);
' 2>/dev/null
sleep 0.3

COUNT=$(agent-browser eval 'PU.shortlist.count()' 2>/dev/null)
[ "$COUNT" = "1" ] && log_pass "Duplicate ignored (still 1 entry)" || log_fail "Duplicates: $COUNT"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 16: Ancestor expansion respects wildcard locks
# ============================================================================
echo ""
log_info "TEST 16: Ancestor expansion with locked wildcards"

# Lock persona to [CEO, CTO]
agent-browser eval '
    PU.state.previewMode.lockedValues["persona"] = ["CEO", "CTO"];
' 2>/dev/null
sleep 0.3

# Add a child pick at 0.0 — ancestor block 0 should expand with locked persona
agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# Block 0 should have multiple entries (persona locked to 2 values)
BLOCK_0_COUNT=$(agent-browser eval '
    PU.state.previewMode.shortlist.filter(e => e.sources[0].blockPath === "0").length
' 2>/dev/null)
[ "$BLOCK_0_COUNT" -ge 2 ] 2>/dev/null && log_pass "Block 0 expanded to $BLOCK_0_COUNT entries (locked persona)" || log_fail "Block 0 entries: $BLOCK_0_COUNT"

# Verify CEO and CTO both present
HAS_CEO=$(agent-browser eval '
    PU.state.previewMode.shortlist.some(e => e.sources[0].blockPath === "0" && e.sources[0].comboKey.includes("persona=CEO"))
' 2>/dev/null)
HAS_CTO=$(agent-browser eval '
    PU.state.previewMode.shortlist.some(e => e.sources[0].blockPath === "0" && e.sources[0].comboKey.includes("persona=CTO"))
' 2>/dev/null)
[ "$HAS_CEO" = "true" ] && [ "$HAS_CTO" = "true" ] && log_pass "Both CEO and CTO entries created" || log_fail "CEO=$HAS_CEO CTO=$HAS_CTO"

# Clean up locks
agent-browser eval '
    delete PU.state.previewMode.lockedValues["persona"];
    PU.shortlist.clearAll();
' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 17: has() finds entries across separate blocks
# ============================================================================
echo ""
log_info "TEST 17: has() finds entries across separate blocks"

# Add child → creates entries for block 0 and block 0.0
agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# has() should find block 0 (auto-expanded ancestor)
HAS_ANCESTOR=$(agent-browser eval '
    const entry = PU.state.previewMode.shortlist.find(e => e.sources[0].blockPath === "0");
    entry ? PU.shortlist.has("0", entry.sources[0].comboKey) : false
' 2>/dev/null)
[ "$HAS_ANCESTOR" = "true" ] && log_pass "has() finds ancestor block entry" || log_fail "Ancestor not found"

# hasBlock should find it too
HAS_BLOCK=$(agent-browser eval 'PU.shortlist.hasBlock("0")' 2>/dev/null)
[ "$HAS_BLOCK" = "true" ] && log_pass "hasBlock() finds ancestor block" || log_fail "hasBlock missing"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 18: Hover highlights ancestor variations
# ============================================================================
echo ""
log_info "TEST 18: Hover highlights ancestor variations"

# Simulate highlighting via JS
agent-browser eval '
    const container = document.querySelector("[data-testid=\"pu-preview-body\"]");
    if (container) PU.shortlist._highlightAncestors("0.0", container);
' 2>/dev/null
sleep 0.3

HAS_ALL=$(agent-browser eval 'document.querySelectorAll(".pu-shortlist-hover-all").length' 2>/dev/null)
[ "$HAS_ALL" -ge 1 ] 2>/dev/null && log_pass "Ancestor variations highlighted ($HAS_ALL)" || log_fail "No hover-all highlights: $HAS_ALL"

# Clear highlights
agent-browser eval '
    const container = document.querySelector("[data-testid=\"pu-preview-body\"]");
    if (container) PU.shortlist._clearAncestorHighlights(container);
' 2>/dev/null
sleep 0.2

HAS_HOVER_AFTER=$(agent-browser eval 'document.querySelectorAll(".pu-shortlist-hover-all").length' 2>/dev/null)
[ "$HAS_HOVER_AFTER" = "0" ] && log_pass "Hover highlights cleared" || log_fail "Highlights not cleared: $HAS_HOVER_AFTER"

# ============================================================================
# TEST 19: Hover shows picked ancestor in green
# ============================================================================
echo ""
log_info "TEST 19: Hover shows picked ancestor in green"

# Add parent pick using the CURRENT variation's combo key
agent-browser eval '
    const parentVar = document.querySelector("[data-testid=\"pu-shortlist-var\"][data-block-path=\"0\"]");
    if (parentVar) {
        const comboKey = parentVar.dataset.comboKey;
        const combo = comboKey.split("|").map(p => { const [n, v] = p.split("="); return {name: n, value: v}; });
        PU.shortlist.add("0", combo);
    }
' 2>/dev/null
sleep 0.5

# Highlight ancestors of 0.0
agent-browser eval '
    const container = document.querySelector("[data-testid=\"pu-preview-body\"]");
    if (container) PU.shortlist._highlightAncestors("0.0", container);
' 2>/dev/null
sleep 0.3

HAS_PICK_HOVER=$(agent-browser eval 'document.querySelectorAll(".pu-shortlist-hover-pick").length' 2>/dev/null)
[ "$HAS_PICK_HOVER" -ge 1 ] 2>/dev/null && log_pass "Picked ancestor variation highlighted green ($HAS_PICK_HOVER)" || log_fail "No hover-pick highlights: $HAS_PICK_HOVER"

# Clean up
agent-browser eval '
    const container = document.querySelector("[data-testid=\"pu-preview-body\"]");
    if (container) PU.shortlist._clearAncestorHighlights(container);
    PU.shortlist.clearAll();
' 2>/dev/null

# ============================================================================
# TEST 20: Server sanitizer accepts new format
# ============================================================================
echo ""
log_info "TEST 20: Server sanitizer accepts text + sources format"

api_call POST "$BASE_URL/api/pu/job/hiring-templates/session" '{"prompt_id": "stress-test-prompt", "data": {"composition": 1, "shortlist": [{"text": "As a CEO, write a memo\nUse urgent tone", "sources": [{"block": "0", "combo": "persona=CEO"}, {"block": "0.0", "combo": "tone=urgent"}]}, {"bad": "item"}, {"text": "Block 1", "sources": [{"block": "1", "combo": ""}]}]}}'

api_call GET "$BASE_URL/api/pu/job/hiring-templates/session"
VALID_COUNT=$(echo "$BODY" | ./venv/bin/python -c "
import sys, json
d = json.load(sys.stdin)
sl = d.get('prompts',{}).get('stress-test-prompt',{}).get('shortlist',[])
valid = [i for i in sl if 'text' in i and 'sources' in i]
print(len(valid))
" 2>/dev/null)

[ "$VALID_COUNT" = "2" ] && log_pass "Valid entries preserved (2)" || log_fail "Valid entries: $VALID_COUNT"

# Verify sources structure (each entry has sources array)
SRC_CHECK=$(echo "$BODY" | ./venv/bin/python -c "
import sys, json
d = json.load(sys.stdin)
sl = d.get('prompts',{}).get('stress-test-prompt',{}).get('shortlist',[])
ok = len(sl) >= 1 and all(len(i.get('sources',[])) >= 1 for i in sl)
print('true' if ok else 'false')
" 2>/dev/null)
[ "$SRC_CHECK" = "true" ] && log_pass "Sources preserved in session" || log_fail "Sources check: $SRC_CHECK"

# ============================================================================
# TEST 21: Each entry has single-block resolved text
# ============================================================================
echo ""
log_info "TEST 21: Each entry has single-block resolved text"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

# Add child → 2 entries (block 0 + block 0.0)
agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# Block 0 entry text is just block 0's content (no child text)
BLOCK_0_TEXT=$(agent-browser eval '
    const e = PU.state.previewMode.shortlist.find(e => e.sources[0].blockPath === "0");
    e ? e.text : ""
' 2>/dev/null | tr -d '"')
echo "$BLOCK_0_TEXT" | grep -qvi "urgent" && log_pass "Block 0 text does NOT contain child value 'urgent'" || log_fail "Block 0 text contains child content: $BLOCK_0_TEXT"

# Block 0.0 entry text contains 'urgent'
BLOCK_00_TEXT=$(agent-browser eval '
    const e = PU.state.previewMode.shortlist.find(e => e.sources[0].blockPath === "0.0");
    e ? e.text : ""
' 2>/dev/null | tr -d '"')
echo "$BLOCK_00_TEXT" | grep -qi "urgent" && log_pass "Block 0.0 text contains 'urgent'" || log_fail "Missing in: $BLOCK_00_TEXT"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 22: toggleVariation removes leaf entry (ancestor remains)
# ============================================================================
echo ""
log_info "TEST 22: toggleVariation removes leaf entry"

agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.3

# Should have 2 entries (block 0 + block 0.0)
BEFORE=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$BEFORE" = "2" ] && log_pass "2 entries before toggle" || log_fail "Before: $BEFORE"

# Get leaf (0.0) combo key
LEAF_KEY=$(agent-browser eval '
    const e = PU.state.previewMode.shortlist.find(e => e.sources[0].blockPath === "0.0");
    e ? e.sources[0].comboKey : ""
' 2>/dev/null | tr -d '"')

# Toggle off leaf — no descendants, no cascade
agent-browser eval "PU.shortlist.toggleVariation('0.0', '$LEAF_KEY')" 2>/dev/null
sleep 0.3

# Block 0 entry should remain
AFTER=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$AFTER" = "1" ] && log_pass "Leaf removed, ancestor remains (1 entry)" || log_fail "After toggle: $AFTER"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 23: Ancestor toggle with cascade confirmation
# ============================================================================
echo ""
log_info "TEST 23: Ancestor toggle cascades with confirm()"

# Add child → 2 entries (block 0 + block 0.0)
agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# Verify ancestor has entry
ANCESTOR_KEY=$(agent-browser eval '
    const e = PU.state.previewMode.shortlist.find(e => e.sources[0].blockPath === "0");
    e ? e.sources[0].comboKey : ""
' 2>/dev/null | tr -d '"')

HAS_ANCESTOR=$(agent-browser eval "PU.shortlist.has('0', '$ANCESTOR_KEY')" 2>/dev/null)
[ "$HAS_ANCESTOR" = "true" ] && log_pass "Ancestor block 0 has entry (green)" || log_fail "Ancestor missing: $HAS_ANCESTOR"

# Mock confirm() to return true (cascade)
agent-browser eval 'window._origConfirm = window.confirm; window.confirm = () => true' 2>/dev/null

# Toggle ancestor — should cascade-remove descendants too
agent-browser eval "PU.shortlist.toggleVariation('0', '$ANCESTOR_KEY')" 2>/dev/null
sleep 0.3

AFTER=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$AFTER" = "0" ] && log_pass "Cascade removed all entries (ancestor + descendants)" || log_fail "Entries remaining: $AFTER"

# Restore confirm
agent-browser eval 'window.confirm = window._origConfirm; delete window._origConfirm' 2>/dev/null

# ============================================================================
# TEST 24: Footer × removes only the specific entry
# ============================================================================
echo ""
log_info "TEST 24: Footer × removes only the specific entry"

# Add root entry directly (no ancestors)
agent-browser eval '
    PU.shortlist.clearAll();
    PU.state.previewMode.shortlist.push({ text: "Entry A", sources: [{blockPath: "0", comboKey: "p=1"}] });
    PU.state.previewMode.shortlist.push({ text: "Entry B", sources: [{blockPath: "0", comboKey: "p=2"}] });
    PU.shortlist._lookupSet = null;
    PU.shortlist.render();
' 2>/dev/null
sleep 0.3

BEFORE=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$BEFORE" = "2" ] && log_pass "Two entries added" || log_fail "Count: $BEFORE"

# Remove first entry — no descendants, no cascade
agent-browser eval 'PU.shortlist.remove("0", "p=1")' 2>/dev/null
sleep 0.3

AFTER=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$AFTER" = "1" ] && log_pass "Footer × removed only 1 entry (other remains)" || log_fail "After: $AFTER"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 25: Skip existing ancestors on second add
# ============================================================================
echo ""
log_info "TEST 25: Skip existing ancestors on second add"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

# First add: 0.0 → creates entries for block 0 + block 0.0
agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.3

FIRST_COUNT=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$FIRST_COUNT" = "2" ] && log_pass "First add: 2 entries (block 0 + 0.0)" || log_fail "First: $FIRST_COUNT"

# Second add: different 0.0 combo → block 0 already has entries → skip → just 1 new entry
agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "calm"}, {name: "audience", value: "team"}]);
' 2>/dev/null
sleep 0.3

SECOND_COUNT=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$SECOND_COUNT" = "3" ] && log_pass "Second add: 3 entries (ancestor skipped, +1 leaf)" || log_fail "Second: $SECOND_COUNT"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 26: Ancestor expansion with locks creates multiple entries
# ============================================================================
echo ""
log_info "TEST 26: Locked wildcards expand ancestor into multiple entries"

agent-browser eval '
    PU.state.previewMode.lockedValues["persona"] = ["CEO", "CTO"];
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# Block 0 should have 2+ entries (persona locked to 2 values)
BLOCK_0=$(agent-browser eval '
    PU.state.previewMode.shortlist.filter(e => e.sources[0].blockPath === "0").length
' 2>/dev/null)
[ "$BLOCK_0" -ge 2 ] 2>/dev/null && log_pass "Block 0 has $BLOCK_0 entries (locked persona expansion)" || log_fail "Block 0: $BLOCK_0"

# Block 0.0 should have 1 entry (leaf)
BLOCK_00=$(agent-browser eval '
    PU.state.previewMode.shortlist.filter(e => e.sources[0].blockPath === "0.0").length
' 2>/dev/null)
[ "$BLOCK_00" = "1" ] && log_pass "Block 0.0 has 1 entry (leaf)" || log_fail "Block 0.0: $BLOCK_00"

agent-browser eval '
    delete PU.state.previewMode.lockedValues["persona"];
    PU.shortlist.clearAll();
' 2>/dev/null
sleep 0.3

# ============================================================================
# TEST 27: Cascade confirm(false) keeps descendants
# ============================================================================
echo ""
log_info "TEST 27: Cascade confirm(false) removes only ancestor"

agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.3

# Mock confirm() to return false (no cascade)
agent-browser eval 'window._origConfirm = window.confirm; window.confirm = () => false' 2>/dev/null

ANCESTOR_KEY=$(agent-browser eval '
    const e = PU.state.previewMode.shortlist.find(e => e.sources[0].blockPath === "0");
    e ? e.sources[0].comboKey : ""
' 2>/dev/null | tr -d '"')

# Toggle ancestor off — confirm(false) = keep descendants
agent-browser eval "PU.shortlist.toggleVariation('0', '$ANCESTOR_KEY')" 2>/dev/null
sleep 0.3

# Block 0 entry removed, block 0.0 remains
REMAINING=$(agent-browser eval 'PU.state.previewMode.shortlist.length' 2>/dev/null)
[ "$REMAINING" = "1" ] && log_pass "Only ancestor removed (1 descendant remains)" || log_fail "Remaining: $REMAINING"

REMAINING_BP=$(agent-browser eval 'PU.state.previewMode.shortlist[0]?.sources[0]?.blockPath' 2>/dev/null | tr -d '"')
[ "$REMAINING_BP" = "0.0" ] && log_pass "Remaining entry is block 0.0" || log_fail "Remaining: $REMAINING_BP"

# Restore confirm
agent-browser eval 'window.confirm = window._origConfirm; delete window._origConfirm' 2>/dev/null
agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 28: Hover tip appears on mouseenter
# ============================================================================
echo ""
log_info "TEST 28: Hover tip appears on mouseenter"

# Trigger hover tip via JS
agent-browser eval '
    const v = document.querySelector("[data-testid=\"pu-shortlist-var\"][data-block-path=\"0.0\"]");
    if (v) PU.shortlist._showHoverTip(v.dataset.blockPath, v.dataset.comboKey, v.textContent.trim());
' 2>/dev/null
sleep 0.3

TIP_VISIBLE=$(agent-browser eval '
    const tip = document.querySelector("[data-testid=\"pu-footer-tip\"]");
    tip ? tip.classList.contains("visible") : "missing"
' 2>/dev/null | tr -d '"')
[ "$TIP_VISIBLE" = "true" ] && log_pass "Hover tip visible" || log_fail "Tip visible: $TIP_VISIBLE"

# Check content has ancestor chain format
TIP_TEXT=$(agent-browser eval '
    document.querySelector("[data-testid=\"pu-footer-tip\"]")?.textContent || ""
' 2>/dev/null | tr -d '"')
echo "$TIP_TEXT" | grep -q "click to add" && log_pass "Tip says 'click to add'" || log_fail "Tip text: $TIP_TEXT"
echo "$TIP_TEXT" | grep -q "0:" && log_pass "Tip shows ancestor '0:' count" || log_fail "Missing ancestor info: $TIP_TEXT"

# Hide hover tip
agent-browser eval 'PU.shortlist._hideHoverTip()' 2>/dev/null
sleep 0.2

TIP_AFTER=$(agent-browser eval '
    const tip = document.querySelector("[data-testid=\"pu-footer-tip\"]");
    tip ? tip.classList.contains("visible") : "missing"
' 2>/dev/null | tr -d '"')
[ "$TIP_AFTER" = "false" ] && log_pass "Hover tip hidden after mouseleave" || log_fail "Tip after: $TIP_AFTER"

# ============================================================================
# TEST 29: Hover tip shows "click to remove" for shortlisted variation
# ============================================================================
echo ""
log_info "TEST 29: Hover tip shows 'click to remove' when shortlisted"

# Add an entry for block 0
agent-browser eval '
    const v = document.querySelector("[data-testid=\"pu-shortlist-var\"][data-block-path=\"0\"]");
    if (v) v.click();
' 2>/dev/null
sleep 0.5

# Now hover the same variation — should say "click to remove"
agent-browser eval '
    const v = document.querySelector("[data-testid=\"pu-shortlist-var\"][data-block-path=\"0\"]");
    if (v) PU.shortlist._showHoverTip(v.dataset.blockPath, v.dataset.comboKey, v.textContent.trim());
' 2>/dev/null
sleep 0.3

TIP_TEXT=$(agent-browser eval '
    document.querySelector("[data-testid=\"pu-footer-tip\"]")?.textContent || ""
' 2>/dev/null | tr -d '"')
echo "$TIP_TEXT" | grep -q "click to remove" && log_pass "Tip says 'click to remove' for shortlisted" || log_fail "Tip: $TIP_TEXT"

agent-browser eval 'PU.shortlist._hideHoverTip(); PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 30: Tree view groups entries by block path
# ============================================================================
echo ""
log_info "TEST 30: Tree view groups entries by block path"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
sleep 0.3

agent-browser eval '
    PU.shortlist.add("0.0.0", [{name: "hook", value: "statistic"}]);
' 2>/dev/null
sleep 0.5

# Should have 3 groups: 0, 0.0, 0.0.0
GROUP_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-group").length
' 2>/dev/null)
[ "$GROUP_COUNT" = "3" ] && log_pass "3 tree groups (0, 0.0, 0.0.0)" || log_fail "Groups: $GROUP_COUNT"

# Each group has a path header
HEADER_COUNT=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-path-header").length
' 2>/dev/null)
[ "$HEADER_COUNT" = "3" ] && log_pass "3 path headers" || log_fail "Headers: $HEADER_COUNT"

# Path labels exist for each
LABELS=$(agent-browser eval '
    [...document.querySelectorAll(".pu-shortlist-path-label")].map(el => el.textContent).join(",")
' 2>/dev/null | tr -d '"')
echo "$LABELS" | grep -q "0.0.0" && log_pass "Path labels include 0.0.0" || log_fail "Labels: $LABELS"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 31: Full text includes ancestor prefix joined with ──
# ============================================================================
echo ""
log_info "TEST 31: Full text includes ancestor chain joined with ──"

agent-browser eval '
    PU.shortlist.add("0.0", [{name: "tone", value: "urgent"}, {name: "audience", value: "board"}]);
' 2>/dev/null
sleep 0.5

# Block 0.0 items should have full text with ── separator
ITEM_TEXT=$(agent-browser eval '
    const item = document.querySelector("[data-testid=\"pu-shortlist-item-0.0\"] .pu-shortlist-item-text");
    item ? item.textContent : ""
' 2>/dev/null | tr -d '"')

# The full text should contain ── (the separator between ancestor and leaf text)
echo "$ITEM_TEXT" | grep -q "──" && log_pass "Full text contains ── separator" || log_fail "Missing separator in: $ITEM_TEXT"

# Block 0 items should NOT have ── (root blocks have no ancestors)
ROOT_TEXT=$(agent-browser eval '
    const item = document.querySelector("[data-testid=\"pu-shortlist-item-0\"] .pu-shortlist-item-text");
    item ? item.textContent : ""
' 2>/dev/null | tr -d '"')
echo "$ROOT_TEXT" | grep -qv "──" && log_pass "Root block text has no ── prefix" || log_fail "Root has separator: $ROOT_TEXT"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 32: Click item toggles dim class
# ============================================================================
echo ""
log_info "TEST 32: Click item toggles dim class"

agent-browser eval '
    PU.shortlist.add("0", [{name: "persona", value: "CEO"}, {name: "format", value: "memo"}, {name: "topic", value: "retention"}]);
' 2>/dev/null
sleep 0.5

# Click the item to dim it
agent-browser eval '
    document.querySelector("[data-testid=\"pu-shortlist-item-0\"]")?.click();
' 2>/dev/null
sleep 0.3

HAS_DIMMED=$(agent-browser eval '
    !!document.querySelector(".pu-shortlist-item.pu-shortlist-dimmed")
' 2>/dev/null)
[ "$HAS_DIMMED" = "true" ] && log_pass "Click adds dim class" || log_fail "No dimmed class"

# Click again to un-dim
agent-browser eval '
    document.querySelector("[data-testid=\"pu-shortlist-item-0\"]")?.click();
' 2>/dev/null
sleep 0.3

NO_DIMMED=$(agent-browser eval '
    document.querySelectorAll(".pu-shortlist-item.pu-shortlist-dimmed").length
' 2>/dev/null)
[ "$NO_DIMMED" = "0" ] && log_pass "Second click removes dim class" || log_fail "Still dimmed: $NO_DIMMED"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# TEST 33: Click path header dims all items in that group
# ============================================================================
echo ""
log_info "TEST 33: Click path header dims all items in group"

agent-browser eval '
    PU.state.previewMode.shortlist = [];
    PU.state.previewMode.shortlist.push({ text: "Entry A", sources: [{blockPath: "0", comboKey: "p=CEO"}] });
    PU.state.previewMode.shortlist.push({ text: "Entry B", sources: [{blockPath: "0", comboKey: "p=CTO"}] });
    PU.shortlist._lookupSet = null;
    PU.shortlist.render();
' 2>/dev/null
sleep 0.3

# Click path header for block 0
agent-browser eval '
    document.querySelector("[data-testid=\"pu-shortlist-path-header-0\"]")?.click();
' 2>/dev/null
sleep 0.3

DIMMED_COUNT=$(agent-browser eval '
    document.querySelectorAll("[data-testid=\"pu-shortlist-group-0\"] .pu-shortlist-dimmed").length
' 2>/dev/null)
[ "$DIMMED_COUNT" = "2" ] && log_pass "Both items dimmed via path header" || log_fail "Dimmed: $DIMMED_COUNT"

# ============================================================================
# TEST 34: Click dimmed path header un-dims all
# ============================================================================
echo ""
log_info "TEST 34: Click dimmed path header un-dims all"

# Click again to un-dim
agent-browser eval '
    document.querySelector("[data-testid=\"pu-shortlist-path-header-0\"]")?.click();
' 2>/dev/null
sleep 0.3

UNDIMMED_COUNT=$(agent-browser eval '
    document.querySelectorAll("[data-testid=\"pu-shortlist-group-0\"] .pu-shortlist-dimmed").length
' 2>/dev/null)
[ "$UNDIMMED_COUNT" = "0" ] && log_pass "All items un-dimmed via path header" || log_fail "Still dimmed: $UNDIMMED_COUNT"

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

# Clear shortlist from session file to avoid polluting future page loads
api_call POST "$BASE_URL/api/pu/job/hiring-templates/session" '{"prompt_id": "stress-test-prompt", "data": {"composition": 1}}'

agent-browser eval 'PU.shortlist.clearAll()' 2>/dev/null
agent-browser close 2>/dev/null
log_pass "Browser closed"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
