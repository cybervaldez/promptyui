---
name: ui-review
description: Visual design quality guard that detects AI slop patterns. Run after /ui-planner to identify generic aesthetics and get actionable refinement suggestions. Enables rapid iteration toward distinctive design.
argument-hint: [preview file path]
---

## TL;DR

**What:** AI slop detector. Catches generic design patterns, enforces styleguide compliance.

**When:** After `/ui-planner` generates previews, before `/create-task`.

**Output:** Slop audit with scores. PASS → ready for implementation. NEEDS ITERATION → fix and re-run.

---

## Tech Context Detection

Before performing review, check for technology-specific UI patterns:

1. **Scan task/context** for technology mentions (component libraries, styling frameworks)
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: Typography validation? Color system check? Animation capabilities?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and incorporate tech-specific validation rules

**Domains that affect this skill:** UI Components, Styling, Animation

---

# UI Review (Slop Guard)

A visual design quality gate that detects AI slop and generic aesthetics after `/ui-planner` generates previews. Provides specific, actionable feedback to iterate toward distinctive design.

## Philosophy

- **Anti-slop** - Every visual choice should be intentional, not defaulted
- **Intentionality over defaults** - Question why each element looks the way it does
- **Distinctive over safe** - Generic is the enemy; push toward memorable
- **Styleguide as source of truth** - If tokens exist, they define correctness
- **Context-aware scoring** - What's slop in one aesthetic may be intentional in another
- **Lazy research** - Stay current by web searching for latest slop patterns

## Pipeline Position

```
+---------------------------------------------------------------------+
|                    Visual Design Pipeline                            |
+---------------------------------------------------------------------+
|                                                                      |
|  /ux-planner → /ui-planner → /ui-review → Pass? → /create-task       |
|                     ↑              │          │                      |
|                     └──────────────┘          No                     |
|                   Iterate with suggestions    │                      |
|                                               ↓                      |
|                                   Fix and re-run /ui-review          |
|                                                                      |
+---------------------------------------------------------------------+
```

**Key Differentiation:**
- `/ui-planner`: "Generate visual design options and previews"
- `/ui-review`: "Does this look like AI slop? What makes it distinctive?"

---

## What is AI Slop?

**Definition:** Low-effort, generic, AI-generated visual design lacking intentionality, personality, or brand identity.

**Core Problem:** LLMs trained on internet patterns converge to the most common solutions, making every AI-generated design look the same: Generic, Safe, Forgettable.

### Common AI Slop Indicators

| Category | Slop Indicator | Why It's Generic |
|----------|----------------|------------------|
| **Typography** | Inter font everywhere | Most common web font |
| **Typography** | System fonts only (Arial, Roboto) | Default fallbacks |
| **Typography** | Same weight throughout | No hierarchy |
| **Color** | Purple-to-blue gradients | Overused AI aesthetic |
| **Color** | Blue accent for everything | Default, not chosen |
| **Color** | Exact inverted dark mode | No thoughtfulness |
| **Layout** | All spacing identical | No rhythm or tension |
| **Layout** | Every corner rounded-lg | One-size-fits-all |
| **Layout** | Centered everything | Avoids hard decisions |
| **Components** | Every button rounded-full | No hierarchy |
| **Components** | Gradient text everywhere | Readability issues |
| **Components** | Glassmorphism on everything | Trend over function |
| **Motion** | No hover states | Static, lifeless |
| **Motion** | No micro-interactions | Missing feedback |
| **Decoration** | Random floating 3D shapes | Decoration without purpose |
| **Decoration** | Generic stock illustrations | Forgettable, impersonal |

---

## Input Detection

The skill auto-detects input from recent `/ui-planner` output:

### Auto-Detection Priority

1. **Preview files** - Look for recent `preview-*.html` files
2. **Styleguide** - Check for `styleguide.css`, `design-tokens.css`, or tech-specific config
3. **Handoff spec** - Look for "Visual Design Spec" in recent conversation

### Manual Input

User can specify:
```
/ui-review webui/previews/preview-industrial-dashboard.html
```

---

## Step 1: Context Extraction

Extract design context from `/ui-planner` output:

### From Preview Files

```
Parse HTML preview for:
- Aesthetic direction (from filename, comments, or token values)
- Layout pattern (from DOM structure)
- Color palette (from CSS custom properties)
- Typography (from --font-* variables)
- Component patterns (button styles, card styles, etc.)
```

### From Styleguide

```
Parse styleguide for:
- Design token definitions (CSS variables)
- Theme support (light/dark)
- Component base styles
- Spacing scale
- Border radius scale
```

### Context Summary Format

```markdown
### Design Context (Extracted)
- **Aesthetic**: {e.g., "Dark Industrial"}
- **Layout**: {e.g., "Dashboard"}
- **Preview**: {file path}
- **Tech**: {CSS variables / Tailwind / CSS-in-JS / etc.}
- **Key Tokens Detected**: {count} CSS variables
```

---

## Step 1.5: Styleguide Detection & Alignment (Critical)

This step determines whether the review uses styleguide compliance or aesthetic-based evaluation.

### Styleguide File Patterns

Search for existing styleguide files:

| Pattern | Tech Context |
|---------|--------------|
| `styleguide.css` | Standard CSS |
| `design-tokens.css` | CSS custom properties |
| `theme.css` | Theme-based systems |
| `variables.css` | Generic CSS variables |
| `tailwind.config.js` | Tailwind CSS |
| `theme.ts`, `theme.js` | CSS-in-JS (Emotion, Styled) |
| `src/styles/tokens.*` | Organized token files |

### If Styleguide Exists

1. **Parse design tokens** from the styleguide file
2. **Map tokens to categories**: colors, typography, spacing, radius, shadows
3. **Use styleguide as source of truth** for validation
4. **Flag deviations** as potential slop (hardcoded values vs. token usage)

### If No Styleguide

1. **Fall back to aesthetic-based evaluation** (Step 2 research)
2. **Suggest creating styleguide** after review passes
3. **Note in report** that compliance checking was skipped

### Styleguide Parsing Output

```markdown
### Styleguide Detected
- **Location**: `webui/styleguide.css`
- **Tokens found**: 24 CSS variables
- **Categories**:
  - Colors: 12 tokens (--color-*)
  - Typography: 5 tokens (--font-*, --text-*)
  - Spacing: 4 tokens (--space-*)
  - Radius: 3 tokens (--radius-*)
- **Key values**:
  - `--color-accent: #00d4ff`
  - `--font-heading: 'JetBrains Mono'`
  - `--radius-md: 0.5rem`
```

---

## Step 2: Lazy Slop Research

Perform web searches to identify current slop patterns relevant to the detected aesthetic and layout.

### Why Lazy Research?

- Slop patterns evolve as AI tools change
- Static checklists become outdated
- Context-specific patterns require current knowledge
- Each aesthetic has different slop indicators

### Search Query Templates

Adapt queries based on extracted context:

```
"{aesthetic} AI slop design patterns {year}"
e.g., "minimal AI slop design patterns 2026"

"generic AI {layout} patterns avoid"
e.g., "generic AI dashboard patterns avoid"

"distinctive {aesthetic} {element} examples"
e.g., "distinctive industrial typography examples"

"{aesthetic} design anti-patterns"
e.g., "brutalist design anti-patterns"
```

### Research Output

```markdown
### Research Performed
Searched for current slop patterns relevant to: {aesthetic} + {layout}
- "{search query 1}" → {key finding}
- "{search query 2}" → {key finding}
- "{search query 3}" → {key finding}

### Context-Specific Checklist Built
For {aesthetic} aesthetic with {layout} layout, flagging:
- [pattern 1] - why it's slop in this context
- [pattern 2] - why it's slop in this context
- [pattern 3] - intentional for this aesthetic (skip)
```

---

## Step 3: Context-Aware Audit

Apply the research findings and styleguide compliance to audit the design.

### Audit Layers

**Layer 1: Styleguide Compliance** (if styleguide exists)
- Are components using defined CSS variables?
- Do colors match `--color-*` tokens?
- Is typography using `--font-*` and `--text-*` tokens?
- Do radii match `--radius-*` tokens?
- Any hardcoded values that should use tokens?

**Layer 2: Aesthetic Alignment** (from research)
- Does the design match the declared aesthetic?
- Are choices intentional or defaulted?
- Is there visual hierarchy?
- Does color usage follow aesthetic guidelines?

**Layer 3: Generic Slop Detection** (universal patterns)
- Blue accent without justification
- Purple-to-pink gradients
- All-same border radius
- Missing hover/interaction states
- No typography hierarchy

### Context Changes What's Slop

| Element | Neo-Minimal | Brutalist | Maximalist |
|---------|-------------|-----------|------------|
| No curves | Slop (too rigid) | Intentional | Slop (contradicts richness) |
| Purple gradient | Slop (too flashy) | Slop (too soft) | Might be intentional |
| Excessive whitespace | Intentional | Slop (lacks density) | Slop (contradicts fullness) |
| Single font | Intentional | Intentional | Slop (lacks variety) |
| Thick borders | Slop (too heavy) | Intentional | Context-dependent |

---

## Scoring System

### Score Per Category (0-2)

| Score | Meaning |
|-------|---------|
| 0 | **Blocking** - Contradicts aesthetic OR objectively generic slop OR styleguide deviation |
| 1 | **Passable** - Acceptable but not distinctive; could improve |
| 2 | **Distinctive** - Intentional and appropriate for the aesthetic |

### Scoring Priority

1. **Styleguide deviation = automatic 0** (if styleguide exists)
2. **Then apply aesthetic-based scoring** from research
3. **Generic slop patterns = 0** regardless of aesthetic

### Categories (dynamically determined)

Common categories include:
- **Typography** - Font choice, weight variation, hierarchy
- **Color** - Palette cohesion, semantic meaning, theme adaptation
- **Layout** - Spacing rhythm, visual tension, asymmetry/symmetry fit
- **Components** - Radius variation, hierarchy clarity, styling intention
- **Motion** - Hover states, transitions, micro-interactions
- **Decoration** - Purpose-driven elements, brand reinforcement

### Pass Criteria

- **No blocking issues** (no scores of 0)
- **Majority at 1+** with documented reasoning
- Context determines acceptable trade-offs

---

## Fix Suggestions

For each failed check (score = 0), provide:

1. **What** - The specific issue found
2. **Why** - Why it's problematic in this context
3. **Fix** - Specific remediation with code snippet
4. **Token reference** - If styleguide exists, reference the token to use

### Example Fix Format

```markdown
**Issue**: Hardcoded color `#3b82f6` in button
**Why**: Deviates from styleguide; makes theming impossible
**Fix**: Use `var(--color-accent)` instead
**Code**:
```css
/* Before (slop) */
.btn-primary { background: #3b82f6; }

/* After (correct) */
.btn-primary { background: var(--color-accent); }
```
```

---

## Report Format

```markdown
## UI Review Results

### Design Context (Extracted)
- **Aesthetic**: {from ui-planner}
- **Layout**: {from ui-planner}
- **Preview**: {file path}
- **Tech**: {CSS variables / Tailwind / etc.}

---

### Styleguide Detected
- **Location**: `{path}`
- **Tokens found**: {count} CSS variables
- **Key values**:
  - `--color-accent: {value}`
  - `--font-heading: {value}`
  - `--radius-md: {value}`

*(Or: "No styleguide found - using aesthetic-based evaluation")*

---

### Styleguide Compliance Check
| Element | Expected (from styleguide) | Actual | Status |
|---------|---------------------------|--------|--------|
| Button accent | `--color-accent` (#00d4ff) | #3b82f6 | MISMATCH |
| Heading font | `--font-heading` | JetBrains Mono | MATCH |
| Card radius | `--radius-md` (0.5rem) | 1rem | MISMATCH |

---

### Research Performed
Searched for current slop patterns relevant to: {aesthetic} + {layout}
- "{search query 1}" → {key finding}
- "{search query 2}" → {key finding}

---

### Context-Specific Checklist Built
For {aesthetic} aesthetic, flagging:
- [x] {pattern} - {why it's slop}
- [x] {pattern} - {why it's slop}
- [ ] {pattern} - intentional for this aesthetic

---

### AI Slop Audit
| Category | Score | Issue | Why It's Slop | Fix |
|----------|-------|-------|---------------|-----|
| Color | 0 | Hardcoded #3b82f6 | Styleguide deviation | Use `var(--color-accent)` |
| Typography | 2 | - | Using tokens correctly | - |
| Components | 0 | Hardcoded radius | Styleguide deviation | Use `var(--radius-md)` |
| Layout | 1 | All same spacing | No visual rhythm | Vary with --space-{4,6,8} |
| Motion | 1 | Basic hover states | Could be more intentional | Add transition timing |

---

### Blocking Issues (Score = 0)
1. **Color**: Using hardcoded color instead of styleguide token
   → Replace `#3b82f6` with `var(--color-accent)`

2. **Components**: Using hardcoded radius instead of styleguide token
   → Replace `border-radius: 1rem` with `var(--radius-md)`

---

### Status: NEEDS ITERATION | PASS

---

### Next Steps

**If NEEDS ITERATION:**
Fix blocking issues:
1. {specific fix 1}
2. {specific fix 2}

Then run `/ui-review` again, or `/ui-planner` to regenerate.

**If PASS:**
Design is distinctive and styleguide-compliant.
Ready for `/create-task` implementation.
```

---

## Example Review Conversation

### Scenario: Post-ui-planner Review

```
User: /ui-review

Skill: Detecting ui-planner output...

Found:
- Preview: webui/previews/preview-industrial-dashboard.html
- Styleguide: webui/styleguide.css

Extracting design context...

## UI Review Results

### Design Context (Extracted)
- **Aesthetic**: Dark Industrial
- **Layout**: Dashboard
- **Preview**: webui/previews/preview-industrial-dashboard.html
- **Tech**: CSS custom properties

---

### Styleguide Detected
- **Location**: `webui/styleguide.css`
- **Tokens found**: 24 CSS variables
- **Key values**:
  - `--color-accent: #00d4ff`
  - `--font-heading: 'JetBrains Mono', monospace`
  - `--radius-md: 0.5rem`

---

### Styleguide Compliance Check
| Element | Expected | Actual | Status |
|---------|----------|--------|--------|
| Button background | `--color-accent` | `#00d4ff` | MATCH |
| Heading font | `--font-heading` | JetBrains Mono | MATCH |
| Card radius | `--radius-md` (0.5rem) | 1rem | MISMATCH |
| Body text color | `--color-text-primary` | #e5e5e5 | MATCH |

---

### Research Performed
Searched for current slop patterns: Dark Industrial + Dashboard
- "industrial UI slop 2026" → Avoid: excessive glow effects, generic grid metrics
- "dark dashboard anti-patterns" → Avoid: all-same-size metric cards, no hierarchy

---

### Context-Specific Checklist Built
For Dark Industrial aesthetic:
- [x] Generic blue accent - replaced with cyan (good)
- [x] Rounded corners on everything - need sharp/minimal
- [ ] Monospace typography - intentional for industrial

---

### AI Slop Audit
| Category | Score | Issue | Why It's Slop | Fix |
|----------|-------|-------|---------------|-----|
| Typography | 2 | - | JetBrains Mono fits industrial | - |
| Color | 2 | - | Cyan accent is distinctive | - |
| Components | 0 | Cards use 1rem radius | Industrial = sharp corners | Use `--radius-sm` or none |
| Layout | 1 | Same-size metrics | No hierarchy in dashboard | Vary metric card sizes |
| Motion | 1 | Basic hover | Could use precision timing | Add `ease-sharp` transitions |

---

### Blocking Issues (Score = 0)
1. **Components**: Card border-radius too rounded for Industrial aesthetic
   → Replace `border-radius: 1rem` with `var(--radius-sm)` or `0`

---

### Status: NEEDS ITERATION

---

### Next Steps
Fix the border-radius issue:
1. Update preview CSS: `.card { border-radius: var(--radius-sm); }`
2. Or regenerate with `/ui-planner` specifying "sharp corners"

Then run `/ui-review` again.

---

User: I fixed the radius, review again

Skill: Re-running review...

### Styleguide Compliance Check
| Element | Expected | Actual | Status |
|---------|----------|--------|--------|
| Card radius | `--radius-sm` (0.25rem) | 0.25rem | MATCH |
... (all other checks)

### AI Slop Audit
| Category | Score | Issue | Fix |
|----------|-------|-------|-----|
| Typography | 2 | - | - |
| Color | 2 | - | - |
| Components | 2 | Sharp corners | - |
| Layout | 1 | Same-size metrics | Consider varying |
| Motion | 1 | Basic hover | Could enhance |

### Blocking Issues (Score = 0)
None

### Status: PASS

Design is distinctive and styleguide-compliant.
Ready for `/create-task` implementation.

Optional improvements:
- Consider varying metric card sizes for visual hierarchy
- Add precision timing to hover transitions for industrial feel
```

---

## Limitations

| Limitation | Next Step |
|------------|-----------|
| No preview files | Run `/ui-planner` to generate previews |
| No styleguide | Run `/ui-planner` or create `webui/styleguide.css` manually |

## When NOT to Run This Skill

- Before `/ui-planner` has generated output
- For code-only changes (no visual impact)
- For UX flow changes (use `/ux-review` instead)
- When user explicitly says "skip review"

---

## See Also

- `references/slop-research.md` - Research methodology and query templates
- `/ui-planner` - Generates previews this skill reviews
- `/ux-planner` - Interaction flows (review with `/ux-review`)
- `/create-task` - Implementation after design passes
- `TECH_CONTEXT.md` - Tech-specific UI patterns
