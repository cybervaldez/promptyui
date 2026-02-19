#!/bin/bash
# ============================================================================
# E2E Test Suite: Push Wildcards to Theme API
# ============================================================================
# Tests POST /api/pu/extension/push-wildcards — surgically merges local
# wildcard values back into an existing ext/ theme file.
#
# Usage: ./tests/test_push_to_theme.sh [--port 8085]
# ============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
[[ "$2" == "--port" ]] && PORT="$3"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"
BASE_URL="http://localhost:$PORT"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXT_DIR="$PROJECT_ROOT/ext"

# Backup/restore helpers for the roles.yaml theme
ROLES_FILE="$EXT_DIR/hiring/roles.yaml"
ROLES_BACKUP="$ROLES_FILE.test-backup"

# Temp test theme for isolated tests
TEST_THEME_DIR="$EXT_DIR/test-push"
TEST_THEME_FILE="$TEST_THEME_DIR/sample.yaml"

restore_roles() {
    if [ -f "$ROLES_BACKUP" ]; then
        cp "$ROLES_BACKUP" "$ROLES_FILE"
    fi
}

cleanup() {
    restore_roles
    rm -f "$ROLES_BACKUP"
    rm -rf "$TEST_THEME_DIR"
}

trap cleanup EXIT
print_header "Push Wildcards to Theme API"

# ── Prerequisites ──────────────────────────────────────────────────────
log_info "PREREQUISITES"

if ! wait_for_server "$BASE_URL/api/pu/jobs"; then
    log_fail "Server not running on port $PORT"
    exit 1
fi
log_pass "Server running"

# Backup roles.yaml
cp "$ROLES_FILE" "$ROLES_BACKUP"
log_pass "roles.yaml backed up"

# Create isolated test theme
mkdir -p "$TEST_THEME_DIR"
cat > "$TEST_THEME_FILE" <<'YAML'
id: sample
text:
  - "Test content with __color__"
wildcards:
  - name: color
    text: ["red", "green", "blue"]
YAML
log_pass "Test theme created"

# ============================================================================
# TEST 1: Happy path — Push updated values to theme
# ============================================================================
echo ""
log_test "OBJECTIVE: Push updated wildcard values to theme"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "color",
    "values": ["red", "green", "blue", "yellow"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on push" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

SUCCESS=$(json_get "$BODY" '.success' 'false')
[ "$SUCCESS" = "true" ] \
    && log_pass "success=true" \
    || log_fail "Expected success=true, got $SUCCESS"

ADDED=$(json_get "$BODY" '.added | length' '0')
[ "$ADDED" = "1" ] \
    && log_pass "1 value added (yellow)" \
    || log_fail "Expected 1 added, got $ADDED"

REMOVED=$(json_get "$BODY" '.removed | length' '0')
[ "$REMOVED" = "0" ] \
    && log_pass "0 values removed" \
    || log_fail "Expected 0 removed, got $REMOVED"

# Verify file was actually updated
THEME_CONTENT=$(cat "$TEST_THEME_FILE")
echo "$THEME_CONTENT" | grep -q "yellow" \
    && log_pass "Theme file contains 'yellow'" \
    || log_fail "Theme file missing 'yellow'"

# ============================================================================
# TEST 2: Push with removals
# ============================================================================
echo ""
log_test "OBJECTIVE: Push values that remove existing ones"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "color",
    "values": ["red", "purple"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on push with removals" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

ADDED=$(json_get "$BODY" '.added | length' '0')
REMOVED=$(json_get "$BODY" '.removed | length' '0')
[ "$ADDED" = "1" ] \
    && log_pass "1 value added (purple)" \
    || log_fail "Expected 1 added, got $ADDED: $(json_get "$BODY" '.added')"

[ "$REMOVED" = "3" ] \
    && log_pass "3 values removed (green, blue, yellow)" \
    || log_fail "Expected 3 removed, got $REMOVED: $(json_get "$BODY" '.removed')"

# ============================================================================
# TEST 3: Push identical values (no diff)
# ============================================================================
echo ""
log_test "OBJECTIVE: Push identical values — no changes"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "color",
    "values": ["red", "purple"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on identical push" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

ADDED=$(json_get "$BODY" '.added | length' '0')
REMOVED=$(json_get "$BODY" '.removed | length' '0')
[ "$ADDED" = "0" ] && [ "$REMOVED" = "0" ] \
    && log_pass "No changes (0 added, 0 removed)" \
    || log_fail "Expected 0 changes, got +$ADDED/-$REMOVED"

# ============================================================================
# TEST 4: Push to real theme (hiring/roles — seniority wildcard)
# ============================================================================
echo ""
log_test "OBJECTIVE: Push to hiring/roles seniority wildcard"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "hiring/roles",
    "wildcard_name": "seniority",
    "values": ["Junior", "Mid-level", "Senior", "Staff", "Principal", "Fellow"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on hiring/roles push" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

ADDED=$(json_get "$BODY" '.added | length' '0')
[ "$ADDED" = "1" ] \
    && log_pass "1 value added (Fellow)" \
    || log_fail "Expected 1 added, got $ADDED"

# Verify and restore
grep -q "Fellow" "$ROLES_FILE" \
    && log_pass "roles.yaml contains Fellow" \
    || log_fail "roles.yaml missing Fellow"

restore_roles
log_pass "roles.yaml restored"

# ============================================================================
# TEST 5: Error — missing path
# ============================================================================
echo ""
log_test "OBJECTIVE: Reject missing path"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "wildcard_name": "color",
    "values": ["red"]
}'

[ "$HTTP_CODE" = "400" ] \
    && log_pass "HTTP 400 for missing path" \
    || log_fail "Expected 400, got $HTTP_CODE: $BODY"

# ============================================================================
# TEST 6: Error — missing wildcard_name
# ============================================================================
echo ""
log_test "OBJECTIVE: Reject missing wildcard_name"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "values": ["red"]
}'

[ "$HTTP_CODE" = "400" ] \
    && log_pass "HTTP 400 for missing wildcard_name" \
    || log_fail "Expected 400, got $HTTP_CODE: $BODY"

# ============================================================================
# TEST 7: Error — empty values
# ============================================================================
echo ""
log_test "OBJECTIVE: Reject empty values array"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "color",
    "values": []
}'

[ "$HTTP_CODE" = "400" ] \
    && log_pass "HTTP 400 for empty values" \
    || log_fail "Expected 400, got $HTTP_CODE: $BODY"

# ============================================================================
# TEST 8: Error — theme not found
# ============================================================================
echo ""
log_test "OBJECTIVE: 404 for non-existent theme"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "nonexistent/theme",
    "wildcard_name": "color",
    "values": ["red"]
}'

[ "$HTTP_CODE" = "404" ] \
    && log_pass "HTTP 404 for missing theme" \
    || log_fail "Expected 404, got $HTTP_CODE: $BODY"

# ============================================================================
# TEST 9: Error — wildcard not in theme
# ============================================================================
echo ""
log_test "OBJECTIVE: 404 for wildcard not in theme"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "nonexistent",
    "values": ["red"]
}'

[ "$HTTP_CODE" = "404" ] \
    && log_pass "HTTP 404 for missing wildcard" \
    || log_fail "Expected 404, got $HTTP_CODE: $BODY"

# ============================================================================
# TEST 10: Error — invalid path characters
# ============================================================================
echo ""
log_test "OBJECTIVE: Reject path with special characters"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "../etc/passwd",
    "wildcard_name": "color",
    "values": ["red"]
}'

[ "$HTTP_CODE" = "400" ] \
    && log_pass "HTTP 400 for invalid path" \
    || log_fail "Expected 400, got $HTTP_CODE: $BODY"

# ============================================================================
# TEST 11: Order-only change — same values, different order
# ============================================================================
echo ""
log_test "OBJECTIVE: Order-only change reports 0 added / 0 removed but writes new order"

# Reset test theme to known state
cat > "$TEST_THEME_FILE" <<'YAML'
id: sample
text:
  - "Test content with __color__"
wildcards:
  - name: color
    text: ["red", "green", "blue"]
YAML

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "color",
    "values": ["blue", "green", "red"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on order-only push" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

ADDED=$(json_get "$BODY" '.added | length' '0')
REMOVED=$(json_get "$BODY" '.removed | length' '0')
[ "$ADDED" = "0" ] && [ "$REMOVED" = "0" ] \
    && log_pass "Diff reports 0 added / 0 removed (set equality)" \
    || log_fail "Expected 0 changes, got +$ADDED/-$REMOVED"

# Verify new order was actually written
FIRST_VAL=$(./venv/bin/python -c "
import yaml
with open('$TEST_THEME_FILE') as f:
    d = yaml.safe_load(f)
print(d['wildcards'][0]['text'][0])
")
[ "$FIRST_VAL" = "blue" ] \
    && log_pass "File written with new order (first value: blue)" \
    || log_fail "Expected first value 'blue', got '$FIRST_VAL'"

# ============================================================================
# TEST 12: YAML special characters in values survive round-trip
# ============================================================================
echo ""
log_test "OBJECTIVE: Values with YAML special chars survive round-trip"

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "color",
    "values": ["value: with colon", "- dash start", "quotes \"inside\"", "hash # comment"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on special-char push" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

# Verify round-trip: read the file back via API and check values survive
api_call GET "$BASE_URL/api/pu/extension/test-push/sample" ''

ROUND_TRIP_COUNT=$(echo "$BODY" | jq '.wildcards[0].text | length' 2>/dev/null)
[ "$ROUND_TRIP_COUNT" = "4" ] \
    && log_pass "All 4 special-char values readable via API" \
    || log_fail "Expected 4 values after round-trip, got $ROUND_TRIP_COUNT"

COLON_VAL=$(echo "$BODY" | jq -r '.wildcards[0].text[0]' 2>/dev/null)
[ "$COLON_VAL" = "value: with colon" ] \
    && log_pass "Colon value survived round-trip" \
    || log_fail "Colon value corrupted: '$COLON_VAL'"

DASH_VAL=$(echo "$BODY" | jq -r '.wildcards[0].text[1]' 2>/dev/null)
[ "$DASH_VAL" = "- dash start" ] \
    && log_pass "Dash-start value survived round-trip" \
    || log_fail "Dash value corrupted: '$DASH_VAL'"

# ============================================================================
# TEST 13: Other wildcards in theme untouched after push
# ============================================================================
echo ""
log_test "OBJECTIVE: Push one wildcard, verify others are untouched"

# Create multi-wildcard theme
cat > "$TEST_THEME_FILE" <<'YAML'
id: sample
text:
  - "Test __color__ and __size__"
wildcards:
  - name: color
    text: ["red", "green", "blue"]
  - name: size
    text: ["small", "medium", "large"]
YAML

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "color",
    "values": ["red", "cyan"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on multi-wildcard theme push" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

# Verify 'size' wildcard is completely untouched
SIZE_VALUES=$(./venv/bin/python -c "
import yaml
with open('$TEST_THEME_FILE') as f:
    d = yaml.safe_load(f)
for wc in d['wildcards']:
    if wc['name'] == 'size':
        print(','.join(wc['text']))
")
[ "$SIZE_VALUES" = "small,medium,large" ] \
    && log_pass "Size wildcard untouched: $SIZE_VALUES" \
    || log_fail "Size wildcard corrupted: '$SIZE_VALUES'"

# Verify 'color' was updated
COLOR_VALUES=$(./venv/bin/python -c "
import yaml
with open('$TEST_THEME_FILE') as f:
    d = yaml.safe_load(f)
for wc in d['wildcards']:
    if wc['name'] == 'color':
        print(','.join(wc['text']))
")
[ "$COLOR_VALUES" = "red,cyan" ] \
    && log_pass "Color wildcard updated: $COLOR_VALUES" \
    || log_fail "Color wildcard wrong: '$COLOR_VALUES'"

# Also verify the text and id fields weren't mangled
THEME_ID=$(./venv/bin/python -c "
import yaml
with open('$TEST_THEME_FILE') as f:
    d = yaml.safe_load(f)
print(d.get('id', ''))
")
[ "$THEME_ID" = "sample" ] \
    && log_pass "Theme id field preserved" \
    || log_fail "Theme id corrupted: '$THEME_ID'"

# ============================================================================
# TEST 14: Duplicate values in array
# ============================================================================
echo ""
log_test "OBJECTIVE: Duplicate values in push array are written as-is"

# Reset to clean state
cat > "$TEST_THEME_FILE" <<'YAML'
id: sample
text:
  - "Test __color__"
wildcards:
  - name: color
    text: ["red", "green"]
YAML

api_call POST "$BASE_URL/api/pu/extension/push-wildcards" '{
    "path": "test-push/sample",
    "wildcard_name": "color",
    "values": ["red", "red", "blue"]
}'

[ "$HTTP_CODE" = "200" ] \
    && log_pass "HTTP 200 on duplicate-values push" \
    || log_fail "Expected 200, got $HTTP_CODE: $BODY"

# Verify the file has exactly 3 values (duplicates preserved)
VAL_COUNT=$(./venv/bin/python -c "
import yaml
with open('$TEST_THEME_FILE') as f:
    d = yaml.safe_load(f)
print(len(d['wildcards'][0]['text']))
")
[ "$VAL_COUNT" = "3" ] \
    && log_pass "3 values written (duplicates preserved)" \
    || log_fail "Expected 3 values, got $VAL_COUNT"

# Diff uses sets: "red" appears once locally → not added. "green" missing → removed.
ADDED=$(json_get "$BODY" '.added | length' '0')
REMOVED=$(json_get "$BODY" '.removed | length' '0')
[ "$ADDED" = "1" ] \
    && log_pass "Diff: +1 added (blue)" \
    || log_fail "Expected 1 added, got $ADDED"

[ "$REMOVED" = "1" ] \
    && log_pass "Diff: -1 removed (green)" \
    || log_fail "Expected 1 removed, got $REMOVED"

# ── Summary ──────────────────────────────────────────────────────────
print_summary
