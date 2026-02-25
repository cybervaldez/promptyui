#!/bin/bash
# ============================================================================
# E2E Test Suite: Annotation Examples (hiring-templates)
# ============================================================================
# Verifies that the hiring-templates job loads with annotations at all 3
# levels (defaults, prompt, block) and that the ext-sourcing-strategy prompt
# demonstrates full inheritance including null sentinel removal.
#
# Usage: ./tests/test_annotation_examples.sh [--port 8085]
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

print_header "Annotation Examples (hiring-templates)"

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

# ============================================================================
# TEST 1: API serves annotations for hiring-templates
# ============================================================================
echo ""
log_info "TEST 1: API serves hiring-templates with annotations"

api_call GET "$BASE_URL/api/pu/job/hiring-templates"
[ "$HTTP_CODE" = "200" ] \
    && log_pass "API returns hiring-templates (HTTP 200)" \
    || log_fail "API failed: HTTP $HTTP_CODE"

# Check defaults.annotations
DEFAULTS_ANN=$(json_get "$BODY" '.defaults.annotations.output_format' '')
[ "$DEFAULTS_ANN" = "professional" ] \
    && log_pass "defaults.annotations.output_format = professional" \
    || log_fail "defaults.annotations.output_format: $DEFAULTS_ANN"

DEFAULTS_AUD=$(json_get "$BODY" '.defaults.annotations.audience' '')
[ "$DEFAULTS_AUD" = "hiring-managers" ] \
    && log_pass "defaults.annotations.audience = hiring-managers" \
    || log_fail "defaults.annotations.audience: $DEFAULTS_AUD"

# ============================================================================
# TEST 2: API serves prompt-level annotations on ext-sourcing-strategy
# ============================================================================
echo ""
log_info "TEST 2: Prompt-level annotations on ext-sourcing-strategy"

# Extract ext-sourcing-strategy prompt
PROMPT_ANN=$(echo "$BODY" | ./venv/bin/python -c "
import json,sys
d=json.load(sys.stdin)
for p in d.get('prompts',[]):
    if p['id']=='ext-sourcing-strategy':
        print(json.dumps(p.get('annotations',{})))
        break
" 2>/dev/null)

echo "$PROMPT_ANN" | grep -q '"recruiters"' \
    && log_pass "prompt.annotations.audience = recruiters" \
    || log_fail "prompt.annotations.audience missing: $PROMPT_ANN"

echo "$PROMPT_ANN" | grep -q '"outbound"' \
    && log_pass "prompt.annotations.channel_priority = outbound" \
    || log_fail "prompt.annotations.channel_priority missing: $PROMPT_ANN"

# ============================================================================
# TEST 3: API serves block-level annotations with null sentinel
# ============================================================================
echo ""
log_info "TEST 3: Block-level annotations with null sentinel"

BLOCK_ANN=$(echo "$BODY" | ./venv/bin/python -c "
import json,sys
d=json.load(sys.stdin)
for p in d.get('prompts',[]):
    if p['id']=='ext-sourcing-strategy':
        for t in p.get('text',[]):
            if isinstance(t,dict):
                for a in t.get('after',[]):
                    if isinstance(a,dict) and a.get('annotations') is not None:
                        print(json.dumps(a['annotations']))
                        break
        break
" 2>/dev/null)

echo "$BLOCK_ANN" | grep -q '"actionable"' \
    && log_pass "block.annotations.detail_level = actionable" \
    || log_fail "block.annotations.detail_level missing: $BLOCK_ANN"

echo "$BLOCK_ANN" | grep -q '"output_format": null' \
    && log_pass "block.annotations.output_format = null (sentinel)" \
    || log_fail "block.annotations.output_format not null: $BLOCK_ANN"

# ============================================================================
# TEST 4: Non-annotated prompts still work (no annotations key)
# ============================================================================
echo ""
log_info "TEST 4: Non-annotated prompts have no annotations key"

JP_ANN=$(echo "$BODY" | ./venv/bin/python -c "
import json,sys
d=json.load(sys.stdin)
for p in d.get('prompts',[]):
    if p['id']=='job-posting':
        print('has_ann' if 'annotations' in p else 'no_ann')
        break
" 2>/dev/null)

[ "$JP_ANN" = "no_ann" ] \
    && log_pass "job-posting has no prompt-level annotations" \
    || log_fail "job-posting unexpectedly has annotations"

# ============================================================================
# TEST 5: Load ext-sourcing-strategy in browser
# ============================================================================
echo ""
log_info "TEST 5: Browser loads ext-sourcing-strategy with annotations"

agent-browser open "$BASE_URL/?job=hiring-templates&prompt=ext-sourcing-strategy" 2>/dev/null
sleep 4

# Verify page loaded
TITLE=$(agent-browser get title 2>/dev/null)
echo "$TITLE" | grep -qi "prompty" \
    && log_pass "Page loaded" \
    || log_fail "Page did not load: $TITLE"

# ============================================================================
# TEST 6: Defaults annotations loaded in JS state
# ============================================================================
echo ""
log_info "TEST 6: Defaults annotations in JS state"

DEF_ANN=$(agent-browser eval 'JSON.stringify((PU.helpers.getActiveJob().defaults || {}).annotations || {})' 2>/dev/null | decode_json)

echo "$DEF_ANN" | grep -q '"output_format"' \
    && log_pass "JS state has defaults.annotations.output_format" \
    || log_fail "JS state missing defaults.annotations.output_format: $DEF_ANN"

echo "$DEF_ANN" | grep -q '"audience"' \
    && log_pass "JS state has defaults.annotations.audience" \
    || log_fail "JS state missing defaults.annotations.audience: $DEF_ANN"

# ============================================================================
# TEST 7: Prompt annotations loaded in JS state
# ============================================================================
echo ""
log_info "TEST 7: Prompt annotations in JS state"

PROMPT_ANN_JS=$(agent-browser eval 'JSON.stringify((PU.helpers.getActivePrompt() || {}).annotations || {})' 2>/dev/null | decode_json)

echo "$PROMPT_ANN_JS" | grep -q '"recruiters"' \
    && log_pass "JS prompt annotations has audience=recruiters" \
    || log_fail "JS prompt annotations missing audience: $PROMPT_ANN_JS"

echo "$PROMPT_ANN_JS" | grep -q '"outbound"' \
    && log_pass "JS prompt annotations has channel_priority=outbound" \
    || log_fail "JS prompt annotations missing channel_priority: $PROMPT_ANN_JS"

# ============================================================================
# TEST 8: Prompt annotations section visible in right panel
# ============================================================================
echo ""
log_info "TEST 8: Right panel shows prompt annotations"

HAS_SECTION=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-rp-prompt-ann\"]")' 2>/dev/null)
[ "$HAS_SECTION" = "true" ] \
    && log_pass "Prompt annotations section exists in right panel" \
    || log_fail "Prompt annotations section missing"

# Check count
ANN_COUNT=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-rp-prompt-ann-count\"]")?.textContent?.trim()' 2>/dev/null | tr -d '"')
[ "$ANN_COUNT" = "(2)" ] \
    && log_pass "Prompt annotation count shows (2)" \
    || log_fail "Prompt annotation count: $ANN_COUNT (expected (2))"

# ============================================================================
# TEST 9: Annotation resolve computes inheritance correctly
# ============================================================================
echo ""
log_info "TEST 9: Annotation inheritance resolution"

# resolve() returns {computed, sources, removed, hasNullOverrides}
# Path "1.0" = second root block's first child (the after: block)
COMPUTED=$(agent-browser eval '
(function() {
    var prompt = PU.helpers.getActivePrompt();
    if (!prompt || !prompt.text) return "no_prompt";
    var resolved = PU.annotations.resolve("1.0", prompt, PU.helpers.getActiveJob());
    return JSON.stringify(resolved.computed || {});
})()
' 2>/dev/null | decode_json)

REMOVED=$(agent-browser eval '
(function() {
    var prompt = PU.helpers.getActivePrompt();
    var resolved = PU.annotations.resolve("1.0", prompt, PU.helpers.getActiveJob());
    return JSON.stringify(resolved.removed || {});
})()
' 2>/dev/null | decode_json)

# Check computed: audience should be "recruiters" (prompt overrides defaults)
echo "$COMPUTED" | grep -q '"recruiters"' \
    && log_pass "Resolved computed: audience=recruiters (prompt overrides defaults)" \
    || log_fail "Resolved computed audience not recruiters: $COMPUTED"

# Check computed: channel_priority should be "outbound" (from prompt)
echo "$COMPUTED" | grep -q '"outbound"' \
    && log_pass "Resolved computed: channel_priority=outbound (from prompt)" \
    || log_fail "Resolved computed channel_priority not outbound: $COMPUTED"

# Check computed: detail_level should be "actionable" (from block)
echo "$COMPUTED" | grep -q '"actionable"' \
    && log_pass "Resolved computed: detail_level=actionable (from block)" \
    || log_fail "Resolved computed detail_level not actionable: $COMPUTED"

# Check computed: output_format should NOT be in computed (null removes it)
echo "$COMPUTED" | grep -q '"output_format"' \
    && log_fail "Computed still has output_format (null should remove it)" \
    || log_pass "Resolved computed: output_format removed by null sentinel"

# Check removed: output_format should be in removed dict
echo "$REMOVED" | grep -q '"output_format"' \
    && log_pass "Resolved removed: output_format tracked in removed dict" \
    || log_fail "Resolved removed missing output_format: $REMOVED"

# ============================================================================
# TEST 10: Defaults popover shows annotations
# ============================================================================
echo ""
log_info "TEST 10: Defaults popover has annotations"

HAS_DEF_ANN=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-defaults-popover-ann\"]")' 2>/dev/null)
[ "$HAS_DEF_ANN" = "true" ] \
    && log_pass "Defaults popover annotation section exists" \
    || log_fail "Defaults popover annotation section missing"

# ============================================================================
# TEST 11: Other prompts inherit defaults but have no prompt-level annotations
# ============================================================================
echo ""
log_info "TEST 11: Non-annotated prompt inherits defaults only"

# Navigate to job-posting prompt
agent-browser open "$BASE_URL/?job=hiring-templates&prompt=job-posting" 2>/dev/null
sleep 3

JP_HAS_ANN=$(agent-browser eval '(PU.helpers.getActivePrompt() || {}).hasOwnProperty("annotations")' 2>/dev/null | tr -d '"')

[ "$JP_HAS_ANN" = "false" ] \
    && log_pass "job-posting has no prompt-level annotations" \
    || log_fail "job-posting unexpectedly has annotations property: $JP_HAS_ANN"

# But resolved should still inherit defaults
JP_RESOLVED=$(agent-browser eval '
(function() {
    var prompt = PU.helpers.getActivePrompt();
    var job = PU.helpers.getActiveJob();
    if (!prompt || !prompt.text) return "no_prompt";
    var resolved = PU.annotations.resolve("0", prompt, job);
    return JSON.stringify(resolved);
})()
' 2>/dev/null | decode_json)

echo "$JP_RESOLVED" | grep -q '"professional"' \
    && log_pass "job-posting block inherits defaults output_format=professional" \
    || log_fail "job-posting block missing inherited output_format: $JP_RESOLVED"

echo "$JP_RESOLVED" | grep -q '"hiring-managers"' \
    && log_pass "job-posting block inherits defaults audience=hiring-managers" \
    || log_fail "job-posting block missing inherited audience: $JP_RESOLVED"

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
