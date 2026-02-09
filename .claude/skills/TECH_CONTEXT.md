# Tech Context Detection

Shared reference for all skills to detect and handle technology-specific patterns.

---

## Preflight: Playbook Assumptions

Before using `/research` or `/create-task`, understand these assumptions:

### Assumption 1: Single Project Context

The playbook assumes Claude is working within **one coherent project**.

| Works Well | May Need Adjustment |
|------------|---------------------|
| Single app (React, Node, etc.) | Monorepo with unrelated apps |
| Multi-tech single app (XState + React Query) | Separate projects in same repo |
| Feature folders within one codebase | Polyglot repos (JS + Python + Go) |

**If you have a monorepo:** Specify the subdirectory context in your task.
```bash
# Good: Scoped to specific app
/create-task "add auth to apps/web using xstate"

# Ambiguous: Which app?
/create-task "add auth using xstate"
```

### Assumption 2: Tech Detection is Task-Scoped

Skills detect techs mentioned in **the current task**, not the entire project.

| Implication | Mitigation |
|-------------|------------|
| May miss techs used elsewhere | Run `/research` for key techs upfront |
| Reference docs are per-tech, not per-project | Keep `techs/` folder as project memory |

### Assumption 3: No Persistent Project Type

The playbook doesn't remember "this is a Next.js app" between sessions. Both tech detection and project archetype classification (see `PROJECT_CONTEXT.md`) are session-scoped — they re-read project files each session rather than persisting results to disk.

| Each session | Relies on |
|--------------|-----------|
| `/research` | `techs/{tech}/README.md` if it exists |
| `/create-task` | Tech detection in task + existing `techs/` |
| `/ux-planner`, `/ui-planner`, `/create-task`, `/e2e-guard`, `/coding-guard`, `/cli-first`, `/e2e`, `/kaizen` | `PROJECT_CONTEXT.md` archetype detection from README.md, package.json |

**Best practice:** Run `/research {your-framework}` early to establish project context.

---

### What the Playbook IS and ISN'T

| IS | ISN'T |
|----|-------|
| Skill system for Claude | Project template/starter |
| Convention guide | Architectural constraint |
| Documentation pipeline | "Pick one per category" framework |

The playbook doesn't restrict what techs you use. It documents patterns for whatever techs you choose.

---

## Two-Phase Research

Skills use a lazy evaluation approach to tech-specific documentation:

1. **Phase 1 (On tech mention):** `/research` creates `techs/{tech}/README.md` with domain classification
2. **Phase 2 (On skill invocation):** Each skill produces `references/{tech}.md` when needed

---

## Domain Classification Table

| Domain | Examples | Skills Affected |
|--------|----------|-----------------|
| **State Management** | XState, Redux, Zustand, Jotai, MobX | coding-guard, cli-first, create-task |
| **UI Components** | Radix, Shadcn, MUI, Chakra, Ant Design | ux-planner, ui-planner, ui-review, ux-review, create-task |
| **Data Fetching** | TanStack Query, SWR, tRPC, Apollo | coding-guard, e2e-guard, create-task |
| **Form Handling** | React Hook Form, Formik, Zod, Yup | ux-planner, coding-guard, e2e-guard |
| **Animation** | Framer Motion, GSAP, React Spring | ux-review, ui-planner, ui-review, e2e (wait patterns) |
| **Routing** | React Router, TanStack Router, Next.js | create-task, e2e, e2e-guard |
| **Testing Tools** | Playwright, Vitest, Jest, Cypress | e2e, e2e-guard, e2e-investigate |
| **Build Tools** | Vite, Turbopack, esbuild, Webpack | create-task, e2e (server startup) |
| **Styling** | Tailwind, CSS Modules, Styled Components | ux-review, ux-planner, ui-planner, ui-review |
| **Auth** | NextAuth, Clerk, Auth0, Supabase Auth | coding-guard, e2e, create-task |

---

## Project Type Pipeline Matrix

Each kickstart project type has different pipeline capabilities:

| Project Type | Server | Port | Has API | Health Check | API Testing |
|--------------|--------|------|---------|--------------|-------------|
| `python-cli-with-webui` | Flask | 8080 | ✓ Yes | `curl /` | ✓ Full |
| `nextjs-with-cli` | Next.js | 3000 | ✓ Yes | `curl /` | ✓ Full (API routes) |
| `react-with-cli` | Vite (dev only) | 5173 | ✗ No | `curl /` | ⚠️ None until backend added |

### Project Type Details

#### python-cli-with-webui
- **Server**: Flask serves both static files and API
- **API**: Add routes in `app.py`
- **Pipeline**: Full compatibility (UI + API testing)

#### nextjs-with-cli
- **Server**: Next.js unified server
- **API**: Add routes in `app/api/` or `pages/api/`
- **Pipeline**: Full compatibility (UI + API testing)

#### react-with-cli
- **Server**: Vite dev server (development only)
- **API**: None out of the box
- **Pipeline**: UI testing works, API testing requires backend

⚠️ **React API Testing Note:**
The `/api/pu` placeholder exists but has no backend. Skills showing API patterns (curl to `/api/*`) are examples for when you add a backend (Express, Fastify, etc.).

**To add API capabilities:**
1. Add backend framework (Express, Fastify)
2. Update `8085` in PROJECT_CONFIG.md
3. Either:
   - Configure Vite proxy to backend, OR
   - Serve React build from backend

---

## Skill Concern Matrix

Each skill has fixed concerns. When producing a reference doc, evaluate these against the tech:

### create-task
| Concern | Question |
|---------|----------|
| File structure | Does this tech require specific folder organization? (e.g., `machines/`, `stores/`) |
| Scaffolding | Does this tech have boilerplate patterns or generators? |
| Test organization | Does this tech change where/how tests should be structured? |
| Debug containers | Does this tech require special debug visualization? |

### coding-guard
| Concern | Question |
|---------|----------|
| Anti-patterns | Does this tech have known misuse patterns to flag? |
| Silent failures | Does this tech have failure modes that don't throw errors? |
| State mutation | Does this tech have immutability or mutation gotchas? |
| Error handling | Does this tech have unconventional error patterns? |

### cli-first
| Concern | Question |
|---------|----------|
| State exposure | Does this tech require special patterns to expose state for AI verification? |
| TestID conventions | Does this tech have recommended testID patterns? |
| Verification commands | Does this tech have unique ways to verify state via CLI? |
| Token costs | Does this tech affect the cost of different verification methods? |

### ux-planner
| Concern | Question |
|---------|----------|
| Component constraints | Does this tech limit or enable specific UI patterns? |
| Async feedback | Does this tech affect how loading/error states should be shown? |
| Accessibility | Does this tech have accessibility implications or built-in a11y? |
| Form patterns | Does this tech change how forms should be designed? |

### ui-planner
| Concern | Question |
|---------|----------|
| Design tokens | Does this tech have a token/theming system? (e.g., Tailwind config, CSS-in-JS themes) |
| Animation constraints | Does this tech affect animation implementation? (e.g., Framer Motion, CSS-only) |
| Component theming | Does this tech have built-in theming patterns? (e.g., MUI theme, Chakra tokens) |
| Layout systems | Does this tech provide grid/layout utilities? (e.g., Tailwind grid, CSS Grid libraries) |
| Styleguide format | Where should design tokens live? (e.g., CSS variables, JS theme object, Tailwind config) |

### ui-review
| Concern | Question |
|---------|----------|
| Typography validation | Does this tech provide/constrain font choices? (e.g., system fonts, custom fonts) |
| Color system check | Does this tech have theme/palette constraints? (e.g., Tailwind colors, CSS-in-JS themes) |
| Animation capabilities | Does this tech enable/limit motion design? (e.g., Framer Motion, CSS transitions only) |
| Component theming | Does this tech have built-in styling that may cause slop? (e.g., MUI defaults, Chakra defaults) |
| Brand alignment | Does this tech integrate with design systems? (e.g., Tailwind config, theme tokens) |

### e2e-guard
| Concern | Question |
|---------|----------|
| Coverage patterns | Does this tech require specific test coverage patterns? |
| Element selection | Does this tech affect how elements should be selected in tests? |
| API verification | Does this tech change how API responses should be verified? |
| State assertions | Does this tech require special state verification patterns? |

### e2e
| Concern | Question |
|---------|----------|
| Server startup | Does this tech affect how the dev server starts? |
| Artifact paths | Does this tech produce artifacts in non-standard locations? |
| Timing/waits | Does this tech require special wait patterns? |
| Cleanup | Does this tech require special cleanup between tests? |

### e2e-investigate
| Concern | Question |
|---------|----------|
| Failure patterns | Does this tech have common failure signatures? |
| Log formats | Does this tech produce logs in a specific format? |
| Reproduction | Does this tech require specific steps to reproduce issues? |
| Debug tools | Does this tech have built-in debugging tools to leverage? |

### ux-review
| Concern | Question |
|---------|----------|
| Visual patterns | Does this tech have visual conventions to verify? |
| Animations | Does this tech affect timing or transition verification? |
| Design system | Does this tech integrate with specific design systems? |
| Responsive | Does this tech affect responsive behavior verification? |

---

## Threshold

**Produce a reference doc if 2+ concerns are relevant.**

---

## Tech Context Detection Preamble

Each skill should include this check before executing:

```markdown
## Tech Context Detection

Before executing:
1. Scan task for technology mentions
2. For each tech detected:
   a. Check `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   b. Check `references/{tech}.md` exists — if not AND domain affects this skill:
      - Read `TECH_CONTEXT.md` for concern matrix
      - Evaluate concerns (see matrix above)
      - If 2+ concerns relevant, produce reference doc
3. Read relevant reference docs and apply patterns
```

---

## Reference Doc Style

Follow existing patterns (see `testing-conventions.md`, `ux-patterns.md`, `cli-patterns.md`):

- **Practical and actionable** — code examples, shell commands, conventions
- **Tables for quick reference** — patterns, anti-patterns, checklists
- **No theory/overview** — just patterns the skill needs
- **Anti-patterns clearly marked** — GOOD vs BAD examples
- **Greppable section headers** — easy to search

---

## Extending the Domain Table

The domain table is extensible. New domains can be added without changing the architecture.

### When to Add a New Domain

Add a domain when:
- Multiple technologies share similar pipeline impacts
- Existing domains don't capture the tech's nature
- 2+ skills would need similar reference patterns

### How to Add a Domain

1. **Identify the domain category**
   - What problem space does this tech address?
   - What other techs would belong to this domain?

2. **Map skills affected**
   - Which skills need tech-specific patterns?
   - Use the Skill Concern Matrix to evaluate

3. **Add to Domain Classification Table**
   ```markdown
   | **New Domain** | Example1, Example2 | skill1, skill2, skill3 |
   ```

4. **Document verification patterns** (if non-browser)
   - What CLI tools verify the output?
   - Add patterns to testing-conventions.md

### Example: Media Generation Domain

Technologies like Remotion (video), Sharp (images), or FFmpeg don't produce browser-viewable output. They need:

| Domain | Examples | Skills Affected |
|--------|----------|-----------------|
| **Media Generation** | Remotion, FFmpeg, Sharp, Canvas | create-task, e2e, e2e-guard, coding-guard, e2e-investigate |

**Why these skills:**
- **create-task**: Unique file structure (compositions/, assets/)
- **coding-guard**: Domain-specific anti-patterns (non-deterministic renders)
- **e2e**: Non-browser verification (ffprobe, file checks)
- **e2e-guard**: Coverage for each output type
- **e2e-investigate**: Domain-specific failure patterns

---

# Simulation: XState (State Machines) with Playbook Pipeline

## Question: How does a complex State Management tech work with our structure?

**XState** is fundamentally different from simple state libs:
- Finite state machines with explicit states/transitions
- Actor model for complex async flows
- Visual state charts (inspect, visualize)
- State is a first-class concept, not hidden

| Simulation Goal | Remotion | XState |
|-----------------|----------|--------|
| Domain fit | Needed new "Media Generation" domain | Fits existing "State Management" |
| Purpose | Prove extensibility for new domains | Prove alignment for existing domains |
| E2E challenge | Non-browser output (video files) | Browser-based but state is invisible |

---

## Phase 1: Does XState Fit State Management Domain?

### Current Domain Classification

| Domain | XState Fit? | Notes |
|--------|-------------|-------|
| **State Management** | ✅ YES | Perfect fit - explicit state machines |

### Comparison with Domain Siblings

| Aspect | Redux/Zustand | XState |
|--------|---------------|--------|
| State model | Key-value store | Finite state machine |
| Transitions | Actions/reducers | Explicit events/transitions |
| Async | Middleware (thunks, sagas) | Built-in (invoke, actors) |
| Visualization | DevTools (state tree) | Statecharts (visual diagrams) |
| Testing | Snapshot state | Test state transitions |

**Conclusion:** XState fits State Management but has unique patterns that affect all 3 skills differently than Redux/Zustand.

---

## Phase 2: Skill Concern Matrix for XState

### coding-guard

| Concern | Applies? | XState-Specific |
|---------|----------|-----------------|
| Anti-patterns | ✅ YES | Mutating context directly, infinite loops in guards |
| Silent failures | ✅ YES | Unreachable states, unhandled events silently ignored |
| State mutation | ✅ YES | XState enforces immutability but actions can violate |
| Error handling | ✅ YES | onError in services, error states in machines |

**Result:** 4/4 concerns → **produces reference doc**

### cli-first

| Concern | Applies? | XState-Specific |
|---------|----------|-----------------|
| State exposure | ✅ YES | `actor.getSnapshot().value` for current state |
| TestID conventions | ⚠️ Partial | State-based testIDs (`data-state="loading"`) |
| Verification commands | ✅ YES | `actor.getSnapshot().context.field` |
| Token costs | ✅ YES | Full context can be large - need selective exposure |

**Result:** 3.5/4 concerns → **produces reference doc**

### create-task

| Concern | Applies? | XState-Specific |
|---------|----------|-----------------|
| File structure | ✅ YES | `machines/`, `actors/` folders |
| Scaffolding | ✅ YES | Machine templates, actor patterns |
| Test organization | ✅ YES | State transition tests, actor tests |
| Debug containers | ✅ YES | State inspector, visual debugger |

**Result:** 4/4 concerns → **produces reference doc**

---

## Phase 3: Simulated Flow

### Scenario: "/create-task implement checkout flow with xstate"

```
1. /create-task Tech Context Detection activates
   → Scans task → finds "xstate"
   → Checks techs/xstate/README.md → doesn't exist
   → Triggers /research xstate first

2. /research xstate (Phase 1)
   → Confirms: State machine library
   → Domain(s): State Management
   → Pipeline Impact:
     - coding-guard: context mutation anti-patterns
     - cli-first: actor state exposure patterns
     - create-task: machines/ folder structure

3. User confirms → techs/xstate/README.md saved

4. /create-task resumes
   → Produces references/xstate.md with:
     - File structure patterns
     - Machine boilerplate
     - Test patterns for state transitions
```

---

## Phase 4: E2E Testing Patterns

### The Challenge

XState state is **invisible in DOM** but **critical to verify**.

### Exposing Machine State for CLI Verification

```javascript
// In component - expose for testing
useEffect(() => {
  if (process.env.NODE_ENV !== 'production') {
    window.__CHECKOUT_MACHINE__ = {
      state: actor.getSnapshot().value,
      context: actor.getSnapshot().context,
      send: actor.send
    };
  }
}, [actor]);
```

### E2E Verification Pattern

```bash
# Verify current state
STATE=$(agent-browser eval "window.__CHECKOUT_MACHINE__?.state" 2>/dev/null)
[ "$STATE" = "cart" ] && pass "Initial state: cart" || fail "Wrong state: $STATE"

# Trigger transition
agent-browser eval "window.__CHECKOUT_MACHINE__.send({ type: 'CHECKOUT' })"
sleep 0.5

# Verify new state
STATE=$(agent-browser eval "window.__CHECKOUT_MACHINE__?.state" 2>/dev/null)
[ "$STATE" = "payment" ] && pass "Transitioned to: payment" || fail "Wrong state: $STATE"

# Verify context
ITEMS=$(agent-browser eval "window.__CHECKOUT_MACHINE__?.context?.items?.length" 2>/dev/null)
[ "$ITEMS" -gt 0 ] && pass "Has $ITEMS items" || fail "Empty cart"
```

### State-Based TestIDs

```html
<!-- Component reflects machine state -->
<div data-testid="checkout" data-state={state.value}>
  ...
</div>
```

```bash
# Verify via testID attribute
SNAPSHOT=$(agent-browser snapshot -c)
echo "$SNAPSHOT" | grep -q 'data-state="payment"' && pass "State reflected" || fail "State not in DOM"
```

---

## Phase 5: Architecture Implications

### Does Our Structure Work?

| Component | Works? | Notes |
|-----------|--------|-------|
| Two-phase research | ✅ YES | Domain classification correct |
| Domain classification | ✅ YES | State Management fits perfectly |
| Skill concern matrix | ✅ YES | All concerns map to XState |
| E2E testing | ✅ YES | State exposure patterns work |
| CLI-first philosophy | ✅ YES | Machine state is queryable |

### No Changes Needed

Unlike Remotion, XState works with existing structure:
- Domain table already includes State Management
- Concern matrix questions all apply
- E2E can use existing agent-browser patterns

---

## Phase 6: XState-Specific Patterns

### Anti-Patterns (coding-guard)

```javascript
// BAD: Direct context mutation
actions: {
  addItem: (context, event) => {
    context.items.push(event.item); // ❌ Mutates directly
  }
}

// GOOD: Return new context (XState v5) or use assign
actions: {
  addItem: assign({
    items: (context, event) => [...context.items, event.item] // ✅ Immutable
  })
}
```

### Silent Failures

```javascript
// BAD: Unhandled event silently ignored
// If user sends 'CHECKOUT' while in 'payment' state, nothing happens

// GOOD: Explicit catch-all or strict mode
const machine = createMachine({
  // ...
  strict: true // Throws on unhandled events
});
```

### State Exposure (cli-first)

```javascript
// Minimal exposure for verification
window.__APP_STATE__ = {
  checkout: () => checkoutActor.getSnapshot().value,
  cartItems: () => checkoutActor.getSnapshot().context.items.length
};
```

```bash
# Efficient verification
STATE=$(agent-browser eval "window.__APP_STATE__.checkout()")
```

---

## Conclusion

### Does XState Work With Our Pipeline?

**Yes, fully compatible** with existing State Management domain.

| Verdict | Reason |
|---------|--------|
| ✅ Research skill | Correctly identifies State Management domain |
| ✅ Lazy evaluation | Produces refs for all 3 affected skills |
| ✅ Concern matrix | All questions relevant to XState |
| ✅ E2E testing | State exposure patterns work with agent-browser |
| ✅ CLI-first | Machine state is inherently queryable |

### Key Insight

XState is an **ideal State Management tech for the playbook** because:
1. State is explicit (easy to verify)
2. Transitions are defined (testable)
3. Context is queryable (CLI-friendly)
4. Visual debugging available (dev experience)

The playbook's State Management domain was designed with complex state in mind, making XState a perfect fit.
