#!/bin/bash
# ============================================================================
# E2E Test Suite: Annotation Persistence (Phase 1)
# ============================================================================
# Tests 3-layer annotation inheritance (defaults → prompt → block),
# null sentinel removal, computed badge, source-aware editor, and YAML
# round-trip persistence.
#
# Usage: ./tests/test_annotation_persistence.sh [--port 8085]
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
# agent-browser wraps JSON.stringify results in string encoding: "{\"key\":\"val\"}"
# This strips outer quotes and unescapes inner quotes
decode_json() {
    sed 's/^"//;s/"$//' | sed 's/\\"/"/g'
}

print_header "Annotation Persistence (Phase 1)"

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
# This prompt has: defaults.annotations={quality:strict, audience:general}
#                  prompt.annotations={audience:technical}
#                  block[0].annotations={quality:null, tone:conversational}
agent-browser open "$BASE_URL/?job=test-fixtures&prompt=nested-blocks" 2>/dev/null
sleep 3

# ============================================================================
# TEST 1: PU.annotations.resolve exists
# ============================================================================
echo ""
log_info "TEST 1: resolve() function exists"

HAS_RESOLVE=$(agent-browser eval 'typeof PU.annotations.resolve' 2>/dev/null | tr -d '"')
[ "$HAS_RESOLVE" = "function" ] \
    && log_pass "PU.annotations.resolve is a function" \
    || log_fail "PU.annotations.resolve not found: $HAS_RESOLVE"

# ============================================================================
# TEST 2: Defaults annotations loaded from YAML
# ============================================================================
echo ""
log_info "TEST 2: Defaults annotations loaded"

DEFAULTS_ANN=$(agent-browser eval 'JSON.stringify((PU.helpers.getActiveJob().defaults || {}).annotations || {})' 2>/dev/null | decode_json)
echo "$DEFAULTS_ANN" | grep -q '"quality"' \
    && log_pass "defaults.annotations has quality" \
    || log_fail "defaults.annotations missing quality: $DEFAULTS_ANN"

echo "$DEFAULTS_ANN" | grep -q '"audience"' \
    && log_pass "defaults.annotations has audience" \
    || log_fail "defaults.annotations missing audience: $DEFAULTS_ANN"

# ============================================================================
# TEST 3: Prompt-level annotations loaded from YAML
# ============================================================================
echo ""
log_info "TEST 3: Prompt-level annotations loaded"

PROMPT_ANN=$(agent-browser eval 'JSON.stringify(PU.helpers.getActivePrompt().annotations || {})' 2>/dev/null | decode_json)
echo "$PROMPT_ANN" | grep -q '"technical"' \
    && log_pass "prompt.annotations has audience=technical" \
    || log_fail "prompt.annotations wrong: $PROMPT_ANN"

# ============================================================================
# TEST 4: Block-level annotations loaded (including null sentinel)
# ============================================================================
echo ""
log_info "TEST 4: Block-level annotations loaded"

BLOCK_ANN=$(agent-browser eval 'var p = PU.helpers.getActivePrompt(); var b = PU.blocks.findBlockByPath(p.text, "0"); JSON.stringify(b.annotations || {})' 2>/dev/null | decode_json)
echo "$BLOCK_ANN" | grep -q '"tone"' \
    && log_pass "block.annotations has tone" \
    || log_fail "block.annotations missing tone: $BLOCK_ANN"

echo "$BLOCK_ANN" | grep -q '"quality":null' \
    && log_pass "block.annotations has quality=null (sentinel)" \
    || log_fail "block.annotations missing null sentinel: $BLOCK_ANN"

# ============================================================================
# TEST 5: resolve() computes correct merged annotations for block 0
# ============================================================================
echo ""
log_info "TEST 5: resolve() computes inheritance for block 0"

RESOLVED=$(agent-browser eval 'JSON.stringify(PU.annotations.resolve("0"))' 2>/dev/null | decode_json)

# quality should be REMOVED (null override)
echo "$RESOLVED" | grep -q '"hasNullOverrides":true' \
    && log_pass "hasNullOverrides=true (quality removed)" \
    || log_fail "hasNullOverrides should be true: $RESOLVED"

# audience should be "technical" (from prompt, overrides defaults)
echo "$RESOLVED" | grep -q '"audience":"technical"' \
    && log_pass "audience=technical (prompt overrides defaults)" \
    || log_fail "audience wrong in computed: $RESOLVED"

# tone should be "conversational" (from block)
echo "$RESOLVED" | grep -q '"tone":"conversational"' \
    && log_pass "tone=conversational (from block)" \
    || log_fail "tone wrong in computed: $RESOLVED"

# quality should NOT be in computed (null removed it)
COMPUTED_KEYS=$(agent-browser eval 'Object.keys(PU.annotations.resolve("0").computed).join(",")' 2>/dev/null | tr -d '"')
echo "$COMPUTED_KEYS" | grep -qv "quality" \
    && log_pass "quality not in computed (null removed)" \
    || log_fail "quality should not be in computed: $COMPUTED_KEYS"

# ============================================================================
# TEST 6: resolve() for child block (inherits defaults+prompt only, NOT parent block)
# ============================================================================
echo ""
log_info "TEST 6: Child block inherits defaults+prompt, not parent block"

CHILD_RESOLVED=$(agent-browser eval 'JSON.stringify(PU.annotations.resolve("0.0"))' 2>/dev/null | decode_json)

# Child should have quality=strict (from defaults, parent null doesn't cascade)
echo "$CHILD_RESOLVED" | grep -q '"quality":"strict"' \
    && log_pass "Child has quality=strict (from defaults, no cascade)" \
    || log_fail "Child quality wrong: $CHILD_RESOLVED"

# Child should have audience=technical (from prompt)
echo "$CHILD_RESOLVED" | grep -q '"audience":"technical"' \
    && log_pass "Child has audience=technical (from prompt)" \
    || log_fail "Child audience wrong: $CHILD_RESOLVED"

# Child should NOT have tone (block-level, does not cascade)
echo "$CHILD_RESOLVED" | grep -qv '"tone"' \
    && log_pass "Child does not have tone (no block cascade)" \
    || log_fail "Child should not have tone: $CHILD_RESOLVED"

# ============================================================================
# TEST 7: computedCount returns correct numbers
# ============================================================================
echo ""
log_info "TEST 7: computedCount()"

COUNT_0=$(agent-browser eval 'JSON.stringify(PU.annotations.computedCount("0"))' 2>/dev/null | decode_json)
echo "$COUNT_0" | grep -q '"count":2' \
    && log_pass "Block 0: count=2 (audience+tone)" \
    || log_fail "Block 0 count wrong: $COUNT_0"

COUNT_00=$(agent-browser eval 'JSON.stringify(PU.annotations.computedCount("0.0"))' 2>/dev/null | decode_json)
echo "$COUNT_00" | grep -q '"count":2' \
    && log_pass "Block 0.0: count=2 (quality+audience)" \
    || log_fail "Block 0.0 count wrong: $COUNT_00"

# ============================================================================
# TEST 8: Annotation badge shows computed count
# ============================================================================
echo ""
log_info "TEST 8: Badge shows computed count"

BADGE_COUNT=$(agent-browser eval 'var b = document.querySelector(".pu-ann-count"); b ? b.textContent : "NONE"' 2>/dev/null | tr -d '"')
[ "$BADGE_COUNT" = "2" ] \
    && log_pass "Badge shows computed count: 2" \
    || log_fail "Badge count wrong: $BADGE_COUNT"

# ============================================================================
# TEST 9: Badge has amber tint for null overrides
# ============================================================================
echo ""
log_info "TEST 9: Badge amber tint for overrides"

HAS_OVERRIDE_CLASS=$(agent-browser eval 'var b = document.querySelector(".pu-annotation-badge"); b ? b.classList.contains("has-overrides") : false' 2>/dev/null)
[ "$HAS_OVERRIDE_CLASS" = "true" ] \
    && log_pass "Badge has has-overrides class" \
    || log_fail "Badge missing has-overrides class: $HAS_OVERRIDE_CLASS"

# ============================================================================
# TEST 10: Annotation editor shows inherited rows with source badges
# ============================================================================
echo ""
log_info "TEST 10: Editor shows inheritance"

agent-browser eval 'PU.annotations.openEditor("0"); "opened"' 2>/dev/null
sleep 1

# Check source badges exist
SOURCE_COUNT=$(agent-browser eval 'document.querySelectorAll(".pu-ann-source").length' 2>/dev/null | tr -d '"')
[ "$SOURCE_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Source badges rendered: $SOURCE_COUNT" \
    || log_fail "No source badges: $SOURCE_COUNT"

# Check for inherited row
HAS_INHERITED=$(agent-browser eval 'document.querySelectorAll(".pu-ann-inherited").length' 2>/dev/null | tr -d '"')
[ "$HAS_INHERITED" -gt 0 ] 2>/dev/null \
    && log_pass "Inherited rows rendered: $HAS_INHERITED" \
    || log_fail "No inherited rows: $HAS_INHERITED"

# Check for removed row (strikethrough)
HAS_REMOVED=$(agent-browser eval 'document.querySelectorAll(".pu-ann-removed").length' 2>/dev/null | tr -d '"')
[ "$HAS_REMOVED" -gt 0 ] 2>/dev/null \
    && log_pass "Removed rows rendered: $HAS_REMOVED" \
    || log_fail "No removed rows: $HAS_REMOVED"

# Check for restore button
HAS_RESTORE=$(agent-browser eval 'document.querySelectorAll(".pu-ann-restore").length' 2>/dev/null | tr -d '"')
[ "$HAS_RESTORE" -gt 0 ] 2>/dev/null \
    && log_pass "Restore button present: $HAS_RESTORE" \
    || log_fail "No restore button: $HAS_RESTORE"

agent-browser eval 'PU.annotations.closeEditor("0"); "closed"' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 11: YAML round-trip (API export includes annotations)
# ============================================================================
echo ""
log_info "TEST 11: YAML export includes annotations"

YAML_RESULT=$(curl -sf "$BASE_URL/api/pu/export" \
    -H "Content-Type: application/json" \
    -d '{"job_id":"test-fixtures","dry_run":true}' 2>/dev/null)

YAML_CONTENT=$(echo "$YAML_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('yaml',''))" 2>/dev/null)

echo "$YAML_CONTENT" | grep -q "quality: strict" \
    && log_pass "YAML has defaults quality: strict" \
    || log_fail "YAML missing defaults quality"

echo "$YAML_CONTENT" | grep -q "audience: general" \
    && log_pass "YAML has defaults audience: general" \
    || log_fail "YAML missing defaults audience"

echo "$YAML_CONTENT" | grep -q "audience: technical" \
    && log_pass "YAML has prompt audience: technical" \
    || log_fail "YAML missing prompt audience"

echo "$YAML_CONTENT" | grep -q "tone: conversational" \
    && log_pass "YAML has block tone: conversational" \
    || log_fail "YAML missing block tone"

# ============================================================================
# TEST 12: Restore null override
# ============================================================================
echo ""
log_info "TEST 12: Restore null override"

agent-browser eval 'PU.annotations.openEditor("0"); "opened"' 2>/dev/null
sleep 1

# Click restore on the null-overridden annotation
agent-browser eval 'var btn = document.querySelector(".pu-ann-restore"); if (btn) btn.click(); "clicked"' 2>/dev/null
sleep 0.5

# quality should now be back in computed
AFTER_RESTORE=$(agent-browser eval 'JSON.stringify(PU.annotations.resolve("0").computed)' 2>/dev/null | decode_json)
echo "$AFTER_RESTORE" | grep -q '"quality"' \
    && log_pass "quality restored after clicking restore" \
    || log_fail "quality not restored: $AFTER_RESTORE"

agent-browser eval 'PU.annotations.closeEditor("0"); "closed"' 2>/dev/null
sleep 0.5

# ============================================================================
# TEST 13: Set null override via editor
# ============================================================================
echo ""
log_info "TEST 13: Set null override"

# First restore original state (quality=null on block)
agent-browser eval 'var p = PU.editor.getModifiedPrompt(); var b = PU.blocks.findBlockByPath(p.text, "0"); if (!b.annotations) b.annotations = {}; b.annotations.quality = null; "set"' 2>/dev/null

AFTER_NULL=$(agent-browser eval 'JSON.stringify(PU.annotations.resolve("0").computed)' 2>/dev/null | decode_json)
echo "$AFTER_NULL" | grep -qv '"quality"' \
    && log_pass "quality removed after setting null" \
    || log_fail "quality should not be in computed: $AFTER_NULL"

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
