#!/bin/bash
# E2E Test: PromptyUI API
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

print_header "PromptyUI API Tests"

# Prerequisites
log_info "Checking server..."
if wait_for_server; then
    log_pass "Server running on port $PORT"
else
    log_fail "Server not running"
    exit 1
fi

# Test 1: List jobs
log_info "TEST 1: GET /api/pu/jobs"
api_call GET "$BASE_URL/api/pu/jobs"
[ "$HTTP_CODE" = "200" ] && log_pass "HTTP 200" || log_fail "HTTP $HTTP_CODE"
echo "$BODY" | grep -q "hiring-templates" && log_pass "Found hiring-templates" || log_fail "Missing job"

# Test 2: Get single job
log_info "TEST 2: GET /api/pu/job/hiring-templates"
api_call GET "$BASE_URL/api/pu/job/hiring-templates"
[ "$HTTP_CODE" = "200" ] && log_pass "HTTP 200" || log_fail "HTTP $HTTP_CODE"
echo "$BODY" | grep -q "prompts" && log_pass "Has prompts" || log_fail "Missing prompts"

# Test 3: List extensions
log_info "TEST 3: GET /api/pu/extensions"
api_call GET "$BASE_URL/api/pu/extensions"
[ "$HTTP_CODE" = "200" ] && log_pass "HTTP 200" || log_fail "HTTP $HTTP_CODE"

# Test 4: Validate job
log_info "TEST 4: POST /api/pu/validate"
api_call POST "$BASE_URL/api/pu/validate" '{"job_id": "hiring-templates"}'
[ "$HTTP_CODE" = "200" ] && log_pass "HTTP 200" || log_fail "HTTP $HTTP_CODE"

print_summary
exit $?
