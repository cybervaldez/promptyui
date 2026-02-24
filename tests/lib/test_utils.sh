#!/bin/bash
# Shared test utilities for E2E tests

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0
declare -a TESTS=()

# Logging
log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASSED++)); TESTS+=("PASS: $1"); }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAILED++)); TESTS+=("FAIL: $1"); }
log_skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; ((SKIPPED++)); TESTS+=("SKIP: $1"); }
log_info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }
log_test() { echo -e "  [TEST] $1"; }

# Server check with retry
wait_for_server() {
    local url="${1:-$BASE_URL/api/pu/jobs}"
    local max=10
    local i=1
    while [ $i -le $max ]; do
        curl -sf "$url" > /dev/null 2>&1 && return 0
        ((i++))
        sleep 1
    done
    return 1
}

# Browser cleanup trap
setup_cleanup() {
    trap 'agent-browser close 2>/dev/null || true' EXIT
}

# Summary
print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  SUMMARY: $PASSED passed, $FAILED failed, $SKIPPED skipped"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    for t in "${TESTS[@]}"; do echo "  $t"; done
    echo ""
    [ "$FAILED" -eq 0 ] && return 0 || return 1
}

# API call helper
api_call() {
    local method="$1"
    local url="$2"
    local data="$3"
    if [ -n "$data" ]; then
        RESULT=$(curl -sf -w "\n%{http_code}" -X "$method" "$url" \
            -H "Content-Type: application/json" -d "$data" 2>&1)
    else
        RESULT=$(curl -sf -w "\n%{http_code}" -X "$method" "$url" 2>&1)
    fi
    HTTP_CODE=$(echo "$RESULT" | tail -1)
    BODY=$(echo "$RESULT" | sed '$d')
}

# JSON extraction with fallback
json_get() {
    local json="$1"
    local path="$2"
    local default="$3"
    echo "$json" | jq -r "$path // \"$default\"" 2>/dev/null || echo "$default"
}

# Header
print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════"
    echo ""
}
