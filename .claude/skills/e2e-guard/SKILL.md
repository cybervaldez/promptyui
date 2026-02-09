---
name: e2e-guard
description: Analyze code changes, auto-generate e2e tests, and run them. Use after implementing changes to ensure test coverage.
---

## TL;DR

**What:** Auto-generate E2E tests for code changes. Ensures coverage exists.

**When:** After `/create-task`, in parallel with other guards.

**Output:** New/updated test files in `tests/`. Runs tests to verify.

---

## Tech Context Detection

Before generating tests, check for technology-specific coverage patterns:

1. **Scan changed files** for technology imports/usage
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: Coverage patterns? Element selection? API verification? State assertions?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and apply tech-specific test generation patterns

**Domains that affect this skill:** Data Fetching, Form Handling, Routing, Testing Tools

---

# E2E Test Guard - Post-Implementation Test Generator

> **PROJECT TESTING PHILOSOPHY**
>
> This project uses **E2E tests exclusively**:
> - **API changes** -> Test via `curl` / `api_call` helper
> - **UI changes** -> Test via `agent-browser` (snapshot + grep)
> - **NO unit tests** -> pytest for isolated functions is forbidden
> - **NO mocks** -> Test against real server with debug mode
>
> Why: E2E tests catch integration bugs that unit tests miss. They test the actual user experience.

## Objective-Based Test Requirements

Every test MUST verify **behavior**, not just **existence**:

| Element Test (Bad) | Objective Test (Good) |
|-------------------|----------------------|
| "Button exists" | "Button exists AND click triggers expected action" |
| "Container renders" | "Container shows correct data (not 0/0)" |
| "No JS errors" | "No JS errors AND state matches expected values" |

**The key question**: "What should the USER see when this works correctly?"

### Test Structure (Required)

1. **Objective**: What user goal does this test verify?
2. **Setup**: Navigate to correct state
3. **Verify Element**: Check element exists
4. **Verify Behavior**: Check element shows CORRECT values
5. **Verify Side Effects**: Check state changes are correct

### Example: Component Test

```bash
# BAD: Element-only test
test_component_visible() {
    SNAPSHOT=$(agent-browser snapshot -c)
    if echo "$SNAPSHOT" | grep -q "component-container"; then
        log_pass "Component container visible"  # Passes even with wrong data!
    fi
}

# GOOD: Objective test
test_component_shows_correct_data() {
    # Objective: User sees actual data (e.g., "5/10", not "0/0")

    # Get actual data from API
    api_total=$(curl -sf "$BASE_URL/api/pu/data" | jq '.total')

    # Verify UI shows non-zero when data exists
    ui_text=$(agent-browser eval "document.querySelector('.stat-value')?.textContent")

    if [ "$api_total" -gt 0 ]; then
        if echo "$ui_text" | grep -qE "[1-9][0-9]*/[1-9][0-9]*"; then
            log_pass "Shows actual counts: $ui_text"
        else
            log_fail "Shows 0/0 but API has $api_total items"
        fi
    fi
}
```

### Checklist for Test Reviews

- [ ] Does test verify user-facing behavior (not just element existence)?
- [ ] Does test compare UI to expected data (API response, state)?
- [ ] Does test fail when feature is broken (not just missing)?
- [ ] Does test document the OBJECTIVE being verified?

---

## Startup Behavioral Tests

Tests MUST verify data loads correctly at startup. Many bugs only manifest on fresh page load when state is not yet initialized.

### Required Startup Checks

1. **Counts match API**: Verify UI counts match API data
2. **Elements load**: Verify key elements appear on page load
3. **State initialized**: Verify `window.state` or similar is set
4. **No fallback data**: Verify UI shows real data, not defaults

### Example: Startup Test

```bash
test_data_loads_at_startup() {
    log_test "OBJECTIVE: User sees data on load"

    # Navigate fresh (no prior state)
    agent-browser close 2>/dev/null || true
    agent-browser open "$BASE_URL/"
    sleep 3

    # Check API has data
    api_count=$(curl -sf "$BASE_URL/api/pu/items" | jq '.total')

    # Check UI shows count
    ui_count=$(agent-browser eval "parseInt(document.getElementById('items-count')?.textContent || '0')")

    if [ "$api_count" -gt 0 ] && [ "$ui_count" = "0" ]; then
        log_fail "API has $api_count items but UI shows 0 - STARTUP BUG"
    else
        log_pass "UI count matches API: $ui_count"
    fi
}
```

### Startup Test Checklist

- [ ] Test opens fresh browser (calls `agent-browser close` first)
- [ ] Test waits for page load (sleep 3+ seconds)
- [ ] Test compares UI to API data (ground truth)
- [ ] Test fails when UI shows 0 but API has data
- [ ] Test documents the OBJECTIVE being verified

---

Run this skill after implementing changes to ensure e2e test coverage exists and passes.

## How to Use

```
/e2e-guard
```

No arguments needed. The skill automatically:
1. Finds recently modified files via `git diff`
2. Analyzes what tests are needed based on change type
3. Checks existing test coverage
4. Auto-generates missing tests following project standards
5. Runs all relevant tests

## Workflow Steps

> **E2E TESTS ONLY** - This project uses exclusively end-to-end tests. No unit tests (pytest for isolated functions). All Python backend changes are tested via API calls (curl). All JS changes are tested via browser automation (agent-browser).

### Step 1: Find Changed Files

```bash
# Get modified files
git diff --name-only HEAD -- '*.js' '*.py' '*.css'

# Or check unstaged changes
git diff --name-only -- '*.js' '*.py' '*.css'
```

### Git State Handling

| Git State | Behavior |
|-----------|----------|
| Has commits, changes exist | Uses `git diff HEAD` |
| First commit ever | Uses `git diff --cached` |
| No changes | No tests to generate - success |
| No git repo | Error: "Not a git repository" |

**First commit scenario:**
```bash
# Stage your files first
git add .

# Then run e2e-guard
/e2e-guard  # Will use --cached automatically
```

### Step 2: Categorize Changes

| File Pattern | Test Type | Tool |
|--------------|-----------|------|
| `webui/prompty/server/api/*.py` | API test | curl via `api_call` |
| `webui/prompty/js/modal/*.js` | Modal UI test | agent-browser |
| `webui/prompty/js/home/*.js` | Home grid test | agent-browser |
| `webui/prompty/js/sidebar/*.js` | Sidebar test | agent-browser |
| `webui/prompty/js/core/*.js` | Core integration | agent-browser |
| `src/*.py` | API integration | curl via `api_call` |
| `*.css` | Visual only | Skip (no auto-test) |

### Step 3: Check Existing Coverage

For each changed file:

1. **API files** - Check if endpoint is covered in test files
   ```bash
   grep -l "endpoint_name" tests/*.sh
   ```

2. **JS files** - Check for corresponding test
   ```bash
   # webui/prompty/js/modal/foo.js -> tests/test_foo*.sh
   ls tests/test_*foo*.sh 2>/dev/null
   ```

3. **TestIDs** - Verify new UI elements have testids
   ```bash
   ./venv/bin/python list-testids.py --json | grep "component-name"
   ```

### Step 4: Auto-Generate Tests

#### 4.1 API Tests (curl-based)

For new/modified API endpoints:

```bash
log_test "Test: New endpoint returns expected data"
api_call GET "$BASE_URL/api/pu/new-endpoint"
if echo "$BODY" | jq -e '.expected_key' > /dev/null; then
    log_pass "Endpoint returns expected_key"
else
    log_fail "Missing expected_key in response"
fi
```

#### 4.2 Modal UI Tests (agent-browser)

For new/modified modals:

```bash
#!/bin/bash
set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Modal Name Tests"

# Pre-flight
if ! wait_for_server "$BASE_URL"; then
    log_fail "Server not running"
    exit 1
fi

# Test: Modal opens
log_test "Modal opens via URL parameter"
agent-browser open "$BASE_URL/?modal=modalname"
sleep 2
SNAPSHOT=$(agent-browser snapshot -c)
if echo "$SNAPSHOT" | grep -q 'data-testid="modal-testid"'; then
    log_pass "Modal visible"
else
    log_fail "Modal not found in DOM"
fi

# Test: No JS errors
log_test "No JavaScript errors"
JS_ERRORS=$(agent-browser errors 2>/dev/null || echo "")
if [ -z "$JS_ERRORS" ] || echo "$JS_ERRORS" | grep -q "^\[\]$"; then
    log_pass "No JS errors"
else
    log_fail "JS errors: $JS_ERRORS"
fi

# Test: Key elements present
log_test "Key elements have testids"
for TESTID in "element-1" "element-2" "element-3"; do
    if echo "$SNAPSHOT" | grep -q "data-testid=\"$TESTID\""; then
        log_pass "Found $TESTID"
    else
        log_fail "Missing $TESTID"
    fi
done

agent-browser close 2>/dev/null || true
print_summary
```

#### 4.3 Component Tests (agent-browser)

For JS component changes:

```bash
#!/bin/bash
set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_utils.sh"

PORT="${1:-8085}"
BASE_URL="http://localhost:$PORT"

setup_cleanup
print_header "Component Name Tests"

if ! wait_for_server "$BASE_URL"; then
    log_fail "Server not running"
    exit 1
fi

# Test: Component renders
log_test "Component renders on page"
agent-browser open "$BASE_URL/?param=value"
sleep 3
SNAPSHOT=$(agent-browser snapshot -c)

if echo "$SNAPSHOT" | grep -q 'expected-content'; then
    log_pass "Component content visible"
else
    log_fail "Component content missing"
fi

# Test: Interaction works
log_test "Click interaction works"
agent-browser find role button click --name "Button Text" 2>/dev/null
sleep 1
SNAPSHOT=$(agent-browser snapshot -c)
if echo "$SNAPSHOT" | grep -q 'expected-result'; then
    log_pass "Interaction successful"
else
    log_fail "Interaction failed"
fi

agent-browser close 2>/dev/null || true
print_summary
```

### Step 5: Run Tests

```bash
# Run the generated/updated test
bash tests/test_component.sh 8085

# Run full test suite if major changes
./venv/bin/python test-ui.py --port 8085
```

### Step 6: Report Results

```
## E2E Test Guard Results

### Files Changed
- webui/prompty/js/modal/example.js (UI)
- webui/prompty/server/api/operations.py (API)

### Coverage Analysis

| File | Existing Test | Coverage | Action |
|------|---------------|----------|--------|
| modal/example.js | test_example_modal.sh | Adequate | None |
| api/operations.py | test_operations.sh | Gap found | Added test |

### Tests Generated
- tests/test_operations_new_endpoint.sh (NEW)

### Test Results
| Test | Status |
|------|--------|
| test_example_modal.sh | PASS (5/5) |
| test_operations.sh | PASS (14/14) |
| test_operations_new_endpoint.sh | PASS (3/3) |

### Summary
- Files analyzed: 2
- Coverage gaps: 1
- Tests generated: 1
- All tests passing: YES
```

## Test File Locations

| Test Type | Directory | Naming |
|-----------|-----------|--------|
| API (shell) | `tests/` | `test_{feature}.sh` |
| UI modal | `tests/ui/` | `test_{modal}_modal.sh` |
| UI component | `tests/ui/` | `test_{component}.sh` |

## Standards Reference

### TestID Requirements
All new UI elements MUST have `data-testid` attributes:
```javascript
// Good
<button data-testid="action-generate-btn">Generate</button>

// Bad - no testid
<button>Generate</button>
```

### API Test Pattern
```bash
api_call METHOD "$BASE_URL/api/pu/endpoint" '{"json":"body"}'
# HTTP_CODE and BODY are set by api_call
if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | jq -e '.success' > /dev/null; then
    log_pass "Test passed"
fi
```

### UI Test Pattern
```bash
# Always use snapshot + grep (never screenshots)
agent-browser open "$URL"
sleep 2
SNAPSHOT=$(agent-browser snapshot -c)
echo "$SNAPSHOT" | grep -q 'expected' && log_pass "Found"

# Always check for JS errors
agent-browser errors

# Always cleanup
agent-browser close
```

## Starting Servers for Testing

**IMPORTANT:** Always use the startup scripts, not raw python commands.

```bash
# Start server (default port 8085)
./start-prompty.sh
```

**Never use raw python commands** - the startup scripts handle venv activation, default flags, and port configuration.

## Quick Reference

```bash
# List all testids
./venv/bin/python list-testids.py --json

# Run specific UI test
bash tests/ui/test_component.sh 8085

# Run all UI tests
./venv/bin/python test-ui.py --port 8085
```

## Limitations

- **Modifies files** - Creates new test files; updates existing tests
- **Pipeline position** - Runs in parallel with `/coding-guard`, `/cli-first`, `/ux-review` after `/create-task`
- **Prerequisites** - Requires `git diff` output; changed files must be committed or staged
- **Not suitable for** - CSS-only changes; visual-only changes that don't affect behavior
- **Non-testable changes** - Skip for: styling tweaks, comments, documentation, type-only changes

## See Also

- `/coding-guard` - Code pattern auditing (run before this)
- `/e2e` - Full e2e test orchestration
- `/e2e-investigate` - Failure investigation
- `tests/lib/test_utils.sh` - Shell test utilities
