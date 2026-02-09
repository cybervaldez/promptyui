# CLI-First Patterns for AI Verification

Universal patterns for making code observable and AI-verifiable.

## Token Cost Reference

Every verification method has a cost. Use the cheapest one that answers the question:

| Method | Token Cost | Use Case | Example |
|--------|------------|----------|---------|
| `curl + jq` | ~200 | API responses, data verification | `curl -sf "$URL/api/x" \| jq '.field'` |
| `eval "expr"` | ~100 | Single value check | `agent-browser eval "window.state.x"` |
| `snapshot -c \| grep` | ~500 | Element presence, text check | `snapshot -c \| grep -q "testid"` |
| `snapshot -c` (full) | ~800 | Multiple element checks | Save to variable, multiple greps |
| `snapshot -i` | ~1000 | Interactive elements with refs | Find clickable elements |
| `screenshot` | ~2000+ | Visual layout verification ONLY | Last resort |

### Decision Tree

```
Need to verify something?
    |
    +-> Is it API data?
    |       +-> YES: curl + jq (~200 tokens)
    |
    +-> Is it a single JS value?
    |       +-> YES: eval "expr" (~100 tokens)
    |
    +-> Is it element presence?
    |       +-> YES: snapshot -c | grep (~500 tokens)
    |
    +-> Is it multiple elements?
    |       +-> YES: snapshot -c to variable (~800 tokens)
    |
    +-> Is it VISUAL layout (spacing, alignment, colors)?
            +-> YES: screenshot (~2000+ tokens)
            +-> NO: Use one of the above methods
```

---

## Greppability Patterns

### File Naming

```
GOOD: Self-descriptive, greppable
------------------------------------
test_bake_modal.sh          # grep "bake" finds it
test_stage_ordering.sh      # grep "stage" finds it
webui/js/modal/bake.js      # Path shows purpose
server/api/variants.py      # Path shows domain

BAD: Generic, noise in search
------------------------------------
test_1.sh                   # grep returns nothing useful
utils.js                    # grep "utils" returns everything
helpers.py                  # No domain context
```

### TestID Naming

```
GOOD: Semantic, greppable
------------------------------------
data-testid="bake-generate-btn"      # grep "bake" or "generate" finds it
data-testid="stage-manager-total"    # Domain-specific
data-testid="prompt-input"           # Describes purpose

BAD: Non-semantic, numbered
------------------------------------
data-testid="btn-1"          # What button?
data-testid="input-a"        # What input?
data-testid="container"      # Which container?
```

### Function Naming

```
GOOD: Specific, searchable
------------------------------------
function getCompositionFromURL() { }    # grep "composition" finds it
function handleBakeGenerate() { }       # grep "bake" finds it
function updateStageCount() { }         # grep "stage" finds it

BAD: Generic, returns noise
------------------------------------
function get() { }           # grep "get" returns 500 results
function handle() { }        # Too common
function update() { }        # Too generic
```

---

## State Exposure Patterns

### Pattern 1: Window Object

```javascript
// Expose state on window for AI queries
const Modal = {
    state: { /* private state */ },

    // Public accessor for testing
    get debugState() {
        return this.state;
    }
};

// Or directly
window.ModalState = Modal.state;

// AI verification:
// agent-browser eval "window.ModalState.selectedItem"
```

### Pattern 2: Debug Container

```html
<!-- Hidden debug container for AI inspection -->
<div id="modal-debug" style="display:none;">
    <pre data-testid="modal-debug-state"></pre>
    <div data-testid="modal-debug-log"></div>
</div>
```

```javascript
// Update debug container
function debugLog(key, value) {
    const log = document.querySelector('[data-testid="modal-debug-log"]');
    if (!log) return;
    const entry = document.createElement('div');
    entry.dataset.debugKey = key;
    entry.textContent = JSON.stringify(value);
    log.appendChild(entry);
}

// AI verification:
// agent-browser eval "document.querySelector('[data-debug-key=\"status\"]').textContent"
```

### Pattern 3: Data Attributes

```html
<!-- Encode state in data attributes -->
<div data-testid="stage-manager"
     data-total="42"
     data-completed="15"
     data-status="active">
    15/42 completed
</div>
```

```bash
# AI verification:
agent-browser eval "document.querySelector('[data-testid=\"stage-manager\"]').dataset.total"
```

---

## TestID Patterns by Component

| Component Type | TestID Pattern | Example |
|---------------|----------------|---------|
| Modal container | `{name}-modal` | `bake-modal` |
| Modal close button | `{name}-modal-close` | `bake-modal-close` |
| Primary action button | `{name}-{action}-btn` | `bake-generate-btn` |
| Input field | `{name}-{field}-input` | `prompt-text-input` |
| Display value | `{name}-{field}-value` | `stage-count-value` |
| Container | `{name}-container` | `results-container` |
| List item | `{name}-item-{id}` | `variant-item-123` |
| Status indicator | `{name}-status` | `generation-status` |

---

## Verification Command Patterns

### API Verification

```bash
# Check endpoint returns expected data
curl -sf "$BASE_URL/api/endpoint" | jq -e '.expected_field' > /dev/null && \
    echo "PASS" || echo "FAIL"

# Check specific value
VALUE=$(curl -sf "$BASE_URL/api/endpoint" | jq -r '.field')
[ "$VALUE" = "expected" ] && echo "PASS" || echo "FAIL"

# Check array length
COUNT=$(curl -sf "$BASE_URL/api/items" | jq '. | length')
[ "$COUNT" -gt 0 ] && echo "PASS" || echo "FAIL"
```

### DOM Verification

```bash
# Check element exists
agent-browser snapshot -c | grep -q 'data-testid="element"' && \
    echo "PASS" || echo "FAIL"

# Check element text
TEXT=$(agent-browser eval "document.querySelector('[data-testid=\"x\"]').textContent")
echo "$TEXT" | grep -q "expected" && echo "PASS" || echo "FAIL"

# Check element count
COUNT=$(agent-browser eval "document.querySelectorAll('[data-testid*=\"item\"]').length")
[ "$COUNT" -gt 0 ] && echo "PASS" || echo "FAIL"
```

### State Verification

```bash
# Check window state
STATE=$(agent-browser eval "window.AppState.status")
[ "$STATE" = "ready" ] && echo "PASS" || echo "FAIL"

# Check nested state
VALUE=$(agent-browser eval "window.Modal.state.selectedItem?.id")
[ -n "$VALUE" ] && echo "PASS" || echo "FAIL"

# Compare UI to API (ground truth)
API_COUNT=$(curl -sf "$BASE_URL/api/items" | jq '. | length')
UI_COUNT=$(agent-browser eval "window.AppState.items.length")
[ "$API_COUNT" = "$UI_COUNT" ] && echo "PASS" || echo "FAIL: API=$API_COUNT UI=$UI_COUNT"
```

---

## Anti-Patterns to Avoid

### In Tests

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| `screenshot` for data check | 2000+ tokens wasted | Use `eval` or `snapshot \| grep` |
| CSS class selector | Fragile, breaks on refactor | Use `data-testid` |
| Fixed sleep | May be too short or wasteful | Use retry loop |
| Manual verification comment | AI can't automate | Add testid + automated check |
| Numbered testids | Non-semantic, hard to grep | Use descriptive names |

### In Implementation

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| State in closure | AI can't inspect | Expose via window or debug container |
| Generic function names | Grep returns noise | Use domain-specific names |
| No testids | AI can't target elements | Add data-testid to interactive elements |
| Silent API calls | AI can't verify responses | Add debug logging |

---

## Wait Patterns (Avoiding Hardcoded Sleeps)

### Retry Loop Pattern

```bash
wait_for_element() {
    local testid="$1"
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if agent-browser snapshot -c | grep -q "data-testid=\"$testid\""; then
            return 0
        fi
        ((attempt++))
        sleep 0.5
    done
    return 1
}

# Usage
wait_for_element "results-container" && echo "Found" || echo "Timeout"
```

### Wait for State Pattern

```bash
wait_for_state() {
    local expr="$1"
    local expected="$2"
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        VALUE=$(agent-browser eval "$expr" 2>/dev/null)
        if [ "$VALUE" = "$expected" ]; then
            return 0
        fi
        ((attempt++))
        sleep 0.5
    done
    return 1
}

# Usage
wait_for_state "window.AppState.status" "ready"
```

### Wait for Server Pattern

```bash
wait_for_server() {
    local url="$1"
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            return 0
        fi
        ((attempt++))
        sleep 1
    done
    return 1
}

# Usage - works with any server (static or API)
wait_for_server "$BASE_URL/"
```

---

## Checklist for New Features

Before implementing, ensure:

- [ ] All interactive elements have semantic `data-testid` attributes
- [ ] State is exposed via window object or debug container
- [ ] File names are greppable and domain-specific
- [ ] Function names are specific, not generic
- [ ] API responses are verifiable via curl + jq
- [ ] Tests use cheapest verification method possible
- [ ] No hardcoded long sleeps (use retry loops)
- [ ] No CSS class selectors in tests

---

## See Also

- Parent: `SKILL.md` - Main CLI-first skill documentation
- `/coding-guard` - Code quality anti-patterns
- `/e2e-guard` - E2E test coverage
