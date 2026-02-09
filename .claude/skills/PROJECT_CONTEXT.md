# Project Context Detection

Shared reference for `/ux-planner` and `/ui-planner` to classify projects by content archetype and rank suggestions accordingly.

---

## Content Archetype Taxonomy

Every project maps to 1-2 archetypes. These drive layout/aesthetic recommendations — not restrictions.

| Archetype | Examples | Natural Layouts | Natural Aesthetics |
|-----------|---------|----------------|-------------------|
| `text-heavy` | Blog, docs, knowledge base | Hero+Content (4), List View (6) | Neo-Minimal (B), Editorial (C), Warm Organic (E) |
| `data-dashboard` | Analytics, admin panel | Dashboard (2), Sidebar (1) | Dark Industrial (D), Neo-Minimal (B) |
| `form-heavy` | SaaS settings, onboarding | Split Panel (5), Sidebar (1) | Neo-Minimal (B), Soft Pastel (H) |
| `media-gallery` | Portfolio, e-commerce catalog | Card Grid (3), Hero+Content (4) | Editorial (C), Retro-Futurism (F) |
| `task-management` | Project mgmt, todo, CRM | Kanban (7), List View (6), Sidebar (1) | Neo-Minimal (B), Dark Industrial (D) |
| `real-time` | Chat, feeds, collaboration | Timeline (8), List View (6) | Neo-Minimal (B), Soft Pastel (H) |
| `e-commerce` | Online stores, marketplaces | Card Grid (3), Hero+Content (4) | Warm Organic (E), Art Deco (G) |
| `landing-page` | Marketing, waitlists | Hero+Content (4), Split Panel (5) | Brutalist (A), Retro-Futurism (F), Art Deco (G) |

---

## Detection Instructions

**When:** At the start of `/ux-planner` or `/ui-planner`, after Tech Context Detection.

**How:**

1. **Read project signals** (in priority order):
   - `README.md` — project description, purpose, features
   - `package.json` — `description` field, dependencies (e.g., `chart.js` → data-dashboard, `stripe` → e-commerce)
   - Existing routes/pages — scan for patterns (e.g., `/dashboard`, `/blog`, `/products`)

2. **Classify into 1-2 archetypes** based on:
   - Primary content type (text, data, media, tasks, forms)
   - User interaction model (reading, monitoring, creating, browsing, managing)
   - Core dependencies that signal domain

3. **Present to user for confirmation** before applying:

```
Based on your project, I'd classify this as: **data-dashboard**
(Analytics tool with chart.js, multiple data views)

Does this match your intent? If not, which archetype fits better?
- text-heavy, data-dashboard, form-heavy, media-gallery
- task-management, real-time, e-commerce, landing-page
```

4. **Apply classification** only after user confirms or corrects.

**Session-scoped:** Classification is NOT written to disk. Each session re-reads project files. This respects Assumption 3 in `TECH_CONTEXT.md`.

---

## Per-Skill Mapping

### ui-planner

Use the confirmed archetype to annotate both galleries:

**Aesthetic Gallery (Step 1):**
```
Based on your project archetype ({archetype}):
  Recommended:  [{letter}] {name}, [{letter}] {name}
  Good fit:     [{letter}] {name}
  Less typical: [{letter}] [{letter}] [{letter}] [{letter}] [{letter}]
All 8 remain available — these are suggestions, not restrictions.
```

**Layout Gallery (Step 2):**
```
Based on your project archetype ({archetype}):
  Recommended:  [{number}] {name}, [{number}] {name}
  Good fit:     [{number}] {name}
  Less typical: [{number}] [{number}] [{number}] [{number}] [{number}]
All 8 remain available — these are suggestions, not restrictions.
```

### ux-planner

Use the confirmed archetype to prioritize clarifying questions:

| Archetype | Priority Questions |
|-----------|-------------------|
| `text-heavy` | "How long are typical articles?" · "Reading order (linear vs. browsable)?" · "Search or category-first navigation?" |
| `data-dashboard` | "Primary metric the user monitors?" · "Drill-down needed from overview to detail?" · "Real-time updates or periodic refresh?" |
| `form-heavy` | "How many steps/fields?" · "Save progress mid-form?" · "Conditional fields based on prior answers?" |
| `media-gallery` | "Grid browsing or detail-focused?" · "Filtering/sorting needed?" · "Upload or consume-only?" |
| `task-management` | "Status workflow (how many states)?" · "Single user or team collaboration?" · "Drag-and-drop reordering needed?" |
| `real-time` | "Message threading or flat?" · "Presence indicators needed?" · "Notification model (push, badge, sound)?" |
| `e-commerce` | "Cart model (single item or basket)?" · "Checkout steps?" · "Product comparison needed?" |
| `landing-page` | "Primary CTA (signup, waitlist, demo)?" · "Social proof elements?" · "Above-the-fold priorities?" |

Annotate options analysis with archetype fit:
```
### Option A: [Name] (Recommended for {archetype})
```

### create-task

Archetype guides test fixture selection and scaffold patterns:

| Archetype | Test Data Focus | Scaffold Hints |
|-----------|----------------|----------------|
| `text-heavy` | Long-form content, edge case article lengths | Content templates, reading-focused components |
| `data-dashboard` | Multiple data volumes (empty, 10, 1000+), stale data | Metric cards, filter components, chart containers |
| `form-heavy` | Conditional field combos, validation edge cases | Multi-step form scaffolds, validation schemas |
| `media-gallery` | Multiple media types, broken images, large files | Grid/lightbox components, lazy loading patterns |
| `task-management` | Status transitions, concurrent edits | Kanban/list components, drag-drop scaffolds |
| `real-time` | Race conditions, connection drops, rapid updates | WebSocket/SSE patterns, optimistic UI |
| `e-commerce` | Cart edge cases (empty, max items, price calcs) | Product card, cart, checkout step components |
| `landing-page` | CTA variants, viewport sizes | Hero sections, social proof, CTA components |

### e2e-guard

Archetype guides test generation templates:

| Archetype | Must-Test Patterns |
|-----------|-------------------|
| `text-heavy` | Content renders fully, TOC navigation works, search returns results |
| `data-dashboard` | Metrics load with correct values, empty states handled, filters apply correctly |
| `form-heavy` | All conditional fields render, validation fires inline, multi-step progression works |
| `media-gallery` | Images load (not broken), grid responsive, lightbox opens/closes |
| `task-management` | Status transitions complete, drag-drop reorders, concurrent state consistent |
| `real-time` | Messages appear without refresh, connection recovery works |
| `e-commerce` | Add-to-cart updates count, checkout completes, price calculations correct |
| `landing-page` | CTA visible above fold, form submission works, social proof loads |

### coding-guard

Archetype guides anti-pattern focus:

| Archetype | Priority Anti-Patterns |
|-----------|----------------------|
| `text-heavy` | Hardcoded content dimensions, missing truncation handling, DOM assumptions about article length |
| `data-dashboard` | Assumed data shapes (`data[0]`), missing empty states, hardcoded data volumes in loops |
| `form-heavy` | Missing conditional field guards, shared state across steps, sync validation blocking UI |
| `media-gallery` | Missing image error handlers, unoptimized media loading, layout shift from unset dimensions |
| `task-management` | Unguarded concurrent mutations, missing optimistic rollback, stale state after drag |
| `real-time` | Missing reconnection logic, unthrottled renders, memory leaks from subscriptions |
| `e-commerce` | Floating-point price math, missing cart boundary checks, unvalidated quantity inputs |
| `landing-page` | Viewport-dependent CTA visibility, blocking scripts above fold, missing form honeypot |

### cli-first

Archetype guides testID conventions and state exposure depth:

| Archetype | Key TestIDs | State Exposure |
|-----------|------------|----------------|
| `text-heavy` | `data-testid="article-{slug}"`, `toc-item-{section}` | `{ currentSection, readingProgress }` |
| `data-dashboard` | `data-testid="metric-{name}-value"`, `filter-{name}-control` | `{ metrics, activeFilters, lastRefresh }` |
| `form-heavy` | `data-testid="field-{name}-input"`, `step-{n}-indicator` | `{ values, errors, currentStep, touched }` |
| `media-gallery` | `data-testid="item-{id}-image"`, `gallery-filter-{type}` | `{ visibleItems, activeFilter, loadedCount }` |
| `task-management` | `data-testid="task-{id}-card"`, `lane-{status}` | `{ tasks, lanes, dragState }` |
| `real-time` | `data-testid="message-{id}"`, `presence-{user}` | `{ connectionStatus, unreadCount }` |
| `e-commerce` | `data-testid="product-{id}-card"`, `cart-count` | `{ cartItems, cartTotal, checkoutStep }` |
| `landing-page` | `data-testid="hero-cta"`, `signup-form` | `{ formSubmitted, variant }` |

### e2e

Archetype guides test phase priorities and verification criteria:

| Archetype | Critical Phases | Verification Focus |
|-----------|----------------|-------------------|
| `text-heavy` | Startup, URL Navigation, Region Click-Through | Content renders, navigation works, search functional |
| `data-dashboard` | Startup, User Flow (filter→drill-down) | Metrics match API, filters apply, drill-down loads |
| `form-heavy` | Startup, User Flow (complete form) | Conditional fields render, validation fires, submission completes |
| `media-gallery` | Startup, Region Click-Through | Grid loads, images render, lightbox opens |
| `task-management` | Startup, User Flow (create→move→complete) | Status transitions, drag-drop, persistence |
| `real-time` | Startup, User Flow (send→receive) | Messages appear, connection stable, presence updates |
| `e-commerce` | Startup, User Flow (browse→cart→checkout) | Product loads, cart updates, checkout completes |
| `landing-page` | Startup, Region Click-Through | CTA visible, form submits, animations run |

### kaizen

Archetype guides persona auto-selection weighting:

| Archetype | Priority Personas | Why |
|-----------|------------------|-----|
| `text-heavy` | Grandma Dorothy, Rushed Ryan, Elena (screen reader) | Readability, scannability, accessibility |
| `data-dashboard` | Marcus (IT professional), Marcus (colorblind), Frustrated Frank | Efficiency, data legibility, loading tolerance |
| `form-heavy` | Tommy (intern), Frustrated Frank, Priya (motor disability) | Field clarity, friction, input precision |
| `media-gallery` | Kevin (14), Robert (72), Subway Sam | Visual appeal, touch targets, slow connections |
| `task-management` | Marcus (IT professional), Tommy (intern), Multitasking Maya | Efficiency, learnability, multitasking |
| `real-time` | Rushed Ryan, Elena (screen reader), Subway Sam | Speed, accessibility, connectivity |
| `e-commerce` | Skeptical Sarah, Carlos (CEO), Grandma Dorothy | Trust, decision-making, usability |
| `landing-page` | Derek (sales), Skeptical Sarah, Rushed Ryan | Persuasion, trust, attention span |

---

## Web Research Guidance

**When:** User asks for design inspiration, or context would benefit from current trends.

**How:** Use inline `WebSearch` (NOT `/research` — design trends aren't tech classifications).

```
WebSearch "{archetype} web design trends {current_year}"
WebSearch "{archetype} UI patterns {current_year}"
```

**Output:** Summarize 2-3 trending patterns to inform gallery annotations.

**Skip when:** User wants to move fast, or the archetype mapping already provides sufficient guidance.

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Session-scoped, not persisted | Respects Assumption 3 — each session re-reads README.md |
| Soft recommendations, not hard filters | All options remain available; archetype just annotates "Recommended" / "Less typical" |
| User confirmation required | Present classification before applying (same pattern as `/research` Step 4) |
| Web research is optional | Only when user asks or context demands; uses `WebSearch`, not `/research` |
| 1-2 archetypes per project | Projects can blend (e.g., "data-dashboard + form-heavy" for an admin panel with settings) |
