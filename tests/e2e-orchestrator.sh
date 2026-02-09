#!/bin/bash
# E2E Test Orchestrator for PromptyUI
# Runs full test suite with screenshots and generates report
#
# Usage:
#   ./tests/e2e-orchestrator.sh                    # Full suite
#   ./tests/e2e-orchestrator.sh --phase api        # Single phase
#   ./tests/e2e-orchestrator.sh --no-cleanup       # Keep server running
#   ./tests/e2e-orchestrator.sh --port 9000        # Custom port

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Defaults
PORT=8085
CLEANUP=true
SINGLE_PHASE=""
SERVER_PID=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port) PORT="$2"; shift 2 ;;
        --no-cleanup) CLEANUP=false; shift ;;
        --phase) SINGLE_PHASE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Setup run directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="$SCRIPT_DIR/e2e-runs/$TIMESTAMP"
SCREENSHOTS_DIR="$RUN_DIR/screenshots"
mkdir -p "$SCREENSHOTS_DIR"

# Create symlink to latest run
ln -sfn "$RUN_DIR" "$SCRIPT_DIR/e2e-runs/latest"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Phase tracking
declare -A PHASE_RESULTS
declare -A PHASE_DURATIONS
PHASES=("setup" "api" "ui" "cleanup")
TOTAL_PASSED=0
TOTAL_FAILED=0
START_TIME=$(date +%s)

log() { echo -e "${CYAN}[E2E]${NC} $1"; }
log_phase() { echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  PHASE: $1${NC}"; echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"; }
log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }

# Cleanup handler
cleanup() {
    if [ -n "$SERVER_PID" ] && [ "$CLEANUP" = true ]; then
        log "Stopping server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
    fi
    agent-browser close 2>/dev/null || true
}
trap cleanup EXIT

# Run a phase and track results
run_phase() {
    local phase="$1"
    local phase_start=$(date +%s)
    local result=0

    log_phase "$phase"

    case $phase in
        setup) phase_setup || result=1 ;;
        api) phase_api || result=1 ;;
        ui) phase_ui || result=1 ;;
        cleanup) phase_cleanup || result=1 ;;
    esac

    local phase_end=$(date +%s)
    PHASE_DURATIONS[$phase]=$((phase_end - phase_start))

    if [ $result -eq 0 ]; then
        PHASE_RESULTS[$phase]="PASS"
        ((TOTAL_PASSED++))
    else
        PHASE_RESULTS[$phase]="FAIL"
        ((TOTAL_FAILED++))
    fi

    return $result
}

# Phase: Setup
phase_setup() {
    log "Starting server on port $PORT..."

    # Kill any existing server on the port
    pkill -f "webui/prompty/start.py.*--port $PORT" 2>/dev/null || true
    sleep 1

    # Start server in background
    ./start-prompty.sh $PORT > "$RUN_DIR/server.log" 2>&1 &
    SERVER_PID=$!

    # Wait for server to be ready
    log "Waiting for server (PID: $SERVER_PID)..."
    local max=30
    local i=1
    while [ $i -le $max ]; do
        if curl -sf "http://localhost:$PORT/api/pu/jobs" > /dev/null 2>&1; then
            log_pass "Server ready on port $PORT"
            return 0
        fi
        ((i++))
        sleep 1
    done

    log_fail "Server failed to start"
    cat "$RUN_DIR/server.log"
    return 1
}

# Phase: API Tests
phase_api() {
    local result=0

    # Test 1: List jobs
    log "API: GET /api/pu/jobs"
    if response=$(curl -sf "http://localhost:$PORT/api/pu/jobs" 2>&1); then
        if echo "$response" | grep -q "hiring-templates"; then
            log_pass "List jobs - found hiring-templates"
        else
            log_fail "List jobs - missing hiring-templates"
            result=1
        fi
    else
        log_fail "List jobs - request failed"
        result=1
    fi

    # Test 2: Get single job
    log "API: GET /api/pu/job/hiring-templates"
    if response=$(curl -sf "http://localhost:$PORT/api/pu/job/hiring-templates" 2>&1); then
        if echo "$response" | grep -q "prompts"; then
            log_pass "Get job - has prompts"
        else
            log_fail "Get job - missing prompts"
            result=1
        fi
    else
        log_fail "Get job - request failed"
        result=1
    fi

    # Test 3: Extensions endpoint
    log "API: GET /api/pu/extensions"
    if curl -sf "http://localhost:$PORT/api/pu/extensions" > /dev/null 2>&1; then
        log_pass "Extensions endpoint"
    else
        log_fail "Extensions endpoint"
        result=1
    fi

    # Test 4: Validate endpoint
    log "API: POST /api/pu/validate"
    if curl -sf -X POST "http://localhost:$PORT/api/pu/validate" \
        -H "Content-Type: application/json" \
        -d '{"job_id": "hiring-templates"}' > /dev/null 2>&1; then
        log_pass "Validate endpoint"
    else
        log_fail "Validate endpoint"
        result=1
    fi

    return $result
}

# Phase: UI Tests
phase_ui() {
    local result=0
    local BASE_URL="http://localhost:$PORT"

    # Test 1: Page loads
    log "UI: Page loads"
    agent-browser open "$BASE_URL" 2>/dev/null
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/01-startup.png" 2>/dev/null || true

    TITLE=$(agent-browser get title 2>/dev/null || echo "")
    if [ "$TITLE" = "PromptyUI" ]; then
        log_pass "Page title correct"
    else
        log_fail "Page title: '$TITLE' (expected 'PromptyUI')"
        result=1
    fi

    # Check for JS errors
    ERRORS=$(agent-browser errors 2>/dev/null || echo "[]")
    if [ -z "$ERRORS" ] || [ "$ERRORS" = "[]" ]; then
        log_pass "No JS errors"
    else
        log_fail "JS errors: $ERRORS"
        result=1
    fi

    # Test 2: Sidebar loads
    log "UI: Sidebar with jobs"
    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -qi "hiring-templates"; then
        log_pass "Jobs sidebar visible"
    else
        log_fail "Jobs sidebar missing"
        result=1
    fi

    # Test 3: Job selection
    log "UI: Select job"
    agent-browser find text "hiring-templates" click 2>/dev/null || true
    sleep 1
    agent-browser screenshot "$SCREENSHOTS_DIR/02-job-selected.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -qi "Prompts"; then
        log_pass "Job content loads"
    else
        log_fail "Job content missing"
        result=1
    fi

    # Test 4: Preview mode
    log "UI: Preview mode"
    agent-browser find role button click --name "Preview" 2>/dev/null || \
        agent-browser find text "Preview" click 2>/dev/null || true
    sleep 1
    agent-browser screenshot "$SCREENSHOTS_DIR/03-preview-mode.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -qi "Edit Mode"; then
        log_pass "Preview mode active"
    else
        log_fail "Preview mode not active"
        result=1
    fi

    # ── Behavioral: Wildcard Dropdown & Preview Navigation ──

    # Test 5: Wildcard chip shows "* (Any <Name>)" format
    log "UI: Wildcard chip displays * (Any <Name>)"
    # We're already in preview mode from Test 4. Select interview-questions which has wildcards.
    agent-browser find text "interview-questions" click 2>/dev/null || true
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/05-wildcard-chips.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -q '\* (Any Count)' && \
       echo "$SNAPSHOT" | grep -q '\* (Any Role)' && \
       echo "$SNAPSHOT" | grep -q '\* (Any Skill)'; then
        log_pass "Wildcard chips show * (Any <Name>) format"
    else
        log_fail "Wildcard chips missing * (Any <Name>) format"
        result=1
    fi

    # Test 6: Open wildcard dropdown — first item reads "* (Any <Name>)" and is selected
    log "UI: Wildcard dropdown shows * (Any <Name>) selected"
    agent-browser click '[data-testid="pu-wc-dropdown-count"]' 2>/dev/null || true
    sleep 1
    agent-browser screenshot "$SCREENSHOTS_DIR/06-wildcard-dropdown.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -q '\* (Any Count)'; then
        log_pass "Dropdown shows * (Any Count) item"
    else
        log_fail "Dropdown missing * (Any Count) item"
        result=1
    fi

    # Test 7: Pin a wildcard value — chip shows just the value (no * prefix)
    log "UI: Pin wildcard value"
    # Click outside to close dropdown from Test 6, then re-open and select
    agent-browser click 'body' 2>/dev/null || true
    sleep 1
    agent-browser click '[data-testid="pu-wc-dropdown-count"]' 2>/dev/null || true
    sleep 1
    agent-browser click '[data-testid="pu-wc-option-count-0"]' 2>/dev/null || true
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/07-wildcard-pinned.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    # After pinning count, the chip should NOT show "* (Any Count)" anymore
    if echo "$SNAPSHOT" | grep -q '\* (Any Count)'; then
        log_fail "Pinned wildcard still shows * (Any Count)"
        result=1
    else
        log_pass "Pinned wildcard shows value without * prefix"
    fi

    # Test 8: Un-pin via * (Any) — chip returns to * (Any <Name>)
    log "UI: Un-pin wildcard via * (Any)"
    agent-browser click '[data-testid="pu-wc-dropdown-count"]' 2>/dev/null || true
    sleep 1
    agent-browser click '[data-testid="pu-wc-option-count-any"]' 2>/dev/null || true
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/08-wildcard-unpinned.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -q '\* (Any Count)'; then
        log_pass "Un-pinned wildcard shows * (Any Count)"
    else
        log_fail "Un-pinned wildcard missing * (Any Count)"
        result=1
    fi

    # Test 9: Independent wildcard control — pin one, others stay * (Any)
    log "UI: Independent wildcard control"
    # Pin role only
    agent-browser click '[data-testid="pu-wc-dropdown-role"]' 2>/dev/null || true
    sleep 1
    agent-browser click '[data-testid="pu-wc-option-role-0"]' 2>/dev/null || true
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/09-independent-wildcards.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    # count and skill should still be Any, role should not
    if echo "$SNAPSHOT" | grep -q '\* (Any Count)' && \
       echo "$SNAPSHOT" | grep -q '\* (Any Skill)'; then
        log_pass "Other wildcards remain * (Any) when one is pinned"
    else
        log_fail "Other wildcards did not remain * (Any)"
        result=1
    fi
    # Reset: un-pin role
    agent-browser click '[data-testid="pu-wc-dropdown-role"]' 2>/dev/null || true
    sleep 1
    agent-browser click '[data-testid="pu-wc-option-role-any"]' 2>/dev/null || true
    sleep 1

    # Test 10: Sidebar navigation in preview mode updates content
    log "UI: Sidebar navigation in preview mode"
    agent-browser find text "outreach-email" click 2>/dev/null || true
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/10-sidebar-nav-preview.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -q '\* (Any Tone)'; then
        log_pass "Sidebar nav updates preview to new prompt"
    else
        log_fail "Sidebar nav did not update preview content"
        result=1
    fi

    # Test 11: URL syncs after sidebar click in preview mode
    log "UI: URL syncs in preview mode"
    URL=$(agent-browser get url 2>/dev/null || echo "")
    if echo "$URL" | grep -q "prompt=outreach-email" && echo "$URL" | grep -q "mode=preview"; then
        log_pass "URL params updated after sidebar nav"
    else
        log_fail "URL params not synced: $URL"
        result=1
    fi

    # Return to edit mode for export test
    agent-browser find role button click --name "Edit Mode" 2>/dev/null || \
        agent-browser find text "Edit Mode" click 2>/dev/null || true
    sleep 1

    # Test 12: Export dialog
    log "UI: Export dialog"
    agent-browser find role button click --name "Export" 2>/dev/null || \
        agent-browser find text "Export" click 2>/dev/null || true
    sleep 1
    agent-browser screenshot "$SCREENSHOTS_DIR/12-export-dialog.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -qi "Export"; then
        log_pass "Export dialog opens"
    else
        log_fail "Export dialog missing"
        result=1
    fi

    return $result
}

# Phase: Cleanup
phase_cleanup() {
    log "Closing browser..."
    agent-browser close 2>/dev/null || true

    if [ "$CLEANUP" = true ] && [ -n "$SERVER_PID" ]; then
        log "Stopping server..."
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
        SERVER_PID=""
        log_pass "Server stopped"
    else
        log "Server left running (--no-cleanup)"
    fi

    return 0
}

# Generate report
generate_report() {
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    local MINS=$((DURATION / 60))
    local SECS=$((DURATION % 60))

    cat > "$RUN_DIR/report.md" << EOF
# E2E Test Report - $TIMESTAMP

## Summary
- **Total Phases**: ${#PHASES[@]}
- **Passed**: $TOTAL_PASSED
- **Failed**: $TOTAL_FAILED
- **Duration**: ${MINS}m ${SECS}s
- **Port**: $PORT

## Phase Results

EOF

    for phase in "${PHASES[@]}"; do
        local status="${PHASE_RESULTS[$phase]:-SKIP}"
        local duration="${PHASE_DURATIONS[$phase]:-0}"
        local icon="✓"
        [ "$status" = "FAIL" ] && icon="✗"
        [ "$status" = "SKIP" ] && icon="○"

        cat >> "$RUN_DIR/report.md" << EOF
### Phase: $phase - $status
- Duration: ${duration}s
- Status: $icon $status

EOF
    done

    cat >> "$RUN_DIR/report.md" << EOF
## Screenshots

EOF

    for screenshot in "$SCREENSHOTS_DIR"/*.png; do
        if [ -f "$screenshot" ]; then
            local name=$(basename "$screenshot")
            echo "- [$name](screenshots/$name)" >> "$RUN_DIR/report.md"
        fi
    done

    cat >> "$RUN_DIR/report.md" << EOF

## Logs

- [server.log](server.log)

---
*Generated by e2e-orchestrator.sh*
EOF

    log "Report saved to: $RUN_DIR/report.md"
}

# Main execution
main() {
    log "E2E Test Run: $TIMESTAMP"
    log "Run directory: $RUN_DIR"
    log "Port: $PORT"

    if [ -n "$SINGLE_PHASE" ]; then
        # Single phase mode
        run_phase "$SINGLE_PHASE" || true
    else
        # Full suite
        for phase in "${PHASES[@]}"; do
            run_phase "$phase" || true
        done
    fi

    generate_report

    # Final summary
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  E2E RESULTS: $TOTAL_PASSED passed, $TOTAL_FAILED failed${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Report: $RUN_DIR/report.md"
    echo "Screenshots: $SCREENSHOTS_DIR/"
    echo ""

    [ $TOTAL_FAILED -eq 0 ]
}

main
