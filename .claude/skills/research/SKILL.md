---
name: research
description: Research technologies and classify their impact on the playbook pipeline.
argument-hint: <technology name>
---

## TL;DR

**What:** Research a technology, classify its domain, document pipeline impact.

**When:** Before using a new library/framework. Enables tech-aware skills.

**Output:** `techs/{tech}/README.md` with domain classification and skill impact matrix.

---

# /research — Technology Research (Phase 1)

Research a technology and classify its domain and pipeline impact. This is **Phase 1** of two-phase research:

1. **Phase 1 (this skill):** Domain classification → `techs/{tech}/README.md`
2. **Phase 2 (automatic):** Skill-specific references produced lazily when skills are invoked with the tech

**IMPORTANT:** Research should happen in your **kickstarted project**, not the playbook source. Projects have real context (file structure, conventions, existing techs) that makes research deterministic and useful.

## What It Does

1. Identify and research the technology via web search
2. Classify the tech's domain(s)
3. **Present findings to user for confirmation**
4. Document pipeline impact (which skills are affected)
5. Produce `techs/{tech}/README.md` (only after user confirms)

**Note:** Skill-specific reference docs are NOT produced here. They are produced automatically when a skill is invoked with this tech (see `TECH_CONTEXT.md`).

## Usage

```
/research xstate
/research tanstack-query
/research {any-technology-name}
```

---

## Step 1: Check for Existing Research

Check if `techs/{tech}/README.md` exists:

- If exists → report what's there. Ask user: update existing research or done?
- If not → proceed to Step 2.

---

## Step 2: Identify the Technology

Web search for "{tech} javascript library" or "{tech} npm package" to find matches.

If multiple matches:

```
Which {tech}?
  1. {Best match} — {one-line description}
  2. {Second match} — {one-line description}
  3. {Third match} — {one-line description}
  4. Something else
```

If one clear match, confirm directly:
```
{tech}: {one-line description}. Correct?
```

---

## Step 3: Research & Domain Classification

Using the confirmed identity, web search for:
- Core concepts (what problem does it solve?)
- Ecosystem (related packages, integrations)
- Common patterns and anti-patterns
- Testing approaches

Then classify into one or more domains using the Domain Classification Table:

| Domain | Examples | Skills Affected |
|--------|----------|-----------------|
| **State Management** | XState, Redux, Zustand, Jotai | coding-guard, cli-first, create-task |
| **UI Components** | Radix, Shadcn, MUI, Chakra | ux-planner, ux-review, create-task |
| **Data Fetching** | TanStack Query, SWR, tRPC, Apollo | coding-guard, e2e-guard, create-task |
| **Form Handling** | React Hook Form, Formik, Zod | ux-planner, coding-guard, e2e-guard |
| **Animation** | Framer Motion, GSAP, React Spring | ux-review, e2e (wait patterns) |
| **Routing** | React Router, TanStack Router | create-task, e2e, e2e-guard |
| **Testing Tools** | Playwright, Vitest, Jest | e2e, e2e-guard, e2e-investigate |
| **Build Tools** | Vite, Turbopack, esbuild | create-task, e2e (server startup) |
| **Styling** | Tailwind, CSS Modules | ux-review, ux-planner |
| **Auth** | NextAuth, Clerk, Auth0 | coding-guard, e2e, create-task |

---

## Step 4: Present & Confirm (REQUIRED)

**CRITICAL:** Present research findings to user and wait for confirmation before saving.

Present findings in this format:

```
Based on my research:

**{tech}:** {one paragraph description of what it is and what problem it solves}

**Domain(s):** {domain classification from table above}

**Pipeline Impact:**
- {skill}: {why this skill is affected}
- {skill}: {why this skill is affected}
- (other skills not affected)

**Key Patterns:**
- {pattern 1}
- {pattern 2}
- {pattern 3}

Is this correct? Any corrections or additional context about how you'll use {tech}?
```

**User can respond:**
- **Confirm** — "Yes" or "Correct" → Proceed to Step 5
- **Correct** — "Actually it's for X, not Y" → Update classification and re-confirm
- **Add context** — "I'll be using it with React for form workflows" → Include in README

**Do NOT proceed to Step 5 until user confirms.** This ensures:
- Domain classification is accurate for your use case
- Pipeline impact is relevant to your project
- Reference docs will be useful, not speculative

---

## Step 5: Produce Tech README (After Confirmation)

**Only after user confirms findings in Step 4**, create `techs/{tech}/README.md` with this structure:

```markdown
# {Tech Name}

{One paragraph description — what it is, what problem it solves}

## Domain Classification

| Domain | Applies |
|--------|---------|
| State Management | {Yes/No} |
| UI Components | {Yes/No} |
| Data Fetching | {Yes/No} |
| Form Handling | {Yes/No} |
| Animation | {Yes/No} |
| Routing | {Yes/No} |
| Testing Tools | {Yes/No} |
| Build Tools | {Yes/No} |
| Styling | {Yes/No} |
| Auth | {Yes/No} |

## Pipeline Impact

Based on domain classification, these skills may need tech-specific references:

| Skill | Impact | Reason |
|-------|--------|--------|
| {skill} | {High/Medium/Low/None} | {Why this skill is affected} |
| ... | ... | ... |

## User's Use Case

{If user provided context during confirmation, include it here}

Example: "Using for multi-step form workflows with React"

## Core Concepts

{Brief summary of key concepts — just enough for skills to understand the tech}

## Common Patterns

{Patterns that affect how skills operate}

## Anti-Patterns & Gotchas

{Common mistakes that coding-guard should flag}

## Testing Considerations

{How this tech affects E2E testing}

## Resources

- Official docs: {url}
- GitHub: {url}
- npm: {url}
```

---

## After Research (Step 6)

After saving the README, report to the user:

```
✓ Research complete for {tech}

Domain: {primary domain(s)}
Pipeline impact: {list affected skills}
Use case: {user's stated use case, if provided}

Saved: techs/{tech}/README.md

Skill-specific reference docs will be produced automatically when you invoke
skills with {tech} context. For example:
  - "create a checkout wizard with {tech}" → /create-task produces references/{tech}.md
  - Running /coding-guard on {tech} code → produces references/{tech}.md if needed

To manually produce all reference docs now, say "produce all {tech} references".
```

---

## Manual Full Research (Optional)

If user requests "produce all {tech} references", evaluate each skill using the Skill Concern Matrix in `TECH_CONTEXT.md` and produce reference docs for skills where 2+ concerns are relevant.

This bypasses lazy evaluation for users who want complete docs upfront.

## Limitations

- **Modifies files** - Creates `techs/{tech}/README.md` after user confirmation
- **Pipeline position** - Pre-implementation; informs all other skills with tech context
- **Prerequisites** - Web search access required; user confirmation before saving
- **Not suitable for** - Quick implementation (use `/create-task` directly if tech is already researched)

## See Also

- `/create-task` - Consumes tech context for implementation patterns
- `/coding-guard` - Uses tech context for anti-pattern detection
- `/cli-first` - Uses tech context for observability patterns
- `/e2e-guard` - Uses tech context for test generation patterns
- `/ux-planner` - Uses tech context for UX component constraints
- `/ui-planner` - Uses tech context for visual component patterns
- `TECH_CONTEXT.md` - Domain classification and skill concern matrix
