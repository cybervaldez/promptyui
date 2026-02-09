# cybervaldez-prompt-generator Testing Conventions

Detailed patterns for e2e testing with agent-browser and curl.

**IMPORTANT:** Customize the placeholders below for your project.

## Placeholders Reference

| Placeholder | Your Value | Description |
|-------------|------------|-------------|
| `cybervaldez-prompt-generator` | | Your project name |
| `test-fixtures` | | Test job/fixture name |
| `8085` | | Default server port |
| `./start-prompty.sh` | | Server startup command |
| `./venv/bin/python` | | Python path |
| `/api/pu` | | API base path |
| `webui/prompty` | | WebUI source path |
| `tests/` | | Test files path |
| `outputs` | | Generated outputs path |

## Core Testing Principles

| Principle | Rule |
|-----------|------|
| Test tools | `agent-browser` + `curl` ONLY |
| Test type | E2E tests only (no unit tests) |
| Test job | Use `test-fixtures` job |
| Python | Always `./venv/bin/python` |
| Fallbacks | NO fallback logic in code |
| Debug | Use hidden debug containers |

## TestID Discovery

```bash
./venv/bin/python list-testids.py              # List all
./venv/bin/python list-testids.py --filter "*" # Filter
./venv/bin/python list-testids.py --json       # JSON output
```

## agent-browser Commands

```bash
# Navigation
agent-browser open <url>
agent-browser close

# Snapshot
agent-browser snapshot -i     # Interactive elements with refs
agent-browser snapshot -c     # Compact for grep

# Interactions
agent-browser click @e1
agent-browser fill @e2 "text"
agent-browser find role button click --name "..."

# Info
agent-browser get title
agent-browser get url
agent-browser errors

# JavaScript
agent-browser eval "document.querySelector('.class').click()"
```

## API Endpoints

```bash
# Config
curl -s http://localhost:8085/api/pu/config | jq '.'

# Standard CRUD pattern
curl -s http://localhost:8085/api/pu/resource
curl -s -X PUT http://localhost:8085/api/pu/resource/{id} -H "Content-Type: application/json" -d '{...}'
curl -s -X DELETE http://localhost:8085/api/pu/resource/{id}

# Queue operations
curl -X POST http://localhost:8085/api/pu/queue/add -H "Content-Type: application/json" -d '{...}'
curl -s http://localhost:8085/api/pu/queue/status
```

## Setup Patterns

### Server Check with Retry

```bash
wait_for_server() {
    local max_attempts=10
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$BASE_URL/" > /dev/null 2>&1; then
            return 0
        fi
        ((attempt++))
        sleep 1
    done
    return 1
}

# Usage
if ! wait_for_server; then
    fail "Server not available after 10 attempts"
    exit 1
fi
pass "Server is running"
```

### Browser Cleanup Trap

```bash
cleanup() {
    agent-browser close 2>/dev/null || true
}
trap cleanup EXIT

# Now browser will auto-close even on script errors
```

## Test Patterns

### Server Check (Simple)
```bash
curl -sf "$BASE_URL/" > /dev/null 2>&1 && pass "Running" || fail "Down"
```

### UI Element
```bash
SNAPSHOT=$(agent-browser snapshot -c 2>/dev/null)
echo "$SNAPSHOT" | grep -q "testid" && pass "Found" || fail "Missing"
```

### JS State
```bash
RESULT=$(agent-browser eval "Object.property" 2>/dev/null)
[ "$RESULT" = "expected" ] && pass "OK" || fail "Wrong"
```

### API Response
```bash
curl -sf "$URL" | grep -q "expected" && pass "OK" || fail "Failed"
```

## Non-Browser Output Testing

Some technologies produce output that isn't a web page (video, images, files). These require alternative verification tools.

### Output Verification Tools

| Output Type | Verification Tool | Install | Example |
|-------------|------------------|---------|---------|
| Video | ffprobe | `apt install ffmpeg` | Duration, fps, codec |
| Image | file, identify | `apt install imagemagick` | Dimensions, format |
| JSON file | jq | `apt install jq` | Schema validation |
| PDF | pdfinfo | `apt install poppler-utils` | Page count, metadata |
| Audio | ffprobe | `apt install ffmpeg` | Duration, sample rate |

### Video Output Pattern (e.g., Remotion)

```bash
# Render video
npx remotion render src/index.ts CompositionName out/video.mp4 --codec=h264
[ $? -eq 0 ] && pass "Render completed" || fail "Render failed"

# Verify file exists
[ -f "out/video.mp4" ] && pass "Video file exists" || fail "Missing"

# Verify duration (ffprobe)
DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 out/video.mp4)
[ "$(echo "$DURATION > 5" | bc)" = "1" ] && pass "Duration: ${DURATION}s" || fail "Too short"

# Verify fps
FPS=$(ffprobe -v error -select_streams v -show_entries stream=r_frame_rate -of csv=p=0 out/video.mp4)
echo "$FPS" | grep -q "30/1" && pass "FPS: 30" || fail "Wrong FPS: $FPS"

# Verify codec
CODEC=$(ffprobe -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 out/video.mp4)
[ "$CODEC" = "h264" ] && pass "Codec: h264" || fail "Wrong codec: $CODEC"
```

### Image Output Pattern

```bash
# Generate image
node generate-image.js --output out/image.png

# Verify file exists and is valid PNG
file out/image.png | grep -q "PNG image" && pass "Valid PNG" || fail "Invalid"

# Verify dimensions (ImageMagick)
DIMS=$(identify -format "%wx%h" out/image.png)
[ "$DIMS" = "1920x1080" ] && pass "Dimensions: $DIMS" || fail "Wrong size: $DIMS"
```

### File Output Pattern

```bash
# Generate file
node generate-data.js --output out/data.json

# Verify file exists
[ -f "out/data.json" ] && pass "File exists" || fail "Missing"

# Verify JSON structure
jq -e '.required_field' out/data.json > /dev/null && pass "Has required_field" || fail "Missing field"

# Verify array length
COUNT=$(jq '.items | length' out/data.json)
[ "$COUNT" -gt 0 ] && pass "Has $COUNT items" || fail "Empty array"
```

### Key Differences from Browser Testing

| Aspect | Browser (agent-browser) | Non-Browser (file tools) |
|--------|------------------------|--------------------------|
| Verification | DOM snapshot | File properties |
| State check | JS eval | Parse file content |
| Visual check | Screenshot | Extract frame/thumbnail |
| Failure artifacts | Screenshots | Output files, render logs |
| Cleanup | `agent-browser close` | `rm -rf out/` |

### JSON Validation with jq Fallbacks
```bash
# Safe extraction with defaults
STATUS=$(echo "$RESULT" | jq -r '.status // "error"')
COUNT=$(echo "$RESULT" | jq -r '.count // 0')
NAME=$(echo "$DATA" | jq -r '.name // "unknown"')
```

### HTTP Status Code Capture
```bash
# Capture body AND HTTP status code in one request
RESULT=$(curl -sf -w "\n%{http_code}" -X POST "$URL" -d '...' 2>&1)
HTTP_CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')

[ "$HTTP_CODE" = "200" ] && pass "HTTP OK" || fail "HTTP $HTTP_CODE"
```

### Snapshot + grep
```bash
# Save snapshot for multiple checks
agent-browser snapshot -c > /tmp/snapshot_$$.txt
grep -qi "expected text" /tmp/snapshot_$$.txt && pass "Found" || fail "Missing"
grep -qi "another item" /tmp/snapshot_$$.txt && pass "Found another" || fail "Missing"
```

### Interactive Snapshot for Clicking
```bash
# Get interactive snapshot with element refs
agent-browser snapshot -i > /tmp/snap.txt
REF=$(grep "Button Text" /tmp/snap.txt | grep -oE '\[ref=e[0-9]+\]' | head -1 | tr -d '[]')
agent-browser click "@${REF#ref=}"
```

### JS Eval for State
```bash
# Get JavaScript state with fallback
RESULT=$(agent-browser eval "Modal.state?.field || 'default'" 2>/dev/null | tr -d '"')
[ "$RESULT" = "expected" ] && pass "State OK" || fail "State: $RESULT"
```

### TestID Exists
```bash
HAS=$(agent-browser eval "!!document.querySelector('[data-testid=\"id\"]')" 2>/dev/null)
[ "$HAS" = "true" ] && pass "Has testid" || fail "Missing testid"
```

## TestID Patterns

| Pattern | Component |
|---------|-----------|
| `modal-*` | Modal dialogs |
| `sidebar-*` | Sidebar elements |
| `grid-*` | Grid/list items |
| `btn-*` | Buttons |
| `form-*` | Form elements |

## Debug Containers

Add hidden debug containers for state visibility in tests:

```html
<div id="modal-debug" style="display:none;">
    <pre id="debug-state"></pre>
    <div id="debug-log"></div>
</div>
```

```javascript
// In component code
function debugLog(key, value) {
    const container = document.getElementById('debug-log');
    if (!container) return;
    const entry = document.createElement('div');
    entry.dataset.key = key;
    entry.textContent = `${key}: ${JSON.stringify(value)}`;
    container.appendChild(entry);
}

// Usage
debugLog('state', currentState);
debugLog('api-response', response);
```

```bash
# In tests - read debug state via agent-browser
agent-browser eval "document.getElementById('debug-log')?.innerText"
agent-browser eval "document.querySelector('[data-key=\"state\"]')?.textContent"
```

## Anti-Patterns in Implementation Code

**NEVER use these patterns in implementation code:**

```javascript
// BAD: Default values for required params
const value = params.get('value') || 42;

// BAD: Fallback chains
const value = x ?? y ?? z ?? defaultValue;

// BAD: State fallbacks mask stale data
const comp = state.config?.value || 99;

// BAD: Silent failures
if (error) return [];
```

**ALWAYS use explicit error handling:**

```javascript
// GOOD: Fail explicitly
const value = params.get('value');
if (!value) {
    return { error: 'value parameter required', status: 400 };
}

// GOOD: Clear error messages
throw new Error(`Invalid value: expected integer, got "${typeof value}"`);
```

## Timing Patterns

### Environment Setup

**ALWAYS use `./venv/bin/python`** - Never system python:

```bash
# CORRECT - Always use project python
./venv/bin/python script.py
./venv/bin/python -m module.name

# WRONG - Never use system python
python script.py
python3 -m module.name
```

### Test Job

**ALWAYS use `test-fixtures` for testing** - Its outputs can be safely deleted and rebuilt:

```bash
# Standard server startup
./start-prompty.sh

# Clean slate for testing
rm -rf outputs/*
```

### Timing Constants

| Wait Type | Duration | Use Case |
|-----------|----------|----------|
| UI state change | 0.3-0.5s | Checkbox, toggle, quick animation |
| Quick interaction | 1s | Click, form input |
| Modal render | 1.5-2s | Modal open, dialog display |
| Page load | 4s | Full page navigation |
| Generation complete | 4s | After triggering generation |
| File write sync | 0.2s | After file operations |

## Error Handling Patterns

### Graceful Skip
```bash
# Skip tests when required conditions aren't met
if ! curl -sf "$BASE_URL/" > /dev/null 2>&1; then
    echo "  ! Server not available - skipping tests"
    exit 0
fi
```

### Fallback Values
```bash
# Always provide defaults for optional fields
VALUE=$(curl -sf "$URL" | jq -r '.field // "default"')
COUNT=$(curl -sf "$URL" | jq -r '.count // 0')
```

## Debug Output Patterns

### Colored Status
```bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'  # No Color

pass() { echo -e "${GREEN}[PASS] $1${NC}"; ((PASSED++)); }
fail() { echo -e "${RED}[FAIL] $1${NC}"; ((FAILED++)); }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
```

### Section Headers
```bash
echo "--- TEST 1: Feature Name ---"
echo ""
echo "==================================================================="
echo "  RESULTS: $PASSED passed, $FAILED failed"
echo "==================================================================="
```

### Debug Mode Toggle
```bash
# Enable verbose output for debugging
set -x  # Turn on at start of problematic section
# ... commands ...
set +x  # Turn off after
```

## Test Organization

### Counter Pattern
```bash
PASSED=0
FAILED=0

pass() { echo "  [PASS] $1"; ((PASSED++)); }
fail() { echo "  [FAIL] $1"; ((FAILED++)); }

# At end of test
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
```

### Test ID Pattern
```bash
# Unique test ID for cleanup/isolation
TEST_ID="e2e-test-$$"
```

## Gotchas

1. Use `find role ... --name` not `find text`
2. `find` only supports click/hover - use snapshot for text
3. Checkbox clicks may not trigger handlers - use eval
4. Always close browser in cleanup
5. Use `$$` (PID) in temp filenames to avoid collisions
6. Always redirect stderr with `2>/dev/null` for eval commands
7. Use `|| true` after cleanup commands to prevent trap failures
8. **Never use fallback defaults in implementation code** - Test fallbacks OK, code fallbacks BAD
9. **Always use `./venv/bin/python`** - Never system python
10. **Always use `test-fixtures` for testing** - Safe to rebuild

## Pre-Implementation Checklist

Before implementing changes, verify:

- [ ] Can be tested with `agent-browser` and `curl` only?
- [ ] No fallback values for required parameters?
- [ ] Debug containers added for complex state?
- [ ] User consulted on ambiguous decisions?
- [ ] E2E test planned (not unit test)?
- [ ] Using `test-fixtures` for testing?
- [ ] Using `./venv/bin/python`?
- [ ] Error messages are clear and specific?

See also: `/coding-guard` (post-implementation audit)

---

## Advanced: API Configuration Endpoint

When your project has an API backend, consider adding a `/api/config` endpoint for enhanced testing capabilities:

```python
@app.route('/api/config')
def config():
    return jsonify({
        "debug": app.config.get('DEBUG', False),
        "job_name": os.environ.get('JOB_NAME', 'default')
    })
```

This enables:

### Debug Mode Checks
```bash
# Check server mode before testing mode-specific features
DEBUG_MODE=$(curl -sf "$BASE_URL/api/pu/config" | jq -r '.debug // false')
if [ "$DEBUG_MODE" != "true" ]; then
    echo "  ! Server not in debug mode - skipping generation tests"
fi
```

### Configuration Verification
```bash
# Verify server is running with expected config
CONFIG=$(curl -sf "$BASE_URL/api/pu/config")
echo "Debug mode: $(echo "$CONFIG" | jq -r '.debug')"
echo "Job: $(echo "$CONFIG" | jq -r '.job_name')"
```

**Note:** The basic health check (`wait_for_server`) uses root path `/` and works without an API. Use `/api/config` patterns only when your project has an API backend.
