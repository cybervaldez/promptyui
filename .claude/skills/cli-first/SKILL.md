---
name: cli-first
description: Enforce code observability for AI-powered dynamic verification. Replaces brittle unit tests with mocks - instead, make code queryable so AI can verify against the live system.
argument-hint: [--recent | --design "feature"]
---

## TL;DR

**What:** Audit code for observability - testIDs, state exposure, token-efficient verification patterns.

**When:** After `/create-task` (use `--recent`), or before implementation (use `--design`).

**Output:** Report of missing testIDs, closure state, token-heavy patterns with fixes.

---

## Table of Contents

- [Tech Context Detection](#tech-context-detection)
- [How to Use](#how-to-use) (3 modes)
- [Audit Steps](#audit-steps)
  - [Category 1: Greppability](#category-1-can-ai-find-it-greppability)
  - [Category 2: Accessibility](#category-2-can-ai-query-it-accessibility)
  - [Category 3: Token Cost](#category-3-can-ai-verify-efficiently-token-cost)
  - [Category 4: Test Patterns](#category-4-is-it-ai-verifiable-test-patterns)
- [Output Format](#output-format)
- [Design Advisor Mode](#design-advisor-mode)
- [Differentiation from /coding-guard](#differentiation-from-coding-guard)
- [Integration with Other Skills](#integration-with-other-skills)
- [Quick Commands](#quick-commands)
- [Why This Matters](#why-this-matters)
- [Limitations](#limitations)
- [When NOT to Use](#when-not-to-use)
- [See Also](#see-also)

---

## Tech Context Detection

Before executing, check for technology-specific observability patterns:

1. **Scan target files** for technology imports/usage
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: State exposure? TestID conventions? Verification commands? Token costs?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and apply tech-specific observability patterns

**Domains that affect this skill:** State Management, UI Components

---

## Project Context Detection

After Tech Context Detection, classify the project to tailor testID and state exposure recommendations:

1. **Read project signals** — `README.md`, `package.json` description/dependencies, existing routes
2. **Classify into 1-2 archetypes** from `PROJECT_CONTEXT.md` taxonomy
3. **Apply archetype context** — use per-skill mapping table in `PROJECT_CONTEXT.md` to recommend archetype-appropriate testID conventions and state exposure

Note: Unlike ux-planner/ui-planner, cli-first does not need user confirmation of archetype — it uses the classification silently to inform testID and state exposure recommendations.

---

# CLI-First - Observability for AI Verification

> **The Core Philosophy**
>
> Traditional unit tests with mocks are **static lies** - they freeze assumptions
> at write-time and pass even when production breaks. CLI-first observability
> enables AI to verify your code **dynamically** against the real system, every time.
>
> This skill ensures your code is observable enough for AI to replace unit tests
> with something better: live verification that adapts as your code evolves.

## The Equation

```
Unit Tests + Mocks = Static verification of frozen assumptions
CLI-First + AI    = Dynamic verification of live reality
```

**You don't write tests. You make code observable. AI does the rest.**

---

## How to Use

### Mode 1: Full Audit (Standalone)
```
/cli-first
```
Scans entire codebase for all CLI-first violations that block AI verification.

**When to use:** Initial project setup, major refactoring, comprehensive review.

**Cost:** High (scans all files). Use sparingly.

### Mode 2: Post-Implementation Review
```
/cli-first --recent
```
Analyzes only recently changed files (like `/coding-guard`).

**When to use:** After `/create-task` completes, as part of parallel verification gates.

**Cost:** Low (only changed files). Use after every implementation.

### Mode 3: Design Advisor (Pre-Implementation)
```
/cli-first --design "feature description"
```
Provides CLI-first design guidance before implementation starts.

**When to use:** After `/ux-planner`, before `/create-task`. Helps plan testIDs and state exposure upfront.

**Cost:** Minimal (analysis only). Recommended for complex features.

### Mode Selection Guide

| Scenario | Mode | Why |
|----------|------|-----|
| Starting new project | Full audit | Establish baseline |
| After each `/create-task` | `--recent` | Verify changes only |
| Planning complex feature | `--design` | Design for observability |
| Debugging test failures | Full audit | Find missing testIDs |
| Regular development | `--recent` | Part of verification loop |

---

## Audit Steps

### Step 1: Find Target Files

**Full Audit:**
```bash
# All implementation files
find webui/prompty -name "*.js" -o -name "*.py" -o -name "*.html"
```

**Recent Changes:**
```bash
# Recently modified files
git diff --name-only HEAD~1 -- '*.js' '*.py' '*.html' 2>/dev/null || \
git diff --name-only --cached -- '*.js' '*.py' '*.html'
```

### Step 2: Check Observability Categories

For each file, audit these four categories:

---

### Category 1: Can AI Find It? (Greppability)

**Check for generic file names:**
```bash
# Bad: Non-descriptive names
ls tests// | grep -E "^test_[0-9]+\.sh$"   # test_1.sh, test_2.sh
ls webui/prompty/js/ | grep -E "^(utils|helpers|common)\.js$"
```

**Check for numbered test IDs:**
```bash
# Bad: Non-semantic testids
grep -rn 'data-testid="[a-z]*-[0-9]+"' webui/prompty/*.html
grep -rn 'data-testid="btn-[0-9]"' webui/prompty/*.html
```

**Check for generic function names:**
```bash
# Bad: Names that return noise when grepped
grep -rn "function get\s*(" webui/prompty/js/
grep -rn "function handle\s*(" webui/prompty/js/
grep -rn "function process\s*(" webui/prompty/js/
```

**Violations:**
| Issue | Example | Fix |
|-------|---------|-----|
| Generic file name | `test_1.sh` | `test_bake_modal.sh` |
| Numbered testid | `data-testid="btn-1"` | `data-testid="bake-generate-btn"` |
| Generic function | `function get()` | `function getCompositionFromURL()` |

---

### Category 2: Can AI Query It? (Accessibility)

**Check for missing testids on interactive elements:**
```bash
# Bad: Buttons/inputs without testids
grep -rn '<button[^>]*>' webui/prompty/*.html | grep -v 'data-testid'
grep -rn '<input[^>]*>' webui/prompty/*.html | grep -v 'data-testid'
grep -rn '<select[^>]*>' webui/prompty/*.html | grep -v 'data-testid'
```

**Check for state only in closures:**
```bash
# Bad: State not exposed to window/debug
grep -rn "let state = " webui/prompty/js/ | grep -v "window\."
grep -rn "const state = " webui/prompty/js/ | grep -v "window\."
```

**Check for silent API calls:**
```bash
# Bad: Fetch without debug logging
grep -rn "fetch(" webui/prompty/js/ | grep -v "debugLog\|console\."
```

**Check for non-canonical verbs in testids:**
```bash
# Canonical action verbs: create, add, save, edit, delete, remove, submit, confirm,
#   login, logout, register, run, start, stop, generate, export, download, cancel, publish, deploy
# Plus VIEW: expand, collapse, toggle, show, hide, sort, filter, search, refresh
NON_CANONICAL='destroy\|purge\|wipe\|trash\|erase\|drop\|update\|modify\|rename\|apply\|overwrite\|merge\|patch\|insert\|upload\|import\|clone\|duplicate\|send\|proceed\|done\|finish\|accept\|approve\|execute\|trigger\|process\|build\|queue\|dismiss'

grep -rn 'data-testid=' webui/prompty/*.html | grep -oP 'data-testid="[^"]*"' | grep -iE "$NON_CANONICAL"
```

**Violations:**
| Issue | Example | Fix |
|-------|---------|-----|
| Missing testid | `<button>Generate</button>` | `<button data-testid="bake-generate-btn">` |
| Closure state | `let state = {}` | `window.ModalState = state` or debug container |
| Silent API | `fetch('/api/x')` | Add debug logging or expose response |
| Non-canonical testid action | `data-testid="user-destroy-btn"` | `data-testid="user-delete-btn"` |

See `skills/browser/references/element-operations.md` → Canonical Verbs.

---

### Category 3: Can AI Verify Efficiently? (Token Cost)

**Check for screenshot-heavy test patterns:**
```bash
# Bad: Using screenshot when snapshot suffices
grep -rn "screenshot" tests// | grep -v "screenshot_on_fail\|failure"
```

**Check for full snapshot when eval suffices:**
```bash
# Bad: Full DOM snapshot to check single value
grep -rn "snapshot -c" tests// | xargs -I {} sh -c '
    if ! grep -A5 "snapshot -c" {} | grep -q "eval"; then
        echo "Possible optimization: {}"
    fi
'
```

**Token Cost Reference:**
| Method | Token Cost | Use When |
|--------|------------|----------|
| `curl + jq` | ~200 | API response verification |
| `eval "expr"` | ~100 | Single value check |
| `snapshot -c \| grep` | ~500 | DOM element presence |
| `snapshot -c` (full) | ~800 | Multiple element checks |
| `screenshot` | ~2000+ | Visual layout verification ONLY |

**Violations:**
| Issue | Example | Savings |
|-------|---------|---------|
| Screenshot for data | `screenshot` to check text | ~1500 tokens |
| Full snapshot for one check | `snapshot -c` then one grep | ~300 tokens |

---

### Category 4: Is It AI-Verifiable? (Test Patterns)

**Check for manual verification comments:**
```bash
# Bad: Comments telling humans to verify
grep -rn "# TODO: manually\|# VERIFY:\|# CHECK:" tests//
grep -rn "# visual inspection\|# look at" tests//
```

**Check for CSS class selectors in tests:**
```bash
# Bad: Fragile CSS selectors
grep -rn "querySelector.*\\.class" tests//
grep -rn "getElementsByClassName" tests//
```

**Check for hardcoded waits:**
```bash
# Bad: Fixed sleep instead of wait-for-condition
grep -rn "sleep [5-9]\|sleep 1[0-9]" tests//
```

**Violations:**
| Issue | Example | Fix |
|-------|---------|-----|
| Manual verification | `# TODO: check visually` | Add testid + automated check |
| CSS selector | `.querySelector('.btn')` | Use `[data-testid="..."]` |
| Hardcoded wait | `sleep 10` | Use retry loop or event wait |

---

## Output Format

```markdown
## CLI-First Audit Results

### Critical: Missing TestIDs (5 elements)
AI cannot target these elements for verification.

| Element | File | Line | Suggested TestID |
|---------|------|------|------------------|
| `<button>Generate</button>` | index.html | 156 | `bake-generate-btn` |
| `<input type="text">` | modal.html | 89 | `prompt-input` |

### Warning: Token-Heavy Verification (2 patterns)
These tests waste context tokens unnecessarily.

| Test File | Line | Current | Suggested | Savings |
|-----------|------|---------|-----------|---------|
| test_modal.sh | 45 | screenshot | snapshot -c \| grep | ~1500 tokens |
| test_api.sh | 23 | snapshot -c (full) | eval "value" | ~700 tokens |

### Warning: Non-Greppable Names (3 items)
AI search returns too much noise for these.

| Item | Current | Suggested |
|------|---------|-----------|
| test_1.sh | test_1.sh | test_bake_modal.sh |
| btn-1 | data-testid="btn-1" | data-testid="generate-btn" |

### Info: Closure State (1 pattern)
State hidden from AI inspection.

| File | Line | Pattern | Suggestion |
|------|------|---------|------------|
| modal.js | 42 | `let state = {}` | Expose via `window.ModalState` or debug container |

### Summary
- Critical issues: 5 (must fix)
- Warnings: 5 (should fix)
- Token savings potential: ~3700 tokens per test run
- Status: NEEDS ATTENTION
```

---

## Design Advisor Mode

When invoked with `--design "feature description"`:

### Step 1: Analyze Feature Requirements

Parse the feature description for:
- UI elements needed
- State to be managed
- API endpoints involved
- User interactions

### Step 2: Generate Observability Recommendations

```markdown
## CLI-First Design for: [Feature Name]

### Recommended TestIDs
| Element | TestID | Purpose |
|---------|--------|---------|
| Generate button | `feature-generate-btn` | Trigger action |
| Status text | `feature-status-text` | Show result |
| Input field | `feature-input` | User input |

### State Exposure
```javascript
// Expose state for AI verification
window.FeatureState = {
    get current() { return state; },
    get lastAction() { return lastAction; }
};
```

### Debug Container
```html
<div id="feature-debug" style="display:none;">
    <pre data-testid="feature-debug-state"></pre>
</div>
```

### Verification Commands
```bash
# Check element exists
agent-browser snapshot -c | grep -q "feature-generate-btn"

# Check state value
agent-browser eval "window.FeatureState.current"

# Check API response
curl -sf "$URL/api/pu/feature" | jq '.status'
```

### Token-Efficient Test Pattern
```bash
# ~300 tokens total
agent-browser eval "window.FeatureState.current.status" | grep -q "success"
curl -sf "$URL/api/pu/feature" | jq -e '.success' > /dev/null
```
```

---

## Differentiation from /coding-guard

| Concern | /cli-first | /coding-guard |
|---------|------------|---------------|
| **Core goal** | Enable AI dynamic verification | Prevent anti-patterns |
| **Replaces** | Unit tests with mocks | Bad coding patterns |
| **Questions** | "Can AI verify this live?" | "Does this hide bugs?" |
| **Focus** | Observability (testids, state exposure) | Code quality (fallbacks, silent failures) |

Use both together:
- `/coding-guard` ensures code doesn't hide bugs
- `/cli-first` ensures AI can verify the code

---

## Integration with Other Skills

```
/ux-planner -> (optional) /cli-first --design -> /create-task
                                                      |
              +---------------------------------------+
              |                 |                     |
              v                 v                     v
         /coding-guard    /cli-first             /ux-review
         (code quality)   (observability)        (visual UX)
              |                 |                     |
              +---------------------------------------+
                                |
                                v
                           /e2e-guard
```

**Integration points:**
- After `/create-task`: Auto-suggested alongside `/coding-guard`
- Before `/e2e-guard`: Validates tests use CLI patterns
- With `/coding-guard`: Complementary - different concerns

---

## Quick Commands

```bash
# Find all missing testids
grep -rn '<button\|<input\|<select' webui/prompty/*.html | grep -v 'data-testid'

# Find screenshot usage in tests (should be minimal)
grep -rn "screenshot" tests// | grep -v "failure\|_on_fail"

# Find closure state patterns
grep -rn "let state = \|const state = " webui/prompty/js/ | grep -v "window\."

# Find generic function names
grep -rn "function get(\|function handle(\|function process(" webui/prompty/js/
```

---

## Why This Matters

### Traditional Unit Test (Static, Fragile)

```javascript
// test_user_service.js
test('getUser returns user data', () => {
  const mockApi = jest.fn().mockResolvedValue({ id: 1, name: 'John' });
  const result = await getUser(mockApi, 1);
  expect(result.name).toBe('John');  // Passes forever, even when API changes
});
```

**Problems:**
- Mock frozen at write-time
- API adds `firstName`/`lastName`, test still passes
- False confidence

### CLI-First Verification (Dynamic, Honest)

```bash
# AI verifies against REAL system
curl -sf "$URL/api/pu/users/1" | jq '.name'        # Actual response
agent-browser eval "window.userState.name"               # Actual state
agent-browser snapshot -c | grep "John"                  # Actual DOM
```

**Benefits:**
- Queries live system every time
- API changes? Verification catches it immediately
- AI adapts verification strategy as code evolves

---

## Limitations

- **Read-only** - Audits code but doesn't modify files directly
- **Pipeline position** - Runs in parallel with `/coding-guard` and `/ux-review` after `/create-task`
- **Prerequisites** - Requires source files to exist; best used on recent changes
- **Not suitable for** - API-only projects with no UI; pure backend services without frontend state

## When NOT to Use

Skip `/cli-first` when:
- **API-only project** - No browser state to expose
- **Documentation changes** - No code to audit
- **Backend-only change** - No frontend observability needed
- **Styleguide already comprehensive** - TestIDs and state exposure in place
- **Already ran recently** - Full audit is expensive; use `--recent` for incremental

## See Also

- `/coding-guard` - Code quality anti-pattern detection
- `/e2e-guard` - E2E test coverage verification
- `/ux-review` - Visual UX verification
- `references/cli-patterns.md` - Token cost table and universal patterns
