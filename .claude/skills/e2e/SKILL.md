---
name: e2e
description: Orchestrate full e2e test run with visual verification. Cleans state, starts server, runs test phases, takes screenshots, and generates detailed report.
argument-hint: [--phase <name> | --port <number> | --no-cleanup]
---

## TL;DR

**What:** Full E2E test orchestration with screenshots. Clean state → run tests → generate report.

**When:** Final verification gate after all parallel guards pass.

**Output:** Test report in `tests/e2e-runs/` with screenshots and pass/fail analysis.

---

## Tech Context Detection

Before executing, check for technology-specific test orchestration patterns:

1. **Scan test files and codebase** for technology usage
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: Server startup? Artifact paths? Timing/waits? Cleanup?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and apply tech-specific orchestration patterns

**Domains that affect this skill:** Testing Tools, Animation (wait patterns), Build Tools (server startup), Routing

---

# E2E Test Orchestrator

Full end-to-end test suite with visual verification via screenshots.

## Quick Start

```bash
/e2e
```

## What It Does

1. **Clean Slate**: Removes `outputs` for fresh state
2. **Server Start**: Starts server with debug mode for fast testing
3. **Run Test Phases**: Executes phases in sequence with screenshots
4. **Visual Verification**: Takes screenshots at each checkpoint
5. **Generate Report**: Produces detailed pass/fail analysis

## Usage

```bash
# Run full e2e suite
./tests/e2e-orchestrator.sh

# Run single phase (for debugging)
./tests/e2e-orchestrator.sh --phase startup
./tests/e2e-orchestrator.sh --phase navigation
./tests/e2e-orchestrator.sh --phase generation

# Keep server running after tests (for debugging)
./tests/e2e-orchestrator.sh --no-cleanup

# Use different port
./tests/e2e-orchestrator.sh --port 8085
```

## Test Phases

| # | Phase | Screenshot | Pass Criteria |
|---|-------|------------|---------------|
| 1 | Setup | - | Clean outputs, server starts |
| 2 | Startup | `01-startup-clean.png` | No JS errors, main UI visible |
| 3 | Navigation | `02-navigation.png` | Content loads correctly |
| 4 | Generation | `03-generation.png` | Generated content visible |
| 5 | Post-Gen | `04-post-generation.png` | Counts and state updated |
| 6 | Persistence | `05-persistence.png` | State survives page refresh |
| 7 | Server Restart | `06-server-restart.png` | Data persists after server restart |

## Output Structure

```
tests/e2e-runs/
  {YYYYMMDD_HHMMSS}/
    screenshots/
      01-startup-clean.png
      02-navigation.png
      03-generation.png
      04-post-generation.png
      05-persistence.png
      06-server-restart.png
    report.md
    server.log
    server_restart.log
```

## Visual Verification Criteria

| Phase | What to Check |
|-------|---------------|
| Startup | Main UI visible, no console errors, elements load |
| Navigation | Content loads, parameters work |
| Generation | Generated content appears in grid |
| Post-Gen | Counts update, state changes visible |
| Persistence | After page refresh, same state preserved |
| Server Restart | After server stop/start, data still visible |

## Starting Servers

**IMPORTANT:** Always use the startup scripts, not raw python commands.

```bash
# Start server (default port 8085)
./start-prompty.sh
```

**Never use raw python commands** - the startup scripts handle venv activation, default flags, and port configuration.

## Phase Details

### Phase 1: Setup
```bash
# Clean outputs folder
rm -rf outputs

# Start server (use the startup script)
./start-prompty.sh &
```

### Phase 2: Startup
```bash
agent-browser open "http://localhost:8085/"
sleep 3
agent-browser screenshot "$RUN_DIR/screenshots/01-startup-clean.png"

# Verify no JS errors
errors=$(agent-browser errors)
[ -z "$errors" ] || [ "$errors" = "[]" ]

# Verify main UI visible
agent-browser snapshot -c | grep -q "main-container"
```

### Phase 3: Navigation
```bash
agent-browser open "http://localhost:8085/?param=value"
sleep 3
agent-browser screenshot "$RUN_DIR/screenshots/02-navigation.png"

# Verify content loaded
agent-browser snapshot -c | grep -q "expected-content"

# Verify state set
agent-browser eval "window.state.param === 'value'"
```

### Phase 4: Generation
```bash
# Trigger generation via API
curl -X POST "http://localhost:8085/api/pu/generate" \
  -H "Content-Type: application/json" \
  -d '{"param":"value"}'

# Wait for generation
sleep 15

agent-browser reload
sleep 3
agent-browser screenshot "$RUN_DIR/screenshots/03-generation.png"

# Verify content visible
content_count=$(agent-browser eval "document.querySelectorAll('.generated-item').length")
[ "$content_count" -gt 0 ]
```

### Phase 5: Post-Generation
```bash
agent-browser screenshot "$RUN_DIR/screenshots/04-post-generation.png"

# Verify counts updated
count_text=$(agent-browser eval "document.querySelector('.count-value')?.textContent")
echo "$count_text" | grep -qE "[1-9][0-9]*"

# Verify state updated
item_count=$(agent-browser eval "parseInt(document.getElementById('items-count')?.textContent || '0')")
[ "$item_count" -gt 0 ]
```

### Phase 6: Persistence
```bash
# Refresh and verify state persists
agent-browser reload
sleep 3
agent-browser screenshot "$RUN_DIR/screenshots/05-persistence.png"

# Re-verify counts
item_count=$(agent-browser eval "parseInt(document.getElementById('items-count')?.textContent || '0')")
[ "$item_count" -gt 0 ]
```

## Report Format

```markdown
# E2E Test Report - {timestamp}

## Summary
- Total Phases: 6
- Passed: X
- Failed: Y
- Duration: Xm Ys

## Phase Results

### Phase 1: Setup - PASS
- Cleaned outputs folder
- Server started on port 8085
- Duration: 3s

### Phase 2: Startup - PASS
- Screenshot: 01-startup-clean.png
- No JS errors
- Main UI visible
- Duration: 5s

...

## Screenshots
- [01-startup-clean.png](screenshots/01-startup-clean.png)
- [02-navigation.png](screenshots/02-navigation.png)
- [03-generation.png](screenshots/03-generation.png)
- [04-post-generation.png](screenshots/04-post-generation.png)
- [05-persistence.png](screenshots/05-persistence.png)

## Failures (if any)
- Phase X: Error message
- Suggested fix: ...
```

## Failure Analysis

When a phase fails, the orchestrator:

1. **Captures state**: Takes a failure screenshot
2. **Diagnoses**: Checks console errors, network failures
3. **Suggests**: Provides actionable fix suggestions

Common failures:
- **JS errors on startup**: Check browser console, likely module load issue
- **Navigation fails**: Check API response
- **Generation times out**: Check worker status, increase timeout
- **Persistence fails**: Check localStorage/sessionStorage handling

## Cleanup

The orchestrator cleans up automatically:
- Stops server process
- Closes browser
- Preserves test artifacts in `tests/e2e-runs/`

Use `--no-cleanup` to keep server running for debugging.

## Integration with CI

```bash
# Run and exit with proper code
./tests/e2e-orchestrator.sh
exit_code=$?

# Check artifacts
if [ $exit_code -ne 0 ]; then
    cat tests/e2e-runs/latest/report.md
fi

exit $exit_code
```

## Limitations

- **Requires browser** - Needs `agent-browser` installed and functional
- **Pipeline position** - Final verification gate; runs after all parallel guards pass
- **Prerequisites** - Test files must exist; server must be running; `/e2e-guard` should have run
- **Not suitable for** - CLI-only tools; API-only projects; headless backend services

| Limitation | Next Step |
|------------|-----------|
| No test files | Run `/e2e-guard` to auto-generate tests |
| Server not running | Run `./start-prompty.sh` |
| 3+ failures | **Mandatory:** Run `/e2e-investigate` before retrying |

## Circuit Breaker Protocol

Repeated failures waste time. Follow this escalation:

| Attempt | Action |
|---------|--------|
| 1st failure | Review error, make fix, re-run `/e2e` |
| 2nd failure | Review more carefully, check if same test |
| 3rd failure | **STOP.** Run `/e2e-investigate` |
| After investigation | Fix with `/create-task`, then `/e2e` |

### Why This Matters

```
WITHOUT CIRCUIT BREAKER:
/e2e fail → retry → fail → retry → fail → retry → frustration

WITH CIRCUIT BREAKER:
/e2e fail → retry → fail → retry → fail → /e2e-investigate → root cause → fix → /e2e pass
```

### Flaky Test Detection

If a test passes sometimes and fails others:
1. Don't keep retrying hoping it passes
2. Run `/e2e-investigate` to identify:
   - Timing issues (insufficient `sleep`)
   - Race conditions
   - State pollution between tests
   - External dependencies

## See Also

- `/e2e-guard` - Test coverage for specific changes
- `/e2e-investigate` - Failure investigation
- `/agent-browser` - Browser automation commands
- `tests/lib/test_utils.sh` - Shared test utilities
