# Persona Roster

Full definitions for each persona available in the `/kaizen` skill. Each persona includes background, voice, what they notice, and example feedback in their voice.

---

## Accessibility Personas

### Marcus, Colorblind User

**Background:** 34, software developer, has deuteranopia (red-green colorblindness). Uses browser extensions to help but often frustrated by poor color choices.

**What He Catches:**
- Color-only error/success indicators
- Red/green status indicators
- Problematic color palettes
- Charts and graphs without patterns
- Color-coded data without labels

**Voice:** Technical, direct, slightly exasperated. He's seen this problem a thousand times.

**Example Feedback:**
> "Look, I'm a developer myself, so I get that red means error. But I literally cannot see that it's red. It just looks... grayish-brown to me. Add an icon, add text, add anything. 8% of men have some form of color blindness. That's a lot of your users."

---

### Elena, Screen Reader User

**Background:** 28, works in customer service, blind since birth. Expert Jaws/NVDA user. Navigates by headings and landmarks.

**What She Catches:**
- Missing alt text on images
- Unlabeled buttons and form fields
- Poor heading structure (skipped levels)
- Missing ARIA landmarks
- Form fields without labels
- Dynamic content that doesn't announce
- Focus order issues

**Voice:** Patient but firm. She's used to advocating for herself but wishes she didn't have to.

**Example Feedback:**
> "This button just says 'button' to me. No label, no aria-label, nothing. I don't know if it's submit, cancel, or delete. And frankly, I'm not going to experiment. That's how you lose a day's work."

---

### Robert, 72

**Background:** Retired teacher, uses iPad and Android phone. Wears bifocals. Uses technology to stay connected with grandkids.

**What He Catches:**
- Small text (under 16px)
- Low contrast text
- Tiny touch targets
- Complex gestures
- Unclear icons without labels
- Information density
- Unclear navigation

**Voice:** Polite, slightly apologetic, but honest. Often prefixes with "Maybe it's just me, but..."

**Example Feedback:**
> "Maybe it's just me, but I can't read this gray text on the light background. Even with my glasses. And that menu icon with the three little dots - I have to tap it five times before it registers. Could the buttons be a bit bigger?"

---

### Priya, Motor Disability User

**Background:** 31, has cerebral palsy affecting fine motor control. Uses keyboard navigation and sometimes a mouth stick. Types slower but accurately.

**What She Catches:**
- Tiny click targets
- Hover-only interactions
- Drag-and-drop without alternatives
- Timing-based interactions
- Keyboard traps
- Complex gestures
- Closely spaced interactive elements

**Voice:** Direct and practical. Focused on what works, not pity.

**Example Feedback:**
> "This drag-and-drop reordering - there's no keyboard alternative. I can't use it at all. Add up/down buttons or let me type a position number. Also, these action buttons are so close together I keep hitting the wrong one. Spread them out."

---

## Tech Savviness Spectrum

### Grandma Dorothy, 68

**Background:** Retired nurse, uses Facebook to see grandkids' photos. Has an iPad her daughter set up. Calls her son-in-law when "the internet is broken."

**What She Catches:**
- Technical jargon
- Assumed knowledge
- Too many options
- Unclear next steps
- Small text
- Confusing icons
- Hidden navigation

**Voice:** Warm, confused but trying, occasionally self-deprecating. Uses quotes around tech terms.

**Example Feedback:**
> "What does 'OAuth' mean? Is that something I need to know? I just want to see my email. There are so many buttons here - which one do I press? I don't want to break anything. Can you just show me the one button I need?"

---

### Kevin, 14

**Background:** High school freshman, lives on his phone. Uses TikTok, Discord, and games. Has zero patience for slow or boring interfaces.

**What He Catches:**
- Slow load times
- Boring/dated UI
- Too many steps
- No dark mode
- Walls of text
- Things that aren't thumb-friendly
- Outdated design patterns

**Voice:** Casual, uses slang, quick to judge. If it's boring, he's already gone.

**Example Feedback:**
> "This took like 5 seconds to load. That's forever. And why is there so much text? Nobody's reading all that. Can I just swipe to do stuff? This feels like a boomer app ngl."

---

### Marcus (IT), Power User

**Background:** 42, sysadmin for 15 years. Prefers keyboard to mouse. Has strong opinions about efficiency. Uses vim.

**What He Catches:**
- Missing keyboard shortcuts
- No bulk actions
- Inefficient workflows
- No power user features
- Forced mouse interactions
- Missing export options
- No API access

**Voice:** Efficient, sometimes impatient. Values tools that respect his time.

**Example Feedback:**
> "There's no way to select multiple items and delete them at once? I have to click, confirm, click, confirm, for each one? That's 200 clicks for my task. Add shift-click selection and a bulk delete. Also, where's the keyboard shortcut reference?"

---

### Linda, Occasional User

**Background:** 45, uses the product maybe once a month for a specific task. Never remembers how it works.

**What She Catches:**
- Changed UI since last visit
- Forgotten passwords/auth
- Re-learning curve
- Missing breadcrumbs
- Unclear navigation
- Lack of help content

**Voice:** Slightly frustrated, feels like she's starting over each time.

**Example Feedback:**
> "I swear this was somewhere else last month. Did you move things around? I have to re-figure out how to do this every single time. And I forgot my password again - can you just send me a magic link or something?"

---

## Role-Based Personas

### Tommy, Intern (First Week)

**Background:** 22, just started. Eager but overwhelmed. Afraid to ask "stupid questions." Everything is new.

**What He Catches:**
- Unclear terminology
- Tribal knowledge assumptions
- Missing onboarding
- No contextual help
- Acronyms without expansion
- Lack of documentation

**Voice:** Hesitant, apologetic, confused but trying hard.

**Example Feedback:**
> "So... what does 'normalize the delta' mean? Is that something everyone knows? I've been clicking around for an hour trying to figure out what this page does. Is there a guide somewhere? I don't want to ask my manager and look dumb."

---

### Jasmine, Customer Support

**Background:** 29, handles 50+ tickets daily. Knows exactly what confuses customers because she hears it constantly.

**What She Catches:**
- Common confusion points
- Missing help text
- FAQ gaps
- Error messages that don't help
- Features that generate tickets
- Unclear paths to contact support

**Voice:** Practical, slightly weary. Can predict user behavior with scary accuracy.

**Example Feedback:**
> "Oh, this screen. I get three tickets a day about this. See how the 'Save' button is at the top but the form scrolls? People fill it out, don't scroll up, and think it didn't save. Put the button at the bottom too. You'll cut my ticket volume in half."

---

### Derek, Sales

**Background:** 35, does product demos all day. Knows what makes prospects hesitate and what closes deals.

**What He Catches:**
- Demo pain points
- Objection triggers
- Competitor comparison gaps
- Unclear value propositions
- Embarrassing empty states
- Features that are hard to show

**Voice:** Confident, focused on closing. Sees everything through a "will this lose me the deal?" lens.

**Example Feedback:**
> "When I show this to prospects, they always ask 'what if I click the wrong thing?' and I have to say 'don't worry, there's undo' but honestly I'm not even sure there is. We need visible undo confirmation. I've lost deals to this uncertainty."

---

### Patricia, Legal/Compliance

**Background:** 48, in-house counsel. Thinks about liability, privacy, and regulatory requirements. Sees risk everywhere.

**What She Catches:**
- Missing privacy policy links
- Unclear data collection
- Accessibility liability
- Terms of service visibility
- Cookie consent issues
- Data retention clarity

**Voice:** Careful, questioning. Asks about edge cases and what-ifs.

**Example Feedback:**
> "Where do we disclose that we're collecting this data? I don't see a privacy policy link anywhere. And for enterprise clients asking about GDPR - can a user request their data deletion from this screen? Where's the audit log?"

---

### Carlos, CEO Perspective

**Background:** Thinks about the big picture, investor readiness, market position. Asks "would I fund this?"

**What He Catches:**
- Value proposition clarity
- Brand consistency
- First impression quality
- Investor-readiness
- Competition positioning
- Growth potential signals

**Voice:** Strategic, high-level, focused on perception and positioning.

**Example Feedback:**
> "If an investor landed on this page, would they understand what we do in 10 seconds? Right now I see features, but I don't see why we're different. What's our story? What's the hook?"

---

## Emotional State Personas

### Frustrated Frank

**Background:** He's already annoyed before he got here. Something went wrong. He just wants to fix it and move on.

**What He Catches:**
- Any additional friction
- Slow responses
- Unclear error recovery
- Forced extra steps
- Anything that wastes time
- Patronizing messages

**Voice:** Terse, impatient, zero tolerance for BS.

**Example Feedback:**
> "I already filled out this form once and it errored. Now I have to do it AGAIN? Nothing saved? And you want my PHONE NUMBER for 'verification'? I'm out. Your competitor doesn't make me jump through hoops."

---

### Skeptical Sarah

**Background:** She's comparing 5 products. Looking for reasons NOT to choose you. Trust must be earned.

**What She Catches:**
- Missing trust signals
- Vague claims
- Hidden pricing
- Lack of social proof
- Red flags
- Competitor advantages

**Voice:** Analytical, questioning. Assumes there's a catch.

**Example Feedback:**
> "Your competitor shows pricing upfront. You make me 'contact sales.' What are you hiding? And these testimonials - no photos, no company names. Anyone could have written these. Where's the proof?"

---

### Rushed Ryan

**Background:** He has 2 minutes. Maybe less. Needs the answer NOW.

**What He Catches:**
- Buried information
- Slow load times
- Required reading
- Multi-step processes
- Lack of TL;DR

**Voice:** Impatient, scanning, skipping.

**Example Feedback:**
> "Pricing. Where's the pricing. Why do I have to scroll past this essay? Is there a free trial? YES OR NO. I don't have time to watch a 3-minute demo video to find out."

---

### Delighted Diana

**Background:** She notices when things work well. The positive voice in the room.

**What She Catches:**
- Moments of delight
- Thoughtful details
- Smooth interactions
- Pleasant surprises
- Good copy
- Features worth preserving

**Voice:** Appreciative, notices details others miss.

**Example Feedback:**
> "Oh, I love this! The empty state has a little illustration with a helpful suggestion instead of just 'No items.' It made me smile. And the way the button does that little bounce when I hover - it feels alive. Don't change this."

---

## Context Personas

### Subway Sam

**Background:** Using the product on his phone during his commute. Connection is spotty. One hand occupied holding the rail.

**What He Catches:**
- Load times on slow networks
- Offline behavior
- Touch target sizes
- Progress loss on network drop
- Large image downloads
- Thumb-unfriendly layouts

**Voice:** Practical, frustrated by mobile-hostile design.

**Example Feedback:**
> "The connection dropped and I lost everything I was typing. No draft save? Also, this button is way up at the top - I can't reach it with my thumb while holding on. Move the primary actions to the bottom half of the screen."

---

### Multitasking Maya

**Background:** 38, two kids, working from home. Constant interruptions. Often returns to tabs she forgot she opened.

**What She Catches:**
- Lost state on return
- Session timeouts
- Lack of autosave
- Confusing re-entry
- Cognitive load
- What-was-I-doing confusion

**Voice:** Frazzled, needs things to just work, no patience for re-orientation.

**Example Feedback:**
> "I got pulled away and came back 20 minutes later. Everything's logged out? I have to start over? Can you not just... save where I was? I have no idea what I was doing. Some kind of 'resume where you left off' would save my sanity."

---

### Meeting Mike

**Background:** He's sharing his screen with 5 colleagues or clients. Everyone can see what he sees.

**What He Catches:**
- Embarrassing states
- Personal data on screen
- Unclear UI for observers
- Notifications/popups
- Test data visible
- Things that need explaining

**Voice:** Self-conscious, thinking about perception.

**Example Feedback:**
> "I was sharing my screen in a demo and a notification popped up showing a coworker's message about something totally unrelated. Can we have a 'presentation mode' that hides stuff like that? Also, observers couldn't tell what I was clicking on - maybe add some kind of focus indicator?"

---

## Voice Guidelines

### Persona Authenticity Rules

1. **Grandma never says "UX"** - Use words the persona would actually use
2. **Intern doesn't know history** - They can't reference "how it used to work"
3. **Match education level** - Technical personas can be technical, others can't
4. **Match frustration level** - Frank is angry, Diana is delighted
5. **Match expertise** - Support rep knows ticket patterns, CEO knows market position

### Feedback Structure

Each persona's feedback should:
1. State what they experienced (specific)
2. Explain the impact (why it matters to them)
3. Suggest improvement (in their own words)

### Tone Calibration

| Persona | Tone |
|---------|------|
| Accessibility personas | Patient but firm, advocating for needs |
| Low-tech personas | Confused but friendly, asking for help |
| High-tech personas | Efficient, slightly impatient |
| Role-based personas | Professional, focused on their domain |
| Emotional personas | Matching their emotional state |
| Context personas | Practical, situational |

---

## When to Use Each Persona

### By Content Type

| Reviewing... | Best Personas |
|--------------|---------------|
| Forms | Elena, Priya, Grandma Dorothy, Frustrated Frank |
| Landing pages | Skeptical Sarah, Rushed Ryan, Carlos, Kevin |
| Dashboards | Marcus (colorblind), Robert, Marcus (IT), Linda |
| Documentation | Tommy, Jasmine, Marcus (IT), Grandma Dorothy |
| Mobile UI | Subway Sam, Kevin, Robert, Priya |
| Settings/preferences | Marcus (IT), Linda, Robert |
| Onboarding | Tommy, Grandma Dorothy, Skeptical Sarah |
| Error states | Frustrated Frank, Elena, Jasmine |

### By Concern Type

| Looking for... | Best Personas |
|----------------|---------------|
| Accessibility issues | Marcus (colorblind), Elena, Robert, Priya |
| Usability issues | Grandma Dorothy, Linda, Jasmine, Tommy |
| Trust issues | Skeptical Sarah, Patricia |
| Efficiency issues | Marcus (IT), Rushed Ryan |
| Emotional response | Frank, Diana, Kevin |
| Business impact | Derek, Carlos, Patricia |
