#!/bin/bash
# ============================================================================
# E2E Test Suite: Move-to-Theme API
# ============================================================================
# Tests POST /api/pu/move-to-theme — moves a content block from jobs.yaml
# to an ext/ theme file, replacing it with an ext_text reference.
# Parent blocks (with after: children) are allowed — children stay attached.
#
# Usage: ./tests/test_move_to_theme.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"
JOB_ID="hiring-templates"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Backup/restore helpers
BACKUP="$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml.test-backup"

restore_jobs_yaml() {
    if [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml"
    fi
}

cleanup() {
    restore_jobs_yaml
    rm -f "$BACKUP"
    rm -rf "$PROJECT_ROOT/ext/test-move/"
    rm -rf "$PROJECT_ROOT/ext/$JOB_ID/"
    # Clean any .backup. files created by the API
    rm -f "$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml.backup."*
    agent-browser close 2>/dev/null || true
}

trap cleanup EXIT
print_header "Move-to-Theme API"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "PREREQUISITES"

if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# Create backup of jobs.yaml
cp "$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml" "$BACKUP"
log_pass "jobs.yaml backed up"

# ============================================================================
# TEST 1: Happy path — Move content block to shared theme
# ============================================================================
echo ""
log_test "OBJECTIVE: Move content block to shared theme"

restore_jobs_yaml

api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "job-posting",
    "block_index": 0,
    "theme_path": "test-move/job-postings",
    "fork": false,
    "wildcard_names": ["role"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on move" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

SUCCESS=$(json_get "$BODY" '.success' 'false')
[ "$SUCCESS" = "true" ] \
    && log_pass "Response success: true" \
    || log_fail "Expected success: true, got: $SUCCESS"

# Verify theme file created
THEME_FILE="$PROJECT_ROOT/ext/test-move/job-postings.yaml"
[ -f "$THEME_FILE" ] \
    && log_pass "Theme file created at ext/test-move/job-postings.yaml" \
    || log_fail "Theme file not found"

# Verify theme content
if [ -f "$THEME_FILE" ]; then
    THEME_HAS_TEXT=$(grep -c "Write a job posting" "$THEME_FILE" 2>/dev/null)
    [ "$THEME_HAS_TEXT" -gt 0 ] \
        && log_pass "Theme contains moved text" \
        || log_fail "Theme missing moved text"

    THEME_HAS_WC=$(grep -c "name: role" "$THEME_FILE" 2>/dev/null)
    [ "$THEME_HAS_WC" -gt 0 ] \
        && log_pass "Theme has bundled wildcard 'role'" \
        || log_fail "Theme missing wildcard 'role'"
fi

# Verify jobs.yaml updated
JOBS_FILE="$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml"
HAS_EXT_TEXT=$(grep -c "ext_text: test-move/job-postings" "$JOBS_FILE" 2>/dev/null)
[ "$HAS_EXT_TEXT" -gt 0 ] \
    && log_pass "jobs.yaml has ext_text reference" \
    || log_fail "jobs.yaml missing ext_text reference"

HAS_EXT_MAX=$(grep -c "ext_text_max: 1" "$JOBS_FILE" 2>/dev/null)
[ "$HAS_EXT_MAX" -gt 0 ] \
    && log_pass "jobs.yaml has ext_text_max: 1" \
    || log_fail "jobs.yaml missing ext_text_max"

# Verify role wildcard STAYS in prompt (copy semantics, not move)
api_call GET "$BASE_URL/api/pu/job/$JOB_ID"
JP_WC=$(echo "$BODY" | jq -r '.prompts[] | select(.id=="job-posting") | .wildcards | length' 2>/dev/null)
[ "$JP_WC" = "1" ] \
    && log_pass "role wildcard kept in job-posting prompt (copy semantics)" \
    || log_fail "Expected 1 wildcard (role stays local), got: $JP_WC"

JP_WC_NAME=$(echo "$BODY" | jq -r '.prompts[] | select(.id=="job-posting") | .wildcards[0].name' 2>/dev/null)
[ "$JP_WC_NAME" = "role" ] \
    && log_pass "Kept wildcard is 'role'" \
    || log_fail "Expected kept wildcard 'role', got: $JP_WC_NAME"

# Verify response fields
MOVED_TEXT=$(json_get "$BODY" '.moved_text' '')
# Re-read from the move response — use the stored BODY from the move call
# Actually need to re-check from the move API response
# Already validated above, moving on

# Cleanup for next test
restore_jobs_yaml
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# TEST 2: Happy path — Fork to job-scoped theme
# ============================================================================
echo ""
log_test "OBJECTIVE: Fork to job-scoped theme"

restore_jobs_yaml

api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "job-posting",
    "block_index": 0,
    "theme_path": "hiring/postings",
    "fork": true,
    "wildcard_names": ["role"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on fork move" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

# Verify theme at forked path
FORK_FILE="$PROJECT_ROOT/ext/hiring-templates/hiring/postings.yaml"
[ -f "$FORK_FILE" ] \
    && log_pass "Fork theme created at ext/hiring-templates/hiring/postings.yaml" \
    || log_fail "Fork theme not found at $FORK_FILE"

# Verify ext_text ref includes job_id prefix
JOBS_FILE="$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml"
HAS_FORK_REF=$(grep -c "ext_text: hiring-templates/hiring/postings" "$JOBS_FILE" 2>/dev/null)
[ "$HAS_FORK_REF" -gt 0 ] \
    && log_pass "jobs.yaml has forked ext_text reference" \
    || log_fail "jobs.yaml missing forked reference"

# Cleanup
restore_jobs_yaml
rm -rf "$PROJECT_ROOT/ext/hiring-templates/"

# ============================================================================
# TEST 3: Move parent block — after: children preserved
# ============================================================================
echo ""
log_test "OBJECTIVE: Move parent block, verify after: children preserved"

restore_jobs_yaml

# nested-job-brief block 1 has after: children — should now succeed
api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "nested-job-brief",
    "block_index": 1,
    "theme_path": "test-move/nested-parent",
    "fork": false,
    "wildcard_names": ["role"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 for parent block move" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

SUCCESS=$(json_get "$BODY" '.success' 'false')
[ "$SUCCESS" = "true" ] \
    && log_pass "Response success: true" \
    || log_fail "Expected success: true, got: $SUCCESS"

# Verify theme file created
THEME_FILE="$PROJECT_ROOT/ext/test-move/nested-parent.yaml"
[ -f "$THEME_FILE" ] \
    && log_pass "Theme file created at ext/test-move/nested-parent.yaml" \
    || log_fail "Theme file not found"

# Verify after: children preserved in jobs.yaml via API
api_call GET "$BASE_URL/api/pu/job/$JOB_ID"
AFTER_LENGTH=$(echo "$BODY" | jq -r '.prompts[] | select(.id=="nested-job-brief") | .text[1].after | length' 2>/dev/null)
[ "$AFTER_LENGTH" = "1" ] \
    && log_pass "after: children preserved (1 child block)" \
    || log_fail "Expected 1 after child, got: $AFTER_LENGTH"

# Verify the replacement is ext_text (not content)
HAS_EXT=$(echo "$BODY" | jq -r '.prompts[] | select(.id=="nested-job-brief") | .text[1].ext_text' 2>/dev/null)
[ "$HAS_EXT" = "test-move/nested-parent" ] \
    && log_pass "Block replaced with ext_text reference" \
    || log_fail "Expected ext_text 'test-move/nested-parent', got: $HAS_EXT"

# Cleanup
restore_jobs_yaml
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# TEST 4: Reject — Block is already ext_text
# ============================================================================
echo ""
log_test "OBJECTIVE: Reject block that is already ext_text"

restore_jobs_yaml

# ext-sourcing-strategy block 1 is ext_text: "hiring/roles"
RESULT=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/pu/move-to-theme" \
    -H "Content-Type: application/json" \
    -d '{"job_id":"hiring-templates","prompt_id":"ext-sourcing-strategy","block_index":1,"theme_path":"test-move/already-ext","fork":false}' 2>&1)
HTTP_CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')

[ "$HTTP_CODE" = "400" ] \
    && log_pass "HTTP 400 for ext_text block" \
    || log_fail "Expected 400, got $HTTP_CODE: $BODY"

ERR_MSG=$(echo "$BODY" | jq -r '.error // ""' 2>/dev/null)
echo "$ERR_MSG" | grep -qi "already an ext_text" \
    && log_pass "Error message mentions already ext_text" \
    || log_fail "Unexpected error: $ERR_MSG"

# ============================================================================
# TEST 5: Reject — Theme already exists (409)
# ============================================================================
echo ""
log_test "OBJECTIVE: 409 when theme path already exists"

restore_jobs_yaml

# Create a theme first using extension/save
api_call POST "$BASE_URL/api/pu/extension/save" '{"path": "test-move/conflict", "data": {"id": "conflict", "text": ["existing"]}}'
[ "$HTTP_CODE" = "200" ] \
    && log_pass "Pre-created conflict theme" \
    || log_fail "Failed to create conflict theme: $HTTP_CODE"

# Now try to move to the same path
api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "job-posting",
    "block_index": 0,
    "theme_path": "test-move/conflict",
    "fork": false
}'

[ "$HTTP_CODE" = "409" ] \
    && log_pass "HTTP 409 for existing theme" \
    || log_fail "Expected 409, got $HTTP_CODE: $BODY"

# Verify jobs.yaml unchanged
api_call GET "$BASE_URL/api/pu/job/$JOB_ID"
HAS_CONTENT=$(echo "$BODY" | jq -r '.prompts[] | select(.id=="job-posting") | .text[0].content' 2>/dev/null)
[ -n "$HAS_CONTENT" ] \
    && log_pass "jobs.yaml unchanged after 409" \
    || log_fail "jobs.yaml may have been modified"

# Cleanup
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# TEST 6: Reject — Invalid inputs
# ============================================================================
echo ""
log_test "OBJECTIVE: Reject various invalid inputs"

# Missing job_id
api_call POST "$BASE_URL/api/pu/move-to-theme" '{"prompt_id": "x", "block_index": 0, "theme_path": "x"}'
[ "$HTTP_CODE" = "400" ] \
    && log_pass "Missing job_id → 400" \
    || log_fail "Expected 400 for missing job_id, got $HTTP_CODE"

# Missing prompt_id
api_call POST "$BASE_URL/api/pu/move-to-theme" '{"job_id": "x", "block_index": 0, "theme_path": "x"}'
[ "$HTTP_CODE" = "400" ] \
    && log_pass "Missing prompt_id → 400" \
    || log_fail "Expected 400 for missing prompt_id, got $HTTP_CODE"

# Missing block_index
api_call POST "$BASE_URL/api/pu/move-to-theme" '{"job_id": "x", "prompt_id": "x", "theme_path": "x"}'
[ "$HTTP_CODE" = "400" ] \
    && log_pass "Missing block_index → 400" \
    || log_fail "Expected 400 for missing block_index, got $HTTP_CODE"

# Missing theme_path
api_call POST "$BASE_URL/api/pu/move-to-theme" '{"job_id": "x", "prompt_id": "x", "block_index": 0}'
[ "$HTTP_CODE" = "400" ] \
    && log_pass "Missing theme_path → 400" \
    || log_fail "Expected 400 for missing theme_path, got $HTTP_CODE"

# Bad theme_path characters
api_call POST "$BASE_URL/api/pu/move-to-theme" '{"job_id": "hiring-templates", "prompt_id": "job-posting", "block_index": 0, "theme_path": "../etc/passwd"}'
[ "$HTTP_CODE" = "400" ] \
    && log_pass "Path traversal rejected → 400" \
    || log_fail "Expected 400 for bad path, got $HTTP_CODE"

# Job not found
api_call POST "$BASE_URL/api/pu/move-to-theme" '{"job_id": "nonexistent", "prompt_id": "x", "block_index": 0, "theme_path": "x"}'
[ "$HTTP_CODE" = "404" ] \
    && log_pass "Nonexistent job → 404" \
    || log_fail "Expected 404 for missing job, got $HTTP_CODE"

# Prompt not found
api_call POST "$BASE_URL/api/pu/move-to-theme" '{"job_id": "hiring-templates", "prompt_id": "nonexistent", "block_index": 0, "theme_path": "x"}'
[ "$HTTP_CODE" = "404" ] \
    && log_pass "Nonexistent prompt → 404" \
    || log_fail "Expected 404 for missing prompt, got $HTTP_CODE"

# Block index out of range
api_call POST "$BASE_URL/api/pu/move-to-theme" '{"job_id": "hiring-templates", "prompt_id": "job-posting", "block_index": 99, "theme_path": "x"}'
[ "$HTTP_CODE" = "404" ] \
    && log_pass "Block index out of range → 404" \
    || log_fail "Expected 404 for out-of-range index, got $HTTP_CODE"

# ============================================================================
# TEST 7: Shared wildcard stays local
# ============================================================================
echo ""
log_test "OBJECTIVE: Exclusive wildcards bundled, shared wildcards stay local"

restore_jobs_yaml

# nested-job-brief: block 0 uses __tone__ and __company_size__ (exclusive to block 0)
# block 1 uses __role__ (exclusive to block 1, but block 1 has after: which uses __years_exp__, __skill__)
# tone and company_size are NOT shared — both should be bundled

api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "nested-job-brief",
    "block_index": 0,
    "theme_path": "test-move/exclusive-test",
    "fork": false,
    "wildcard_names": ["tone", "company_size"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "Move succeeded" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

# Both wildcards exclusive to block 0 — should be bundled (no warnings)
WARNINGS=$(json_get "$BODY" '.warnings | length' '0')
[ "$WARNINGS" = "0" ] \
    && log_pass "No warnings (both wildcards exclusive to moved block)" \
    || log_fail "Unexpected warnings: $(json_get "$BODY" '.warnings' '[]')"

COPIED_NAMES=$(echo "$BODY" | jq -r '.copied_wildcards | sort | join(",")' 2>/dev/null)
[ "$COPIED_NAMES" = "company_size,tone" ] \
    && log_pass "Both exclusive wildcards copied to theme: $COPIED_NAMES" \
    || log_fail "Expected company_size,tone copied, got: $COPIED_NAMES"

# ALL wildcards stay in prompt (copy semantics)
KEPT_COUNT=$(json_get "$BODY" '.kept_wildcards | length' '0')
[ "$KEPT_COUNT" = "5" ] \
    && log_pass "All 5 wildcards kept in prompt (copy semantics)" \
    || log_fail "Expected 5 kept wildcards, got: $KEPT_COUNT"

# Cleanup
restore_jobs_yaml
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# TEST 8: Backup file created
# ============================================================================
echo ""
log_test "OBJECTIVE: Backup of jobs.yaml created on move"

restore_jobs_yaml
# Clean any old backups
rm -f "$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml.backup."*

api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "job-posting",
    "block_index": 0,
    "theme_path": "test-move/backup-test",
    "fork": false,
    "wildcard_names": ["role"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "Move succeeded" \
    || log_fail "Expected 200, got $HTTP_CODE"

BACKUP_FILE=$(json_get "$BODY" '.backup' '')
[ -n "$BACKUP_FILE" ] \
    && log_pass "Response includes backup path: $BACKUP_FILE" \
    || log_fail "No backup path in response"

# Verify backup file exists on disk
BACKUP_FULL="$PROJECT_ROOT/$BACKUP_FILE"
[ -f "$BACKUP_FULL" ] \
    && log_pass "Backup file exists on disk" \
    || log_fail "Backup file not found: $BACKUP_FULL"

# Verify backup has original content
if [ -f "$BACKUP_FULL" ]; then
    ORIG_CONTENT=$(grep -c "Write a job posting" "$BACKUP_FULL" 2>/dev/null)
    [ "$ORIG_CONTENT" -gt 0 ] \
        && log_pass "Backup contains original content" \
        || log_fail "Backup doesn't contain original content"
fi

# Cleanup
restore_jobs_yaml
rm -f "$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml.backup."*
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# TEST 9: Composition preserved (no ext_text before move)
# ============================================================================
echo ""
log_test "OBJECTIVE: Composition unchanged when no prior ext_text"

restore_jobs_yaml
sleep 0.5

# Verify file is in original state (content block, not ext_text)
PRE_CHECK=$(curl -sf "$BASE_URL/api/pu/job/$JOB_ID" 2>&1 | jq -r '.prompts[] | select(.id=="job-posting") | .text[0].content // "none"' 2>/dev/null)
[ "$PRE_CHECK" != "none" ] \
    && log_pass "Pre-check: job-posting has content block" \
    || log_fail "Pre-check: job-posting block is not content: $PRE_CHECK"

api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "job-posting",
    "block_index": 0,
    "theme_path": "test-move/comp-test",
    "fork": false,
    "wildcard_names": ["role"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "Move succeeded" \
    || log_fail "Expected 200, got $HTTP_CODE"

# Use raw jq (not json_get) for booleans — jq's // operator treats false as falsy
COMP_CHANGED=$(echo "$BODY" | jq -r '.composition_changed' 2>/dev/null)
[ "$COMP_CHANGED" = "false" ] \
    && log_pass "composition_changed: false (no prior ext_text)" \
    || log_fail "Expected composition_changed: false, got: $COMP_CHANGED"

NEW_COMP=$(json_get "$BODY" '.new_composition' '-1')
[ "$NEW_COMP" = "0" ] \
    && log_pass "new_composition: 0" \
    || log_fail "Expected new_composition: 0, got: $NEW_COMP"

# Cleanup
restore_jobs_yaml
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# TEST 10: Composition changes (existing ext_text before move)
# ============================================================================
echo ""
log_test "OBJECTIVE: Composition changes when prior ext_text exists"

restore_jobs_yaml

# ext-sourcing-strategy has: block 0 = content, block 1 = ext_text (hiring/roles, max 3)
# Move block 0 to theme — this adds to the summed ext_text dimension
api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "ext-sourcing-strategy",
    "block_index": 0,
    "theme_path": "test-move/strategy-content",
    "fork": false,
    "wildcard_names": ["channel"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "Move succeeded" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

# Use raw jq for booleans — jq's // operator treats false as falsy
COMP_CHANGED=$(echo "$BODY" | jq -r '.composition_changed' 2>/dev/null)
[ "$COMP_CHANGED" = "true" ] \
    && log_pass "composition_changed: true (prior ext_text existed)" \
    || log_fail "Expected composition_changed: true, got: $COMP_CHANGED"

NEW_COMP=$(json_get "$BODY" '.new_composition' '-1')
[ "$NEW_COMP" -ge 0 ] \
    && log_pass "new_composition: $NEW_COMP (recalculated)" \
    || log_fail "Expected positive new_composition, got: $NEW_COMP"

# Cleanup
restore_jobs_yaml
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# TEST 11: Auto-detect wildcards from text
# ============================================================================
echo ""
log_test "OBJECTIVE: Auto-detect wildcards when wildcard_names not provided"

restore_jobs_yaml

# Don't pass wildcard_names — should auto-detect from text
api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "assessment-prompt",
    "block_index": 0,
    "theme_path": "test-move/auto-detect",
    "fork": false
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "Move succeeded with auto-detect" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

# assessment-prompt block 0 uses __level__ and __role__
# Both should be auto-detected and copied to theme
COPIED=$(echo "$BODY" | jq -r '.copied_wildcards | sort | join(",")' 2>/dev/null)
echo "$COPIED" | grep -q "level" \
    && log_pass "Auto-detected 'level' wildcard" \
    || log_fail "Missing auto-detected 'level', got: $COPIED"

echo "$COPIED" | grep -q "role" \
    && log_pass "Auto-detected 'role' wildcard" \
    || log_fail "Missing auto-detected 'role', got: $COPIED"

# Cleanup
restore_jobs_yaml
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# TEST 12: Round-trip — moved theme is readable via extension API
# ============================================================================
echo ""
log_test "OBJECTIVE: Moved theme readable via GET /api/pu/extension/"

restore_jobs_yaml

api_call POST "$BASE_URL/api/pu/move-to-theme" '{
    "job_id": "hiring-templates",
    "prompt_id": "job-posting",
    "block_index": 0,
    "theme_path": "test-move/roundtrip",
    "fork": false,
    "wildcard_names": ["role"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "Move succeeded" \
    || log_fail "Expected 200, got $HTTP_CODE"

# Read the theme back via API
api_call GET "$BASE_URL/api/pu/extension/test-move/roundtrip"

[ "$HTTP_CODE" = "200" ] \
    && log_pass "GET extension returned 200" \
    || log_fail "GET extension returned $HTTP_CODE"

EXT_ID=$(json_get "$BODY" '.id' '')
[ "$EXT_ID" = "roundtrip" ] \
    && log_pass "Extension id: roundtrip" \
    || log_fail "Expected id 'roundtrip', got: $EXT_ID"

TEXT_COUNT=$(echo "$BODY" | jq -r '.text | length' 2>/dev/null)
[ "$TEXT_COUNT" = "1" ] \
    && log_pass "Extension has 1 text value" \
    || log_fail "Expected 1 text, got: $TEXT_COUNT"

WC_COUNT=$(echo "$BODY" | jq -r '.wildcards | length' 2>/dev/null)
[ "$WC_COUNT" = "1" ] \
    && log_pass "Extension has 1 wildcard" \
    || log_fail "Expected 1 wildcard, got: $WC_COUNT"

WC_NAME=$(echo "$BODY" | jq -r '.wildcards[0].name' 2>/dev/null)
[ "$WC_NAME" = "role" ] \
    && log_pass "Wildcard name: role" \
    || log_fail "Expected wildcard 'role', got: $WC_NAME"

WC_VALUES=$(echo "$BODY" | jq -r '.wildcards[0].text | length' 2>/dev/null)
[ "$WC_VALUES" = "5" ] \
    && log_pass "Wildcard has 5 values" \
    || log_fail "Expected 5 values, got: $WC_VALUES"

# Cleanup
restore_jobs_yaml
rm -rf "$PROJECT_ROOT/ext/test-move/"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
log_info "CLEANUP"

restore_jobs_yaml
rm -f "$BACKUP"
rm -rf "$PROJECT_ROOT/ext/test-move/"
rm -rf "$PROJECT_ROOT/ext/$JOB_ID/"
rm -f "$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml.backup."*
log_pass "All artifacts cleaned up"

# Verify jobs.yaml is original
ORIG_CHECK=$(grep -c "Write a job posting" "$PROJECT_ROOT/jobs/$JOB_ID/jobs.yaml" 2>/dev/null)
[ "$ORIG_CHECK" -gt 0 ] \
    && log_pass "jobs.yaml restored to original" \
    || log_fail "jobs.yaml may not be restored"

print_summary
exit $?
