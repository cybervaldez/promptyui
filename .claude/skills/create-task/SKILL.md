---
name: create-task
description: Plan and implement tasks for the cybervaldez-prompt-generator WebUI with e2e test validation. Use when the user asks to implement a feature, fix a bug, update functionality, or any task that modifies the WebUI codebase.
argument-hint: <task description>
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

## TL;DR

**What:** Implement features with built-in E2E tests. No screenshots, no manual verification.

**When:** After `/ux-planner` defines flows, or directly for well-defined tasks.

**Output:** Code changes + test files. Triggers parallel verification gates.

---

## Table of Contents

- [Tech Context Detection](#tech-context-detection)
- [Core Principles](#core-principles-must-follow)
- [Workflow](#workflow)
  - [1. Analyze the Task](#1-analyze-the-task)
  - [2. Discover Context](#2-discover-context)
  - [3. Plan the Implementation](#3-plan-the-implementation)
  - [4. Implement the Task](#4-implement-the-task)
  - [5. Create/Update E2E Test](#5-createupdate-e2e-test)
  - [6. Run the E2E Test](#6-run-the-e2e-test-required)
  - [7. Report Results](#7-report-results)
- [Shared Test Library](#shared-test-library-tests_pathlibtestutilssh)
- [Testing Rules](#testing-rules)
- [Anti-Patterns to AVOID](#anti-patterns-to-avoid)
- [Required Patterns](#required-patterns)
- [Quick Reference](#quick-reference)
- [Timing Patterns](#timing-patterns)
- [Error Handling Patterns](#error-handling-patterns)
- [Project Structure](#project-structure)
- [Verification Pattern Rankings](#verification-pattern-rankings)
- [Troubleshooting](#troubleshooting)
- [Superior Patterns Summary](#superior-patterns-summary)
- [Post-Implementation](#post-implementation)
- [Limitations](#limitations)
- [See Also](#see-also)
- [Advanced: API Configuration Endpoint](#advanced-api-configuration-endpoint)

---

## Tech Context Detection

Before executing, check for technology-specific patterns:

1. **Scan task** for technology mentions (libraries, frameworks, tools)
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: File structure? Scaffolding patterns? Test organization? Debug containers?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and apply tech-specific patterns

**Domains that affect this skill:** State Management, UI Components, Data Fetching, Routing, Build Tools, Auth

---

## Project Context Detection

After Tech Context Detection, classify the project to guide scaffolding and test fixtures:

1. **Read project signals** — `README.md`, `package.json` description/dependencies, existing routes
2. **Classify into 1-2 archetypes** from `PROJECT_CONTEXT.md` taxonomy
3. **Apply archetype context** — use per-skill mapping table in `PROJECT_CONTEXT.md` to select appropriate test data patterns and scaffold hints

Note: Unlike ux-planner/ui-planner, create-task does not need user confirmation of archetype — it uses the classification silently to inform test fixture selection and scaffold patterns.

---

# Task Implementation Skill

You are implementing tasks for the cybervaldez-prompt-generator WebUI. Each task includes planning, implementation, and **automated e2e test validation**.

**IMPORTANT:** Before implementing, review your project's coding conventions documentation.

## Core Principles (MUST FOLLOW)

| # | Principle | Rule |
|---|-----------|------|
| 1 | **Testable via agent-browser + curl** | No manual verification steps |
| 2 | **No fallback logic** | Fail explicitly, never default |
| 3 | **Debug containers** | Use hidden debug divs for JS state |
| 4 | **Ask, don't assume** | Clarify ambiguous requirements first |
| 5 | **E2E TESTS ONLY** | No unit tests. All tests via curl (API) or agent-browser (UI) |
| 6 | **Use test fixture** | Test with designated test job/data |
| 7 | **Use project Python** | Use ./venv/bin/python or project-configured Python |
| 8 | **Prioritize debuggability** | Clear errors over clever code |

## IMPORTANT: Fully Automated Testing

- **NO screenshots** - Never use screenshot commands
- **NO manual browser testing** - The user will NOT manually verify anything
- **ALL verification is automated** via `agent-browser` and `curl`
- You MUST run the e2e test after implementation to verify it works

## Workflow

### 1. Analyze the Task

Parse `$ARGUMENTS` to understand:
- **What** needs to be done (feature, fix, update, refactor)
- **Where** in the codebase (modal, API, component)
- **How** to validate (what should the e2e test verify)

### 2. Discover Context

```bash
# Find relevant source files
ls webui/prompty/js/**/*.js
ls webui/prompty/server/api/*.py

# Find existing tests for the area
ls tests//test_*.sh

# Get available testids
./venv/bin/python list-testids.py --json

# Search for related code
grep -r "pattern" webui/prompty/
```

### 3. Plan the Implementation

Create a brief plan covering:
1. **Files to modify** - List specific files
2. **Changes needed** - Describe modifications
3. **New testids** - Any data-testid attributes to add
4. **E2E test cases** - What to verify automatically

### 4. Implement the Task

Make the code changes following project conventions:
- JavaScript in `webui/prompty/js/`
- Python API in `webui/prompty/server/api/`
- Add `data-testid` attributes for testable elements

**CRITICAL - No Fallback Logic:**
```javascript
// WRONG - silent default
const composition = params.get('composition') || 42;

// RIGHT - explicit error
const composition = params.get('composition');
if (!composition) {
    return { error: 'composition parameter required', status: 400 };
}
```

**Add Debug Containers for Complex State:**
```html
<div id="component-debug" style="display:none;">
    <pre id="debug-state"></pre>
    <div id="debug-log"></div>
</div>
```

```javascript
function debugLog(key, value) {
    const container = document.getElementById('debug-log');
    if (!container) return;
    const entry = document.createElement('div');
    entry.dataset.key = key;
    entry.textContent = `${key}: ${JSON.stringify(value)}`;
    container.appendChild(entry);
}
```

### 5. Create/Update E2E Test

Write a test at `tests//test_<feature>.sh` that validates the implementation.

**IMPORTANT:** All tests MUST use the shared library at `tests//lib/test_utils.sh`.

#### Test Template (Standard Pattern)

```bash
#!/bin/bash
# ============================================================================
# E2E Test Suite: <Feature Name>
# ============================================================================
# <Brief description of what this tests>
#
# Usage: ./tests//test_<feature>.sh [--port 8085]
# ============================================================================

set +e  # Don't exit on error - let all tests run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

# Parse arguments
PORT="8085"
[[ "$1" == "--port" ]] && PORT="$2"
[[ "$1" =~ ^[0-9]+$ ]] && PORT="$1"

BASE_URL="http://localhost:$PORT"
TEST_ID="e2e-test-$$"

setup_cleanup  # Trap-based cleanup ensures browser closes on exit

print_header "<Test Suite Name>"

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

# ============================================================================
# TEST 1: <Test Name>
# ============================================================================
echo ""
log_info "TEST 1: <Test Name>"

# Test logic here using agent-browser and curl ONLY
# Use log_pass, log_fail, log_skip, log_info for output

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
```

### 6. Run the E2E Test (REQUIRED)

After implementation, you MUST run the test to verify everything works:

```bash
chmod +x tests//test_<feature>.sh
./tests//test_<feature>.sh
```

If tests fail, fix the issues and re-run until all tests pass.

### 7. Report Results

Provide:
- Summary of changes made
- Test results (pass/fail with counts)
- Any issues encountered and how they were resolved

## Shared Test Library (`tests//lib/test_utils.sh`)

All tests source this library for standardized functions:

### Logging Functions
```bash
log_pass "Message"   # [PASS] in green
log_fail "Message"   # [FAIL] in red
log_skip "Message"   # [SKIP] in yellow
log_info "Message"   # [INFO] in yellow
log_test "Message"   # [TEST] neutral
```

### Server Functions
```bash
wait_for_server              # Retry 10x with 1s delay, returns 0/1
wait_for_server "$CUSTOM_URL" # Custom URL
```

### Cleanup Functions
```bash
setup_cleanup  # Sets trap to close agent-browser on EXIT
```

### Summary Functions
```bash
print_summary  # Prints results, lists all TESTS, exits with 0/1
```

### API Functions
```bash
api_call METHOD URL [DATA]  # Sets HTTP_CODE and BODY globals
json_get "$json" ".path" "default"  # Safe JSON extraction
```

### Browser Helpers
```bash
open_page "$URL" [max_retries]  # Opens page with retry
check_snapshot "pattern" "success message"  # Snapshot + grep
print_header "Test Suite Name"  # Standard header output
```

## Testing Rules

1. **NO screenshots** - Use `agent-browser snapshot -c | grep` for verification
2. **NO manual testing** - Everything is automated
3. **agent-browser** for all UI testing
4. **curl** for all API testing
5. **data-testid** for element selection
6. **ALWAYS run tests** after implementation
7. **ALWAYS use shared library** - Source `lib/test_utils.sh`
8. **Use test job/fixture** - Test with designated test data
9. **Use project Python** - Use ./venv/bin/python

## Test Environment

Start servers for testing:
```bash
# Start server (default port 8085)
./start-prompty.sh
```

The `test-fixtures` job is designated for testing - its `outputs` folder can be safely deleted and rebuilt.

## Anti-Patterns to AVOID

| Anti-Pattern | Example | Why It's Wrong |
|--------------|---------|----------------|
| Default values | `params.get('x', 42)` | Silent wrong value |
| Fallback chains | `x ?? y ?? z ?? 42` | Untraceable source |
| State fallbacks | `state.x \|\| default` | False positives |
| Silent failures | `catch(e) { return [] }` | Bugs hidden |
| Unit tests | `pytest test_modal.py` | Not e2e |
| Manual verification | "Click and check..." | Not automatable |

## Required Patterns

| Pattern | Example | Benefit |
|---------|---------|---------|
| Required params | `if (!x) return error(400)` | Clear failure |
| Single source | `getFromURL()` only | Traceable |
| Explicit errors | `{"error": "x required"}` | Debuggable |
| Debug containers | `debugLog('key', value)` | Visible to agent-browser |
| E2E tests | `tests/test_*.sh` | Full coverage |

## Quick Reference

### Browser Commands (agent-browser only)

```bash
agent-browser open "http://localhost:8085"
agent-browser snapshot -c          # Compact output for grep
agent-browser snapshot -i          # Interactive elements with refs
agent-browser click @e1            # Click by ref
agent-browser eval "JS code"       # Execute JavaScript
agent-browser get title            # Get page title
agent-browser get url              # Get current URL
agent-browser close                # Always close when done
```

### API Commands (curl only)

```bash
# GET request
curl -sf http://localhost:8085/api/pu/endpoint | jq '.'

# POST request
curl -sf -X POST http://localhost:8085/api/pu/endpoint \
  -H "Content-Type: application/json" -d '{"key": "value"}'

# DELETE request
curl -sf -X DELETE http://localhost:8085/api/pu/endpoint
```

### Verification Patterns (Using Shared Library)

```bash
# Check UI element exists via JS eval (preferred)
HAS_ELEM=$(agent-browser eval "!!document.querySelector('[data-testid=\"foo\"]')" 2>/dev/null)
[ "$HAS_ELEM" = "true" ] && log_pass "Element found" || log_fail "Element missing"

# Check API response
curl -sf "$URL" | grep -q "expected" && log_pass "API OK" || log_fail "API failed"

# Check JS state
RESULT=$(agent-browser eval 'Modal.state?.field' 2>/dev/null | tr -d '"')
[ "$RESULT" = "expected" ] && log_pass "State OK" || log_fail "State: $RESULT"

# Using api_call helper
api_call GET "$BASE_URL/api/pu/endpoint"
[ "$HTTP_CODE" = "200" ] && log_pass "GET succeeded" || log_fail "HTTP $HTTP_CODE"

# Using json_get helper
STATUS=$(json_get "$BODY" '.status' 'error')
[ "$STATUS" = "success" ] && log_pass "Success" || log_fail "Status: $STATUS"
```

### HTTP Status Code Capture

```bash
# Capture both body and HTTP status code
RESULT=$(curl -sf -w "\n%{http_code}" -X POST "$URL" -d '...' 2>&1)
HTTP_CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')

# Check status
[ "$HTTP_CODE" = "200" ] && log_pass "OK" || log_fail "HTTP $HTTP_CODE"
```

### Snapshot + grep Pattern

```bash
# Save snapshot for multiple checks
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -qi "expected text" && log_pass "Found" || log_fail "Missing"
echo "$SNAPSHOT" | grep -qi "another item" && log_pass "Found another" || log_fail "Missing"
```

## Timing Patterns

### Standard Wait Durations

| Duration | Use Case |
|----------|----------|
| 0.3-0.5s | UI state change (checkbox, toggle) |
| 1s | Quick interaction, simple click |
| 1.5-2s | Modal render, dialog open |
| 4s | Full page load, generation complete |

## Error Handling Patterns

### Graceful Skip

```bash
# Skip tests when required conditions aren't met
if ! curl -sf "$BASE_URL/" > /dev/null 2>&1; then
    log_info "Server not available - skipping tests"
    exit 0
fi
```

### Fallback Values

```bash
# Always provide defaults for optional fields
VALUE=$(json_get "$RESPONSE" '.field' 'default')
COUNT=$(json_get "$RESPONSE" '.count' '0')
```

## Project Structure

```
webui/prompty/
├── js/
│   ├── app.js              # Main app
│   ├── modal/              # Modal components
│   └── components/         # UI components
├── server/
│   ├── api/                # API endpoints
│   └── cli/                # CLI tools
tests//
├── lib/
│   └── test_utils.sh       # Shared test utilities (REQUIRED)
└── test_*.sh               # E2E test scripts (bash only)
```

## Verification Pattern Rankings

Use patterns in this order of preference:

| Rank | Pattern | Use Case |
|------|---------|----------|
| 1 | HTTP status + jq JSON | API testing |
| 2 | `data-testid` + JS eval | UI element finding |
| 3 | role-based `agent-browser find` | Accessibility-based clicks |
| 4 | Snapshot + grep | Text verification |
| 5 | CSS class selectors | Avoid (fragile) |
| 6 | Ref-based parsing | Avoid (complex) |

## Troubleshooting

### Server Health Check

```bash
# Verify server is running (works with any server type)
curl -sf "$BASE_URL/" > /dev/null && echo "Server running" || echo "Server down"
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Browser not responding | Run `agent-browser close` then retry |
| curl timeout | Check server is running, increase `-m` timeout |
| jq parse error | Add `2>/dev/null` and use `json_get` with fallback |
| Element not found | Add sleep before snapshot, check testid |
| State not updated | Wait longer after interaction |
| Tests exit early | Ensure `set +e` is at top of script |
| Cleanup not running | Use `setup_cleanup` for trap-based cleanup |

### Debug Output

```bash
# Enable verbose output for debugging
set -x  # Turn on at start of problematic section
# ... commands ...
set +x  # Turn off after
```

## Superior Patterns Summary

Always use these patterns for consistency:

| Pattern | Implementation |
|---------|---------------|
| PORT handling | `PORT="${1:-8085}"; [[ "$1" == "--port" ]] && PORT="$2"` |
| Library source | `source "$SCRIPT_DIR/lib/test_utils.sh"` |
| Server check | `wait_for_server` with retry |
| Cleanup | `setup_cleanup` with trap |
| Output format | `[PASS]/[FAIL]/[SKIP]/[INFO]` brackets |
| Error handling | `set +e` at start |
| Summary | `print_summary` with TESTS array |
| JSON parsing | `json_get` with fallbacks |

## Post-Implementation

After completing the task, consider running:
- `/coding-guard` - Check for coding convention violations
- `/e2e-guard` - Ensure test coverage exists
- `/ux-review` - Verify UX from user perspective

## Limitations

- **Modifies files** - Creates and edits source code and test files
- **Pipeline position** - Central implementation skill; receives input from `/ux-planner` or `/ui-planner`
- **Prerequisites** - Server should be running for test execution; project structure must exist
- **Not suitable for** - Pure research tasks; strategic discussions (use `/team` instead)
- **Test execution** - Requires running server on configured port; tests will fail if server is down

## See Also

- `/coding-guard` - Post-implementation audit (run after implementing)
- `/e2e-guard` - E2E test coverage verification
- `/ux-review` - User perspective verification
- `tests//lib/test_utils.sh` - Shared test utilities source code
- `references/testing-conventions.md` - Detailed testing patterns

---

## Advanced: API Configuration Endpoint

When your project has an API backend, add a `/api/config` endpoint for enhanced testing:

```python
@app.route('/api/config')
def config():
    return jsonify({
        "debug": app.config.get('DEBUG', False),
        "job_name": os.environ.get('JOB_NAME', 'default')
    })
```

This enables debug mode checks and configuration verification:

```bash
# Check server mode before testing mode-specific features
DEBUG_MODE=$(curl -sf "$BASE_URL/api/pu/config" | jq -r '.debug // false')
if [ "$DEBUG_MODE" != "true" ]; then
    log_info "Server not in debug mode - skipping generation tests"
fi

# Verify server config
CONFIG=$(curl -sf "$BASE_URL/api/pu/config")
echo "Debug mode: $(echo "$CONFIG" | jq -r '.debug')"
echo "Job: $(echo "$CONFIG" | jq -r '.job_name')"
```

**Note:** Basic health checks use root path `/` and work without an API.
