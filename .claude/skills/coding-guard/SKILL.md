---
name: coding-guard
description: Audit recent code changes for coding convention violations. Use after implementing changes to verify they follow project standards.
---

## TL;DR

**What:** Scan code for anti-patterns - fallback defaults, silent failures, state pollution.

**When:** After `/create-task` completes, before committing.

**Output:** List of violations with line numbers and suggested fixes.

---

## Tech Context Detection

Before executing, check for technology-specific anti-patterns:

1. **Scan changed files** for technology imports/usage
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: Anti-patterns? Silent failures? State mutation gotchas? Error handling?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and check for tech-specific anti-patterns

**Domains that affect this skill:** State Management, Data Fetching, Form Handling, Auth

---

# Coding Guard - Post-Implementation Audit

Run this skill after implementing changes to verify they follow project coding conventions.

## How to Use

```
/coding-guard
```

No arguments needed. The skill automatically:
1. Finds recently modified files via `git diff`
2. Scans for anti-pattern violations
3. Reports issues that need fixing

## Audit Steps

### Step 1: Find Changed Files

```bash
# Get list of modified JS and Python files
git diff --name-only HEAD~1 -- '*.js' '*.py' 2>/dev/null || git diff --name-only --cached -- '*.js' '*.py'

# Or check unstaged changes
git diff --name-only -- '*.js' '*.py'
```

### Git State Handling

| Git State | Behavior |
|-----------|----------|
| Has commits, unstaged changes | Uses `git diff` (working tree) |
| Has commits, staged changes | Uses `git diff --cached` |
| First commit ever | Uses `git diff --cached` (staged files) |
| No git repo | Error: "Not a git repository" |
| Clean working tree | No changes to audit - success |

**First commit scenario:**
```bash
# Stage your files first
git add .

# Then run coding-guard
/coding-guard  # Will use --cached automatically
```

### Step 2: Scan for Anti-Patterns

For each changed file, check for these violations:

#### 2.1 Fallback Defaults (CRITICAL)

```bash
# Search for default value patterns
grep -n "|| [0-9]" $FILE           # || 42, || 99, etc.
grep -n "?? [0-9]" $FILE           # ?? 42, nullish coalescing with number
grep -n "|| '[^']*'" $FILE         # || 'default'
grep -n "|| \"[^\"]*\"" $FILE      # || "default"
grep -n "\.get([^,)]*,[^)]*)" $FILE  # params.get('x', default)
grep -n "|| \[\]" $FILE            # || [] (empty array default)
grep -n "|| {}" $FILE              # || {} (empty object default)
```

**Exceptions (OK in tests, not in implementation):**
- Test files (`test_*.sh`, `test_*.py`)
- jq expressions with `// "default"` (that's jq syntax, not JS)

#### 2.2 Silent Failures

```bash
# Catch blocks that return empty/default
grep -n "catch.*return \[\]" $FILE
grep -n "catch.*return {}" $FILE
grep -n "catch.*return null" $FILE
grep -n "catch.*return ''" $FILE
```

#### 2.3 State Fallbacks

```bash
# State access with fallback
grep -n "state\.[a-zA-Z]*\s*||" $FILE
grep -n "Modal\.state.*||" $FILE
grep -n "\.config.*||" $FILE
```

#### 2.4 Missing Debug Containers (for complex components)

For JS files with complex state, check for debug infrastructure:

```bash
# Should have debug container if file has state management
grep -n "debugLog\|debug-log\|debug-state" $FILE
```

#### 2.5 Unit Tests (FORBIDDEN)

```bash
# Check for pytest unit test files (should not exist)
find tests/ -name "test_*.py" 2>/dev/null
```

### Step 3: Report Format

Output violations in this format:

```
## Coding Guard Audit Results

### Files Checked
- webui/prompty/js/modal/example.js
- webui/prompty/server/api/endpoints.py

### Violations Found

#### [X] webui/prompty/js/modal/example.js

| Line | Issue | Code |
|------|-------|------|
| 42 | Fallback default | `const comp = params.get('composition') || 42` |
| 87 | Silent failure | `catch(e) { return [] }` |

**Fix:** Replace with explicit error handling:
```javascript
const comp = params.get('composition');
if (!comp) {
    return { error: 'composition parameter required' };
}
```

#### [OK] webui/prompty/server/api/endpoints.py
No violations found.

### Summary
- Files checked: 2
- Violations: 2
- Status: FAILED - Fix violations before committing
```

### Step 4: Verify Required Patterns

For files with violations, also check they have:

- [ ] Explicit error returns for missing required params
- [ ] Clear error messages with context
- [ ] Debug containers (for UI components with complex state)
- [ ] `data-testid` attributes (for new UI elements)

## Anti-Pattern Reference

| Pattern | Example | Why Bad |
|---------|---------|---------|
| Default values | `x \|\| 42` | Silent wrong value |
| Fallback chains | `x ?? y ?? z` | Untraceable source |
| State fallbacks | `state.x \|\| default` | Masks stale data |
| Silent catch | `catch(e) { return [] }` | Hides bugs |
| Guessed params | `params.get('x', 42)` | Silent wrong value |
| Unit tests | `pytest test_foo.py` | Not e2e, doesn't test integration |

## Required Pattern Reference

| Pattern | Example | Why Good |
|---------|---------|----------|
| Explicit error | `if (!x) return {error: 'x required'}` | Clear failure |
| Descriptive error | `throw new Error(\`Expected int, got ${typeof x}\`)` | Debuggable |
| Single source | `getValueFromURL()` only | Traceable |
| Debug container | `debugLog('key', value)` | Visible to tests |

## Quick Commands

```bash
# Check for fallback patterns in changed files
git diff --name-only | xargs grep -l "|| [0-9]\|?? [0-9]" 2>/dev/null

# Check for silent catches
git diff --name-only | xargs grep -l "catch.*return \[\]" 2>/dev/null

# Full scan of a specific file
grep -nE "\|\| [0-9]|\?\? [0-9]|\|\| \[\]|\|\| \{\}|catch.*return \[\]" path/to/file.js
```

## Limitations

- **Read-only** - Audits code but doesn't modify files
- **Pipeline position** - Runs in parallel after `/create-task` alongside `/cli-first`, `/ux-review`, `/e2e-guard`
- **Prerequisites** - Requires `git diff` output; works best after commits or staged changes
- **Not suitable for** - Initial project setup (no git history); pure documentation changes
- **Git state assumptions** - Requires at least one prior commit; for first commits, run on staged changes instead

## See Also

- `/create-task` - Task implementation skill (use this first)
- `/e2e-guard` - E2E test coverage verification
- `/ux-review` - User perspective verification
