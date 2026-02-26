#!/bin/bash
# ============================================================================
# E2E Test Suite: CLI --tree Artifact Support
# ============================================================================
# Tests that the CLI --tree path produces artifacts identical to the WebUI:
#   - [ART] lines printed during execution
#   - [CONSUMED] lines for cross-block dependencies
#   - Manifest written to _artifacts/manifest.json
#   - Summary shows correct counts
#   - Failure cascade prints [FAIL] and [BLOCK] (no artifacts)
#
# Usage: ./tests/test_cli_tree_artifacts.sh
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON="$PROJECT_ROOT/venv/bin/python"
JOB_ID="test-fixtures"
JOB_DIR="$PROJECT_ROOT/jobs/$JOB_ID"
ARTIFACT_ROOT="$JOB_DIR/_artifacts"

setup_cleanup

print_header "CLI --tree Artifact Support"

# Helper: run CLI --tree and capture output
run_tree() {
    local prompt="$1"
    rm -rf "$ARTIFACT_ROOT"
    "$PYTHON" -c "
from src.cli.main import main
import sys
sys.argv = ['test', '$JOB_ID', '--tree', '-p', '$prompt', '-c', '0']
exit(main())
" 2>&1
}

# ============================================================================
# TEST 1: nested-blocks — artifacts printed inline and flushed to disk
# ============================================================================
echo ""
log_info "TEST 1: nested-blocks — artifacts printed inline and flushed to disk"

OUTPUT=$(run_tree "nested-blocks")
CLI_EXIT=$?

[ "$CLI_EXIT" = "0" ] \
    && log_pass "CLI exited 0 (success)" \
    || log_fail "CLI exited $CLI_EXIT (expected 0)"

# OBJECTIVE: [ART] lines appear during execution
ART_LINES=$(echo "$OUTPUT" | grep -c '\[ART\]')
[ "$ART_LINES" = "4" ] \
    && log_pass "[ART] lines: $ART_LINES (expected 4)" \
    || log_fail "[ART] lines: $ART_LINES (expected 4)"

# OBJECTIVE: Artifact name, mod_id, preview shown in [ART] line
echo "$OUTPUT" | grep -q '\[ART\].*output-0.0-0.txt.*(echo_generate)' \
    && log_pass "[ART] line has name + mod_id" \
    || log_fail "[ART] line missing name or mod_id"

# OBJECTIVE: Manifest written
[ -f "$ARTIFACT_ROOT/manifest.json" ] \
    && log_pass "manifest.json written" \
    || log_fail "manifest.json not found"

# OBJECTIVE: Manifest has version 3 (JSONL consolidation)
MANIFEST_VER=$(jq -r '.version' "$ARTIFACT_ROOT/manifest.json" 2>/dev/null)
[ "$MANIFEST_VER" = "3" ] \
    && log_pass "Manifest version: $MANIFEST_VER" \
    || log_fail "Manifest version unexpected: $MANIFEST_VER (expected 3)"

# OBJECTIVE: JSONL files written for each block (consolidated, not per-artifact)
[ -f "$ARTIFACT_ROOT/echo_generate/0.0.jsonl" ] \
    && log_pass "JSONL file: echo_generate/0.0.jsonl" \
    || log_fail "Missing JSONL file: echo_generate/0.0.jsonl"

# OBJECTIVE: Summary section printed
echo "$OUTPUT" | grep -qF -- '--- Artifacts ---' \
    && log_pass "Artifact summary section printed" \
    || log_fail "Artifact summary missing"

echo "$OUTPUT" | grep -q '4 artifact(s) across 2 block(s)' \
    && log_pass "Summary shows correct total: 4 across 2 blocks" \
    || log_fail "Summary total incorrect"

echo "$OUTPUT" | grep -q 'Manifest:' \
    && log_pass "Summary shows manifest path" \
    || log_fail "Summary missing manifest path"

# ============================================================================
# TEST 2: cross-block-pipeline — depends_on, artifact_consumed, upstream
# ============================================================================
echo ""
log_info "TEST 2: cross-block-pipeline — depends_on + artifact_consumed"

OUTPUT=$(run_tree "cross-block-pipeline")
CLI_EXIT=$?

[ "$CLI_EXIT" = "0" ] \
    && log_pass "CLI exited 0 (success)" \
    || log_fail "CLI exited $CLI_EXIT (expected 0)"

# OBJECTIVE: [CONSUMED] lines for cross-block data flow
CONSUMED_LINES=$(echo "$OUTPUT" | grep -c '\[CONSUMED\]')
[ "$CONSUMED_LINES" = "2" ] \
    && log_pass "[CONSUMED] lines: $CONSUMED_LINES (expected 2)" \
    || log_fail "[CONSUMED] lines: $CONSUMED_LINES (expected 2)"

echo "$OUTPUT" | grep -q '\[CONSUMED\].*Block 1.*from 0.0' \
    && log_pass "[CONSUMED] from 0.0" \
    || log_fail "[CONSUMED] from 0.0 missing"

echo "$OUTPUT" | grep -q '\[CONSUMED\].*Block 1.*from 0.1' \
    && log_pass "[CONSUMED] from 0.1" \
    || log_fail "[CONSUMED] from 0.1 missing"

# OBJECTIVE: 5 artifacts total (2+2+1)
ART_LINES=$(echo "$OUTPUT" | grep -c '\[ART\]')
[ "$ART_LINES" = "5" ] \
    && log_pass "[ART] lines: $ART_LINES (expected 5)" \
    || log_fail "[ART] lines: $ART_LINES (expected 5)"

echo "$OUTPUT" | grep -q '5 artifact(s) across 3 block(s)' \
    && log_pass "Summary: 5 artifacts across 3 blocks" \
    || log_fail "Summary total incorrect"

# OBJECTIVE: Block 1 artifact has upstream metadata in manifest
UPSTREAM_COUNT=$(jq -r '.blocks["1"].artifacts[0].upstream_source_count // 0' "$ARTIFACT_ROOT/manifest.json" 2>/dev/null)
[ "$UPSTREAM_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Block 1 artifact has upstream_source_count: $UPSTREAM_COUNT" \
    || log_fail "Block 1 artifact missing upstream_source_count"

# OBJECTIVE: depends_on preserved in manifest
DEPS=$(jq -r '.blocks["1"].depends_on | length' "$ARTIFACT_ROOT/manifest.json" 2>/dev/null)
[ "$DEPS" = "2" ] \
    && log_pass "Block 1 has 2 depends_on in manifest" \
    || log_fail "Block 1 depends_on count: $DEPS (expected 2)"

# ============================================================================
# TEST 3: fail-cascade-pipeline — failure cascade, no artifacts
# ============================================================================
echo ""
log_info "TEST 3: fail-cascade-pipeline — failure cascade, no artifacts"

OUTPUT=$(run_tree "fail-cascade-pipeline")
CLI_EXIT=$?

[ "$CLI_EXIT" = "1" ] \
    && log_pass "CLI exited 1 (failure)" \
    || log_fail "CLI exited $CLI_EXIT (expected 1)"

# OBJECTIVE: [FAIL] printed for block 0
echo "$OUTPUT" | grep -q '\[FAIL\].*0.*Forced failure' \
    && log_pass "[FAIL] line for block 0" \
    || log_fail "[FAIL] line missing"

# OBJECTIVE: Block 1 blocked (dependency failed)
echo "$OUTPUT" | grep -q '\[BLOCK\] 1 blocked (dependency failed)' \
    && log_pass "[BLOCK] 1 blocked (dependency failed)" \
    || log_fail "Block 1 blocked message missing"

# OBJECTIVE: No artifacts produced
ART_LINES=$(echo "$OUTPUT" | grep -c '\[ART\]')
[ "$ART_LINES" = "0" ] \
    && log_pass "No [ART] lines (pipeline failed)" \
    || log_fail "[ART] lines found in failed pipeline: $ART_LINES"

# OBJECTIVE: No artifact summary section
echo "$OUTPUT" | grep -qF -- '--- Artifacts ---' \
    && log_fail "Artifact summary should not appear on failure" \
    || log_pass "No artifact summary on failure"

# OBJECTIVE: Stats show failure
echo "$OUTPUT" | grep -q 'Failed:.*1' \
    && log_pass "Stats show 1 failed" \
    || log_fail "Stats missing failed count"

echo "$OUTPUT" | grep -q 'Blocked:.*1' \
    && log_pass "Stats show 1 blocked" \
    || log_fail "Stats missing blocked count"

# ============================================================================
# TEST 4: Prompt filtering — invalid prompt returns error
# ============================================================================
echo ""
log_info "TEST 4: Invalid prompt ID returns error"

OUTPUT=$(run_tree "nonexistent-prompt")
CLI_EXIT=$?

[ "$CLI_EXIT" = "1" ] \
    && log_pass "CLI exited 1 for invalid prompt" \
    || log_fail "CLI exited $CLI_EXIT (expected 1)"

echo "$OUTPUT" | grep -q 'No jobs found' \
    && log_pass "Error message: No jobs found" \
    || log_fail "Missing error message for invalid prompt"

# ============================================================================
# TEST 5: CLI and WebUI produce identical manifests
# ============================================================================
echo ""
log_info "TEST 5: CLI manifest matches WebUI manifest structure"

# Run CLI for cross-block to get a rich manifest
run_tree "cross-block-pipeline" > /dev/null 2>&1

# Check manifest has same structure as what WebUI expects
HAS_VERSION=$(jq -e '.version' "$ARTIFACT_ROOT/manifest.json" > /dev/null 2>&1 && echo "yes" || echo "no")
HAS_RUN=$(jq -e '.run.timestamp' "$ARTIFACT_ROOT/manifest.json" > /dev/null 2>&1 && echo "yes" || echo "no")
HAS_BLOCKS=$(jq -e '.blocks | keys | length' "$ARTIFACT_ROOT/manifest.json" > /dev/null 2>&1 && echo "yes" || echo "no")

[ "$HAS_VERSION" = "yes" ] \
    && log_pass "Manifest has .version" \
    || log_fail "Manifest missing .version"

[ "$HAS_RUN" = "yes" ] \
    && log_pass "Manifest has .run.timestamp" \
    || log_fail "Manifest missing .run.timestamp"

[ "$HAS_BLOCKS" = "yes" ] \
    && log_pass "Manifest has .blocks" \
    || log_fail "Manifest missing .blocks"

# All artifacts have disk_path
DISK_PATHS=$(jq '[.blocks[].artifacts[].disk_path | select(. != null and . != "")] | length' "$ARTIFACT_ROOT/manifest.json" 2>/dev/null)
[ "$DISK_PATHS" = "5" ] \
    && log_pass "All 5 artifacts have disk_path in manifest" \
    || log_fail "disk_path count: $DISK_PATHS (expected 5)"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

log_pass "Cleanup complete"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
