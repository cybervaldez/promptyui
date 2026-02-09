# Slop Research Reference

A comprehensive reference for detecting AI slop patterns, performing lazy research, and building context-specific checklists.

---

## Styleguide Detection & Parsing

### File Patterns to Search

Search for styleguide files in order of specificity:

| Pattern | Location | Priority |
|---------|----------|----------|
| `styleguide.css` | Project root, webui/, src/styles/ | 1 |
| `design-tokens.css` | src/styles/, styles/ | 2 |
| `theme.css` | Project root, src/ | 3 |
| `variables.css` | src/styles/, css/ | 4 |
| `tailwind.config.js` | Project root | 5 (Tailwind) |
| `tailwind.config.ts` | Project root | 5 (Tailwind) |
| `theme.ts`, `theme.js` | src/, src/styles/ | 6 (CSS-in-JS) |
| `tokens.json` | src/design/, design/ | 7 (Design tokens) |

### Extracting CSS Custom Properties

Parse CSS files for custom property definitions:

```css
/* Look for patterns like: */
:root {
  --color-accent: #00d4ff;
  --font-heading: 'JetBrains Mono', monospace;
  --radius-md: 0.5rem;
}

/* And dark theme overrides: */
[data-theme="dark"] {
  --color-bg-primary: #0a0a0a;
}
```

### Extraction Regex Patterns

```
Color tokens:    --color-[a-z-]+:\s*([^;]+);
Font tokens:     --font-[a-z-]+:\s*([^;]+);
Text tokens:     --text-[a-z0-9-]+:\s*([^;]+);
Space tokens:    --space-[a-z0-9-]+:\s*([^;]+);
Radius tokens:   --radius-[a-z-]+:\s*([^;]+);
Shadow tokens:   --shadow-[a-z-]+:\s*([^;]+);
Transition:      --transition-[a-z-]+:\s*([^;]+);
```

### Parsing Tailwind Config

For Tailwind projects, extract design tokens from config:

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        accent: '#00d4ff',        // → --tw-color-accent
        background: {
          primary: '#0a0a0a',     // → --tw-bg-primary
        }
      },
      fontFamily: {
        heading: ['JetBrains Mono', 'monospace'],
      },
      borderRadius: {
        'card': '0.5rem',
      }
    }
  }
}
```

### Token Category Mapping

Map extracted tokens to audit categories:

| Token Pattern | Audit Category |
|---------------|----------------|
| `--color-*`, `--bg-*` | Color |
| `--font-*`, `--text-*`, `--leading-*` | Typography |
| `--space-*`, `--gap-*`, `--padding-*` | Layout (spacing) |
| `--radius-*`, `--rounded-*` | Components (radius) |
| `--shadow-*` | Components (elevation) |
| `--transition-*`, `--ease-*`, `--duration-*` | Motion |

---

## Styleguide Compliance Checking

### How to Compare Preview Against Styleguide

1. **Extract all CSS from preview** (inline styles and `<style>` blocks)
2. **Find hardcoded values** that should use tokens
3. **Map hardcoded values to token equivalents**
4. **Flag mismatches** as compliance issues

### Hardcoded Value Detection

Look for patterns that bypass design tokens:

```css
/* HARDCODED (flag these) */
background: #3b82f6;           /* Should use var(--color-*) */
font-family: 'Inter';          /* Should use var(--font-*) */
border-radius: 1rem;           /* Should use var(--radius-*) */
padding: 16px;                 /* Should use var(--space-*) */
box-shadow: 0 4px 6px rgba(); /* Should use var(--shadow-*) */

/* COMPLIANT (don't flag) */
background: var(--color-accent);
font-family: var(--font-heading);
border-radius: var(--radius-md);
padding: var(--space-4);
```

### Common Deviation Patterns

| Deviation | Why It's a Problem | Detection Pattern |
|-----------|-------------------|-------------------|
| Hardcoded hex color | Theme changes won't apply | `#[0-9a-fA-F]{3,8}` not in token def |
| Hardcoded px/rem | Spacing scale bypassed | `\d+px` or `\d+rem` not in token |
| Inline font-family | Typography system bypassed | `font-family:` without `var(--` |
| Magic number radius | Border radius inconsistent | `border-radius:` without `var(--` |

### Compliance Report Format

```markdown
### Styleguide Compliance Check
| Element | Expected (from styleguide) | Actual | Status |
|---------|---------------------------|--------|--------|
| Button bg | `--color-accent` (#00d4ff) | #3b82f6 | MISMATCH |
| Card radius | `--radius-md` (0.5rem) | var(--radius-md) | MATCH |
| Body font | `--font-body` (Inter) | Arial | MISMATCH |
```

---

## How to Research Slop Patterns

### When to Research

Research is triggered when:
1. `/ui-review` is invoked
2. Aesthetic and layout context is extracted
3. Need current slop patterns for that context

### Research Strategy

1. **Search for aesthetic-specific slop** - What's generic for this style?
2. **Search for layout-specific anti-patterns** - What mistakes are common?
3. **Search for distinctive examples** - What does good look like?

### Search Query Templates

#### Aesthetic-Based Queries

```
"{aesthetic} AI slop design {year}"
Examples:
- "minimal AI slop design 2026"
- "brutalist AI slop design 2026"
- "industrial AI slop design 2026"

"{aesthetic} design anti-patterns"
Examples:
- "minimal design anti-patterns"
- "dark mode design anti-patterns"

"distinctive {aesthetic} {element} examples"
Examples:
- "distinctive minimal typography examples"
- "distinctive industrial color palette examples"
```

#### Layout-Based Queries

```
"generic AI {layout} patterns avoid"
Examples:
- "generic AI dashboard patterns avoid"
- "generic AI landing page patterns avoid"

"{layout} UI best practices {year}"
Examples:
- "dashboard UI best practices 2026"
- "card grid layout best practices"
```

#### Combined Context Queries

```
"{aesthetic} {layout} design inspiration"
Examples:
- "industrial dashboard design inspiration"
- "minimal sidebar layout examples"

"avoid generic {aesthetic} {layout}"
Examples:
- "avoid generic minimal dashboard"
```

### Processing Search Results

From each search result, extract:
1. **Specific patterns to avoid** (slop indicators)
2. **Why they're problematic** (reasoning)
3. **What to do instead** (alternatives)
4. **Context exceptions** (when it's actually fine)

---

## Aesthetic-Specific Slop Indicators

Baseline knowledge for common aesthetics. Web search updates these.

### Neo-Minimal

| Slop Pattern | Why It's Slop | Instead |
|--------------|---------------|---------|
| Blue accent | Default, not chosen | Muted or unexpected accent |
| Tight line-height | Compromises breathing room | 1.6-1.8 line height |
| Rounded-full buttons | Too soft for minimal | Subtle radius or none |
| Purple gradients | Contradicts minimal palette | Single accent or none |
| Busy hover effects | Contradicts calm aesthetic | Subtle opacity change |

### Brutalist

| Slop Pattern | Why It's Slop | Instead |
|--------------|---------------|---------|
| Rounded corners | Contradicts raw aesthetic | Sharp corners always |
| Soft shadows | Too gentle | Hard offset shadows or none |
| Gradient backgrounds | Too polished | Solid colors, high contrast |
| Smooth animations | Too refined | Abrupt transitions |
| Pastel colors | Too soft | Black, white, bold accent |

### Dark Industrial

| Slop Pattern | Why It's Slop | Instead |
|--------------|---------------|---------|
| Pure black (#000) | Harsh, not industrial | Off-black (#0a0a0a, #111) |
| Rainbow accent colors | Too playful | Muted cyan, amber, or single color |
| Large radius | Too friendly | Small radius or none |
| Script fonts | Contradicts technical | Monospace or geometric sans |
| Excessive glow | Over-designed | Subtle, purposeful glow |

### Maximalist/Editorial

| Slop Pattern | Why It's Slop | Instead |
|--------------|---------------|---------|
| Single font | Lacks richness | Mix serif headings, sans body |
| Minimal color palette | Contradicts maximalism | Rich, bold palette |
| Uniform spacing | Lacks visual interest | Varied, intentional spacing |
| Generic stock images | Forgettable | Bold, unique imagery |
| Simple grid | Too orderly | Overlapping, asymmetric |

### Warm Organic

| Slop Pattern | Why It's Slop | Instead |
|--------------|---------------|---------|
| Sharp corners | Too clinical | Rounded, soft edges |
| Pure white background | Too sterile | Warm off-white, cream |
| Neon colors | Too artificial | Earth tones, natural palette |
| Geometric shapes | Too rigid | Organic, natural shapes |
| Fast animations | Too mechanical | Gentle, organic timing |

### Retro-Futurism

| Slop Pattern | Why It's Slop | Instead |
|--------------|---------------|---------|
| Flat colors | Too modern | Gradients, iridescence |
| Sharp corners | Too contemporary | Rounded, pill shapes |
| Minimal palette | Lacks energy | Teal/purple/pink gradients |
| Static design | Missing playfulness | Bouncy animations, glows |
| System fonts | Too generic | Geometric, display fonts |

---

## Building Context-Specific Checklists

### Process

1. **Start with aesthetic baseline** (from above)
2. **Layer in layout-specific patterns** (dashboard vs landing page)
3. **Update with web research** (current trends)
4. **Mark intentional patterns** (don't flag these)

### Checklist Format

```markdown
### Context-Specific Checklist Built
For {aesthetic} aesthetic with {layout} layout, flagging:
- [x] {pattern} - {why it's slop in this context}
- [x] {pattern} - {why it's slop in this context}
- [ ] {pattern} - intentional for this aesthetic (SKIP)
- [x] {pattern} - research finding: {source}
```

### Example: Industrial + Dashboard

```markdown
### Context-Specific Checklist Built
For Dark Industrial aesthetic with Dashboard layout, flagging:

**From Aesthetic (Industrial):**
- [x] Rounded corners > 0.25rem - contradicts technical precision
- [x] Colorful gradients - too playful for industrial
- [ ] Monospace font - intentional for industrial (SKIP)
- [x] Soft shadows - should be sharp or minimal

**From Layout (Dashboard):**
- [x] All metric cards same size - no visual hierarchy
- [x] Generic chart colors - should match accent palette
- [x] No hover states on cards - feels static

**From Research:**
- [x] Excessive glow on metrics - overused in 2025-2026 dashboards
- [x] Rainbow sparklines - contradicts industrial restraint
```

---

## Example Research Session

### Scenario: Reviewing Industrial Dashboard

**Step 1: Extract Context**
```
Aesthetic: Dark Industrial
Layout: Dashboard
Styleguide: webui/styleguide.css (24 tokens)
Key tokens: --color-accent: #00d4ff, --font-heading: JetBrains Mono
```

**Step 2: Check Styleguide Compliance**
```
Scanning preview for hardcoded values...

FOUND:
- Line 45: background: #1a1a1a; → Should use var(--color-bg-secondary)
- Line 78: border-radius: 1rem; → Should use var(--radius-md)
- Line 112: font-family: Inter; → Should use var(--font-body)

Compliance issues: 3 deviations
```

**Step 3: Perform Web Research**
```
Search: "industrial dashboard AI slop 2026"
→ Finding: Avoid "neon grid" aesthetic, overused since 2025

Search: "dark dashboard anti-patterns"
→ Finding: Same-size metric cards create visual monotony

Search: "distinctive industrial UI examples"
→ Finding: Use varied metric sizing, subtle borders, precision animations
```

**Step 4: Build Context Checklist**
```
For Dark Industrial + Dashboard:
- [x] Styleguide deviations (3 found) - BLOCKING
- [x] Rounded corners > 0.5rem - too soft
- [x] Same-size metrics - no hierarchy
- [x] Neon grid aesthetic - overused
- [ ] Monospace typography - intentional
- [ ] Muted cyan accent - distinctive choice
```

**Step 5: Apply to Audit**
```
| Category | Score | Issue |
|----------|-------|-------|
| Color | 0 | Hardcoded #1a1a1a (styleguide deviation) |
| Components | 0 | 1rem radius (should be sharper) |
| Typography | 0 | Using Inter instead of JetBrains Mono |
| Layout | 1 | Same-size metrics |
```

---

## Anti-Slop CSS Patterns

Code snippets for common fixes.

### Using Design Tokens Correctly

```css
/* BAD: Hardcoded values */
.button {
  background: #3b82f6;
  border-radius: 9999px;
  padding: 8px 16px;
  font-family: 'Inter', sans-serif;
}

/* GOOD: Using tokens */
.button {
  background: var(--color-accent);
  border-radius: var(--radius-md);
  padding: var(--space-2) var(--space-4);
  font-family: var(--font-body);
}
```

### Creating Visual Hierarchy

```css
/* BAD: All same */
.metric-card {
  padding: var(--space-4);
  font-size: var(--text-base);
}

/* GOOD: Intentional hierarchy */
.metric-card--featured {
  padding: var(--space-6);
  font-size: var(--text-xl);
}
.metric-card--standard {
  padding: var(--space-4);
  font-size: var(--text-base);
}
.metric-card--compact {
  padding: var(--space-3);
  font-size: var(--text-sm);
}
```

### Proper Dark Mode

```css
/* BAD: Simple inversion */
[data-theme="dark"] {
  --color-bg-primary: #000000; /* Too harsh */
  --color-text-primary: #ffffff; /* Too bright */
}

/* GOOD: Thoughtful dark mode */
[data-theme="dark"] {
  --color-bg-primary: #0a0a0a; /* Off-black */
  --color-bg-secondary: #1a1a1a; /* Elevated surface */
  --color-text-primary: #e5e5e5; /* Off-white, less glare */
  --color-text-secondary: #a1a1a1; /* Muted for secondary */
  --color-accent: #00d4ff; /* May need adjustment for dark bg */
}
```

### Intentional Hover States

```css
/* BAD: No hover */
.card {
  background: var(--color-bg-secondary);
}

/* ALSO BAD: Generic hover */
.card:hover {
  transform: scale(1.05);
  box-shadow: 0 10px 40px rgba(0,0,0,0.3);
}

/* GOOD: Aesthetic-appropriate hover */
/* For Industrial: */
.card:hover {
  border-color: var(--color-accent);
  transition: border-color var(--transition-fast);
}

/* For Minimal: */
.card:hover {
  opacity: 0.9;
  transition: opacity var(--transition-base);
}
```

### Typography Hierarchy

```css
/* BAD: Same weight everywhere */
h1, h2, h3, p { font-weight: 400; }

/* GOOD: Clear hierarchy */
h1 {
  font-family: var(--font-heading);
  font-weight: 700;
  font-size: var(--text-3xl);
  line-height: var(--leading-tight);
}
h2 {
  font-family: var(--font-heading);
  font-weight: 600;
  font-size: var(--text-2xl);
}
p {
  font-family: var(--font-body);
  font-weight: 400;
  font-size: var(--text-base);
  line-height: var(--leading-normal);
}
```

---

## When NOT to Flag as Slop

### Intentional Aesthetic Choices

| Choice | Slop in... | Intentional in... |
|--------|------------|-------------------|
| No border radius | Minimal, Warm Organic | Brutalist, Industrial |
| Single font | Maximalist | Minimal, Brutalist |
| Heavy shadows | Minimal, Industrial | Maximalist, Art Deco |
| Gradient backgrounds | Brutalist, Minimal | Retro-Futurism, Maximalist |
| Monospace everywhere | Editorial, Warm | Industrial, Technical |
| High contrast | Warm Organic | Brutalist |
| Excessive whitespace | Maximalist | Minimal |

### User Overrides

Don't flag if user explicitly stated:
- "I want blue accent" → Don't flag blue as slop
- "Keep it simple with Inter" → Don't flag Inter as generic
- "I like the rounded buttons" → Don't flag rounded-full

### Brand Constraints

If design tokens were intentionally chosen:
- Colors from brand guidelines → Match tokens, don't question
- Typography from brand system → Match tokens, don't question
- Spacing from existing design system → Match tokens, don't question

### Technical Constraints

- Component library defaults that can't change → Note but don't block
- Accessibility requirements → Never flag contrast/size fixes as slop
- Performance constraints → Don't flag missing animations

---

## See Also

- Parent: `SKILL.md` - Main ui-review skill documentation
- `/ui-planner` - Generates the previews this skill reviews
- `ui-patterns.md` (in ui-planner) - Design token reference
- `TECH_CONTEXT.md` - Tech-specific patterns
