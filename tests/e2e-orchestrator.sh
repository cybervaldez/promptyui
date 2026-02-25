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

    # ── Behavioral: Build Panel & Composition Navigation ──

    # Test 4: Build panel opens with composition navigator
    log "UI: Build panel opens"
    agent-browser click '[data-testid="pu-header-build-btn"]' 2>/dev/null || true
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/04-build-panel.png" 2>/dev/null || true

    HAS_BUILD=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-build-panel\"]")' 2>/dev/null || echo "false")
    if [ "$HAS_BUILD" = "true" ]; then
        log_pass "Build panel opens"
    else
        log_fail "Build panel not visible"
        result=1
    fi

    # Test 5: Build panel shows composition total
    log "UI: Composition total visible"
    BUILD_TOTAL=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-build-total\"]")?.textContent?.trim()' 2>/dev/null || echo "")
    if [ -n "$BUILD_TOTAL" ] && [ "$BUILD_TOTAL" != "null" ] && [ "$BUILD_TOTAL" != "undefined" ]; then
        log_pass "Composition total: $BUILD_TOTAL"
    else
        log_fail "Composition total not visible"
        result=1
    fi

    # Test 6: Build panel navigation controls exist
    log "UI: Composition navigation controls"
    HAS_NAV=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-build-nav-prev\"]") && !!document.querySelector("[data-testid=\"pu-build-nav-next\"]")' 2>/dev/null || echo "false")
    if [ "$HAS_NAV" = "true" ]; then
        log_pass "Navigation prev/next buttons present"
    else
        log_fail "Navigation controls missing"
        result=1
    fi

    # Close build panel
    agent-browser click '[data-testid="pu-build-close-btn"]' 2>/dev/null || true
    sleep 1

    # ── Behavioral: Wildcard Chips in Right Panel ──

    # Test 7: Wildcard chips visible for multi-wildcard prompt
    log "UI: Wildcard chips in right panel"
    # Select interview-questions which has count, role, skill wildcards
    agent-browser find text "interview-questions" click 2>/dev/null || true
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/07-wildcard-chips.png" 2>/dev/null || true

    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -qi "count" && \
       echo "$SNAPSHOT" | grep -qi "role" && \
       echo "$SNAPSHOT" | grep -qi "skill"; then
        log_pass "Wildcard chips visible: count, role, skill"
    else
        log_fail "Wildcard chips missing in right panel"
        result=1
    fi

    # Test 8: Wildcard chip values are clickable
    log "UI: Wildcard chip values rendered"
    HAS_CHIPS=$(agent-browser eval 'document.querySelectorAll("[data-testid^=\"pu-rp-wc-chip-\"]").length > 0' 2>/dev/null || echo "false")
    if [ "$HAS_CHIPS" = "true" ]; then
        CHIP_COUNT=$(agent-browser eval 'document.querySelectorAll("[data-testid^=\"pu-rp-wc-chip-\"]").length' 2>/dev/null || echo "0")
        log_pass "Wildcard chips rendered: $CHIP_COUNT chips"
    else
        log_fail "No wildcard chips found"
        result=1
    fi

    # ── Behavioral: Sidebar Navigation & URL ──

    # Test 9: Sidebar navigation loads different prompt
    log "UI: Sidebar navigation changes prompt"
    agent-browser find text "outreach-email" click 2>/dev/null || true
    sleep 2
    agent-browser screenshot "$SCREENSHOTS_DIR/09-sidebar-nav.png" 2>/dev/null || true

    EDITOR_TITLE=$(agent-browser eval 'document.querySelector("[data-testid=\"pu-editor-title\"]")?.textContent?.trim()' 2>/dev/null || echo "")
    if echo "$EDITOR_TITLE" | grep -qi "outreach-email"; then
        log_pass "Editor title updated: $EDITOR_TITLE"
    else
        log_fail "Editor title not updated: '$EDITOR_TITLE'"
        result=1
    fi

    # Test 10: Right panel wildcards update on navigation
    log "UI: Right panel wildcards update"
    SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null || echo "")
    if echo "$SNAPSHOT" | grep -qi "tone"; then
        log_pass "Right panel shows tone wildcard for outreach-email"
    else
        log_fail "Right panel wildcards did not update"
        result=1
    fi

    # Test 11: URL syncs prompt selection
    log "UI: URL syncs prompt selection"
    URL=$(agent-browser get url 2>/dev/null || echo "")
    if echo "$URL" | grep -q "prompt=outreach-email"; then
        log_pass "URL contains prompt=outreach-email"
    else
        log_fail "URL not synced: $URL"
        result=1
    fi

    # ── Behavioral: Export ──

    # Test 12: Export modal opens and has controls
    log "UI: Export modal"
    agent-browser click '[data-testid="pu-header-export-btn"]' 2>/dev/null || true
    sleep 1
    agent-browser screenshot "$SCREENSHOTS_DIR/12-export-modal.png" 2>/dev/null || true

    HAS_EXPORT=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-export-modal\"]")' 2>/dev/null || echo "false")
    if [ "$HAS_EXPORT" = "true" ]; then
        log_pass "Export modal opens"
    else
        log_fail "Export modal not visible"
        result=1
    fi

    # Test 13: Export modal has save/cancel controls
    log "UI: Export modal controls"
    HAS_CONTROLS=$(agent-browser eval '!!document.querySelector("[data-testid=\"pu-export-confirm-btn\"]") && !!document.querySelector("[data-testid=\"pu-export-cancel-btn\"]")' 2>/dev/null || echo "false")
    if [ "$HAS_CONTROLS" = "true" ]; then
        log_pass "Export modal has confirm/cancel buttons"
    else
        log_fail "Export modal missing controls"
        result=1
    fi

    # Close export modal
    agent-browser click '[data-testid="pu-export-cancel-btn"]' 2>/dev/null || true
    sleep 1

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
