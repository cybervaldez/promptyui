# UI Patterns Reference

A comprehensive reference for visual design patterns, design tokens, typography, color theory, and testability patterns.

---

## Design Token Systems

### Token Hierarchy

Design tokens flow from primitive to semantic to component:

```
+------------------------------------------------------------------+
| Token Hierarchy                                                   |
+------------------------------------------------------------------+
|                                                                   |
|  PRIMITIVE (raw values)                                           |
|  --blue-500: #3b82f6;                                             |
|  --gray-900: #111827;                                             |
|  --space-4: 1rem;                                                 |
|           |                                                       |
|           v                                                       |
|  SEMANTIC (meaning)                                               |
|  --color-accent: var(--blue-500);                                 |
|  --color-text-primary: var(--gray-900);                           |
|  --spacing-base: var(--space-4);                                  |
|           |                                                       |
|           v                                                       |
|  COMPONENT (usage)                                                |
|  --btn-bg: var(--color-accent);                                   |
|  --card-padding: var(--spacing-base);                             |
|                                                                   |
+------------------------------------------------------------------+
```

### Standard Token Categories

```css
/* Color Primitives */
--white: #ffffff;
--black: #000000;
--gray-{50-950}: /* 10 shades */
--{color}-{50-950}: /* per brand color */

/* Semantic Colors */
--color-bg-primary: /* main background */
--color-bg-secondary: /* elevated surfaces */
--color-bg-tertiary: /* subtle backgrounds */
--color-text-primary: /* headings, important text */
--color-text-secondary: /* body text */
--color-text-muted: /* captions, hints */
--color-accent: /* interactive elements */
--color-accent-hover: /* hover state */
--color-success: /* positive feedback */
--color-warning: /* caution */
--color-error: /* negative feedback */
--color-border: /* default borders */

/* Typography */
--font-heading: /* heading typeface */
--font-body: /* body typeface */
--font-mono: /* code typeface */
--text-{xs,sm,base,lg,xl,2xl,3xl,4xl}: /* size scale */
--leading-{tight,normal,relaxed}: /* line height */
--tracking-{tight,normal,wide}: /* letter spacing */
--font-weight-{normal,medium,semibold,bold}: /* weights */

/* Spacing */
--space-{1,2,3,4,5,6,8,10,12,16,20,24}: /* scale */

/* Border Radius */
--radius-{none,sm,md,lg,xl,full}: /* scale */

/* Shadows */
--shadow-{sm,md,lg,xl}: /* elevation scale */

/* Transitions */
--transition-{fast,base,slow}: /* timing */
--ease-{in,out,in-out}: /* easing functions */
```

---

## Typography Scales

### Modular Scale Ratios

| Name | Ratio | Use Case |
|------|-------|----------|
| Minor Second | 1.067 | Subtle variation, dense UIs |
| Major Second | 1.125 | Slight variation, compact |
| Minor Third | 1.200 | Balanced, readable |
| Major Third | 1.250 | Classic, comfortable |
| Perfect Fourth | 1.333 | Traditional, spacious |
| Augmented Fourth | 1.414 | Dramatic, editorial |
| Perfect Fifth | 1.500 | Very dramatic, marketing |

### Recommended Scale (Major Third 1.250)

```css
--text-xs: 0.64rem;    /* 10.24px */
--text-sm: 0.8rem;     /* 12.8px */
--text-base: 1rem;     /* 16px - body */
--text-lg: 1.25rem;    /* 20px */
--text-xl: 1.563rem;   /* 25px */
--text-2xl: 1.953rem;  /* 31.25px */
--text-3xl: 2.441rem;  /* 39px */
--text-4xl: 3.052rem;  /* 48.83px */
```

### Font Pairing Guidelines

| Heading | Body | Vibe |
|---------|------|------|
| Inter | Inter | Clean, modern, safe |
| Playfair Display | Source Sans Pro | Editorial, elegant |
| Space Grotesk | Inter | Technical, futuristic |
| Fraunces | Work Sans | Friendly, approachable |
| JetBrains Mono | JetBrains Mono | Developer, technical |
| Outfit | Outfit | Geometric, modern |

### Line Height Guidelines

| Text Type | Line Height | CSS |
|-----------|-------------|-----|
| Headings | 1.1 - 1.2 | `--leading-tight` |
| Body text | 1.5 - 1.6 | `--leading-normal` |
| Small text | 1.6 - 1.75 | `--leading-relaxed` |

---

## Color Theory & Palette Generation

### Color Schemes

```
+------------------------------------------------------------------+
| Color Scheme Types                                                |
+------------------------------------------------------------------+
|                                                                   |
| MONOCHROMATIC        COMPLEMENTARY        ANALOGOUS               |
| (one hue, vary       (opposite hues)      (adjacent hues)         |
|  lightness/sat)                                                   |
|                                                                   |
|      o                   o                  o o                   |
|     /|\                 / \                  \|                   |
|    o   o               o   o                  o                   |
|                                                                   |
| TRIADIC              SPLIT-COMPLEMENT    TETRADIC                 |
| (3 equidistant)      (1 + 2 adjacent     (4 forming               |
|                       to complement)      rectangle)              |
|                                                                   |
|    o                     o                 o   o                  |
|   / \                   /|\               /     \                 |
|  o   o                 o   o             o       o                |
|                                                                   |
+------------------------------------------------------------------+
```

### 60-30-10 Rule

```
60% - Dominant (backgrounds, large areas)
30% - Secondary (cards, containers, navigation)
10% - Accent (CTAs, links, highlights)
```

### Semantic Color Mapping

| Semantic | Typical Hue | Usage |
|----------|-------------|-------|
| Success | Green (120-150) | Confirmations, completed |
| Warning | Yellow/Orange (30-50) | Caution, attention |
| Error | Red (0-10) | Failures, destructive |
| Info | Blue (200-220) | Neutral information |

### Dark Theme Considerations

```css
/* DON'T just invert colors */

/* Light theme */
--color-bg-primary: #ffffff;
--color-text-primary: #1a1a1a;

/* BAD dark theme - pure inversion */
--color-bg-primary: #000000; /* Too harsh */
--color-text-primary: #ffffff; /* Too bright */

/* GOOD dark theme - adjusted values */
--color-bg-primary: #0a0a0a; /* Off-black, easier on eyes */
--color-text-primary: #e5e5e5; /* Off-white, less glare */
```

---

## Layout Patterns (ASCII Templates)

### Sidebar Layout

```
+------------------------------------------------------------------+
|  HEADER                                                [user] [?] |
+--------+---------------------------------------------------------+
|        |                                                          |
| NAV    |  MAIN CONTENT                                            |
| ====   |                                                          |
| Item1  |  +---------------------------------------------+         |
| Item2  |  |                                             |         |
| Item3  |  |  Content Area                               |         |
|        |  |                                             |         |
| ----   |  +---------------------------------------------+         |
| Settings|                                                         |
|        |  +---------------------------------------------+         |
+--------+---------------------------------------------------------+

data-testid mapping:
- main-header
- main-sidebar, nav-item-{name}
- main-content
```

### Dashboard Layout

```
+------------------------------------------------------------------+
|  HEADER                                        [search] [user]    |
+------------------------------------------------------------------+
|  +-------------+  +-------------+  +-------------+  +-------------+
|  | METRIC 1    |  | METRIC 2    |  | METRIC 3    |  | METRIC 4    |
|  | 1,234       |  | 56.7%       |  | $12.3k      |  | 89          |
|  +-------------+  +-------------+  +-------------+  +-------------+
|                                                                   |
|  +------------------------------------------+  +-----------------+
|  |                                          |  |                 |
|  |  MAIN CHART/CONTENT                      |  |  SIDEBAR        |
|  |                                          |  |  WIDGET         |
|  |                                          |  |                 |
|  +------------------------------------------+  +-----------------+
|                                                                   |
|  +------------------------------------------------------------------+
|  |  TABLE / LIST                                                    |
|  +------------------------------------------------------------------+

data-testid mapping:
- main-header
- metric-{name}, metric-{name}-value
- main-chart, sidebar-widget
- data-table
```

### Card Grid Layout

```
+------------------------------------------------------------------+
|  HEADER                              [filter] [sort] [view]       |
+------------------------------------------------------------------+
|                                                                   |
|  +-------------+  +-------------+  +-------------+                 |
|  | CARD        |  | CARD        |  | CARD        |                 |
|  | [image]     |  | [image]     |  | [image]     |                 |
|  | Title       |  | Title       |  | Title       |                 |
|  | Desc...     |  | Desc...     |  | Desc...     |                 |
|  | [Action]    |  | [Action]    |  | [Action]    |                 |
|  +-------------+  +-------------+  +-------------+                 |
|                                                                   |
|  +-------------+  +-------------+  +-------------+                 |
|  | CARD        |  | CARD        |  | CARD        |                 |
|  | ...         |  | ...         |  | ...         |                 |
|  +-------------+  +-------------+  +-------------+                 |
|                                                                   |
|  [Load More]                                                      |
+------------------------------------------------------------------+

data-testid mapping:
- main-header
- filter-{name}, sort-{field}, view-toggle
- card-grid, card-item-{id}, card-{id}-action
- load-more-btn
```

### Hero + Content Layout

```
+------------------------------------------------------------------+
|  NAV                                          [link] [link] [CTA] |
+------------------------------------------------------------------+
|                                                                   |
|  ================================================================ |
|                                                                   |
|                    HERO HEADLINE                                  |
|                    Subheading text here                           |
|                                                                   |
|                 [Primary CTA]  [Secondary]                        |
|                                                                   |
|  ================================================================ |
|                                                                   |
|  +------------------+  +------------------+  +------------------+  |
|  | FEATURE 1        |  | FEATURE 2        |  | FEATURE 3        |  |
|  | Icon + text      |  | Icon + text      |  | Icon + text      |  |
|  +------------------+  +------------------+  +------------------+  |
|                                                                   |
+------------------------------------------------------------------+

data-testid mapping:
- main-nav
- hero-section, hero-headline, hero-cta-primary, hero-cta-secondary
- feature-{name}
```

### Split Panel Layout

```
+------------------------------------------------------------------+
|  HEADER                                                           |
+--------------------------------+---------------------------------+
|                                |                                  |
|  LEFT PANEL (MASTER)           |  RIGHT PANEL (DETAIL)            |
|                                |                                  |
|  +---------------------------+ |  +----------------------------+  |
|  | List Item 1        [>]   | |  |  Detail View               |  |
|  +---------------------------+ |  |                            |  |
|  | List Item 2              | |  |  Title                     |  |
|  +---------------------------+ |  |  Description text...       |  |
|  | List Item 3              | |  |                            |  |
|  +---------------------------+ |  |  [Edit] [Delete]           |  |
|  | List Item 4              | |  |                            |  |
|  +---------------------------+ |  +----------------------------+  |
|                                |                                  |
+--------------------------------+---------------------------------+

data-testid mapping:
- main-header
- panel-left, panel-right
- list-item-{id}, detail-view
- detail-edit-btn, detail-delete-btn
```

### List View Layout

```
+------------------------------------------------------------------+
|  HEADER                                     [+ New] [Filter] [Sort]|
+------------------------------------------------------------------+
|                                                                   |
|  +--------------------------------------------------------------+|
|  | [x] | Item Title          | Status    | Date     | Actions   ||
|  +--------------------------------------------------------------+|
|  | [ ] | First item name     | Active    | Jan 15   | [...] [x] ||
|  +--------------------------------------------------------------+|
|  | [ ] | Second item name    | Pending   | Jan 14   | [...] [x] ||
|  +--------------------------------------------------------------+|
|  | [x] | Third item name     | Complete  | Jan 13   | [...] [x] ||
|  +--------------------------------------------------------------+|
|  | [ ] | Fourth item name    | Active    | Jan 12   | [...] [x] ||
|  +--------------------------------------------------------------+|
|                                                                   |
|  Showing 1-4 of 24                          [<] [1] [2] [3] [>]  |
+------------------------------------------------------------------+

data-testid mapping:
- main-header, create-btn, filter-btn, sort-btn
- list-table, list-row-{id}
- row-{id}-checkbox, row-{id}-actions, row-{id}-delete
- pagination, page-{n}
```

---

## Animation Timing & Easing

### Duration Guidelines

| Duration | Use Case |
|----------|----------|
| 100-150ms | Micro-interactions (hover, toggle) |
| 200-250ms | Small transitions (accordion, tabs) |
| 300-400ms | Medium transitions (modal, drawer) |
| 500-700ms | Large transitions (page, route) |

### Easing Functions

```css
/* Standard easing */
--ease-linear: linear;
--ease-in: cubic-bezier(0.4, 0, 1, 1);
--ease-out: cubic-bezier(0, 0, 0.2, 1);
--ease-in-out: cubic-bezier(0.4, 0, 0.2, 1);

/* Expressive easing */
--ease-bounce: cubic-bezier(0.68, -0.55, 0.265, 1.55);
--ease-smooth: cubic-bezier(0.25, 0.1, 0.25, 1);
--ease-sharp: cubic-bezier(0.4, 0, 0.6, 1);
```

### Easing Selection

| Animation Type | Easing |
|----------------|--------|
| Enter | ease-out (fast start, slow end) |
| Exit | ease-in (slow start, fast end) |
| State change | ease-in-out |
| Emphasis | ease-bounce |
| Loading | linear |

### Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## Anti-Patterns (AI Slop Indicators)

### Generic AI Aesthetics to Avoid

| Anti-Pattern | Why It's Slop | Better Approach |
|--------------|---------------|-----------------|
| Purple-to-pink gradient | Overused in AI-generated UIs | Choose palette with intention |
| Random floating 3D shapes | Decoration without purpose | Meaningful visual elements |
| "Futuristic" glassmorphism everywhere | Trend over function | Use glass effects sparingly |
| Gradient text on everything | Readability issues | Reserve for hero headlines |
| Every button is rounded-full | Lacks hierarchy | Vary radius by importance |
| Excessive shadows on flat elements | Visual noise | Subtle, consistent shadows |
| Blue accent for everything | Default, not chosen | Select accent with meaning |
| Generic stock-style illustrations | Forgettable, impersonal | Custom or intentional style |

### Signs of Unintentional Design

- All spacing is identical
- Colors don't relate to each other
- Typography lacks hierarchy
- Interactive elements look the same
- No visual rhythm or pattern
- Dark mode is just inverted light mode

### How to Avoid Slop

1. **Make explicit choices** - Don't accept defaults
2. **Justify decisions** - "Why this color?" should have an answer
3. **Reference moodboard** - Collect intentional inspiration
4. **Test against brand** - Does it feel like YOUR product?
5. **Less is more** - Remove decoration that doesn't serve purpose

---

## Accessibility for Visual Design

### Contrast Requirements

| Content Type | Min Ratio (AA) | Enhanced (AAA) |
|--------------|----------------|----------------|
| Normal text | 4.5:1 | 7:1 |
| Large text (18px+) | 3:1 | 4.5:1 |
| UI components | 3:1 | 3:1 |
| Non-text contrast | 3:1 | 3:1 |

### Focus States

```css
/* Visible focus indicator */
:focus-visible {
  outline: 2px solid var(--color-accent);
  outline-offset: 2px;
}

/* Remove outline only when not keyboard-focused */
:focus:not(:focus-visible) {
  outline: none;
}
```

### Color Independence

```
DON'T rely on color alone:

BAD:  "Fields in red have errors"
GOOD: "Fields marked with ! have errors" + red color + icon

BAD:  Status shown only as colored dot
GOOD: Colored dot + text label + icon
```

### Motion Sensitivity

- Provide `prefers-reduced-motion` support
- Avoid auto-playing animations
- Keep animations under 5 seconds
- No flashing content (>3 per second)

---

## Discoverability Patterns for E2E Testing

### Standard data-testid Naming

| Element Type | Pattern | Example |
|--------------|---------|---------|
| Layout region | `main-{region}` | `main-sidebar`, `main-content` |
| Navigation | `nav-{name}` | `nav-primary`, `nav-item-home` |
| Button (action) | `{action}-btn` | `submit-btn`, `cancel-btn` |
| Button (entity) | `{entity}-{action}-btn` | `user-delete-btn` |
| Input | `{field}-input` | `email-input`, `search-input` |
| Form | `{name}-form` | `login-form` |
| Card/Item | `{type}-item-{id}` | `task-item-123` |
| Modal | `{name}-modal` | `confirm-modal` |
| Toggle | `{name}-toggle` | `theme-toggle` |
| Status | `{name}-status` | `connection-status` |

### Theme State Exposure

```html
<!-- Root element exposes theme state -->
<html data-theme="light">
  <!-- or -->
<body data-theme="dark">
```

```javascript
// Queryable via E2E
document.documentElement.getAttribute('data-theme')
// Returns: "light" | "dark"
```

### CSS Variable Verification

```javascript
// E2E can verify design tokens are applied
const root = document.documentElement;
const styles = getComputedStyle(root);

// Check specific tokens
styles.getPropertyValue('--color-accent'); // "#3b82f6"
styles.getPropertyValue('--font-heading'); // "'Inter', sans-serif"
```

### Snapshot-Friendly Structure

```html
<!-- Good: Semantic, testable -->
<div data-testid="card-item-123" data-status="active">
  <h3 data-testid="card-123-title">Card Title</h3>
  <p data-testid="card-123-description">Description text</p>
  <button data-testid="card-123-action">View</button>
</div>

<!-- Bad: No testability -->
<div class="card active">
  <h3>Card Title</h3>
  <p>Description text</p>
  <button>View</button>
</div>
```

### State Attributes

```html
<!-- Expose state in DOM for easy verification -->
<button
  data-testid="submit-btn"
  data-loading="true"
  disabled
>
  Submitting...
</button>

<div
  data-testid="form-section"
  data-expanded="false"
>
  ...
</div>
```

---

## Preview Template Code

Base HTML template for generating previews:

```html
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Preview - {aesthetic} + {layout}</title>
  <style>
    /* CSS Custom Properties */
    :root {
      /* Primitives */
      --white: #ffffff;
      --black: #000000;
      /* ... */

      /* Semantic - Light */
      --color-bg-primary: /* value */;
      --color-bg-secondary: /* value */;
      --color-text-primary: /* value */;
      --color-text-secondary: /* value */;
      --color-accent: /* value */;
      /* ... */

      /* Typography */
      --font-heading: /* value */;
      --font-body: /* value */;
      /* ... */
    }

    [data-theme="dark"] {
      --color-bg-primary: /* dark value */;
      /* ... overrides */
    }

    /* Base styles */
    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: var(--font-body);
      background: var(--color-bg-primary);
      color: var(--color-text-primary);
      line-height: 1.5;
    }

    /* Theme toggle */
    .theme-toggle {
      position: fixed;
      top: 1rem;
      right: 1rem;
      z-index: 100;
    }

    /* Typography showcase */
    /* Color palette display */
    /* Component samples */
    /* Layout grid */
  </style>
</head>
<body>
  <!-- Theme Toggle -->
  <button
    data-testid="theme-toggle"
    class="theme-toggle"
    onclick="toggleTheme()"
  >
    Toggle Theme
  </button>

  <!-- Preview Content -->
  <main data-testid="main-content">
    <!-- Typography Section -->
    <section data-testid="typography-section">
      <h1>Heading 1</h1>
      <h2>Heading 2</h2>
      <h3>Heading 3</h3>
      <p>Body text paragraph...</p>
      <small>Small text</small>
      <code>Code sample</code>
    </section>

    <!-- Color Palette Section -->
    <section data-testid="color-palette">
      <div data-testid="color-bg-primary">Background Primary</div>
      <div data-testid="color-accent">Accent</div>
      <!-- ... more colors -->
    </section>

    <!-- Component Samples Section -->
    <section data-testid="components-section">
      <button data-testid="btn-primary" class="btn btn-primary">Primary Button</button>
      <button data-testid="btn-secondary" class="btn btn-secondary">Secondary Button</button>
      <input data-testid="sample-input" type="text" placeholder="Input field">
      <div data-testid="sample-card" class="card">Card component</div>
    </section>

    <!-- Layout Demo Section -->
    <section data-testid="layout-section">
      <!-- Layout-specific content -->
    </section>
  </main>

  <script>
    function toggleTheme() {
      const html = document.documentElement;
      const current = html.getAttribute('data-theme');
      html.setAttribute('data-theme', current === 'light' ? 'dark' : 'light');
    }
  </script>
</body>
</html>
```

---

## See Also

- Parent: `SKILL.md` - Main ui-planner skill documentation
- `/ux-planner` - User experience and interaction patterns
- `/ux-review` - UX review and verification
- `/create-task` - Implementation task creation
