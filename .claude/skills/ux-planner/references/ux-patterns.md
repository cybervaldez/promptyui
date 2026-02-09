# UX Patterns Reference

A comprehensive database of UX patterns, laws, principles, and psychology for web UI design.

---

## Interaction Laws

### Fitts's Law
**The time to acquire a target is a function of the distance to and size of the target.**

- Make important/frequent actions larger and closer
- Place related actions near each other
- Primary buttons should be larger than secondary
- Corner and edge positions are fast to reach (infinite edges)

**Application:**
```
+-------------------------------------+
| [Cancel]            [Save Changes]  |  <- Save is larger, primary color
|  (small)               (large)      |
+-------------------------------------+
```

### Hick's Law
**The time to make a decision increases with the number and complexity of choices.**

- Reduce choices to essential options
- Use progressive disclosure for advanced options
- Group related options into categories
- Provide smart defaults

**Application:**
- Instead of 20 options in a dropdown, group into 4-5 categories
- Hide advanced settings behind "More options"
- Pre-select the most common choice

### Jakob's Law
**Users spend most of their time on other sites. They prefer your site to work the same way.**

- Follow established UI conventions
- Use standard icons (hamburger = menu, X = close)
- Match mental models from popular apps
- Don't innovate on basic interactions

**Application:**
- Settings icon = gear
- Search in top-right or with magnifying glass
- Primary action = right side of dialog
- Red = destructive, green = success

### Miller's Law
**The average person can hold 7 (+/-2) items in working memory.**

- Chunk information into groups of 5-9
- Don't require users to remember info between screens
- Show relevant context at decision points
- Use recognition over recall

**Application:**
- Break long forms into steps
- Show "You selected: X" confirmations
- Display breadcrumbs for navigation history

### Doherty Threshold
**Productivity soars when response time < 400ms.**

- Provide instant feedback for user actions
- Use optimistic UI updates
- Show loading states for anything > 400ms
- Perceived performance matters

**Application:**
```
Click -> Instant visual feedback -> Loading indicator -> Result
        (button state change)     (if > 400ms)
```

---

## Design Principles

### Progressive Disclosure
**Show only what's needed at each stage. Reveal complexity gradually.**

Levels:
1. **Essential** - Always visible (primary actions)
2. **Optional** - On demand (advanced settings)
3. **Deep** - Expert mode (developer tools)

**Pattern:**
```
+-------------------------------------+
| Simple Form                         |
| +-------------------------------+   |
| | Name: [_______________]       |   |
| +-------------------------------+   |
|                                     |
| > Advanced Options                  |  <- Collapsed by default
| +-------------------------------+   |
| | Custom ID: [_______________]  |   |
| | Tags: [_______________]       |   |
| +-------------------------------+   |
+-------------------------------------+
```

### Feedback Loops
**Every action needs a response. Users need to know the system heard them.**

Types of feedback:
- **Immediate** - Button press visual (< 100ms)
- **Progress** - Loading indicator (100ms - 10s)
- **Completion** - Success/error state (result)

**Feedback Matrix:**
| Action Duration | Feedback Type |
|-----------------|---------------|
| < 100ms | Instant visual change |
| 100ms - 1s | Spinner/pulse |
| 1s - 10s | Progress bar + message |
| > 10s | Background task + notification |

### Error Prevention
**Prevent errors before they happen. Make destructive actions harder.**

Strategies:
- Disable invalid actions
- Show constraints upfront
- Confirm destructive actions
- Allow undo when possible

**Severity Ladder:**
```
Low Risk:    Just do it
Medium Risk: Undo available
High Risk:   Confirmation dialog
Critical:    Type to confirm ("delete my-project")
```

### Recognition Over Recall
**Show options rather than requiring memory.**

- Use dropdowns instead of text input when options are known
- Show recent items
- Provide autocomplete
- Display visual thumbnails

**Example:**
```
Bad:  "Enter color code: [________]"
Good: "Pick color: [Red] [Blue] [Green] [Custom...]"
```

### Consistency
**Same action = same result. Match internal and external patterns.**

Internal consistency:
- Same colors mean same things throughout
- Same gestures do same actions
- Same terminology everywhere

External consistency:
- Match platform conventions
- Follow established patterns
- Use standard terminology

---

## Common Patterns

### Modal Dialogs

**When to use:**
- Requires immediate decision
- Blocks workflow intentionally
- Contains focused task

**Structure:**
```
+-------------------------------------------+
| Modal Title                           [X] |
+-------------------------------------------+
|                                           |
| Modal content goes here.                  |
|                                           |
| Form fields or information...             |
|                                           |
+-------------------------------------------+
|               [Cancel]  [Primary Action]  |
+-------------------------------------------+
```

**Best practices:**
- Clear, action-oriented title
- Single purpose per modal
- Escape key and click-outside to close (non-destructive)
- Focus trap within modal
- Primary action on right

### Toast Notifications

**When to use:**
- Non-blocking feedback
- Action completed successfully
- Brief informational messages

**Types:**
| Type | Duration | Dismissable | Use Case |
|------|----------|-------------|----------|
| Success | 3-5s | Auto | Action completed |
| Info | 5s | Auto | FYI messages |
| Warning | 10s | Manual | Needs attention |
| Error | Persistent | Manual | Action failed |

**Positioning:**
- Bottom-right: Standard, out of way
- Top-center: Important, in view
- Bottom-center: Mobile-friendly

### Loading States

**Skeleton Loaders:**
```
+-------------------------------------+
| ################                    |  <- Animated shimmer
| ##########                          |
| ####################                |
+-------------------------------------+
```
Use for: Content areas, cards, lists

**Spinners:**
Use for: Buttons, small inline areas

**Progress Bars:**
Use for: Known-duration operations, uploads

**Determinate vs Indeterminate:**
- Know progress % -> Progress bar with percentage
- Unknown duration -> Spinner or indeterminate bar

### Empty States

**Components:**
1. Visual (illustration or icon)
2. Headline (what's empty)
3. Description (why it's empty)
4. Action (how to fill it)

```
+-------------------------------------+
|                                     |
|           [folder icon]             |
|                                     |
|      No projects yet                |
|                                     |
|   Create your first project to      |
|   get started with generation.      |
|                                     |
|      [+ Create Project]             |
|                                     |
+-------------------------------------+
```

### Error States

**Inline Errors (Forms):**
```
+-------------------------------------+
| Email                               |
| +-------------------------------+   |
| | invalid-email                 |   |  <- Red border
| +-------------------------------+   |
| ! Please enter a valid email        |  <- Error below field
+-------------------------------------+
```

**Page-Level Errors:**
```
+-------------------------------------+
| ! Something went wrong              |
|                                     |
| We couldn't load your data.         |
| Please try again.                   |
|                                     |
| [Retry]  [Go Back]                  |
+-------------------------------------+
```

**Error Message Components:**
1. What happened (brief)
2. Why it might have happened (if known)
3. What to do next (action)

---

## User Psychology

### Decision Fatigue
**Each decision depletes mental energy. Reduce decision points.**

Strategies:
- Smart defaults
- Recommendations ("Popular", "Recommended")
- Limit options per screen
- Save preferences

### Cognitive Load
**Working memory is limited. Don't overload users.**

Types:
- **Intrinsic** - Inherent task complexity (unavoidable)
- **Extraneous** - Poor design adding complexity (fix this)
- **Germane** - Learning/understanding effort (support this)

Reduce extraneous load:
- Remove unnecessary elements
- Group related information
- Use visual hierarchy
- Consistent patterns

### Attention Patterns

**F-Pattern (Text-heavy pages):**
```
########################
################
############
########
```
Users scan top, then left side. Put important info top-left.

**Z-Pattern (Landing pages):**
```
1 ---------------------> 2
                         |
3 <----------------------4
```
Logo top-left, CTA top-right, content bottom.

**Visual Hierarchy:**
1. Size - Larger = more important
2. Color - Contrast draws attention
3. Position - Top-left seen first
4. Whitespace - Isolation = importance

### Habit Formation

**Hook Model:**
1. Trigger (external -> internal)
2. Action (simple behavior)
3. Variable Reward (unpredictable payoff)
4. Investment (user puts something in)

For productivity apps:
- Make frequent actions frictionless
- Reward completion visually
- Build muscle memory with consistency

---

## Accessibility (WCAG)

### Keyboard Navigation
- All interactive elements focusable
- Visible focus indicators
- Logical tab order
- Escape closes modals/menus
- Enter activates buttons

**Focus Order:**
```
1. Skip to content link
2. Navigation
3. Main content (interactive elements)
4. Sidebar
5. Footer
```

### Color Contrast
- Normal text: 4.5:1 ratio minimum
- Large text (18px+): 3:1 ratio minimum
- UI components: 3:1 ratio minimum

**Don't rely on color alone:**
```
Bad:  "Fields in red are required"
Good: "Required *" with asterisk AND color
```

### Screen Readers
- Use semantic HTML (nav, main, button, etc.)
- Add aria-labels to icon buttons
- Announce dynamic content changes
- Provide alt text for images

**ARIA Labels:**
```html
<button aria-label="Close dialog">X</button>
<div role="alert">Form saved successfully</div>
```

### Motion and Animation
- Respect `prefers-reduced-motion`
- Avoid flashing content (seizure risk)
- Keep animations under 5 seconds
- Provide pause controls for auto-playing content

---

## Mobile Considerations

### Touch Targets
- Minimum 44x44px (iOS) / 48x48px (Android)
- 8px minimum spacing between targets
- Increase size for primary actions

### Thumb Zones
```
+---------------------+
|     Hard to reach   |  <- Avoid primary actions here
+---------------------+
|    OK / Stretch     |
+---------------------+
|    Easy / Natural   |  <- Primary actions here
+---------------------+
```

### Mobile Patterns
- Bottom navigation for primary actions
- Pull-to-refresh
- Swipe gestures for quick actions
- Sheet modals from bottom

---

## Performance Perception

### Optimistic UI
Update UI immediately, sync in background.

```
User clicks "Like" ->
  UI: Shows liked immediately
  Background: Sends request to server
  If fails: Revert + show error
```

### Skeleton Loading
Show layout immediately, fill in content.

**Benefits:**
- Perceived faster load
- Reduces layout shift
- Sets expectations

### Progress Indicators
- Under 1s: May not need indicator
- 1-10s: Spinner or progress bar
- Over 10s: Progress bar with time estimate

---

## Common Anti-Patterns to Avoid

### Dark Patterns
- Trick questions
- Hidden costs
- Misdirection
- Confirm-shaming
- Forced continuity

### UX Debt
- Inconsistent patterns across app
- Multiple ways to do same thing
- Orphaned features
- Dead ends without navigation

### Over-Engineering
- Animations that slow users down
- Confirmations for everything
- Too many loading states
- Excessive error handling

---

## Quick Reference Checklist

### Before Implementing
- [ ] What's the user's goal?
- [ ] What's the happy path?
- [ ] What can go wrong?
- [ ] What existing pattern fits?
- [ ] Is this accessible?

### Interaction Design
- [ ] Clear call to action
- [ ] Immediate feedback
- [ ] Loading state if > 400ms
- [ ] Error handling
- [ ] Success confirmation

### Visual Design
- [ ] Clear hierarchy
- [ ] Sufficient contrast
- [ ] Consistent spacing
- [ ] Touch-friendly targets
- [ ] Focus indicators
