---
name: kaizen
description: Gather diverse feedback from fictional personas representing real users at all levels - from colorblind users to CEOs, skeptical evaluators to delighted fans.
argument-hint: [category] <what to review>
---

## TL;DR

**What:** Diverse user personas (Grandma Dorothy, colorblind Marcus, intern Tommy) give real-world reactions.

**When:** User perspective questions, accessibility checks, usability feedback.

**Output:** Kaizen Board with issues by severity, bright spots, and actionable fixes.

---

# Kaizen Feedback

Gather diverse feedback from fictional personas representing real users, employees, and stakeholders at all levels. Inspired by the Kaizen philosophy where everyone's perspective matters - from the intern to the CEO, from the power user to someone's grandmother.

## Philosophy

### Kaizen Principles Applied

1. **Everyone's voice matters** - The intern might spot what the CEO misses
2. **Diverse perspectives catch diverse problems** - Accessibility, clarity, emotional response
3. **Grounded in reality** - Personas react to what's actually there, not assumptions
4. **Small improvements compound** - Each perspective surfaces a potential fix
5. **Fun but useful** - Personality makes it engaging, insights make it valuable

### Key Differentiator from /team

| Skill | Focus | Example Personas |
|-------|-------|------------------|
| `/team` | Expert professionals giving strategic advice | Marketing Expert, UX Expert, Technical Lead |
| `/kaizen` | Regular people giving real-world reactions | Sally from HR, a colorblind user, a skeptical dad |

### The Balance

| Aspect | Approach |
|--------|----------|
| **Fun** | Named personas with personality, casual tone, occasional humor |
| **Useful** | Real accessibility issues, usability problems, clarity concerns |
| **Grounded** | Must read actual context - no generic feedback |
| **Varied** | Range from critical issues to delightful moments |

---

## Persona Categories

### 1. Accessibility Personas

Surface real accessibility issues.

| Persona | Condition | What They Catch |
|---------|-----------|-----------------|
| Marcus, colorblind user | Red-green colorblindness | Color-only indicators, problematic palettes |
| Elena, screen reader user | Visual impairment | Missing alt text, poor heading structure, unlabeled buttons |
| Robert, 72 | Age-related vision decline | Small text, low contrast, tiny touch targets |
| Priya, motor disability | Limited fine motor control | Tiny buttons, hover-only interactions, drag requirements |

### 2. Tech Savviness Spectrum

| Persona | Level | What They Catch |
|---------|-------|-----------------|
| Grandma Dorothy, 68 | Minimal tech experience | Jargon, assumed knowledge, complex flows |
| Kevin, 14 | Digital native, impatient | Slow loads, boring UI, too many steps |
| Marcus, IT professional | Power user | Missing keyboard shortcuts, no bulk actions, inefficiencies |
| Linda, occasional user | Returns monthly | Forgotten passwords, changed UI, re-learning curve |

### 3. Role-Based Personas (Internal perspectives)

| Persona | Role | What They Notice |
|---------|------|------------------|
| Tommy, intern (first week) | New employee | Onboarding gaps, unclear terminology, tribal knowledge |
| Jasmine, customer support | Support rep | Common confusion points, missing help text, FAQ gaps |
| Derek, sales | Sales team | Objection triggers, demo pain points, competitor comparisons |
| Patricia, legal/compliance | Risk-aware | Privacy concerns, unclear terms, accessibility liability |
| Carlos, CEO perspective | Executive | Big picture clarity, value proposition, investor readiness |

### 4. Emotional State Personas

| Persona | State | What They React To |
|---------|-------|-------------------|
| Frustrated Frank | Already annoyed | Friction that pushes over the edge |
| Skeptical Sarah | Evaluating alternatives | Trust signals, proof points, red flags |
| Rushed Ryan | No time, needs quick answers | Buried information, slow paths |
| Delighted Diana | When something works well | Moments of joy worth preserving |

### 5. Context Personas

| Persona | Context | What They Experience |
|---------|---------|---------------------|
| Subway Sam | Mobile, spotty connection | Load times, offline behavior, touch targets |
| Multitasking Maya | Kids yelling, distracted | Cognitive load, lost state, recovery |
| Meeting Mike | Sharing screen with others | Embarrassing states, unclear UI for observers |

---

## Invocation Patterns

### Auto-Select Personas (Default)

When no category is specified, auto-select based on content type:

```bash
/kaizen "what do people think of my login page?"
# -> Auto-selects: accessibility + tech-spectrum + emotional state personas

/kaizen "review webui/index.html"
# -> Reads file, selects relevant personas based on content
```

### Explicit Category Selection

```bash
/kaizen accessibility "check my dashboard for issues"
# -> Marcus (colorblind), Elena (screen reader), Robert (elderly), Priya (motor)

/kaizen tech-spectrum "is this usable for non-technical users?"
# -> Grandma Dorothy, Kevin, Marcus (IT), Linda

/kaizen stakeholders "review my pitch deck"
# -> CEO, sales, investor-perspective, skeptical evaluator

/kaizen internal "review this from an employee perspective"
# -> Tommy (intern), Jasmine (support), Derek (sales), Patricia (legal)
```

### Available Categories

| Category | Personas Included |
|----------|-------------------|
| `accessibility` | Marcus, Elena, Robert, Priya |
| `tech-spectrum` | Grandma Dorothy, Kevin, Marcus (IT), Linda |
| `internal` / `stakeholders` | Tommy, Jasmine, Derek, Patricia, Carlos |
| `emotional` | Frank, Sarah, Ryan, Diana |
| `context` | Sam, Maya, Mike |

---

## Project Context Detection

Before Auto-Selection Logic, classify the project to weight persona selection:

1. **Read project signals** — `README.md`, `package.json` description/dependencies, existing routes
2. **Classify into 1-2 archetypes** from `PROJECT_CONTEXT.md` taxonomy
3. **Apply archetype context** — use per-skill mapping table in `PROJECT_CONTEXT.md` to prioritize personas relevant to the project archetype

Note: Unlike ux-planner/ui-planner, kaizen does not need user confirmation of archetype — it uses the classification silently to inform persona weighting in auto-selection.

---

## Auto-Selection Logic

When no category is specified, detect from context:

| Context Detected | Personas Included |
|-----------------|-------------------|
| UI/visual design | Colorblind, elderly, teen, screen reader |
| Form/input heavy | Motor disability, rushed user, frustrated user |
| Onboarding/first-run | Intern, grandma, skeptical evaluator |
| Pricing/sales page | Sales rep, skeptical user, CEO, rushed user |
| Documentation | Support rep, intern, power user |
| Mobile/responsive | Subway user, distracted parent |
| Settings/preferences | Power user, occasional user, support rep |

---

## Grounding Rules (Critical)

The skill MUST:

1. **Read actual context** - No generic feedback; respond to what's actually there
2. **Reference specific elements** - "The red error message on the email field" not "error messages"
3. **Stay in character** - Grandma doesn't use UX jargon, intern doesn't know company history
4. **Mix sentiment** - Not all negative; include delights and positives
5. **Be actionable** - Each piece of feedback should suggest a fix or preserve a win
6. **Respect project reality** - If it's an image tool, personas react to image generation, not generic software

---

## Output Format: The Kaizen Board

```markdown
## Kaizen Feedback Board

### Critical Issues

**Marcus (colorblind):** "I can't tell which fields have errors. You're using red/green and I literally cannot see the difference."

**Elena (screen reader):** "Your 'Submit' button isn't labeled. My screen reader just says 'button' - I have no idea what it does."

---

### Usability Concerns

**Grandma Dorothy:** "What does 'OAuth' mean? I just want to log in. Why are there so many options?"

**Tommy (intern, day 3):** "I've been clicking around for 10 minutes and I still don't understand what this page is for. Is there a tutorial somewhere?"

**Rushed Ryan:** "I found your pricing page but I can't figure out if you have a free trial without scrolling through this entire essay. Just tell me."

---

### Observations

**Derek (sales):** "When I demo this to clients, they always ask 'what happens if I click the wrong thing?' and honestly I don't know either."

**Jasmine (support):** "I get three tickets a day about this exact screen. People don't realize they need to scroll down."

---

### Bright Spots

**Kevin, 14:** "Okay this animation is actually sick. My friends would think this is cool."

**Delighted Diana:** "The empty state illustration made me smile! Little things like this make me want to use the product more."

---

### Summary

| Category | Count | Top Action |
|----------|-------|------------|
| Accessibility | 2 issues | Add alt text, text labels for indicators |
| Usability | 3 concerns | Clarify jargon, add onboarding, surface key info |
| Quick wins | 2 items | Fix button label, add visual indicator |
```

---

## Example Conversations

### Example 1: Login Page Review

```
User: /kaizen "what do people think of the login page?"

## Kaizen Feedback Board

### Critical Issues

**Elena (screen reader user):** "The social login buttons - Google, GitHub - they're just images with no alt text. I hear nothing. I don't even know they exist."

**Marcus (colorblind):** "Your password strength indicator goes from red to green. For me, it just looks like two shades of brown. Maybe add text like 'Weak' or 'Strong'?"

---

### Usability Concerns

**Grandma Dorothy, 68:** "'Continue with SSO' - what on earth is an SSO? I just want to use my email and password like a normal person. Why is this the first option?"

**Frustrated Frank:** "I mistyped my email and hit enter. Now I'm on a different page and I have to start over? Just let me fix it!"

**Tommy (intern, week 1):** "I tried to log in with my personal email by accident. The error message says 'Invalid domain' but it took me forever to realize I need to use my work email."

---

### Observations

**Jasmine (customer support):** "Oh, the 'Forgot Password' link! Customers miss this constantly. It's too small and it's gray on gray. We get password reset calls daily."

**Skeptical Sarah:** "No mention of how my data is handled. No privacy link visible. No trust badges. I'd Google you before entering my email here."

---

### Bright Spots

**Kevin, 14:** "At least it loads fast. Some login pages take forever."

**Delighted Diana:** "I like that it remembers my email from last time. Small thing but it makes me feel recognized."

---

### Summary

| Category | Count | Top Action |
|----------|-------|------------|
| Accessibility | 2 issues | Add alt text to social buttons, text labels for password strength |
| Usability | 3 concerns | Clarify SSO label, inline error correction, clearer domain error |
| Trust | 1 concern | Add visible privacy/security indicators |
| Wins | 2 bright spots | Keep fast load time and email memory |

**Quick wins:** Alt text + password text labels (high impact, low effort)
```

### Example 2: Explicit Category - Accessibility

```
User: /kaizen accessibility "review my form"

## Kaizen Feedback Board (Accessibility Focus)

### Critical Issues

**Elena (screen reader):** "None of your form labels are associated with inputs. I can't tell what any field is for. Use <label for='id'> or aria-label."

**Marcus (colorblind):** "Required fields are marked with red asterisks. I can't distinguish red from the dark gray text. Add '(required)' text."

**Robert, 72:** "The placeholder text is so light I can barely read it. And once I start typing, I forget what the field was asking for."

**Priya (motor):** "The 'Choose File' button is tiny. I keep missing it. And the dropdown requires precise clicking - can't I just type to filter?"

---

### Observations

**Elena (screen reader):** "Your error messages appear but my screen reader doesn't announce them. Add role='alert' or aria-live."

**Robert, 72:** "Good news - the text input fields are large enough. The font size is readable. But the submit button is smaller than the inputs, which seems odd."

---

### Summary

| Issue | Severity | Fix |
|-------|----------|-----|
| No label associations | Critical | Add for= attribute or aria-label |
| Color-only required indicator | Critical | Add "(required)" text |
| Placeholder contrast | High | Darken placeholder or use visible labels |
| Tiny file button | Medium | Increase touch target to 44px minimum |
| No live region for errors | High | Add aria-live="polite" to error container |

**WCAG Concerns:** Level A failures on labeling, Level AA failures on contrast
```

### Example 3: Internal Stakeholders Review

```
User: /kaizen stakeholders "review the new pricing page"

## Kaizen Feedback Board (Stakeholder Perspectives)

### Critical Issues

**Patricia (legal):** "Where's the link to terms of service? And this 'Enterprise - Contact Us' tier - does that include a BAA for healthcare clients? That needs to be visible."

---

### Usability Concerns

**Derek (sales):** "When clients ask 'what if I need to upgrade mid-cycle?' I don't see an answer here. That's objection #1 in every call."

**Carlos (CEO lens):** "The value proposition is buried. Someone landing here from a Google ad needs to understand what we do in 5 seconds. Right now it's just a price table."

**Jasmine (support):** "I'll tell you exactly what's going to happen - people will sign up for the free tier and then email us asking why they can't do X. The feature comparison needs to be clearer."

---

### Observations

**Tommy (intern):** "I was told we have a startup discount program. I don't see it mentioned anywhere. Is that just something sales offers?"

**Derek (sales):** "The Enterprise tier says 'Custom pricing' but competitors show a 'starting at' price. That gives them an anchor. We look evasive."

---

### Bright Spots

**Skeptical Sarah:** "I appreciate that you show all prices monthly AND annually. Most sites make me do math."

**Carlos (CEO lens):** "The 'Trusted by' logos section is strong. Good social proof placement."

---

### Summary

| Category | Count | Top Action |
|----------|-------|------------|
| Compliance | 1 issue | Add ToS link, clarify enterprise compliance |
| Sales Enablement | 2 gaps | Answer upgrade questions, add enterprise anchor |
| Clarity | 2 concerns | Add value prop, clarify tier differences |
| Wins | 2 items | Good pricing transparency, strong social proof |

**Stakeholder priorities:**
1. Legal needs compliance links (blocking)
2. Sales needs objection-handling content
3. Support needs clearer tier comparison
```

---

## Limitations

- **Read-only** - Provides feedback but doesn't modify files
- **Pipeline-isolated** - Not integrated with `/create-task`, `/coding-guard`, etc.
- **No TECH_CONTEXT.md** - Doesn't track or update tech context
- **Advisory only** - Provides recommendations, not implementations
- **Not a substitute** - Complements real user testing, doesn't replace it

---

## Acting on Feedback

While `/kaizen` is pipeline-isolated, you can convert its output to actionable tasks:

### Converting Persona Feedback to Tasks

**Step 1: Prioritize by impact and severity**

From the Kaizen Board Summary:
```
| Category | Count | Top Action |
|----------|-------|------------|
| Accessibility | 2 issues | Add alt text, text labels for indicators |
| Usability | 3 concerns | Clarify jargon, add onboarding, surface key info |
```

**Step 2: Convert to /create-task input**

```
/create-task Fix accessibility issues from kaizen review:
- Add alt text to social login buttons (Elena's feedback)
- Add text labels to password strength indicator (Marcus's feedback)
```

### Handling Common Feedback Types

| Persona Feedback Type | Action |
|-----------------------|--------|
| **Accessibility** (Marcus, Elena) | `/create-task` with WCAG fixes |
| **Clarity** (Grandma Dorothy) | Review copy, simplify language |
| **Trust** (Skeptical Sarah) | Add privacy links, security badges |
| **Internal** (Support, Sales) | Document FAQ, add help text |

### Output Format for Handoff

Request actionable output explicitly:

```
/kaizen accessibility "review form" --prioritized

# Skill will format as:
## Priority Fixes for /create-task

### P0 - Critical (Blocking)
- [ ] Add aria-labels to form inputs (Elena)
- [ ] Fix color contrast on error messages (Marcus)

### P1 - High (Should fix)
- [ ] Increase touch target size (Priya)

### P2 - Medium (Nice to have)
- [ ] Add visible focus states
```

---

## See Also

- `references/persona-roster.md` - Full persona definitions, voices, and example feedback
- `/team` - Expert professional consultation (strategic advice)
- `/ui-review` - Visual design quality guard (AI slop detection)
- `/create-task` - For implementing recommended fixes
