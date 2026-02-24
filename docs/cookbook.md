# PromptyUI Cookbook

Real problems. Real prompts. Real output.

---

## "I keep copy-pasting the same prompt with small changes"

**You write:**
```
A cozy cabin in the mountains during __season__, __style__ painting
```

**Wildcards:**
- `season`: autumn, winter, spring, summer
- `style`: watercolor, oil, digital, pencil sketch

**You get (16 prompts, zero copy-paste):**
```
A cozy cabin in the mountains during autumn, watercolor painting
A cozy cabin in the mountains during autumn, oil painting
A cozy cabin in the mountains during autumn, digital painting
A cozy cabin in the mountains during autumn, pencil sketch painting
A cozy cabin in the mountains during winter, watercolor painting
A cozy cabin in the mountains during winter, oil painting
...
A cozy cabin in the mountains during summer, pencil sketch painting
```

**How:** Type `__season__` in the editor. A popover opens — add your values. Every `__wildcard__` becomes a dimension. PromptyUI generates every combination automatically.

---

## "I need 40 on-brand variations for a campaign"

**You write:**
```
A __tone__ advertisement targeting __audience__ for __platform__,
showcasing our new product line, emphasize __value_prop__
```

**Wildcards:**
- `tone`: professional, playful
- `audience`: Gen Z, B2B decision makers, creative professionals
- `platform`: Instagram Story, LinkedIn Post, Twitter/X, Email Header
- `value_prop`: innovation, reliability, community

**You get:** 2 x 3 x 4 x 3 = **72 prompts.**

**But you only need 12 right now?** Ctrl+Click "Gen Z" to lock it. Now you're working with just the 24 Gen Z variations. Lock "professional" too — down to 12. Export those, unlock, lock the next audience, repeat.

---

## "I have 6 art styles I reuse across every prompt"

**The problem:** You maintain the same style list in 10 different prompts. You add "Art Deco" to one and forget the other 9.

**The fix:** Put your styles in a theme file once:

```yaml
# ext/my-styles/portrait.yaml
text:
  - "in the style of Studio Ghibli, soft lighting"
  - "in the style of Moebius, high contrast linework"
  - "cyberpunk aesthetic, neon rim lighting"
  - "Art Nouveau, ornate framing"
  - "dark fantasy, dramatic chiaroscuro"
  - "Art Deco, geometric patterns, gold accents"
wildcards:
  - name: mood
    text: [serene, intense, mysterious, playful]
```

**Any prompt** can reference this theme. When you add "Ukiyo-e" to the theme, all 10 prompts get it automatically. No copy-paste, no version drift.

**How:** Add an `ext_text` block in your prompt → pick the theme file. Done. The theme's text entries become variations, and its wildcards merge into your wildcard pool.

---

## "I want to see only the blocks that use a specific wildcard"

**The problem:** Your prompt has 12 blocks but only 4 use `__lighting__`. You're reviewing lighting variations and the other 8 blocks are visual noise.

**The fix:** Click the bulb icon next to `lighting` in the right panel. Blocks without `__lighting__` dim out. A banner shows "Focused on: lighting (4 of 12 blocks)."

Click another bulb (say `mood`) — now you see blocks with lighting OR mood. Click a bulb again to turn it off.

---

## "I need the same prompt but for different clients"

**You write one base prompt:**
```
A __tone__ product shot of __product__ for the __brand__ campaign
```

**With generic wildcard values:**
- `tone`: neutral, energetic, minimal
- `brand`: generic

**Then you create operations** (a type of build hook — value replacement):

```yaml
# operations/client-acme.yaml
mappings:
  brand:
    generic: ACME Corp
  tone:
    neutral: bold and energetic

# operations/client-zen.yaml
mappings:
  brand:
    generic: ZenLife
  tone:
    neutral: calm and minimal
```

**You get:** Select `client-acme` → export ACME batch. Select `client-zen` → export ZenLife batch. One prompt, zero duplication.

**Also works for:** Localization (swap English values for Spanish), A/B testing (swap key phrases between variants), seasonal campaigns (swap "summer" vocabulary for "winter").

**How it fits:** Operations are **build hooks** — they appear in the build flow diagram and transform the pipeline before compositions resolve.

---

## "I have 200 prompts and 8 wildcards each — the UI chokes"

**The math:** 8 wildcards x 6 values each = 1,679,616 combinations. You can't scroll through that.

**The fix — bucketing:** Set `wildcards_max: 3`. Every wildcard with >3 values is sliced into windows:

```
role (6 values) → window 1: [junior, mid, senior]  window 2: [staff, principal, fellow]
tone (4 values) → window 1: [casual, formal, playful]  window 2: [technical]
```

Now you're working with 3 x 3 = 9 compositions at a time. Navigate between windows systematically. Export each window, move to the next.

**Need one wildcard unbucketed?** Override it: set `role` to show all 6 while everything else stays bucketed at 3.

---

## "My prompt has multiple sections that each vary independently"

**You write:**
```
Block 0: [SCENE]
  Block 0.0: Setting: __location__ at __time_of_day__
  Block 0.1: Weather: __weather__
Block 1: [CHARACTER]
  Block 1.0: A __age__ __profession__ wearing __outfit__
  Block 1.1: Expression: __emotion__
Block 2: [CAMERA]
  Block 2.0: __shot_type__, __lens__mm, __lighting__
```

**You get:** Each section varies independently. The output concatenates all sections:

```
Setting: a misty forest at golden hour, Weather: light rain,
A young blacksmith wearing leather apron, Expression: determined,
medium shot, 85mm, dramatic side lighting
```

**Power move:** The CAMERA section is reusable. Move it to a theme (`ext/defaults/camera.yaml`) and reference it from any prompt. Now every character prompt, landscape prompt, and product prompt shares the same camera settings.

---

## "I built great wildcards inline — now I want to share them"

**The lifecycle:**

```
1. CREATE       Type __seniority__ → add: Junior, Mid, Senior
2. ITERATE      Test it. Add Staff and Principal.
3. PROMOTE      Context menu → Move to Theme → ext/hiring/roles.yaml
4. MAINTAIN     Add "Fellow" locally → push icon pulses orange →
                click → Push to Theme → theme updated
5. SYNC         Another prompt references hiring/roles →
                gets "Fellow" automatically on next load
```

This is the full journey from inline experiment to shared infrastructure. No files to manually edit, no YAML to hand-write.

---

## "I closed my browser and lost all my locks and settings"

**What's saved when you click Save Session:**
- Which composition you were looking at
- Which values were locked
- Which operation was active
- Bucketing settings
- Per-block wildcard overrides
- Which wildcards were focused

**What happens next:** Close browser. Come back tomorrow. Select the same job and prompt. Everything restores exactly where you left it.

---

## "I want to send a teammate the exact composition I'm looking at"

**Copy the URL:**
```
http://localhost:8085/?job=game-assets&prompt=boss-fight&composition=42&viz=compact
```

They open it → same job, same prompt, same composition, same visualizer. No "go to job X, then click prompt Y, then navigate to..." instructions.

Add `&focus=0.1` to open directly into the focus editor on block 0.1.

---

## "I want to swap one theme for another without breaking things"

**The problem:** Your prompt uses `portrait-styles.yaml` which defines `__mood__` and `__palette__`. You want to try `landscape-styles.yaml` instead, but it might not have the same wildcards.

**The fix:** Click **Swap** on the theme block. Hover over `landscape-styles` — a diff popover shows:
- **Mapped:** `mood` exists in both (safe)
- **Orphaned:** `palette` exists in current but not target (your `__palette__` references will break)
- **New:** `atmosphere` exists in target but not current (new wildcard available)

You see the risk before you commit. Swap or cancel.

---

## "I need to export 500 compositions for our rendering farm"

**Two export paths:**

**YAML export** (via Export button):
1. Set your locks and bucketing to define the output window
2. Click Export → see a YAML preview with validation (errors in red, warnings in yellow)
3. Fix any issues → Save to File or Download

**Text export** (via Build panel):
1. Open Build Composition → check the estimate: "500 compositions x ~120 chars = ~60 KB"
2. Click Export .txt → client-side generation, instant download
3. Output format:
   ```
   ---
   Composition 42: tone=formal role=engineer seniority=senior
   ---
   A formal job posting for a senior engineer...
   ```

Every composition is addressable by its integer ID. ID 42 always resolves to the same combination of values — deterministic, reproducible, exportable.

---

## "I want to browse variations without reading walls of text"

**Five visualizer modes:**

| Mode | Best for | What it does |
|------|----------|-------------|
| **Compact** | Deliberate selection | Click chips to preview specific combinations |
| **Typewriter** | Reading flow | Values type themselves out, cascading by block depth |
| **Reel** | Discovery | Slot-machine scroll through values |
| **Stack** | Comparison | Card-flip animation between values |
| **Ticker** | Ambient | Horizontal scroll marquee |

Switch modes from the prompt header dropdown. The visualizer doesn't change the data — just how you browse it.

---

## "I want PromptyUI to generate images, not just export text"

**The pipeline:** PromptyUI handles the Cartesian explosion. Your script handles one image at a time.

```yaml
# jobs/product-shoots/hooks.yaml
hooks:
  pre:
    - script: hooks/token_budget_check.py
  generate:
    - script: hooks/comfyui_generate.py
      params:
        workflow: product_photo_v3.json
        output_dir: outputs/product-shoots
  post:
    - script: hooks/watermark_and_catalog.py
  node_end:
    - script: hooks/upload_to_cdn.py
```

Your `generate` script receives `context['resolved_text']`, `context['prompt_id']`, and `context['composition_id']`. It sends the prompt to ComfyUI (or DALL-E, or Stable Diffusion), waits for the image, and returns:

```python
def execute(context, params):
    image_path = send_to_comfyui(context['resolved_text'], params['workflow'])
    return { 'status': 'success', 'data': { 'image_path': image_path } }
```

The `pre` hook checks token budget before wasting a GPU call. The `post` hook adds watermarks. The `node_end` hook bulk-uploads to CDN when all compositions for a block are done.

**The engine doesn't care** what your `generate` script does. It could call ComfyUI, copy a file, or hit an external API. The stage name is a convention — `execute_hook('generate', ctx)` just runs whatever's configured.

---

## "I want quality gates that reject prompts before generation"

**The problem:** You're generating 500 images but some prompts have debug text, exceed token limits, or are missing required annotations.

**The fix:** Add a `pre` hook that validates before `generate` runs:

```yaml
hooks:
  pre:
    - script: hooks/quality_gate.py
      params:
        max_tokens: 300
        banned_phrases: ["test", "placeholder", "TODO"]
        require_annotations: ["output_format"]
```

```python
def execute(context, params):
    text = context['resolved_text']
    tokens = count_tokens(text)
    if tokens > params['max_tokens']:
        return { 'status': 'error', 'message': f'Token budget exceeded: {tokens}/{params["max_tokens"]}' }
    for phrase in params.get('banned_phrases', []):
        if phrase.lower() in text.lower():
            return { 'status': 'error', 'message': f'Banned phrase found: {phrase}' }
    return { 'status': 'success' }
```

Error = block fails cleanly. Remaining compositions for that block are skipped, children are blocked. No GPU wasted.

---

## "I want translations without maintaining translated prompts"

**The problem:** You maintain the same prompt in 4 languages. You edit the English version, then forget to update Japanese.

**The fix:** One English source of truth + a translator mod:

```yaml
# mods.yaml
mods:
  prompt-translator:
    script: ./mods/prompt_translator.py
    stage: [build, pre]
    auto_run: true
    params:
      languages: [ja, es, fr, de]
      cache_dir: .cache/translations
```

At `build` time (`stage: build`), the translator pre-computes translations and caches them. At `pre` (generation time), it swaps English for the target language from cache — instant, no API call.

**One mod, two invocation paths.** The mod checks `context['hook']` to distinguish: `hook == 'mods_build'` → precompute. `hook == 'pre'` → swap from cache.

---

## "I want to auto-flag bad generations"

**The problem:** You generated 500 images. 30 have distorted faces, 12 are low quality. You don't want to review all 500.

**The fix:** A `post` hook that classifies each output:

```yaml
hooks:
  post:
    - script: hooks/visual_qa.py
      params:
        min_aesthetic_score: 6.0
        check_faces: true
```

```python
def execute(context, params):
    image_path = context.get('image_path')  # from generate hook's data
    score = aesthetic_scorer(image_path)
    flags = []
    if score < params['min_aesthetic_score']:
        flags.append('low_quality')
    if params.get('check_faces') and detect_distorted_faces(image_path):
        flags.append('distorted_face')
    if flags:
        return { 'status': 'error', 'data': { 'score': score, 'flags': flags } }
    return { 'status': 'success', 'data': { 'score': score } }
```

**Error = children blocked.** If the parent "character portrait" produced a distorted face, there's no point generating the "character in action scene" children from it. Failure is path-scoped.

---

## "I want to A/B test aesthetic directions at scale"

**The setup:** Same prompt, same wildcards, different aesthetic direction via operations:

```yaml
# operations/ab-warm-tones.yaml
mappings:
  lighting:
    natural: warm golden hour
    studio: warm studio with orange gels
  mood:
    neutral: cozy and inviting

# operations/ab-cool-tones.yaml
mappings:
  lighting:
    natural: cool overcast daylight
    studio: cool studio with blue gels
  mood:
    neutral: crisp and modern
```

Select `ab-warm-tones` in the build flow → export 500 images. Switch to `ab-cool-tones` → export 500 more. **Same prompt, zero duplication.** Show both sets to the client. The operation's filename becomes the variant family label in the output.

---

## How it all fits together

```
YOU WRITE                          YOU GET
─────────────                      ────────
1 prompt template                  Every combination
with __wildcards__                 as separate prompts
         │
         ├── Wildcards (your variables and their values)
         │     └── 3 subjects x 4 styles x 5 lighting = 60 prompts
         │
         ├── Themes (shared variable packs in ext/ files)
         │     └── Reuse across prompts, auto-sync updates
         │
         ├── Bucketing (work in manageable windows)
         │     └── See 9 at a time instead of 1.6 million
         │
         ├── Locks (pin specific values for targeted export)
         │     └── Only Gen Z + professional? Lock them, export 12.
         │
         ├── Hooks (extend the pipeline at three locations)
         │     ├── Editor hooks: UI widgets, token counters while editing
         │     ├── Build hooks: operations, quality gates when assembling
         │     └── Render hooks: annotations, validation when output resolves
         │
         └── Export (YAML or txt, to file or download)
               └── Every composition has a unique ID — deterministic, reproducible
```

---

## Glossary

| Term | What it means |
|------|--------------|
| **Wildcard** | A variable in your prompt (`__style__`). Each one has a list of values. |
| **Theme** | A YAML file in `ext/` with reusable text and wildcards. Reference it from any prompt. |
| **Composition** | One specific combination of wildcard values. Addressed by an integer ID. |
| **Bucket** | A window of wildcard values. `wildcards_max: 3` shows 3 values at a time. |
| **Editor hook** | A hook in the prompt editor — adds UI elements while you write (token counter, live preview). |
| **Build hook** | A hook in the build flow diagram — transforms the pipeline (operations, quality gates). |
| **Render hook** | A hook on resolved output — fires per composition (annotation alerts, token budget). |
| **Operation** | A build hook that remaps values. "casual" → "corporate" without editing the prompt. |
| **Hook** | A script in `hooks.yaml`. The engine is dumb: `execute_hook(name, ctx)` runs whatever's configured. Stage names (`pre`, `generate`, `post`) are conventions, not engine code. |
| **Mod** | A script in `mods.yaml`. Same execution path as hooks, but with guards (stage, scope, filters). Can also run at build time (`stage: build`). |
| **Lock** | Pin a wildcard value (Ctrl+Click). Limits the output to only compositions with that value. |
| **Focus** | Bulb toggle that dims blocks not using a wildcard. Filters your attention. |
| **Push to Theme** | Sync your local wildcard edits back to the shared theme file. |
| **Move to Theme** | Convert an inline block into a theme reference. Creates the theme file for you. |
| **Dissolve** | Reverse of Move to Theme. Converts a theme reference back to inline content. |
| **Swap** | Replace one theme reference with another. Shows a diff of wildcard changes before you commit. |
