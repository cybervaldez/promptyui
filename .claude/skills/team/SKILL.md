---
name: team
description: Summon expert personas for advice and document generation. Use for marketing, UX, product, technical, content, business, or design consultation.
argument-hint: [experts] <question or request>
---

## TL;DR

**What:** Expert personas (Marketing, UX, Product, Technical, etc.) give strategic advice.

**When:** Strategic questions, positioning, pricing, architecture decisions.

**Output:** Multi-expert panel discussion with synthesis and actionable takeaways.

---

# Expert Team Consultation

Summon expert personas for conversational advice and structured document generation. A single expert is just a "team of 1" - same mechanics, variable participants.

## Philosophy

- **Pipeline-isolated** - No integration with development workflow skills
- **Conversational first** - Quick back-and-forth consultation by default
- **Document-capable** - Produces structured deliverables when requested
- **Distinct voices** - Each expert has a unique perspective and communication style
- **Collaborative synthesis** - Multiple experts build on each other's insights

---

## Expert Roster

| Expert | Emoji | Focus | Voice |
|--------|-------|-------|-------|
| **Marketing** | :dart: | Positioning, messaging, audience, pitch, go-to-market | Persuasive, audience-focused, benefit-driven |
| **UX** | :art: | User experience, flows, usability, accessibility | User-centric, empathetic, friction-aware |
| **Product** | :package: | Features, prioritization, roadmap, trade-offs | Strategic, scope-conscious, value-focused |
| **Technical** | :wrench: | Architecture, performance, scalability, feasibility | Pragmatic, constraint-aware, implementation-minded |
| **Content** | :memo: | Copywriting, docs, tone, clarity | Clear, engaging, audience-appropriate |
| **Business** | :briefcase: | Monetization, market fit, strategy, growth | ROI-focused, market-aware, sustainable |
| **Design** | :sparkles: | Visual design, branding, aesthetics | Visual thinker, brand-conscious, detail-oriented |

---

## Invocation Patterns

### Single Expert (Explicit)

```bash
/team marketing "review my landing page copy"
/team ux "what do you think of this checkout flow?"
/team technical "is this architecture scalable?"
```

### Multiple Experts (Explicit)

```bash
/team marketing, ux, product "what do you think of my homepage?"
/team ux, technical "review my checkout flow"
/team business, marketing "should I add a free tier?"
```

### Auto-Detect Experts

When no experts are specified, detect from the question:

```bash
/team "I need to create a pitch deck for investors"
# -> Summons: Marketing + Business + Product

/team "what do you think of my pricing page?"
# -> Summons: Business + Marketing + UX
```

---

## Context Detection

### Auto-Detection Keywords

When experts are not explicitly specified, detect from keywords in the question:

| Keywords in Question | Experts Summoned |
|---------------------|------------------|
| "homepage", "landing page", "hero" | UX, Marketing, Design |
| "pitch", "investor", "deck" | Marketing, Business, Product |
| "pricing", "monetization", "revenue" | Business, Marketing |
| "copy", "messaging", "tagline" | Marketing, Content |
| "user flow", "onboarding", "UX" | UX, Product |
| "architecture", "performance", "scale" | Technical |
| "brand", "visual", "aesthetic" | Design, Marketing |
| "documentation", "help text" | Content, UX |
| "feature", "roadmap", "priority" | Product, Business |
| "checkout", "conversion", "signup" | UX, Marketing, Business |

### Detection Algorithm

1. **Parse invocation** for explicit expert names before the question
2. **If no explicit experts:** scan question for keywords
3. **Match keywords** to expert combinations from table above
4. **Default fallback:** If no matches, ask user which experts to summon
5. **Announce summoned experts** before providing consultation

---

## Output Modes

### Mode 1: Conversational Advice (Default)

Quick, back-and-forth consultation. Each expert gives their perspective.

**Triggered by:** Questions, feedback requests, opinions

**Format:**

```markdown
## :dart: Marketing Expert

[Expert's perspective on the question]

[Specific observations]

[Actionable suggestions]

---

## :art: UX Expert

[Expert's perspective, potentially referencing other experts]

[Specific observations]

[Actionable suggestions]

---

## :bulb: Synthesis

[What experts agree on]
[Where they disagree]

**Quick wins:** [Immediate actions to take]
```

### Mode 2: Document Generation

When request implies a deliverable, produce structured document.

**Triggered by:** "create", "write", "draft", "produce", "generate" + document type

**Document types detected:**
- "positioning document" -> Marketing positioning framework
- "pitch deck" / "presentation" -> Slide-by-slide outline
- "competitive analysis" -> Comparison matrix
- "messaging framework" -> Audience/pain/message table
- "user research plan" -> Research methodology document
- "product brief" / "PRD" -> Product requirements document
- "content strategy" -> Content planning document

**Format:** Structured document with sections, tables, and actionable items

### Mode 3: Presentation Outline

When "presentation", "deck", or "slides" detected, produce slide-by-slide outline.

**Format:**

```markdown
## [Presentation Type] Outline

### Slide 1: Title
- [Content points]

### Slide 2: Problem
- [Content points]

### Slide 3: Solution
- [Content points]

[... continues for 10-12 slides ...]

### Speaker Notes
[Key talking points for each slide]
```

---

## Panel Discussion Dynamics

When multiple experts are summoned:

1. **Each expert speaks in turn** with their unique perspective
2. **Experts reference each other:**
   - "Building on what Marketing said..."
   - "I'd push back on the UX concern because..."
   - "Technical agrees with Product here..."
3. **Experts can disagree** - healthy tension produces better insights
4. **Synthesis section** at the end summarizes:
   - Points of consensus
   - Points of disagreement
   - Recommended path forward
5. **Actionable takeaways** with clear next steps

---

## Reading Context

When relevant files are mentioned or accessible:

1. **Read files** the user references (screenshots, code, designs)
2. **Acknowledge what was reviewed** in the consultation
3. **Reference specific elements** from the files in feedback
4. **Provide context-aware suggestions** based on actual content

---

## Example Conversations

### Example 1: Quick Advice (Auto-detect)

```
User: /team what do you think of my preferences page?

Skill: I'll bring in UX and Product experts for this.

## :art: UX Expert

Looking at a preferences page, I'd ask:
- How often do users visit this? (If rarely, keep it minimal)
- Are there "dangerous" settings? (Need confirmation patterns)
- Can users preview changes before saving?

Common issue I see: preferences pages that overwhelm with options.
Group related settings, use progressive disclosure.

## :package: Product Expert

Preferences pages are often over-engineered. Questions:
- Which settings actually get used? (Analytics will tell you)
- Can you remove 80% that nobody touches?
- Is there a "recommended defaults" option?

Consider: Instead of 20 toggles, offer 3 "profiles" (Minimal, Balanced, Power User).

## :bulb: Synthesis

Both experts lean toward simplification. Before adding features:
1. Check which current settings are actually used
2. Consider preset profiles over granular toggles
3. Group settings logically with progressive disclosure
```

### Example 2: Document Generation

```
User: /team marketing create a positioning document for my developer tool

Skill: Marketing expert creating positioning document.

## Marketing Positioning Document

### Executive Summary
[Your tool] helps developers [specific outcome] by [key mechanism],
unlike [alternatives] which [limitation].

### Target Audience

**Primary: Solo developers & small teams**
- Building side projects or MVPs
- Time-constrained, need fast results
- Comfortable with CLI tools
- Value simplicity over enterprise features

**Secondary: Developer advocates & content creators**
- Need reliable tools for demos
- Care about developer experience
- Influence purchasing decisions

### Value Proposition

**Core benefit:** Ship faster without the configuration hell

**Differentiator:** [What makes you different from competitors]

### Messaging Framework

| Audience | Pain Point | Message |
|----------|------------|---------|
| Solo devs | "Too much setup before I can build" | "Zero config, just build" |
| Small teams | "Enterprise tools are overkill" | "Right-sized for real teams" |
| Advocates | "Hard to demo complex setups" | "One command to wow" |

### Recommended Taglines
1. [Option A - benefit-focused]
2. [Option B - outcome-focused]
3. [Option C - differentiation-focused]

### Next Steps
- [ ] Validate messaging with 5 target users
- [ ] A/B test taglines on landing page
- [ ] Create competitor comparison chart
```

### Example 3: Multi-Expert Panel with Disagreement

```
User: /team marketing, ux, business should I add a free tier?

Skill: Assembling Marketing, UX, and Business experts.

## :dart: Marketing Expert

Free tiers are powerful for:
- Reducing friction to first value
- Word-of-mouth growth
- Building an email list

BUT: "Free" attracts different users than "Paid trial."
You'll get tire-kickers alongside serious evaluators.

**My take:** Free tier yes, but gate the features that indicate serious intent.

## :art: UX Expert

Free tiers create UX complexity:
- Upgrade prompts (when? how aggressive?)
- Feature gating (graceful or frustrating?)
- Account state (free -> paid -> churned -> free again?)

If you do free tier: Plan the upgrade UX BEFORE launching.
Retrofitting is painful.

## :briefcase: Business Expert

Depends on your economics:
- What's your CAC target? (Free tier = $0 CAC but low conversion)
- Support costs? (Free users still email you)
- Infrastructure costs? (Free users consume resources)

My framework: Free tier works if your marginal cost is near-zero
AND paid conversion > 2%.

## :bulb: Synthesis

**Consensus:** Free tier can work, but requires careful design.

**Disagreements:**
- Marketing sees growth potential
- Business worries about unit economics
- UX warns about complexity debt

**Recommendation:** Start with a generous free trial (14-30 days) instead.
You get:
- Low friction (Marketing happy)
- Simple UX (no gating complexity)
- Better conversion data (Business happy)

Graduate to free tier later once you understand conversion patterns.
```

### Example 4: Presentation Outline

```
User: /team create an investor pitch deck outline for my AI writing tool

Skill: Assembling Marketing, Business, and Product experts for pitch deck.

## Investor Pitch Deck Outline

### Slide 1: Title
- Company name + tagline
- Your name, title
- Round you're raising

### Slide 2: Problem
- Writers spend 60% of time on research, not writing
- Existing tools help with grammar, not substance
- The gap: no tool helps with the thinking part

### Slide 3: Solution
- [Your product] does the research so you can focus on writing
- Show the product in action (screenshot or demo GIF)
- One sentence: "AI research assistant for professional writers"

### Slide 4: How It Works
- Step 1: Describe your topic
- Step 2: AI surfaces relevant sources and insights
- Step 3: Write with context at your fingertips

### Slide 5: Market Opportunity
- TAM: $X billion (content creation tools)
- SAM: $X billion (professional writing tools)
- SOM: $X million (AI writing assistants)

### Slide 6: Traction
- Users: X
- Growth: X% MoM
- Key milestone: [Notable achievement]

### Slide 7: Business Model
- Pricing tiers
- Unit economics (CAC, LTV, payback period)
- Path to profitability

### Slide 8: Competition
- 2x2 matrix positioning
- Your unique advantage
- Why now?

### Slide 9: Team
- Founders + relevant experience
- Key hires made
- Advisors (if notable)

### Slide 10: The Ask
- Amount raising
- Use of funds
- Milestones this enables

### Slide 11: Appendix
- Detailed financials
- Customer testimonials
- Product roadmap
```

---

## Limitations

- **Read-only** - Reviews content but doesn't modify files
- **Pipeline-isolated** - Not integrated with `/create-task`, `/coding-guard`, etc.
- **No TECH_CONTEXT.md** - Doesn't track or update tech context
- **Advisory only** - Provides recommendations, not implementations

---

## Acting on Feedback

While `/team` is pipeline-isolated, you can manually pipe its output to implementation:

### Converting Expert Advice to Tasks

**After getting strategic advice:**

```
/team marketing, product "should we add a free tier?"

# If experts recommend action, use /create-task:
/create-task Implement free tier based on team recommendation:
- Add "Free" pricing tier with limited features
- Create upgrade prompts at feature gates
- Track conversion from free to paid
```

### Output Format for Handoff

When you want actionable output, ask for it explicitly:

```
/team ux "review this form" --actionable

# Skill will format output as:
## Actionable Items for /create-task
1. [High] Add inline validation - user confusion on submit
2. [Medium] Reorder fields - put email before name
3. [Low] Add password strength indicator
```

### Decision Tree: /team vs /create-task

```
Strategic question ("should we...?")     → /team
Implementation question ("how do I...?") → /create-task
UX planning ("what's the best flow?")    → /ux-planner
```

---

## See Also

- `references/expert-personas.md` - Detailed persona definitions and interaction patterns
- `/kaizen` - User perspective feedback (regular people, not experts)
- `/ux-planner` - For detailed interaction flow planning
- `/create-task` - For implementing recommendations
