---
name: ui-planner
description: Visual design advisor with interactive ASCII gallery and HTML preview generation. Use for establishing visual identity, typography, color systems, and layout patterns. Generates live previews for iteration.
argument-hint: [design context or feature description]
---

## TL;DR

**What:** Interactive visual design advisor. ASCII galleries → user selects → HTML preview generated.

**When:** After `/ux-planner` defines flows, before implementation.

**Output:** Preview HTML files + styleguide.css with design tokens.

---

## Tech Context Detection

Before providing recommendations, check for technology-specific UI patterns:

1. **Scan task/question** for technology mentions (component libraries, styling frameworks)
2. **For each tech detected:**
   - Check if `techs/{tech}/README.md` exists — if not, run `/research {tech}` first
   - Check if `references/{tech}.md` exists in this skill's directory
   - If not AND tech's domain affects this skill, produce reference doc:
     - Read `TECH_CONTEXT.md` for the Skill Concern Matrix
     - Evaluate concerns: Design tokens? Animation constraints? Component theming? Layout systems?
     - If 2+ concerns relevant → produce `references/{tech}.md`
3. **Read relevant reference docs** and incorporate tech-specific visual patterns

**Domains that affect this skill:** UI Components, Styling, Animation

---

## Project Context Detection

After Tech Context Detection, classify the project to rank aesthetic and layout suggestions:

1. **Read project signals** — `README.md`, `package.json` description/dependencies, existing routes
2. **Classify into 1-2 archetypes** from `PROJECT_CONTEXT.md` taxonomy
3. **Present to user for confirmation:**
   ```
   Based on your project, I'd classify this as: **{archetype}**
   ({brief rationale})
   Does this match your intent?
   ```
4. **Apply only after confirmation** — annotate Step 1 and Step 2 galleries with archetype fit

**Optional web research** (when user asks or context would help):
- `WebSearch "{archetype} web design trends {current_year}"`
- Summarize 2-3 trending patterns to inform gallery annotations
- Skip if user wants to move fast

---

# UI Planner

A visual design advisor that helps establish visual identity through an interactive, preview-driven workflow. This skill prioritizes visual decisions through explicit selection and iteration, preventing default "AI slop" aesthetics.

## Philosophy

- **Pipeline quality gate** - Forces explicit visual decisions before implementation
- **Bold over safe** - Push toward distinctive aesthetics, not generic templates
- **Anti-AI-slop** - Every choice should be intentional, not defaulted
- **Preview-driven iteration** - See before you commit
- **Testable output** - All components get `data-testid` for pipeline integration

## How to Use

### Pipeline Modes

```
+---------------------------------------------------------------------+
|                     Skill Workflow Integration                       |
+---------------------------------------------------------------------+
|                                                                      |
|  STANDALONE MODE:                                                    |
|  User has UI question -> /ui-planner -> (iterate) -> /create-task   |
|                                                                      |
|  POST-UX-PLANNER MODE (Recommended):                                 |
|  /ux-planner -> /ui-planner -> (apply visual layer) -> /create-task |
|                                                                      |
|  PRE-CREATE-TASK MODE:                                               |
|  /create-task needs visuals -> /ui-planner -> (design) -> resume    |
|                                                                      |
+---------------------------------------------------------------------+
```

**Standalone Mode**: User wants to establish visual identity from scratch.

**Post-UX-Planner Mode** (Recommended): User has interaction flows from `/ux-planner`, now needs the visual layer applied.

**Pre-Create-Task Mode**: Implementation needs visual direction before proceeding.

---

## Workflow Overview

```
+-------------------------------------------------------------------+
|                    /ui-planner Workflow                            |
+-------------------------------------------------------------------+
|                                                                    |
|  STEP 1: ASCII Art Direction Gallery (Aesthetic)                   |
|  → Present 6-8 aesthetic directions as ASCII thumbnails            |
|  → User selects ONE (e.g., "B")                                    |
|                                                                    |
|  STEP 2: ASCII Layout Gallery (Structure)                          |
|  → Present 6-8 layout patterns as ASCII thumbnails                 |
|  → User multi-selects (e.g., "1, 3")                               |
|                                                                    |
|  STEP 3: Generate HTML Previews                                    |
|  → Create preview files for each aesthetic+layout combo            |
|  → Each preview has light/dark toggle                              |
|                                                                    |
|  STEP 4: Review & Iterate                                          |
|  → User views previews in browser                                  |
|  → Provides feedback ("like X but with Y's header")                |
|  → Generate hybrid previews until satisfied                        |
|                                                                    |
|  STEP 5: Apply to Styleguide                                       |
|  → Check for existing styleguide                                   |
|  → Create/update with design tokens                                |
|  → All components include data-testid                              |
|                                                                    |
+-------------------------------------------------------------------+
```

---

## Step 1: ASCII Art Direction Gallery (Aesthetic)

Present these aesthetic directions as ASCII art thumbnails. User selects ONE letter.

```
+-------------------------------------------------------------------------+
| Select your aesthetic direction (A-H):                                   |
+-------------------------------------------------------------------------+
|                                                                          |
|  [A] BRUTALIST           [B] NEO-MINIMAL         [C] MAXIMALIST          |
|  +---------------+       +---------------+       +---------------+       |
|  | ############  |       |               |       | ***  +++  @@@ |       |
|  | ##  TEXT  ##  |       |       o       |       | +++  @@@  *** |       |
|  | ############  |       |    ______     |       | @@@  ***  +++ |       |
|  | ############  |       |               |       | +++  @@@  *** |       |
|  +---------------+       +---------------+       +---------------+       |
|  Raw, bold, high         Whitespace-focused,    Layered, textured,      |
|  contrast, brutally      subtle details,        rich visual density,    |
|  honest. No curves.      breathing room.        editorial feel.         |
|                                                                          |
|  [D] DARK INDUSTRIAL     [E] WARM ORGANIC        [F] RETRO-FUTURISM     |
|  +---------------+       +---------------+       +---------------+       |
|  | [===========] |       |    ~~~~~      |       |  ___________  |       |
|  | |   |   |   | |       |   (     )     |       | /           \ |       |
|  | |   |   |   | |       |    ~~~~~      |       | |  [=] [=]  | |       |
|  | [===========] |       |      |        |       | \_____o_____/ |       |
|  +---------------+       +---------------+       +---------------+       |
|  Metallic, muted,        Earth tones, soft      Rounded corners,        |
|  technical precision,    edges, natural         gradients, 70s/80s      |
|  monospace type.         textures, handmade.    sci-fi optimism.        |
|                                                                          |
|  [G] ART DECO            [H] SOFT PASTEL                                |
|  +---------------+       +---------------+                               |
|  |    /\  /\    |       | +-----------+ |                               |
|  |   /  \/  \   |       | |  .  .  .  | |                               |
|  |   \  /\  /   |       | |     ~     | |                               |
|  |    \/  \/    |       | +-----------+ |                               |
|  +---------------+       +---------------+                               |
|  Geometric, luxurious,   Light, airy, soft      |
|  gold accents,           shadows, rounded,      |
|  symmetrical patterns.   calming palette.       |
|                                                                          |
+-------------------------------------------------------------------------+
| Enter letter (e.g., "B"):                                                |
+-------------------------------------------------------------------------+
```

**If project context was detected**, append archetype-based recommendations after the gallery:

```
Based on your project archetype ({archetype}):
  Recommended:  [{letter}] {name}, [{letter}] {name}
  Good fit:     [{letter}] {name}
  Less typical: [{letter}] [{letter}] [{letter}] [{letter}] [{letter}]
All 8 remain available — these are suggestions, not restrictions.
```

See `PROJECT_CONTEXT.md` for archetype-to-aesthetic mapping.

---

## Step 2: ASCII Layout Gallery (Structure)

Present these layout patterns. User can multi-select numbers.

```
+-------------------------------------------------------------------------+
| Select layout pattern(s) (1-8, comma-separated for multiple):            |
+-------------------------------------------------------------------------+
|                                                                          |
|  [1] SIDEBAR LAYOUT      [2] DASHBOARD          [3] CARD GRID           |
|  +---------------+       +---------------+       +---------------+       |
|  | +--+--------+ |       | +--+--+-----+ |       | +--+ +--+ +--+|       |
|  | |  |        | |       | |  |  |     | |       | |  | |  | |  ||       |
|  | |  |        | |       | +--+--+-----+ |       | +--+ +--+ +--+|       |
|  | |  |        | |       | |           | |       | +--+ +--+ +--+|       |
|  | +--+--------+ |       | +-----------+ |       | |  | |  | |  ||       |
|  +---------------+       +---------------+       +---------------+       |
|  Navigation left,        Metrics/widgets top,   Uniform grid of         |
|  content right.          main content below.    repeating elements.     |
|                                                                          |
|  [4] HERO + CONTENT      [5] SPLIT PANEL        [6] LIST VIEW           |
|  +---------------+       +---------------+       +---------------+       |
|  | ============= |       | +-----+-----+ |       | +-------------+|      |
|  | HERO SECTION  |       | |     |     | |       | | ----------- ||      |
|  | ============= |       | |     |     | |       | | ----------- ||      |
|  | +--+ +--+     |       | |     |     | |       | | ----------- ||      |
|  | |  | |  |     |       | +-----+-----+ |       | | ----------- ||      |
|  +---------------+       +---------------+       +---------------+       |
|  Large header area,      Equal or master/       Vertical list           |
|  content sections        detail panels.         with line items.        |
|  below.                                                                  |
|                                                                          |
|  [7] KANBAN              [8] TIMELINE                                   |
|  +---------------+       +---------------+                               |
|  | +--+ +--+ +--+|       | o-----       |                               |
|  | |  | |  | |  ||       |       -----o |                               |
|  | |  | |  | |  ||       | o-----       |                               |
|  | |  | |  | |  ||       |       -----o |                               |
|  +---------------+       +---------------+                               |
|  Columnar workflow,      Sequential events,                             |
|  drag-drop lanes.        chronological flow.                            |
|                                                                          |
+-------------------------------------------------------------------------+
| Enter numbers (e.g., "1, 3"):                                            |
+-------------------------------------------------------------------------+
```

**If project context was detected**, append archetype-based recommendations after the gallery:

```
Based on your project archetype ({archetype}):
  Recommended:  [{number}] {name}, [{number}] {name}
  Good fit:     [{number}] {name}
  Less typical: [{number}] [{number}] [{number}] [{number}] [{number}]
All 8 remain available — these are suggestions, not restrictions.
```

See `PROJECT_CONTEXT.md` for archetype-to-layout mapping.

---

## Step 3: Generate HTML Previews

After selections, generate preview files:

### Preview File Naming

`preview-{aesthetic}-{layout}.html`

Examples:
- `preview-minimal-sidebar.html`
- `preview-minimal-cardgrid.html`

### Preview Location

| Project Type | Preview Location | Styleguide Location |
|--------------|------------------|---------------------|
| Python (webui) | `webui/previews/preview-{name}.html` | `webui/styleguide.css` |
| React (Vite) | `src/previews/preview-{name}.html` | `src/styles/design-tokens.css` |
| Next.js | `public/previews/preview-{name}.html` | `src/styles/design-tokens.css` |

### Preview Content Requirements

Each preview must include:
1. **Theme toggle** (light/dark) at top-right
2. **Typography showcase** - headings, body, code samples
3. **Color palette display** - primary, secondary, accent, semantic colors
4. **Component samples** - buttons, inputs, cards
5. **Layout grid demonstration** - actual layout with placeholder content
6. **All elements with `data-testid`** - for pipeline integration

### Example Preview Generation Prompt

```markdown
Generate HTML preview for: {aesthetic} aesthetic + {layout} layout

Include:
- Embedded CSS (no external deps)
- CSS custom properties for all design tokens
- Light/dark theme toggle (data-testid="theme-toggle")
- Root element with data-theme="light" attribute
- All interactive elements with semantic data-testid
- Typography: headings (h1-h4), body, small, code
- Colors: bg-primary, bg-secondary, text-primary, text-secondary, accent, success, warning, error
- Components: primary button, secondary button, input, card
- Layout regions with data-testid: header, sidebar, main-content, footer (as applicable)
```

---

## Step 4: Review & Iterate Loop

After generating previews:

```
+-------------------------------------------------------------------------+
| Preview files generated:                                                 |
|                                                                          |
| 1. webui/previews/preview-minimal-sidebar.html                           |
|    → Open in browser to review                                           |
|                                                                          |
| 2. webui/previews/preview-minimal-cardgrid.html                          |
|    → Open in browser to review                                           |
|                                                                          |
+-------------------------------------------------------------------------+
| Iteration options:                                                       |
|                                                                          |
| - "I like [1]'s sidebar but want [2]'s card style"                       |
| - "Make the accent color more vibrant"                                   |
| - "Increase typography contrast"                                         |
| - "this one" (when satisfied with a preview)                             |
|                                                                          |
+-------------------------------------------------------------------------+
```

### Hybrid Preview Generation

When user requests combinations:

1. Parse which elements from which previews
2. Generate new hybrid preview
3. Name it `preview-{aesthetic}-hybrid-{n}.html`
4. Loop until user says "this one"

---

## Step 5: Apply to Styleguide

### Check for Existing Styleguide

Look for existing files:
- `styleguide.css`
- `design-tokens.css`
- `theme.css`
- `variables.css`
- Tech-specific: `tailwind.config.js`, `theme.ts`

### If No Styleguide Exists

Create `styleguide.css` with:

```css
/* Design Tokens - Generated by /ui-planner */

:root {
  /* Color Primitives */
  --color-white: #ffffff;
  --color-black: #000000;
  /* ... full palette */

  /* Semantic Colors - Light Theme */
  --color-bg-primary: var(--color-white);
  --color-bg-secondary: #f5f5f5;
  --color-text-primary: #1a1a1a;
  --color-text-secondary: #666666;
  --color-accent: #0066cc;
  --color-success: #22c55e;
  --color-warning: #eab308;
  --color-error: #ef4444;

  /* Typography */
  --font-heading: 'Inter', system-ui, sans-serif;
  --font-body: 'Inter', system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', monospace;

  --text-xs: 0.75rem;
  --text-sm: 0.875rem;
  --text-base: 1rem;
  --text-lg: 1.125rem;
  --text-xl: 1.25rem;
  --text-2xl: 1.5rem;
  --text-3xl: 1.875rem;

  /* Spacing */
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-6: 1.5rem;
  --space-8: 2rem;
  --space-12: 3rem;

  /* Border Radius */
  --radius-sm: 0.25rem;
  --radius-md: 0.5rem;
  --radius-lg: 1rem;
  --radius-full: 9999px;

  /* Shadows */
  --shadow-sm: 0 1px 2px rgba(0,0,0,0.05);
  --shadow-md: 0 4px 6px rgba(0,0,0,0.1);
  --shadow-lg: 0 10px 15px rgba(0,0,0,0.1);

  /* Transitions */
  --transition-fast: 150ms ease;
  --transition-base: 200ms ease;
  --transition-slow: 300ms ease;
}

/* Dark Theme */
[data-theme="dark"] {
  --color-bg-primary: #0a0a0a;
  --color-bg-secondary: #1a1a1a;
  --color-text-primary: #fafafa;
  --color-text-secondary: #a1a1a1;
  /* ... override semantic colors */
}

/* Base Component Styles */
.btn {
  padding: var(--space-2) var(--space-4);
  border-radius: var(--radius-md);
  font-family: var(--font-body);
  font-size: var(--text-sm);
  transition: all var(--transition-fast);
}

.btn-primary {
  background: var(--color-accent);
  color: var(--color-white);
}

.btn-secondary {
  background: var(--color-bg-secondary);
  color: var(--color-text-primary);
  border: 1px solid var(--color-text-secondary);
}

/* Layout Regions - All with data-testid */
[data-testid="main-sidebar"] { /* sidebar styles */ }
[data-testid="main-content"] { /* content styles */ }
[data-testid="main-header"] { /* header styles */ }
```

### If Styleguide Exists

Update with selected design tokens while preserving existing structure.

### Discoverability Requirements

For `/e2e`, `/e2e-guard`, `/e2e-investigate` integration:

| Requirement | Implementation |
|-------------|----------------|
| Layout regions | `data-testid="main-sidebar"`, `data-testid="main-content"` |
| Theme toggle | `data-testid="theme-toggle"` |
| Theme state | `data-theme="light\|dark"` on root element |
| CSS variables | Queryable via `getComputedStyle(root).getPropertyValue('--color-accent')` |
| Buttons | `data-testid="{action}-btn"` |
| Inputs | `data-testid="{field}-input"` |

---

## Aesthetic Direction Specifications

### [A] Brutalist

```
Typography: Heavy sans-serif, uppercase headers, high contrast
Colors: Black, white, single accent (red/yellow), no gradients
Spacing: Tight, intentional crowding, bold borders
Borders: Thick (3-4px), sharp corners
Shadows: None or hard offset (no blur)
Animation: Abrupt, no easing
```

### [B] Neo-Minimal

```
Typography: Thin to regular weight, generous letter-spacing
Colors: Monochromatic with single subtle accent
Spacing: Excessive whitespace, breathing room
Borders: None or hairline (1px), subtle
Shadows: None or very subtle
Animation: Slow, subtle, ease-in-out
```

### [C] Maximalist/Editorial

```
Typography: Mixed weights, serifs for headlines, display fonts
Colors: Rich palette, bold combinations, can clash intentionally
Spacing: Varied, asymmetrical, layered elements
Borders: Varied weights, decorative
Shadows: Multiple layers, depth
Animation: Playful, varied timing
```

### [D] Dark Industrial

```
Typography: Monospace, technical, all-caps labels
Colors: Dark grays, muted accent (amber, cyan), minimal color
Spacing: Grid-strict, modular
Borders: Thin, precise, technical look
Shadows: Subtle glow effects
Animation: Precise, mechanical timing
```

### [E] Warm Organic

```
Typography: Rounded sans or soft serif, natural feel
Colors: Earth tones, greens, browns, cream backgrounds
Spacing: Comfortable, natural flow
Borders: Soft, rounded, or none
Shadows: Soft, natural lighting
Animation: Gentle, organic easing
```

### [F] Retro-Futurism

```
Typography: Geometric sans, rounded display fonts
Colors: Gradients, iridescent, teal/purple/pink
Spacing: Generous, rounded containers
Borders: Rounded corners (full radius), glowing
Shadows: Glows, neon effects
Animation: Bouncy, playful easing
```

### [G] Art Deco

```
Typography: Geometric, tall, elegant serifs
Colors: Gold/brass accents, deep blues/greens, cream
Spacing: Symmetrical, balanced, geometric
Borders: Geometric patterns, stepped
Shadows: Subtle, elegant
Animation: Smooth, luxurious timing
```

### [H] Soft Pastel

```
Typography: Rounded, friendly, medium weights
Colors: Soft pastels, light backgrounds, muted accents
Spacing: Generous, airy, light
Borders: Soft, rounded, subtle
Shadows: Soft, diffused
Animation: Gentle, slow, calming
```

---

## Handoff Format for /create-task

When user says "this one", produce:

```markdown
## Visual Design Spec (for /create-task)

### Styleguide
- **Location**: `webui/styleguide.css` (or `src/styles/design-tokens.css`)
- **Import**: `<link rel="stylesheet" href="styleguide.css">`

### Aesthetic Direction
{Selected aesthetic} - {1-line description}

### Layout Pattern
{Selected layout} - {1-line description}

### Design Tokens Applied
```css
--color-bg-primary: {value};
--color-accent: {value};
--font-heading: {value};
/* ... key tokens */
```

### Component Visual Requirements
- [ ] Buttons: {spec with data-testid pattern}
- [ ] Cards: {spec with data-testid pattern}
- [ ] Inputs: {spec with data-testid pattern}
- [ ] Navigation: {spec with data-testid pattern}

### Layout Regions (testable)
- `data-testid="main-header"` - {description}
- `data-testid="main-sidebar"` - {description}
- `data-testid="main-content"` - {description}

### Theme Support
- Light/dark toggle: `data-testid="theme-toggle"`
- Theme state: `data-theme` attribute on `<html>` or `<body>`
- Test: `document.documentElement.getAttribute('data-theme')`

### Accessibility Notes
- Contrast ratios verified for WCAG AA
- Focus states styled
- Reduced motion respected via `prefers-reduced-motion`

### Preview Reference
- Approved preview: `{path to approved preview}`
```

---

## Example Conversations

### Standalone Mode Example

```
User: /ui-planner design my dashboard

Skill: Let's establish your visual identity. I'll guide you through
aesthetic and layout selection, then generate live previews.

+-----------------------------------------------------------------------+
| STEP 1: Aesthetic Direction                                            |
+-----------------------------------------------------------------------+

[Shows ASCII gallery A-H]

Which aesthetic resonates with your project? (Enter letter)

User: D - I want that dark industrial look

Skill: Great choice - Dark Industrial gives a technical, precise feel.

+-----------------------------------------------------------------------+
| STEP 2: Layout Pattern                                                 |
+-----------------------------------------------------------------------+

[Shows ASCII gallery 1-8]

Which layout(s) fit your dashboard? (Enter numbers, comma-separated)

User: 2

Skill: Dashboard layout selected. Generating preview...

[Creates webui/previews/preview-industrial-dashboard.html]

Preview generated: `webui/previews/preview-industrial-dashboard.html`

Open in your browser to review. The preview includes:
- Light/dark theme toggle (top-right)
- Typography samples
- Color palette
- Component examples
- Dashboard layout with metrics and content area

What would you like to adjust?
- "make the accent more cyan"
- "try with sidebar layout too"
- "this one" (to apply to styleguide)

User: the accent color is too muted, make it more vibrant cyan

Skill: Adjusting accent to vibrant cyan...

[Updates preview with --color-accent: #00d4ff]

Preview updated. Refresh your browser to see changes.

User: this one

Skill: Applying industrial-dashboard design to styleguide...

[Creates/updates webui/styleguide.css]

## Visual Design Spec (for /create-task)

### Styleguide
- **Location**: `webui/styleguide.css`
- **Import**: `<link rel="stylesheet" href="styleguide.css">`

### Aesthetic Direction
Dark Industrial - Technical precision, monospace type, muted palette with cyan accent

### Layout Pattern
Dashboard - Metrics/widgets top, main content below

### Design Tokens Applied
--color-bg-primary: #0a0a0a;
--color-accent: #00d4ff;
--font-heading: 'JetBrains Mono', monospace;
...

Ready for /create-task or continue refining?
```

### Post-UX-Planner Example

```
User: [Coming from /ux-planner with user flow for image generation queue]

/ui-planner apply visual design to this flow

Skill: I see you have a queue management flow from /ux-planner:
- Queue list view
- Progress indicators
- Action buttons (generate, cancel, reorder)

Let's add the visual layer.

+-----------------------------------------------------------------------+
| STEP 1: Aesthetic Direction                                            |
+-----------------------------------------------------------------------+

Given your queue management context, I'd suggest:
- [B] Neo-Minimal for clean, focused interface
- [D] Dark Industrial for technical, tool-like feel
- [H] Soft Pastel for friendly, approachable feel

[Shows full gallery]

Which direction? (Enter letter)

User: B

Skill: Neo-Minimal - clean and focused.

+-----------------------------------------------------------------------+
| STEP 2: Layout Pattern                                                 |
+-----------------------------------------------------------------------+

For queue management, relevant layouts:
- [1] Sidebar - navigation + queue list
- [6] List View - focused queue management
- [7] Kanban - if you want lane-based status

[Shows full gallery]

Which layout(s)? (Enter numbers)

User: 6

Skill: List View layout with Neo-Minimal aesthetic.

Generating preview that shows:
- Queue items as list entries
- Progress indicators per item
- Action buttons matching your UX flow
- Minimal visual noise

[Creates preview]

...
```

---

## Limitations

- **Modifies files** - Creates preview HTML files and styleguide CSS
- **Pipeline position** - Follows `/ux-planner`; precedes `/ui-review` and `/create-task`
- **Prerequisites** - Works best after `/ux-planner` defines interaction flows
- **Not suitable for** - CLI-only tools; API-only projects; non-visual features

## When NOT to Use

Skip `/ui-planner` when:
- **Backend-only feature** - No UI components affected (use `/create-task` directly)
- **Quick bug fix** - Visual design already established
- **API endpoint changes** - No user-facing visual impact
- **Styleguide already exists** - Minor updates don't need full planning
- **Prototype/throwaway code** - Speed over polish is acceptable

## See Also

- `/ux-planner` - Interaction flows and UX planning (run before this)
- `/ui-review` - AI slop detection and design quality guard (run after this)
- `/create-task` - Implementation with design tokens applied
- `references/ui-patterns.md` - Design token hierarchy, typography, color theory

## UX Patterns Reference

For detailed visual patterns, typography scales, and accessibility guidelines, see:
`references/ui-patterns.md`

Key resources:
- Design token hierarchy (primitive → semantic → component)
- Typography scales and font pairing
- Color theory and palette generation
- Layout pattern templates (ASCII)
- Animation timing functions
- Anti-patterns (AI slop indicators)
- Discoverability patterns for E2E testing
