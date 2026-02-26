#!/bin/bash
# ============================================================================
# E2E Test Suite: Cross-Block Artifact Flow
# ============================================================================
# Tests the cross-block dependency system: depends_on, upstream_artifacts,
# per-block disk flush, artifact_consumed events, and failure cascade.
#
# Uses the "cross-block-pipeline" prompt in test-fixtures which has:
#   Block 0.0: "Generate photo/sketch image variation A" (2 compositions)
#   Block 0.1: "Generate photo/sketch image variation B" (2 compositions)
#   Block 1:   "Upscale collected images" (1 composition, depends_on 0.0+0.1)
#
# Usage: ./tests/test_cross_block_artifacts.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"
JOB_ID="test-fixtures"
PROMPT_ID="cross-block-pipeline"
SSE_URL="$BASE_URL/api/pu/job/$JOB_ID/pipeline/run?prompt_id=$PROMPT_ID"

setup_cleanup

print_header "Cross-Block Artifact Flow"

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

# Clean previous artifacts
rm -rf "$(cd "$SCRIPT_DIR/.." && pwd)/jobs/$JOB_ID/_artifacts"

# ============================================================================
# TEST 1: SSE stream — execution order respects depends_on
# ============================================================================
echo ""
log_info "TEST 1: Execution order respects depends_on (0.0 -> 0.1 -> 1)"

# Capture SSE output
SSE_OUTPUT=$(curl -sf --max-time 30 "$SSE_URL" 2>&1)

# Extract block_start events in order using jq
BLOCK_START_ORDER=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    if [ "$TYPE" = "block_start" ]; then
        echo "$DATA" | jq -r '.block_path' 2>/dev/null
    fi
done | tr '\n' ',')

# Block 0.0 and 0.1 must appear before block 1
echo "$BLOCK_START_ORDER" | grep -q '0\.0.*0\.1.*1' \
    && log_pass "Execution order correct: $BLOCK_START_ORDER" \
    || log_fail "Execution order wrong: $BLOCK_START_ORDER (expected 0.0,0.1 before 1)"

# ============================================================================
# TEST 2: init event has all 3 block paths
# ============================================================================
echo ""
log_info "TEST 2: Block paths include all 3 blocks"

INIT_DATA=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    if [ "$TYPE" = "init" ]; then
        echo "$DATA"
        break
    fi
done)

echo "$INIT_DATA" | jq -e '.block_paths | index("0.0")' > /dev/null 2>&1 \
    && log_pass "init contains block 0.0" \
    || log_fail "init missing block 0.0"
echo "$INIT_DATA" | jq -e '.block_paths | index("0.1")' > /dev/null 2>&1 \
    && log_pass "init contains block 0.1" \
    || log_fail "init missing block 0.1"
echo "$INIT_DATA" | jq -e '.block_paths | index("1")' > /dev/null 2>&1 \
    && log_pass "init contains block 1" \
    || log_fail "init missing block 1"

# ============================================================================
# TEST 3: artifact_consumed events emitted
# ============================================================================
echo ""
log_info "TEST 3: artifact_consumed events emitted for dependency blocks"

CONSUMED_EVENTS=$(echo "$SSE_OUTPUT" | grep -c 'event: artifact_consumed')
[ "$CONSUMED_EVENTS" -gt 0 ] 2>/dev/null \
    && log_pass "artifact_consumed events found: $CONSUMED_EVENTS" \
    || log_fail "No artifact_consumed events found"

# Extract consuming_block from first artifact_consumed event using jq
CONSUMING_BLOCK=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    if [ "$TYPE" = "artifact_consumed" ]; then
        echo "$DATA" | jq -r '.consuming_block' 2>/dev/null
        break
    fi
done)
[ "$CONSUMING_BLOCK" = "1" ] \
    && log_pass "artifact_consumed consuming_block is '1'" \
    || log_fail "artifact_consumed consuming_block unexpected: '$CONSUMING_BLOCK'"

# ============================================================================
# TEST 4: Block 1 hook received upstream_artifacts
# ============================================================================
echo ""
log_info "TEST 4: Block 1 hook received upstream_artifacts"

# Block 1's artifact should exist in the SSE stream
BLOCK1_ARTIFACT=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    BP=$(echo "$DATA" | jq -r '.block_path // empty' 2>/dev/null)
    if [ "$TYPE" = "artifact" ] && [ "$BP" = "1" ]; then
        echo "$DATA"
        break
    fi
done)
[ -n "$BLOCK1_ARTIFACT" ] \
    && log_pass "Block 1 produced an artifact via SSE" \
    || log_fail "Block 1 did not produce an artifact"

# ============================================================================
# TEST 5: Per-block disk flush — files written for each block
# ============================================================================
echo ""
log_info "TEST 5: Per-block disk flush with artifact locator contract"

ARTIFACT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)/jobs/$JOB_ID/_artifacts"

# Check JSONL files: _artifacts/{mod_id}/{block_path}.jsonl (consolidated)
[ -f "$ARTIFACT_ROOT/echo_generate/0.0.jsonl" ] \
    && log_pass "JSONL file exists: echo_generate/0.0.jsonl" \
    || log_fail "Missing JSONL file: echo_generate/0.0.jsonl"

[ -f "$ARTIFACT_ROOT/echo_generate/0.1.jsonl" ] \
    && log_pass "JSONL file exists: echo_generate/0.1.jsonl" \
    || log_fail "Missing JSONL file: echo_generate/0.1.jsonl"

[ -f "$ARTIFACT_ROOT/echo_generate/1.jsonl" ] \
    && log_pass "JSONL file exists: echo_generate/1.jsonl" \
    || log_fail "Missing JSONL file: echo_generate/1.jsonl"

# Verify JSONL content matches preview (read first line of block 1's JSONL)
CONTENT=$(head -1 "$ARTIFACT_ROOT/echo_generate/1.jsonl" 2>/dev/null | jq -r '.content // empty' 2>/dev/null)
echo "$CONTENT" | grep -qi "upscale" \
    && log_pass "Upscaler artifact content correct: $CONTENT" \
    || log_fail "Upscaler artifact content unexpected: $CONTENT"

# ============================================================================
# TEST 6: Manifest v2 with run metadata and depends_on
# ============================================================================
echo ""
log_info "TEST 6: Manifest v3 structure with depends_on"

api_call GET "$BASE_URL/api/pu/job/$JOB_ID/artifacts"

[ "$HTTP_CODE" = "200" ] \
    && log_pass "Artifacts API returned 200" \
    || log_fail "Artifacts API returned $HTTP_CODE"

# Version 3 (JSONL consolidation)
MANIFEST_VERSION=$(echo "$BODY" | jq -r '.version // empty' 2>/dev/null)
[ "$MANIFEST_VERSION" = "3" ] \
    && log_pass "Manifest version 3" \
    || log_fail "Manifest version unexpected: $MANIFEST_VERSION (expected 3)"

# Run metadata
RUN_TIMESTAMP=$(echo "$BODY" | jq -r '.run.timestamp // empty' 2>/dev/null)
[ -n "$RUN_TIMESTAMP" ] \
    && log_pass "Manifest has run.timestamp" \
    || log_fail "Manifest missing run.timestamp"

BLOCKS_COMPLETE=$(echo "$BODY" | jq -r '.run.blocks_complete // 0' 2>/dev/null)
[ "$BLOCKS_COMPLETE" = "3" ] \
    && log_pass "run.blocks_complete is 3" \
    || log_fail "run.blocks_complete unexpected: $BLOCKS_COMPLETE"

# Block 1 has depends_on in manifest
BLOCK1_DEPS=$(echo "$BODY" | jq -r '.blocks["1"].depends_on // [] | length' 2>/dev/null)
[ "$BLOCK1_DEPS" = "2" ] \
    && log_pass "Block 1 has 2 depends_on entries in manifest" \
    || log_fail "Block 1 depends_on count unexpected: $BLOCK1_DEPS"

# Total artifact count: 2 (block 0.0) + 2 (block 0.1) + 1 (block 1) = 5
TOTAL_ARTIFACTS=$(echo "$BODY" | jq '[.blocks[].count] | add // 0' 2>/dev/null)
[ "$TOTAL_ARTIFACTS" = "5" ] \
    && log_pass "Total artifacts: $TOTAL_ARTIFACTS (2+2+1)" \
    || log_fail "Total artifacts unexpected: $TOTAL_ARTIFACTS"

# ============================================================================
# TEST 7: disk_path field set on artifacts
# ============================================================================
echo ""
log_info "TEST 7: Artifact locator contract (disk_path field)"

DISK_PATHS=$(echo "$BODY" | jq '[.blocks[].artifacts[].disk_path | select(. != null and . != "")] | length' 2>/dev/null)
[ "$DISK_PATHS" = "5" ] \
    && log_pass "All 5 artifacts have disk_path" \
    || log_fail "disk_path count unexpected: $DISK_PATHS"

# Check path format: _artifacts/{mod_id}/{block_path}.jsonl (JSONL consolidation)
SAMPLE_PATH=$(echo "$BODY" | jq -r '.blocks["1"].artifacts[0].disk_path // empty' 2>/dev/null)
echo "$SAMPLE_PATH" | grep -q '_artifacts/echo_generate/1.jsonl' \
    && log_pass "disk_path format correct: $SAMPLE_PATH" \
    || log_fail "disk_path format unexpected: $SAMPLE_PATH"

# ============================================================================
# TEST 8: Upstream metadata preserved on artifacts
# ============================================================================
echo ""
log_info "TEST 8: Upstream metadata preserved (custom keys not stripped)"

# Block 1's artifact should have upstream_source_count (custom key from hook)
UPSTREAM_COUNT=$(echo "$BODY" | jq -r '.blocks["1"].artifacts[0].upstream_source_count // 0' 2>/dev/null)
[ "$UPSTREAM_COUNT" -gt 0 ] 2>/dev/null \
    && log_pass "Block 1 artifact has upstream_source_count: $UPSTREAM_COUNT" \
    || log_fail "Block 1 artifact missing upstream_source_count"

# Block 1's artifact should list upstream blocks
UPSTREAM_BLOCKS=$(echo "$BODY" | jq -r '.blocks["1"].artifacts[0].upstream_blocks // [] | length' 2>/dev/null)
[ "$UPSTREAM_BLOCKS" = "2" ] \
    && log_pass "Block 1 artifact references 2 upstream blocks" \
    || log_fail "Block 1 upstream_blocks count unexpected: $UPSTREAM_BLOCKS"

# ============================================================================
# TEST 9: run_complete stats include all blocks
# ============================================================================
echo ""
log_info "TEST 9: run_complete stats consistency"

# Parse run_complete stats using jq
RUN_COMPLETE_DATA=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    if [ "$TYPE" = "run_complete" ]; then
        echo "$DATA"
        break
    fi
done)

STATS_BLOCKS=$(echo "$RUN_COMPLETE_DATA" | jq -r '.stats.blocks_total // empty' 2>/dev/null)
STATS_COMPLETE=$(echo "$RUN_COMPLETE_DATA" | jq -r '.stats.blocks_complete // empty' 2>/dev/null)
STATS_TOTAL=$(echo "$RUN_COMPLETE_DATA" | jq -r '.stats.artifacts_total // empty' 2>/dev/null)

[ "$STATS_BLOCKS" = "3" ] \
    && log_pass "stats.blocks_total: 3" \
    || log_fail "stats.blocks_total unexpected: '$STATS_BLOCKS'"

[ "$STATS_COMPLETE" = "3" ] \
    && log_pass "stats.blocks_complete: 3" \
    || log_fail "stats.blocks_complete unexpected: '$STATS_COMPLETE'"

[ "$STATS_TOTAL" = "5" ] \
    && log_pass "stats.artifacts_total: 5" \
    || log_fail "stats.artifacts_total unexpected: '$STATS_TOTAL'"

# ============================================================================
# TEST 10: SSE artifact events have disk_path field
# ============================================================================
echo ""
log_info "TEST 10: SSE artifact events include disk_path field"

ARTIFACT_WITH_DISK=$(echo "$SSE_OUTPUT" | grep '^data:' | grep '"artifact"' | grep -c '"disk_path"')
[ "$ARTIFACT_WITH_DISK" -gt 0 ] 2>/dev/null \
    && log_pass "SSE artifact events include disk_path field: $ARTIFACT_WITH_DISK events" \
    || log_fail "SSE artifact events missing disk_path field"

# ============================================================================
# TEST 11: Artifact file serving API returns actual file content
# ============================================================================
echo ""
log_info "TEST 11: Artifact file serving via disk_path (JSONL)"

# Get disk_path and disk_line from manifest for block 0.0's first artifact
DISK_PATH_00=$(echo "$BODY" | jq -r '.blocks["0.0"].artifacts[0].disk_path // empty' 2>/dev/null)
DISK_LINE_00=$(echo "$BODY" | jq -r '.blocks["0.0"].artifacts[0].disk_line // 0' 2>/dev/null)
if [ -n "$DISK_PATH_00" ]; then
    # Strip _artifacts/ prefix to get the URL path segment, add ?line=N
    URL_PATH=$(echo "$DISK_PATH_00" | sed 's|^_artifacts/||')
    api_call GET "$BASE_URL/api/pu/job/$JOB_ID/artifacts/${URL_PATH}?line=${DISK_LINE_00}"
    [ "$HTTP_CODE" = "200" ] \
        && log_pass "JSONL line served: HTTP 200 for ${URL_PATH}?line=${DISK_LINE_00}" \
        || log_fail "JSONL line serve failed: HTTP $HTTP_CODE for ${URL_PATH}?line=${DISK_LINE_00}"

    # Verify content is non-empty JSON with content field
    LINE_CONTENT=$(echo "$BODY" | jq -r '.content // empty' 2>/dev/null)
    [ -n "$LINE_CONTENT" ] \
        && log_pass "JSONL line has content: ${LINE_CONTENT:0:60}" \
        || log_fail "JSONL line content is empty"
else
    log_fail "No disk_path found for block 0.0 artifact"
fi

# Test 404 for non-existent artifact
api_call GET "$BASE_URL/api/pu/job/$JOB_ID/artifacts/fake_mod/nonexistent.txt"
[ "$HTTP_CODE" = "404" ] \
    && log_pass "Non-existent artifact returns 404" \
    || log_fail "Non-existent artifact returned: $HTTP_CODE"

# ============================================================================
# TEST 12: Multiple artifact_consumed events (one per dependency relationship)
# ============================================================================
echo ""
log_info "TEST 12: artifact_consumed events — one per dependency block"

# Count artifact_consumed events with jq (more reliable)
CONSUMED_DETAILS=$(echo "$SSE_OUTPUT" | grep '^data:' | while read -r line; do
    DATA="${line#data: }"
    TYPE=$(echo "$DATA" | jq -r '.type // empty' 2>/dev/null)
    if [ "$TYPE" = "artifact_consumed" ]; then
        SRC=$(echo "$DATA" | jq -r '.source_block' 2>/dev/null)
        CNT=$(echo "$DATA" | jq -r '.artifact_count' 2>/dev/null)
        echo "source=$SRC,count=$CNT"
    fi
done)

CONSUMED_COUNT=$(echo "$CONSUMED_DETAILS" | grep -c 'source=')
[ "$CONSUMED_COUNT" -ge 2 ] 2>/dev/null \
    && log_pass "artifact_consumed events: $CONSUMED_COUNT (expected >= 2)" \
    || log_fail "artifact_consumed events: $CONSUMED_COUNT (expected >= 2)"

# Verify source blocks include both 0.0 and 0.1
echo "$CONSUMED_DETAILS" | grep -q 'source=0.0' \
    && log_pass "artifact_consumed includes source_block 0.0" \
    || log_fail "artifact_consumed missing source_block 0.0"
echo "$CONSUMED_DETAILS" | grep -q 'source=0.1' \
    && log_pass "artifact_consumed includes source_block 0.1" \
    || log_fail "artifact_consumed missing source_block 0.1"

# ============================================================================
# TEST 13: Manifest re-run idempotency (timestamp changes, no accumulation)
# ============================================================================
echo ""
log_info "TEST 13: Manifest re-run idempotency"

# Capture timestamp from first run
TIMESTAMP_1=$(echo "$BODY" | jq -r '.run.timestamp // 0' 2>/dev/null)

# Wait to ensure time difference
sleep 1

# Re-run the pipeline
SSE_OUTPUT_2=$(curl -sf --max-time 30 "$SSE_URL" 2>&1)

# Fetch fresh manifest
api_call GET "$BASE_URL/api/pu/job/$JOB_ID/artifacts"
TIMESTAMP_2=$(echo "$BODY" | jq -r '.run.timestamp // 0' 2>/dev/null)

# Timestamp must be different (newer)
if [ -n "$TIMESTAMP_1" ] && [ -n "$TIMESTAMP_2" ]; then
    # Compare as floats: T2 > T1
    IS_NEWER=$(echo "$TIMESTAMP_1 $TIMESTAMP_2" | awk '{print ($2 > $1) ? "yes" : "no"}')
    [ "$IS_NEWER" = "yes" ] \
        && log_pass "Manifest timestamp updated: $TIMESTAMP_1 -> $TIMESTAMP_2" \
        || log_fail "Manifest timestamp not updated: $TIMESTAMP_1 vs $TIMESTAMP_2"
fi

# Artifact count must be same (not accumulated)
RERUN_TOTAL=$(echo "$BODY" | jq '[.blocks[].count] | add // 0' 2>/dev/null)
[ "$RERUN_TOTAL" = "5" ] \
    && log_pass "Re-run artifact total unchanged: $RERUN_TOTAL (no accumulation)" \
    || log_fail "Re-run artifact total changed: $RERUN_TOTAL (expected 5)"

# ============================================================================
# TEST 14: Disk files exist at paths referenced by disk_path
# ============================================================================
echo ""
log_info "TEST 14: JSONL files exist at all disk_path locations"

# Deduplicate paths since multiple artifacts share one JSONL file
ALL_DISK_PATHS=$(echo "$BODY" | jq -r '[.blocks[].artifacts[].disk_path // empty] | unique[]' 2>/dev/null)
DISK_CHECK_PASS=0
DISK_CHECK_TOTAL=0
JOB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/jobs/$JOB_ID"
while IFS= read -r dp; do
    [ -z "$dp" ] && continue
    ((DISK_CHECK_TOTAL++))
    FULL_PATH="$JOB_DIR/$dp"
    if [ -f "$FULL_PATH" ]; then
        ((DISK_CHECK_PASS++))
    fi
done <<< "$ALL_DISK_PATHS"

[ "$DISK_CHECK_PASS" = "$DISK_CHECK_TOTAL" ] && [ "$DISK_CHECK_TOTAL" -gt 0 ] 2>/dev/null \
    && log_pass "All $DISK_CHECK_TOTAL JSONL files exist on disk" \
    || log_fail "JSONL file check: $DISK_CHECK_PASS/$DISK_CHECK_TOTAL files exist"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

agent-browser close 2>/dev/null
log_pass "Cleanup complete"

# ============================================================================
# SUMMARY
# ============================================================================
print_summary
exit $?
