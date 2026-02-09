---
name: e2e-investigate
description: Investigate e2e test failures, diagnose root causes, and generate actionable tasks for /create-task.
---

## TL;DR

**What:** Root cause analysis for `/e2e` failures. Reads artifacts, diagnoses issues.

**When:** After `/e2e` fails. Required after 3+ consecutive failures.

**Output:** Task description ready for `/create-task` with root cause and suggested fix.

---

## Tech Context Detection

Before investigating, check for technology-specific failure patterns:

1. **Scan failing tests and error logs** for technology mentions
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: Failure patterns? Log formats? Reproduction? Debug tools?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and apply tech-specific investigation patterns

**Domains that affect this skill:** Testing Tools, State Management (common failure modes), Data Fetching

---

# E2E Failure Investigation

Analyze failing `/e2e` test results, investigate root causes, and produce actionable task descriptions ready for `/create-task`.

**Workflow:** `/e2e` (fails) -> `/e2e-investigate` -> `/create-task` (fix)

## When to Trigger

| Scenario | Action |
|----------|--------|
| `/e2e` fails once | Review failure, attempt quick fix, re-run `/e2e` |
| `/e2e` fails twice | Check if same test; consider `/e2e-investigate` |
| `/e2e` fails 3+ times | **Mandatory:** Run `/e2e-investigate` before more retries |
| Flaky test (passes sometimes) | Run `/e2e-investigate` to identify timing issues |
| New failure after code change | Quick fix first; `/e2e-investigate` if unclear |

### Invocation

```bash
# Automatic (reads latest e2e run)
/e2e-investigate

# After specific run
/e2e-investigate tests/e2e-runs/20240115_143022/
```

The skill automatically reads `tests/e2e-runs/latest/` if no path is specified.

## Quick Start

```bash
/e2e-investigate
```

No arguments needed. Automatically reads the latest e2e run artifacts.

## What It Does

1. **Parse Failure**: Read `tests/e2e-runs/latest/report.md` to identify failed phases
2. **Gather Evidence**: Collect screenshots, server logs, error messages
3. **Investigate Root Cause**: Analyze code, check patterns, identify the bug
4. **Diagnose Issue Type**: Categorize (API, UI, state, timing, persistence)
5. **Generate Task**: Output structured task description for `/create-task`

---

## Investigation Workflow

### Step 1: Parse Failure Report

```bash
# Read the latest report
cat tests/e2e-runs/latest/report.md

# Extract failed phases
grep -A5 "FAIL" tests/e2e-runs/latest/report.md
```

Look for:
- Which phase(s) failed
- Error messages in the Errors section
- Duration (short = early failure, long = timeout)
- Suggested fixes already in the report

### Step 2: Gather Evidence (Screenshots as Reference)

> **Note:** Use screenshots as reference when live reproduction is not possible.
> Prefer Step 2.1 (live debugging) when you can interact with the running server.

**Server Logs:**
```bash
# Check for exceptions and stack traces
cat tests/e2e-runs/latest/server.log | grep -E "(Error|Exception|Traceback|404|500)" -A5

# For server restart issues
cat tests/e2e-runs/latest/server_restart.log
```

**Screenshots:**
```bash
# List available screenshots
ls tests/e2e-runs/latest/screenshots/

# View specific screenshot (use Read tool)
# tests/e2e-runs/latest/screenshots/06-server-restart.png
```

**What to look for in screenshots:**
| Screenshot | Check For |
|------------|-----------|
| 01-startup-clean.png | Main UI visible, no error modals |
| 02-navigation.png | Content loaded, parameters set |
| 03-generation.png | Generated content visible in grid |
| 04-post-generation.png | Counts updated, state reflects changes |
| 05-persistence.png | Same state after refresh |
| 06-server-restart.png | Data still visible after restart |

### Step 2.1: Reproduce Issue Live (Preferred)

Before analyzing screenshots, try to reproduce the failure interactively:

```bash
# Start server
./start-prompty.sh

# Reproduce the failing scenario with curl
curl -sf "{{BASE_URL}}/api/pu/endpoint" | jq '.'

# Or reproduce with agent-browser snapshot (not screenshot)
agent-browser open "{{BASE_URL}}/"
agent-browser snapshot -c | grep "expected-element"
```

**Why live debugging first:**
- Active reproduction reveals more than static screenshot analysis
- You can try variations and narrow down the root cause
- Snapshot + curl are low-cost verification methods (~500 tokens vs ~2000+ for screenshots)

If you cannot reproduce the issue live, then analyze the screenshot artifacts from `/e2e`.

### Step 3: Investigate Root Cause

Search codebase for related code:

```bash
# For API issues
grep -r "relevant_endpoint" webui/prompty/server/api/

# For UI issues
grep -r "component_name" webui/prompty/js/

# For state issues
grep -r "fallback\|default\||| " webui/prompty/js/

# For persistence issues
grep -r "scan\|index\|startup\|outputs" webui/prompty/server/
```

**Check for anti-patterns:**
- Silent defaults: `x || 42`, `x ?? defaultValue`
- Missing error handling: `catch(e) { }`
- Hardcoded values that should be dynamic
- Race conditions in async code

### Step 4: Categorize Issue Type

| Category | Symptoms | Investigation Focus |
|----------|----------|---------------------|
| **API/Data** | 500 errors, missing fields, wrong data | `webui/prompty/server/api/*.py`, server.log |
| **UI Element** | Element not found, wrong visibility | `webui/prompty/js/*.js`, data-testid attrs |
| **State** | Wrong/stale state, 0/0 counts | State initialization, fallback logic |
| **Timing** | Flaky, timeout, intermittent | Sleep durations, async handling |
| **Persistence** | Data lost on restart/refresh | Server startup scan, file I/O |

**Common Root Causes by Category:**

**API/Data:**
- Endpoint returns wrong data structure
- Missing error propagation
- Query parameters not parsed

**UI Element:**
- Missing data-testid
- Element hidden/conditional
- Wrong selector in test

**State:**
- Fallback defaults hiding real errors
- State not initialized before access
- URL params not read correctly

**Timing:**
- Insufficient wait times
- Race between API and render
- SSE events not awaited

**Persistence:**
- Server doesn't scan outputs on startup
- Files written to wrong location
- State not preserved in URL

### Step 5: Generate Task Description

Output this format for `/create-task`:

```markdown
## Fix: [Specific Issue Title]

### Root Cause
[What's broken and why - with file:line references]

### Expected Behavior
[What should happen when working correctly]

### Suggested Fix
[Code location and approach]

### Verification
[How /e2e will verify the fix works]
```

---

## E2E Artifacts Reference

After `/e2e` runs, these artifacts exist:

```
tests/e2e-runs/latest/          <- Symlink to most recent run
├── report.md                   <- Structured failure report
├── server.log                  <- Server output with exceptions
├── server_restart.log          <- Phase 7 restart log (if applicable)
└── screenshots/
    ├── 01-startup-clean.png
    ├── 02-navigation.png
    ├── 03-generation.png
    ├── 04-post-generation.png
    ├── 05-persistence.png
    └── 06-server-restart.png
```

**Report.md Structure:**
- Summary (phases, passed/failed, duration)
- Phase Results (status, duration, errors per phase)
- Screenshots list
- Failures section with suggested fixes

---

## Evidence Checklist

For each failure type, check these:

### API Failures
- [ ] server.log for 4xx/5xx errors
- [ ] Stack traces in server.log
- [ ] API endpoint code in `webui/prompty/server/api/`
- [ ] Request/response format

### UI Failures
- [ ] Screenshot for visual state
- [ ] JS errors in server.log (browser console)
- [ ] Component code in `webui/prompty/js/`
- [ ] data-testid attributes present

### State Failures
- [ ] Screenshot shows wrong values
- [ ] Check for fallback defaults in JS
- [ ] URL parameter handling
- [ ] State initialization order

### Timing Failures
- [ ] Check test sleep durations
- [ ] Look for race conditions
- [ ] SSE event handling
- [ ] Async/await usage

### Persistence Failures
- [ ] server_restart.log for errors
- [ ] Screenshot shows state lost
- [ ] Server startup scan logic
- [ ] File existence in outputs/

---

## Example Investigation

**Scenario:** Phase 7 (Server Restart) fails with "Data not visible after server restart"

### Step 1: Parse Failure

```
Phase 7: Server Restart - FAIL
- Duration: 6s
- Errors: Data not visible after server restart
```

### Step 2: Gather Evidence

```bash
# Screenshot shows "ITEMS (0)" in sidebar
# Read: tests/e2e-runs/latest/screenshots/06-server-restart.png

# Server restart log shows clean startup
cat tests/e2e-runs/latest/server_restart.log
# No exceptions, server started on port 8085

# Check if outputs exist
ls outputs/
# Files are present on disk
```

**Finding:** Files exist on disk but UI shows 0 count.

### Step 3: Investigate

```bash
# How does server discover outputs on startup?
grep -r "scan\|index" webui/prompty/server/ --include="*.py"

# Found: scan_repair.py handles output discovery
# Check if it scans correctly
grep -r "scan" webui/prompty/server/scan_repair.py
```

**Finding:** Server scans outputs but may not index them correctly.

### Step 4: Categorize

- **Type**: Persistence issue
- **Focus**: Server startup scan logic
- **Pattern**: State initialization

### Step 5: Generate Task

```markdown
## Fix: Generated data not persisted across server restart

### Root Cause
The server's startup scan in `webui/prompty/server/scan_repair.py` does not
index existing files correctly. Files are generated and saved
to disk, but when the server restarts, they are not re-discovered.

The scan logic may be filtering incorrectly or not reading the
correct status files.

### Expected Behavior
After server restart, previously generated items should:
1. Appear in the sidebar with correct counts
2. Be visible in the main grid
3. Show "ITEMS (N)" where N > 0

### Suggested Fix
1. Check `webui/prompty/server/scan_repair.py` startup logic
2. Ensure all items are indexed in the scan
3. Verify status files are read correctly from outputs/

### Verification
Run `/e2e` - Phase 7 (Server Restart) should pass with data visible.
```

---

## Failure Patterns Reference

### Pattern: "0/0" Counts
- **Symptom**: UI shows 0/0 even with data
- **Cause**: Fallback defaults, scan not running
- **Check**: UI state code, API endpoints

### Pattern: "Data not visible after restart"
- **Symptom**: Count drops to 0 after server restart
- **Cause**: Server doesn't re-scan outputs on startup
- **Check**: Server startup sequence, scan logic

### Pattern: "Element not found"
- **Symptom**: Test can't find UI element
- **Cause**: Missing data-testid, element not rendered
- **Check**: Component code, conditional rendering

### Pattern: "State lost after refresh"
- **Symptom**: Phase 6 fails, state resets
- **Cause**: URL params not preserved, localStorage issue
- **Check**: URL handling, state persistence code

### Pattern: "Generation timeout"
- **Symptom**: Phase 4 fails after long duration
- **Cause**: Generation hung, wrong parameters
- **Check**: server.log for generation progress, API calls

---

## Integration with /create-task

The output from `/e2e-investigate` is designed to feed directly into `/create-task`:

1. Run `/e2e` -> get failure
2. Run `/e2e-investigate` -> get task description
3. Copy task description to `/create-task <description>`
4. Implement fix
5. Run `/e2e` -> verify fix

---

## Starting Servers for Debugging

**IMPORTANT:** Always use the startup scripts, not raw python commands.

```bash
# Start server (default port 8085)
./start-prompty.sh
```

**Never use raw python commands** - the startup scripts handle venv activation, default flags, and port configuration.

## Limitations

- **Read-only** - Investigates failures but doesn't fix them; outputs to `/create-task`
- **Pipeline position** - Triggered by `/e2e` failures; feeds into `/create-task` for fixes
- **Prerequisites** - Requires `/e2e` to have run and failed; needs failure artifacts in `tests/e2e-runs/`
- **Not suitable for** - Successful test runs; test authoring (use `/e2e-guard` for that)
- **Artifact dependency** - Screenshots and logs must exist; if artifacts are missing, re-run `/e2e` first

| Limitation | Next Step |
|------------|-----------|
| No artifacts | Run `/e2e` first to generate failure artifacts |

## See Also

- `/e2e` - Run the full e2e test suite
- `/create-task` - Implement the fix based on investigation
- `/coding-guard` - Audit code changes
- `/e2e-guard` - Verify test coverage
