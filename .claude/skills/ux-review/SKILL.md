---
name: ux-review
description: Verify UI changes from user perspective via browser testing. Auto-suggested after /create-task completes.
---

## TL;DR

**What:** Visual + behavioral UX verification via screenshots and navigation. Checks feedback, consistency, interactions, and click-through behavior.

**When:** After `/create-task` completes (auto-suggested).

**Output:** UX report with implementation verification, gaps identified, improvement suggestions.

---

## Tech Context Detection

Before reviewing, check for technology-specific visual patterns:

1. **Scan changed UI files** for technology imports/usage (component libraries, animation)
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: Visual patterns? Animations? Design system? Responsive?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and apply tech-specific review criteria

**Domains that affect this skill:** UI Components, Animation, Styling

---

# UX Review - User Perspective Verification

> **Core Philosophy**
>
> "As a user interacting with this feature, do I see what I expect?"
>
> Unlike `/coding-guard` (code patterns) or `/e2e-guard` (test coverage), this skill focuses on:
> - **Visibility**: Is the feedback visible to the user?
> - **Clarity**: Does the user understand what's happening?
> - **Consistency**: Does it look like the rest of the app?

## How to Use

```
/ux-review
```

No arguments needed. The skill automatically:
1. **Reviews the implementation context** - Reads the previous task's description, summary, and solution
2. Finds changed UI files via `git diff`
3. Identifies affected components/views
4. **Takes screenshots** via `agent-browser screenshot` for visual assessment
5. Runs visibility, interaction, and feedback checks via `agent-browser`
6. **Analyzes UX gaps** and suggests improvements
7. Reports from USER perspective
8. **Refers to `/create-task`** for applying fixes or suggestions

## Trigger

Auto-suggested after `/create-task` completes.

## Workflow Steps

### Step 0: Review Implementation Context

**CRITICAL**: Before checking UI behavior, understand what was implemented and why.

#### 0.1 Review the Previous Task/Problem

Look at the conversation context for:
- **Problem description**: What issue was being solved?
- **Summary**: What approach was taken?
- **Solution**: What specific changes were made?

This context is essential to verify the UX matches the intended behavior.

#### 0.2 Extract Expected Behavior

From the implementation context, identify:

| Aspect | Question to Answer |
|--------|-------------------|
| **User action** | What does the user do to trigger this feature? |
| **Expected feedback** | What should the user see/experience? |
| **State changes** | What should change after the action? |
| **Edge cases** | What happens in error/empty/loading states? |

Example extraction:
```
Implementation: "Remove max dropdown, add confirmation modal when starting stage while worker is running"

Expected UX:
- User clicks stage button -> if worker idle, auto-start
- User clicks stage button -> if worker busy, show confirmation dialog
- Dialog shows: "Stop & Start" / "Add to Queue" / "Cancel" options
- No batch limit dropdown should be visible
```

### Step 1: Find Changed UI Files

```bash
# Get modified UI files
git diff --name-only HEAD -- '*.js' '*.css' '*.html'

# Or check unstaged changes
git diff --name-only -- '*.js' '*.css' '*.html'
```

### Step 2: Map to Affected Pages/Components

| File Pattern | Affected Page | Test URL Pattern |
|--------------|---------------|------------------|
| `webui/prompty/js/*.js` | Main WebUI | `http://localhost:8085/` |
| `webui/prompty/js/modal/*.js` | Modal views | `http://localhost:8085/?modal=<name>` |
| `webui/prompty/js/home/*.js` | Home grid | `http://localhost:8085/` |
| `webui/prompty/js/sidebar/*.js` | Sidebar | `http://localhost:8085/?prompt=<id>` |
| `webui/prompty/css/*.css` | Visual styling | Same as parent JS |

### Step 3: Run UX Verification

For each affected area, run these checks using `agent-browser`.

#### 3.1 Feedback Visibility Checks

| Scenario | What to Verify |
|----------|----------------|
| Action triggers | User sees loading indicator |
| Success | User sees confirmation (toast/visual change) |
| Error | Error message is visible (not just console) |
| State change | UI reflects the new state |

```bash
# Example: Verify loading state appears
agent-browser click "@generate-btn"
sleep 0.3
SNAPSHOT=$(agent-browser snapshot -c)
echo "$SNAPSHOT" | grep -qi "loading\|spinner\|generating" && echo "PASS: Loading visible"
```

#### 3.2 Visual Hierarchy Checks

| Check | Expected Pattern |
|-------|------------------|
| Base text | Gray/muted (#6e7681) |
| New/active text | White/bold (#f0f6fc) |
| Interactive hover | Visible state change |
| Selected items | Clear visual distinction |

```bash
# Example: Verify text styling applied
RESULT=$(agent-browser eval "getComputedStyle(document.querySelector('.text-base')).color")
echo "$RESULT" | grep -q "110, 118, 129" && echo "PASS: Base text gray"
```

#### 3.3 Interaction Feedback Checks

| Interaction | Expected Feedback |
|-------------|-------------------|
| Dropdown click | Menu opens, shows options |
| Value selection | Selected value displayed |
| Input change | Visual confirmation of change |
| Button click | Disabled state or loading |

```bash
# Example: Verify dropdown shows selected value
agent-browser click "@dropdown-trigger"
sleep 0.5
SNAPSHOT=$(agent-browser snapshot -c)
echo "$SNAPSHOT" | grep -q "dropdown-menu\|menu-open" && echo "PASS: Dropdown opened"
```

#### 3.4 State Consistency Checks

| Check | What to Verify |
|-------|----------------|
| After action | UI reflects action result |
| Page reload | State persists correctly |
| Navigation | Back/forward work as expected |

```bash
# Example: Verify state persists after reload
BEFORE=$(agent-browser eval "document.querySelector('[data-testid=\"selected-value\"]').textContent")
agent-browser reload
sleep 2
AFTER=$(agent-browser eval "document.querySelector('[data-testid=\"selected-value\"]').textContent")
[ "$BEFORE" = "$AFTER" ] && echo "PASS: State persisted"
```

#### 3.5 Content Quality Checks

**CRITICAL**: Check for content issues that confuse users.

| Check | What to Verify |
|-------|----------------|
| No text duplication | Base and new text don't overlap |
| Proper text separation | Different sections have distinct content |
| Complete content | No truncated or missing text |
| Correct ordering | Parent content before child content |

### Step 3.5: Behavioral Navigation Audit

**Purpose:** Systematically verify that interactive elements respond to clicks and that multi-step user journeys work end-to-end. This is exploratory and discovery-oriented — it finds navigation dead ends, broken links, and unresponsive elements that targeted checks (Steps 3.1-3.5) may miss.

> **Region vs. Flow**
>
> **Region exploration** maps and clicks every interactive element by page area (header, sidebar, main, footer). It answers: "Does each clickable thing actually do something?"
>
> **User flow walkthroughs** follow multi-step journeys across regions (e.g., sidebar item → detail view → action → back). They answer: "Can the user complete real tasks?"
>
> Run regions first (discover elements), then flows (verify journeys).

**Read-only enforcement:** Only `click` (`[NAV]`/`[VIEW]` elements only — filtered via `SKIP_MUTATE`), `hover`, `scroll`, `back`, `forward`, `reload`, `snapshot`, `screenshot`, `eval`, `get`, `open`. Never `click` on `[CRUD]`/`[FORM]`/`[SESSION]`/`[ACTION]` elements. Never `fill`, `type`, `check`, `uncheck`, `select`, or trigger POST/PUT/DELETE.

> **Element Safety Filtering (from `element-operations.md`)**
>
> Navigation testing must NEVER click elements that trigger data mutations. Before extracting refs,
> filter out elements whose labels match CRUD/Form/Session/Action keywords:
> ```bash
> SKIP_MUTATE='create\|add\|save\|edit\|delete\|remove\|submit\|confirm\|login\|logout\|register\|run\|start\|stop\|generate\|export\|download\|cancel\|publish\|deploy'
> ```
> Apply via `grep -vi "$SKIP_MUTATE"` BEFORE extracting `@e` refs. Only `[NAV]` and `[VIEW]` elements are clicked.
> See `skills/browser/references/element-operations.md` for the full category dictionary.
> To test CRUD elements explicitly, use `/e2e` Phase 4+ or `/create-task` with specific test instructions.

#### 3.5.1 Region Discovery

Map all interactive elements on the page:

```bash
# Get interactive element map
agent-browser snapshot -i > /tmp/ux-interactive-map.txt

# Count by type
BUTTONS=$(grep -ci "button" /tmp/ux-interactive-map.txt || echo 0)
LINKS=$(grep -ci "link" /tmp/ux-interactive-map.txt || echo 0)
DROPDOWNS=$(grep -ci "combobox\|listbox\|menu" /tmp/ux-interactive-map.txt || echo 0)
echo "Interactive elements: $BUTTONS buttons, $LINKS links, $DROPDOWNS dropdowns"
```

#### 3.5.2 Region-Based Click Exploration

Extract refs per region and click each to verify response:

```bash
BASE_URL="http://localhost:8085"
SKIP_MUTATE='create\|add\|save\|edit\|delete\|remove\|submit\|confirm\|login\|logout\|register\|run\|start\|stop\|generate\|export\|download\|cancel\|publish\|deploy'

# For each region: extract refs, click, verify, reset
# Cap at 10 elements per region for token efficiency (skip mutation elements)
for REF in $(grep -vi "$SKIP_MUTATE" /tmp/ux-interactive-map.txt | grep -oE '@e[0-9]+' | head -10); do
    # Click element
    agent-browser click "$REF"
    sleep 1

    # Verify something changed (URL or content)
    CURRENT_URL=$(agent-browser get url 2>/dev/null)
    SNAPSHOT=$(agent-browser snapshot -c)

    # Log result
    if [ "$CURRENT_URL" != "$BASE_URL/" ] || echo "$SNAPSHOT" | grep -qi "active\|selected\|open\|expanded"; then
        echo "PASS: $REF responded to click"
    else
        echo "GAP: $REF - no visible response to click (Navigation Dead End)"
    fi

    # Reset to base state
    agent-browser open "$BASE_URL/"
    sleep 2

    # Re-snapshot after reset (don't cache stale refs)
    agent-browser snapshot -i > /tmp/ux-interactive-map.txt
done
```

#### 3.5.3 User Flow Spot-Check

Light flow verification scoped to the changed feature's primary journey:

```bash
# Template: navigate to entry -> click trigger -> verify state -> click next -> verify -> check final URL
BASE_URL="http://localhost:8085"

# Step 1: Navigate to entry point
agent-browser open "$BASE_URL/"
sleep 2

# Step 2: Click primary trigger (e.g., sidebar item)
agent-browser snapshot -i > /tmp/ux-flow-snap.txt
TRIGGER_REF=$(grep -i "sidebar\|nav" /tmp/ux-flow-snap.txt | grep -vi "$SKIP_MUTATE" | grep -oE '@e[0-9]+' | head -1)
[ -n "$TRIGGER_REF" ] && agent-browser click "$TRIGGER_REF"
sleep 1

# Step 3: Verify state changed
SNAPSHOT=$(agent-browser snapshot -c)
CURRENT_URL=$(agent-browser get url 2>/dev/null)
echo "After trigger: URL=$CURRENT_URL"

# Step 4: Click next action in flow
agent-browser snapshot -i > /tmp/ux-flow-snap.txt
NEXT_REF=$(grep -vi "$SKIP_MUTATE" /tmp/ux-flow-snap.txt | grep -oE '@e[0-9]+' | head -1)
[ -n "$NEXT_REF" ] && agent-browser click "$NEXT_REF"
sleep 1

# Step 5: Verify final state
FINAL_URL=$(agent-browser get url 2>/dev/null)
echo "Flow complete: started=$BASE_URL/ -> ended=$FINAL_URL"

# Step 6: Verify back button
agent-browser back
sleep 1
BACK_URL=$(agent-browser get url 2>/dev/null)
echo "After back: URL=$BACK_URL"
```

#### 3.5.4 Navigation Gap Reporting

New gap category that feeds into Step 5 (Gap Analysis) and Step 7 (Refer to /create-task):

| Gap Type | Description | Detection |
|----------|-------------|-----------|
| **Navigation Dead End** | Interactive-looking element with no response | Click produces no URL change, no content change, no visual feedback |
| **Broken Back Navigation** | Back button doesn't restore previous state | URL after `back` doesn't match previous URL |
| **Missing Active State** | Clicked nav item shows no selected/active indicator | No `active`, `selected`, or `aria-current` in snapshot after click |
| **URL State Mismatch** | URL doesn't reflect current navigation state | Content shows page X but URL still shows page Y |

### Step 4: Visual Assessment via Screenshots

**CRITICAL**: Take screenshots to visually verify the implementation matches expected behavior.

#### 4.1 Capture Screenshots for Key States

```bash
# Take screenshot of initial state
agent-browser screenshot --path /tmp/ux-review-initial.png

# Perform action
agent-browser click "@action-button"
sleep 1

# Capture result state
agent-browser screenshot --path /tmp/ux-review-after-action.png

# Capture dialog if expected
agent-browser screenshot --path /tmp/ux-review-dialog.png
```

#### 4.2 Compare Against Expected Behavior

Using the screenshots, verify:

| Check | How to Verify |
|-------|---------------|
| **Element removed** | Screenshot should NOT show the element (e.g., dropdown) |
| **Element added** | Screenshot should show new element (e.g., dialog) |
| **Visual hierarchy** | Colors, sizing, spacing match design |
| **State reflection** | UI shows correct state (loading, success, error) |
| **Layout intact** | No visual regressions in surrounding elements |

#### 4.3 Screenshot Naming Convention

```
/tmp/ux-review-{feature}-{state}.png

Examples:
- /tmp/ux-review-stages-initial.png
- /tmp/ux-review-stages-dropdown-removed.png
- /tmp/ux-review-stages-worker-busy-dialog.png
- /tmp/ux-review-stages-after-queue.png
```

### Step 5: UX Gap Analysis

**Identify gaps between implementation and optimal user experience.**

#### 5.1 Gap Categories

| Category | What to Look For |
|----------|------------------|
| **Missing feedback** | Action has no visible result |
| **Unclear state** | User can't tell what's happening |
| **Inconsistent patterns** | Different from similar features |
| **Accessibility gaps** | Missing labels, poor contrast, no keyboard nav |
| **Error handling** | Errors not shown or unclear |
| **Edge cases** | Empty states, loading states not handled |
| **Navigation dead end** | Interactive element produces no response (from Step 3.5) |

#### 5.2 Gap Detection Checklist

```markdown
## UX Gap Checklist

### Feedback Gaps
- [ ] Loading state visible during async operations?
- [ ] Success confirmation after action completes?
- [ ] Error messages shown (not just console)?
- [ ] Progress indication for long operations?

### Clarity Gaps
- [ ] Labels describe what will happen?
- [ ] Current state is obvious?
- [ ] Options are clearly differentiated?
- [ ] Confirmation dialogs explain consequences?

### Consistency Gaps
- [ ] Similar to other features in app?
- [ ] Follows established UI patterns?
- [ ] Uses standard components?
- [ ] Matches color/spacing conventions?

### Accessibility Gaps
- [ ] Keyboard navigable?
- [ ] Screen reader labels present?
- [ ] Sufficient color contrast?
- [ ] Focus states visible?
```

#### 5.3 Document Gaps Found

```markdown
### Gap: [Brief Description]

**Observed**: What currently happens
**Expected**: What should happen
**Impact**: How this affects users (High/Medium/Low)
**Suggestion**: How to fix it

Example:
### Gap: No loading state when queueing stage

**Observed**: Button text changes to "Queueing..." but no spinner
**Expected**: Visible spinner or progress indicator
**Impact**: Medium - user unsure if action is processing
**Suggestion**: Add spinner icon next to "Queueing..." text
```

### Step 6: Suggest Improvements

**Provide actionable recommendations for UX improvements.**

#### 6.1 Improvement Categories

| Type | When to Suggest |
|------|-----------------|
| **Quick Fix** | Minor CSS/text change, low effort |
| **Enhancement** | Better UX, moderate effort |
| **Alternative** | Different approach worth considering |
| **Future Consideration** | Good idea but not urgent |

#### 6.2 Improvement Template

```markdown
### Improvement: [Title]

**Type**: Quick Fix | Enhancement | Alternative | Future Consideration
**Effort**: Low | Medium | High
**Priority**: P0 (Critical) | P1 (Important) | P2 (Nice-to-have)

**Current State**:
[What currently exists]

**Proposed Change**:
[What should be changed]

**Rationale**:
[Why this improves UX]

**Implementation Hint**:
[Brief technical direction]
```

### Step 7: Refer to /create-task

**IMPORTANT**: After identifying gaps or suggesting improvements, direct user to `/create-task` for implementation.

#### 7.1 When to Refer

- Any gap with Impact: High or Medium
- Any improvement with Priority: P0 or P1
- Multiple related gaps that should be fixed together
- Alternative approaches that need discussion

#### 7.2 Referral Format

```markdown
---

## Next Steps

### Gaps/Issues to Address

The following issues were identified and should be fixed:

1. **[Gap Title]** - [Brief description]
2. **[Gap Title]** - [Brief description]

### Suggested Improvements

The following improvements would enhance UX:

1. **[Improvement Title]** - [Brief description]

---

**To implement these fixes/improvements, run:**

```
/create-task [description of what to fix]
```

Example:
```
/create-task Add loading spinner to stage button and success toast after queueing
```
---
```

#### 7.3 Navigation Gaps → E2E Coverage

Navigation dead ends and broken flows discovered in Step 3.5 should be handed off to `/e2e-guard` for regression test coverage:

```markdown
**Navigation gaps requiring E2E coverage:**

| Gap | Element | Expected Behavior | E2E Test Needed |
|-----|---------|-------------------|-----------------|
| Dead end | Sidebar "Settings" link | Should open settings view | `test_navigation.sh`: verify settings nav |
| Broken back | Detail view back button | Should return to list | `test_navigation.sh`: verify back navigation |

**To generate tests, run:**
```
/e2e-guard
```
```

### Step 8: Report from User Perspective

Output findings using "As a user..." language, including implementation verification, gaps, and suggestions:

```
## UX Review Results

### Implementation Context
**Task**: Remove max dropdown, add confirmation modal when starting stage while worker is running
**Expected Behavior**:
- No batch limit dropdown in stages header
- Auto-start worker when idle
- Show confirmation dialog when worker is busy

### Files Checked
- webui/prompty/index.html (dropdown removal)
- webui/prompty/js/queue/queue.js (worker busy check)
- webui/prompty/css/sections/queue.css (dropdown styles removed)

### Affected Views
- Build Stages section in sidebar (http://localhost:8085)

### Screenshots Captured
- `/tmp/ux-review-stages-initial.png` - Stages section without dropdown
- `/tmp/ux-review-stages-worker-busy.png` - Confirmation dialog appearance

### Implementation Verification

#### Against Expected Behavior
| Expected | Verified | Notes |
|----------|----------|-------|
| Dropdown removed | YES | Not visible in sidebar |
| Auto-start when idle | YES | Worker starts after queue |
| Busy dialog shown | YES | Shows Stop & Start / Queue / Cancel |
| Dialog has correct options | YES | All 3 buttons present |

#### User Experience Checks
- "When I click stage button while idle, generation starts" PASS
- "When I click stage button while busy, I see options" PASS
- "When I choose 'Add to Queue', batch is queued without stopping" PASS
- "When I choose 'Cancel', nothing happens" PASS

### UX Gaps Identified

#### Gap 1: No loading feedback during queue
**Observed**: Button says "Queueing..." but no spinner
**Impact**: Medium
**Suggestion**: Add spinner icon

#### Gap 2: No success confirmation
**Observed**: Batch appears in list silently
**Impact**: Low
**Suggestion**: Show toast "Queued X items"

### Suggested Improvements

1. **Add spinner to Queueing state** (Quick Fix, P2)
2. **Show success toast after queue** (Enhancement, P1)

### Navigation Audit Summary

| Region | Elements Tested | Responsive | Dead Ends |
|--------|----------------|------------|-----------|
| Header/Nav | 3 | 3 | 0 |
| Sidebar | 5 | 4 | 1 |
| Main Content | 4 | 4 | 0 |
| Footer | 2 | 2 | 0 |

| Flow | Steps | Completed | Back Nav |
|------|-------|-----------|----------|
| Sidebar → Detail → Back | 3 | YES | YES |

### Summary
| Category | Count |
|----------|-------|
| Implementation verified | 4/4 |
| UX checks passed | 4/4 |
| Navigation elements tested | 14 |
| Navigation dead ends | 1 |
| Gaps identified | 2 |
| Improvements suggested | 2 |

**Status**: PASSED - Implementation matches expected behavior

---

## Next Steps

To address the identified gaps and improvements, run:

```
/create-task Add spinner to stage button queueing state and success toast after queuing
```
```

## UX Check Categories

### Category 1: Feedback Visibility

Users must see feedback for their actions.

| Action | Required Feedback |
|--------|-------------------|
| Button click | Loading state or immediate result |
| Form submit | Success/error message |
| Long operation | Progress indicator |
| Background task | Completion notification |

### Category 2: Visual Consistency

UI should follow established patterns.

| Element | Expected Style |
|---------|----------------|
| Primary actions | Bold, prominent |
| Secondary text | Muted gray |
| Error states | Red highlight |
| Success states | Green highlight |
| Disabled states | Grayed out, non-interactive |

### Category 3: Interaction Patterns

Interactions should behave predictably.

| Pattern | Expected Behavior |
|---------|-------------------|
| Click -> Result | Immediate or loading state |
| Hover -> Feedback | Visual state change |
| Focus -> Highlight | Clear focus indicator |
| Disabled -> No action | No response to clicks |

### Category 4: State Reflection

UI must reflect current state accurately.

| State | UI Requirement |
|-------|----------------|
| Loading | Spinner or skeleton |
| Error | Error message visible |
| Empty | Empty state message |
| Success | Confirmation visible |
| Updated | New value displayed |

### Category 5: Content Quality

**CRITICAL**: Content must be accurate and non-duplicated.

| Issue | What to Check |
|-------|---------------|
| Text duplication | Base text should NOT appear in new text span |
| Content overlap | Sibling items should have distinct content |
| Missing content | All expected text should be visible |
| Wrong ordering | Parent content should precede child content |
| Truncation | Long text should be handled gracefully |

### Category 6: Navigation Behavior

**CRITICAL**: Navigation must be responsive and predictable.

| Check | What to Verify |
|-------|----------------|
| Nav items responsive | Every nav/sidebar link responds to click with content or URL change |
| URL reflects state | Current URL matches the displayed content/section |
| Back button works | Browser back restores previous view and URL |
| Active state visible | Currently selected nav item has clear visual distinction |
| No dead clicks | No interactive-looking elements that produce zero response |
| Region coverage | Header, sidebar, main content, and footer navigation all functional |

## Quick Verification Commands

```bash
# Start server for testing
./start-prompty.sh

# Open page in agent-browser
agent-browser open "http://localhost:8085/"

# Get compact snapshot for text verification
SNAPSHOT=$(agent-browser snapshot -c)

# Check for specific element
echo "$SNAPSHOT" | grep -q "expected-text" && echo "Found"

# Evaluate CSS property
agent-browser eval "getComputedStyle(document.querySelector('.class')).color"

# Click and verify
agent-browser click "@button-testid"
sleep 0.5
agent-browser snapshot -c | grep -q "expected-result"

# Close when done
agent-browser close
```

## Screenshot Commands Reference

```bash
# Take full-page screenshot
agent-browser screenshot --path /tmp/ux-review-full.png

# Take screenshot of specific element
agent-browser screenshot --selector ".container" --path /tmp/ux-review-section.png

# Capture before/after states
agent-browser screenshot --path /tmp/ux-review-before.png
agent-browser click "@action-button"
sleep 1
agent-browser screenshot --path /tmp/ux-review-after.png

# Capture dialog/modal
agent-browser click "@trigger-dialog"
sleep 0.5
agent-browser screenshot --path /tmp/ux-review-dialog.png

# Capture error state
agent-browser eval "fetch('/api/invalid').catch(() => {})"
sleep 1
agent-browser screenshot --path /tmp/ux-review-error.png
```

## UX Review Workflow Summary

```
+-------------------------------------------------------------+
|                    /ux-review Workflow                       |
+-------------------------------------------------------------+
|                                                              |
|  Step 0: Review Implementation Context                       |
|          +-- What was the task? What's expected?             |
|                           |                                  |
|  Step 1-3: Find Files, Map Views & UX Verification           |
|          +-- git diff, identify affected pages, run checks   |
|                           |                                  |
|  Step 3.5: Behavioral Navigation Audit                       |
|          +-- Region discovery (snapshot -i)                  |
|          +-- Region click exploration (click, verify, reset) |
|          +-- User flow spot-check (multi-step journeys)      |
|          +-- Navigation gap reporting                        |
|                           |                                  |
|  Step 4: Visual Assessment (Screenshots)                     |
|          +-- agent-browser screenshot for key states         |
|                           |                                  |
|  Step 5: UX Gap Analysis                                     |
|          +-- Compare actual vs expected behavior             |
|          +-- Include navigation dead ends from Step 3.5      |
|                           |                                  |
|  Step 6: Suggest Improvements                                |
|          +-- Document fixes and enhancements                 |
|                           |                                  |
|  Step 7: Refer to /create-task                               |
|          +-- Provide command to implement fixes              |
|          +-- 7.3: Hand off nav gaps to /e2e-guard            |
|                           |                                  |
|  Step 8: Report                                              |
|          +-- Full report with navigation audit summary       |
|                                                              |
+-------------------------------------------------------------+
```

## Common UX Issues to Check

| Issue | How to Detect |
|-------|---------------|
| Loading state missing | Click action, immediate snapshot shows no loader |
| Error not visible | Trigger error, snapshot has no error message |
| State not reflected | Change value, snapshot shows old value |
| Broken interaction | Click element, no response in snapshot |
| Missing focus state | Tab to element, no visible change |
| Inconsistent styling | Compare CSS values to design system |
| **Text duplication** | Compare base vs new text spans - new should NOT contain base |
| Content overlap | Compare sibling items for shared content (>50 chars) |
| Wrong text hierarchy | Child content appears before parent content |

## Key Integration Points

### After /create-task
This skill is auto-suggested after `/create-task` completes to verify the implementation from a user perspective.

### Before Next /create-task
When gaps or improvements are identified, use `/create-task` to implement the fixes:
```
/create-task [description based on UX review findings]
```

### Complete Quality Loop
```
/create-task -> implement -> /coding-guard -> /ux-review -> /create-task (for fixes)
```

## Limitations

- **Read-only** - Takes screenshots and reports issues; doesn't modify files
- **Pipeline position** - Runs in parallel with `/coding-guard`, `/cli-first`, `/e2e-guard` after `/create-task`
- **Prerequisites** - Server must be running; implementation must exist
- **Not suitable for** - CLI-only projects; API-only projects; pre-implementation design (use `/ui-planner`)
- **Browser required** - Needs `agent-browser` for screenshots and verification

| Limitation | Next Step |
|------------|-----------|
| Server not running | Run `./start-prompty.sh` and wait for ready message |
| No git diff | Run `git add .` to stage changes, then retry |

## When NOT to Use

Skip `/ux-review` when:
- **Backend-only change** - No visual impact to verify
- **API endpoint change** - No user-facing UI affected
- **CSS-only refactor** - No behavioral changes (use `/ui-review` instead)
- **Test file updates** - No implementation changes
- **Documentation changes** - No UI to review
- **Server not running** - Will fail; start server first

## See Also

- `/create-task` - **Use to implement fixes from UX review**
- `/ui-planner` - Visual design advisor (pre-implementation)
- `/ui-review` - Design quality guard (post `/ui-planner`, pre implementation)
- `/coding-guard` - Code pattern auditing (run in parallel)
- `/e2e-guard` - E2E test coverage
- `/agent-browser` - Browser automation reference (screenshots, clicks, evals)
