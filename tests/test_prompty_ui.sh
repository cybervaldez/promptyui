#!/bin/bash
# E2E Test: PromptyUI UI
set +e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "PromptyUI UI Tests"

# Prerequisites
log_info "Checking server..."
if ! wait_for_server; then
    log_fail "Server not running"
    exit 1
fi
log_pass "Server running"

# Test 1: Page loads
log_info "TEST 1: Page loads"
agent-browser open "$BASE_URL"
TITLE=$(agent-browser get title 2>/dev/null)
[ "$TITLE" = "PromptyUI" ] && log_pass "Title correct" || log_fail "Title: $TITLE"

# Test 2: Jobs sidebar
log_info "TEST 2: Jobs sidebar"
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "hiring-templates" && log_pass "Shows job" || log_fail "Missing job"

# Test 3: Job selection
log_info "TEST 3: Job selection"
agent-browser find text "hiring-templates" click 2>/dev/null
sleep 0.5
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "Prompts" && log_pass "Shows prompts" || log_fail "No prompts"

# Test 4: Preview mode
log_info "TEST 4: Preview mode"
agent-browser find role button click --name "Preview" 2>/dev/null || \
    agent-browser find text "Preview" click 2>/dev/null
sleep 0.5
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "Edit Mode" && log_pass "Preview mode active" || log_fail "Not in preview"

# Test 5: Export dialog
log_info "TEST 5: Export dialog"
agent-browser find role button click --name "Export" 2>/dev/null || \
    agent-browser find text "Export" click 2>/dev/null
sleep 0.5
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "Export jobs.yaml" && log_pass "Export dialog open" || log_fail "No dialog"

# Cleanup
agent-browser close 2>/dev/null

print_summary
exit $?
