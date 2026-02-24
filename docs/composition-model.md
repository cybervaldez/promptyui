# Composition Model

How prompts, wildcards, ext_text, buckets, and hooks work together to generate prompt variations at scale.

---

## The Problem

You have a prompt template:

```
Write a __tone__ recruiting email for __role__ at a __stage__ startup
```

Each wildcard (`__tone__`, `__role__`, `__stage__`) has multiple values. The **Cartesian product** of all values produces every unique combination:

```
tone(3) x role(3) x stage(4) = 36 compositions
```

At 36, this is manageable. But real prompts have 5-10 wildcards with 5-20 values each, plus extension text blocks. The space explodes:

```
5 wildcards x 10 values each = 100,000 compositions
+ 6 ext_text values          = 600,000 compositions
```

You can't generate 600K prompts. You can't review them. You can't navigate them one by one.

The composition model solves this with **three independent layers plus hooks** that each reduce or reshape the space:

```
WILDCARDS + EXT_TEXT ──> BUCKETS ──> HOOKS ──> CARTESIAN PRODUCT ──> OUTPUT
(what)                   (how much)  (extend)  (enumerate)           (files)
```

---

## Layer 1: Wildcards

Wildcards are template variables with multiple values. They're defined inline with the prompt.

### YAML

```yaml
- id: "outreach-email"
  text:
    - content: "Write a __tone__ recruiting email for __role__ at a __stage__ startup"
  wildcards:
    - name: "tone"
      text: ["casual", "professional", "enthusiastic"]
    - name: "role"
      text: ["engineer", "designer", "PM"]
    - name: "stage"
      text: ["seed", "Series A", "Series B", "growth"]
```

### How it works

The build engine takes the Cartesian product of all wildcard values:

```
casual      x engineer x seed       → "Write a casual recruiting email for engineer at a seed startup"
casual      x engineer x Series A   → "Write a casual recruiting email for engineer at a Series A startup"
casual      x engineer x Series B   → ...
...
enthusiastic x PM      x growth     → (last combination)

Total: 3 x 3 x 4 = 36 compositions
```

Each composition has a numeric ID (0-35). The **odometer** maps IDs to value indices — the rightmost wildcard (alphabetically sorted) ticks fastest:

```
Composition 0  → role=designer,  stage=growth,       tone=casual
Composition 1  → role=designer,  stage=seed,         tone=casual
Composition 2  → role=designer,  stage=Series A,     tone=casual
Composition 3  → role=designer,  stage=Series B,     tone=casual
Composition 4  → role=engineer,  stage=growth,       tone=casual
...
```

### Nesting

Prompt blocks can nest via `after:`. Children are appended to their parent text:

```yaml
text:
  - content: "You are a __tone__ HR consultant"
  - content: "Draft a job brief for a __role__ position"
    after:
      - content: "Include requirements for __years_exp__ years of experience"
```

This produces: `"You are a __tone__ HR consultant\nDraft a job brief for a __role__ position\nInclude requirements for __years_exp__ years of experience"` — with wildcards expanded across all levels.

---

## Layer 2: Extension Text (ext_text)

Extension text blocks are **reusable text lists** stored in the `ext/` folder. A prompt can reference them instead of inlining content.

### Theme file

```yaml
# ext/hiring/roles.yaml
id: "roles"
text:
  - "Software Engineer"
  - "Product Manager"
  - "Designer"
  - "Data Scientist"
  - "DevOps Engineer"
  - "Engineering Manager"
wildcards:
  - name: "seniority"
    text: ["Junior", "Mid-level", "Senior", "Staff", "Principal"]
```

A theme file has:
- **text**: A list of text values (like a multi-valued wildcard, but for whole text blocks)
- **wildcards**: Additional wildcard dimensions that come along with the theme

### Referencing ext_text in a prompt

```yaml
- id: "ext-sourcing-strategy"
  ext: "hiring"
  text:
    - content: "Create a sourcing strategy for __channel__ recruitment"
    - ext_text: "hiring/roles"
      ext_text_max: 3
      after:
        - content: "For each role, suggest __count__ __approach__ outreach tactics"
  wildcards:
    - name: "channel"
      text: ["inbound", "outbound", "referral", "campus"]
    - name: "count"
      text: ["2", "3", "5"]
    - name: "approach"
      text: ["personalized", "automated", "hybrid"]
```

### What happens

1. `ext_text: "hiring/roles"` loads the 6 text values from `ext/hiring/roles.yaml`
2. The `seniority` wildcard from `roles.yaml` **merges into the prompt's wildcard pool** — it becomes another dimension in the Cartesian product
3. `ext_text_max: 3` limits to 3 text values per bucket (see Layer 3)

The composition space is now:

```
ext_text(6) x channel(4) x count(3) x approach(3) x seniority(5) = 1,080 compositions
             ↑ local wildcards ↑                     ↑ from theme ↑
```

Theme wildcards appear in the right panel under "from themes" — they work identically to local wildcards but their origin is visible.

### Multiple themes

A prompt can reference multiple theme files. Each adds its text values and wildcards:

```yaml
text:
  - ext_text: "hiring/roles"        # 6 texts + seniority(5)
  - ext_text: "hiring/frameworks"   # 5 texts + evaluation_focus(5) + interview_style(4)
```

All wildcards merge into one pool. The Cartesian product spans everything.

---

## Layer 3: Buckets (Windowing)

Buckets tame the Cartesian explosion by grouping values into **windows**.

### The problem buckets solve

With 1,080 compositions, you can't:
- Generate all of them (API cost)
- Navigate through them one by one (too slow)
- Review all outputs (cognitive overload)

### How bucketing works

`wildcards_max: 3` divides each wildcard into windows of 3 values:

```
seniority has 5 values: [Junior, Mid-level, Senior, Staff, Principal]

Bucket 0: [Junior, Mid-level, Senior]     (indices 0-2)
Bucket 1: [Staff, Principal]              (indices 3-4)

→ ceil(5/3) = 2 buckets for seniority
```

The **bucket-composition** count is the product of bucket counts, not raw value counts:

```
ext_text: ceil(6/3) = 2 buckets
channel:  ceil(4/3) = 2 buckets
count:    ceil(3/3) = 1 bucket
approach: ceil(3/3) = 1 bucket
seniority: ceil(5/3) = 2 buckets

Bucket-compositions: 2 x 2 x 1 x 1 x 2 = 8  (down from 1,080)
```

Each bucket-composition identifies a **window** across all wildcards. Within that window, you see `wcMax` values per wildcard and can pick any of them via a dropdown.

### YAML

```yaml
defaults:
  wildcards_max: 3          # global bucket size

prompts:
  - id: "my-prompt"
    wildcards_max: 3        # per-prompt override (optional)
    text:
      - ext_text: "hiring/roles"
        ext_text_max: 3     # per-block ext_text bucket size
```

### Navigation model

```
Bucket nav (coarse):    ◄ 1 of 8 ►        ← jumps between windows
Dropdown (fine):        [Junior ▼]          ← picks within current window
                        [Mid-level]
                        [Senior]
```

The composition navigator moves between bucket-combinations. The per-wildcard dropdown lets you pick a specific value within the current bucket's window.

### Build-time behavior

When building via `build-job.py`, `wildcards_max` **caps each wildcard** to its first N values:

```python
if wildcards_max > 0 and len(wc_values) > wildcards_max:
    wc_values = wc_values[:wildcards_max]
```

So `wildcards_max: 3` with `seniority(5)` → build uses only `[Junior, Mid-level, Senior]` for that batch. To build with `[Staff, Principal]`, navigate to the next bucket.

---

## Layer 4: Hooks

Hooks extend the pipeline at **three locations**, named by where they appear in the UI. A beginner reads the name and knows exactly where to look.

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   EDITOR HOOK   │      │   BUILD HOOK    │      │  RENDER HOOK    │
│   ✏️ editing     │      │   🔨 assembling  │      │  ▶️ resolving    │
│                 │      │                 │      │                 │
│ Lives in the    │ ──→  │ Lives in the    │ ──→  │ Lives on the    │
│ prompt editor   │      │ flow diagram    │      │ resolved output │
│                 │      │                 │      │                 │
│ Examples:       │      │ Examples:       │      │ Examples:       │
│ • Token counter │      │ • Operations    │      │ • Annotations   │
│ • UI widgets    │      │ • Quality gates │      │ • Validation    │
│ • Live preview  │      │ • Template merge│      │ • Token budget  │
│ • Inline alerts │      │ • Filter combos │      │ • A/B variants  │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

### Editor hooks

Editor hooks inject UI elements into the **prompt editor canvas** — they run while you're writing and editing blocks.

| Hook | What it does |
|------|-------------|
| Token counter | Shows live token count as you type |
| UI widget | Custom input element inside a block |
| Live preview | Real-time preview of resolved output |
| Inline alert | Contextual warnings or info badges |

Editor hooks don't change the composition space. They enhance the editing experience.

### Build hooks

Build hooks transform the **pipeline structure** — they run when the build flow diagram is assembled. The most common build hook is an **operation** (value replacement).

#### Operations (value replacement)

Operations are **named YAML files** that replace wildcard values within a bucket window. They're applied after bucketing, before the Cartesian product.

**The problem operations solve:** With buckets, your window is always a contiguous range. But sometimes you want non-contiguous selections:

```
seniority values: [Junior, Mid-level, Senior, Staff, Principal]
You want: [Junior, Senior, Principal]  — not contiguous!
```

Operations keep the bucket as the only model by **replacing** values within a window:

```
Window (wcMax=3): [Junior, Mid-level, Senior]

Operation "senior-focus":
  Mid-level → Staff
  Senior → Principal

Effective window: [Junior, Staff, Principal]
```

**Operation YAML:**

```yaml
# operations/english-to-japan.yaml
id: "english-to-japan"
name: "English to Japanese"
mappings:
  tone:
    formal: "丁寧"
    casual: "カジュアル"
    urgent: "緊急"
  audience:
    board: "取締役会"
    investors: "投資家"
```

**The pipeline with a build hook (operation):**

```
Prompt YAML          Buckets              Build Hook           Output
┌─────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ tone(5)     │    │ window [0:3] │    │ operation:   │    │ 3 x 4 = 12  │
│ audience(4) │ →  │ tone: 3 vals │ →  │ formal→丁寧  │ →  │ compositions │
│ ext_text(6) │    │ aud: 4 vals  │    │ casual→普通  │    │ with Japanese │
│             │    │ ext: 3 vals  │    │              │    │ tone values   │
└─────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
   L1+L2              L3: BUCKETS        L4: BUILD HOOK       OUTPUT
```

**Variant families:** An operation's filename is its **variant family** name. Applying different operations produces distinct variant families:

```
operations/english.yaml       → variant family "english"       → 12 EN compositions
operations/japanese.yaml      → variant family "japanese"      → 12 JP compositions
```

#### Other build hooks

| Hook | What it does |
|------|-------------|
| Quality gate | Skip nonsense combinations (e.g., `formal` + `meme`) |
| Template merge | Inject shared system prompt before expansion |
| Filter | Exclude specific wildcard combinations from the space |
| Custom resolver | Dynamic wildcard values (e.g., today's date) |

Build hooks appear as nodes in the build flow diagram, showing how they transform the pipeline.

### Render hooks

Render hooks fire when a **specific composition resolves** — they react to the output of one path through the composition space.

| Hook | What it does |
|------|-------------|
| Annotation alert | Shows block annotations when a leaf is reached |
| Token budget | Warns if resolved text exceeds a token limit |
| A/B variant | Splits output between variant A and B per composition ID |
| Output validation | Checks resolved text against rules or patterns |

Render hooks appear **below leaf nodes** in the build flow diagram. They don't change the composition space — they react to individual instances.

### Hook lifecycle

```
Editor hooks (while writing)
    → Structure finalized
        → Build hooks (pressing Build — flow diagram)
            → Composition space assembled
                → Render hooks (navigating/exporting — per composition)
                    → Output
```

### Generation-time lifecycle (pure hook-based pipeline)

The engine (`src/hooks.py`) is dumb: `execute_hook(name, ctx)` looks up `hooks.yaml` and `mods.yaml`, merges scripts, checks guards, and executes. **Stage names are caller conventions, not engine code.** The engine doesn't know what `pre`, `generate`, or `post` mean — it just runs whatever scripts are configured under that key.

```
job_start
│
├─ node_start           ← once per block (first visit)
│  └─ resolve           ← once per block (cached for all compositions)
│     │
│     ├─ pre            ← per composition (hooks + mods with guards)
│     ├─ generate       ← per composition (user-supplied script)
│     ├─ post           ← per composition (hooks + mods with guards)
│     │
│     ├─ (next composition of same block...)
│     │
│     └─ node_end       ← once per block (after last composition)
│
├─ (next block...)
│
job_end

error                   ← on any failure, at any stage
```

**Key distinction:** `generate` is just a hook name — not a built-in function. A user-supplied Python script (configured in `hooks.yaml`) does the actual work. Any external tool (ComfyUI, DALL-E, a file copier) can plug in. You could even rename it — the engine doesn't care.

### Hooks vs Mods

Both use the **same execution path** — `_execute_single_hook()` loads a Python script and calls `execute(context, params)`. Mods are hooks with guards:

| | Hooks | Mods |
|---|---|---|
| **Configured in** | `hooks.yaml` (per job) | `mods.yaml` (global) |
| **Fire at** | Any hook name | Any hook name (self-filter via guards) |
| **Guards** | None (always fire) | Stage, scope, address_index, config_index |
| **Enable/disable** | Present = active | Per-prompt via `jobs.yaml` enable/disable |
| **Purpose** | System lifecycle (start, generate, end) | User extensions (translate, log, inject) |

A mod is a hook with guardrails. Both return the same `HookResult`:

```python
def execute(context, params=None):
    return {
        'status': 'success',     # or 'error', 'skip'
        'data': {...},           # passed to next stage
        'modify_context': {...}, # merged into pipeline context
        'message': 'optional',
    }
```

### Mod configuration

Mods are defined in the global `mods.yaml` at project root:

```yaml
defaults:
  auto_run: false            # global default for auto-enabling

mods:
  error-logger:
    type: script
    script: ./mods/error_logger.py
    execution_scope: image    # checkpoint | image | both
    stage: post               # pre | post | both
    params:
      max_items: 50
    filters:
      config_index: [0, 1]    # only run on these config indices
      address_index: [1, 2]   # only run on these address indices

  prompt-translator:
    type: script
    script: ./mods/prompt_translator.py
    stage: [build, pre]       # build-time precompute + generation-time apply
    auto_run: true            # enabled by default
```

**Stage guard values:** `pre` | `post` | `both` (generation-time hook names). `build` is a separate invocation path — mods with `stage: build` or `stage: [build, pre]` run once per prompt during `build-checkpoints.py`, not during generation. The mod script checks `context['hook']` to distinguish (e.g., `hook == 'mods_build'` vs `hook == 'pre'`).

Per-prompt enable/disable in `jobs.yaml`:

```yaml
prompts:
  - id: "my-prompt"
    mods:
      enable: ["prompt-translator"]
      disable: ["error-logger"]
```

Priority resolution: `job disable > global auto_run > job enable`

### Existing mod scripts

| Mod | Stage | Scope | Pattern |
|-----|-------|-------|---------|
| `error_logger.py` | post | image | Captures generation errors, logs to UI sidebar |
| `prompt_translator.py` | build + pre | — | Pre-computes translations at build time, applies at generation |
| `config_injector.py` | build | — | Injects computed metadata (hash, timestamps) into prompt.json |
| `favorites.py` | — | job | UI bookmark — saves selected artifacts to job-level storage |

### Depth-first execution (planned)

The current `build_jobs()` produces a flat list. The planned **TreeExecutor** adds block-aware depth-first ordering:

```
Block 0 (root, 12 compositions)
  ├─ comp 0 → hooks → done
  ├─ comp 1 → hooks → done
  │   └─ Block 0.0 (child, 12 compositions)
  │       ├─ comp 0 → hooks → done
  │       ...
  │   └─ Block 0.1 (child, 36 compositions)
  │       ├─ comp 0 → hooks → done
  │       ...
  ├─ comp 2 → hooks → done
  ...
Block 1 (root, 6 compositions)
  ...
```

Key additions:
- **`parent_result`** — context key containing the parent block's `HookResult.data`, so child hooks can read parent output
- **`_block_path`** — new field in `build_jobs()` output identifying each entry's block (e.g., `"0"`, `"0.0"`, `"1"`)
- **Path-scoped failure** — when a block fails, remaining compositions are skipped and children are blocked. Siblings and other root paths continue
- **Block state machine** — `UNSEEN → ACTIVE → PARTIAL → ... → COMPLETE`. `node_start` fires on first visit, `node_end` on last composition
- **`resolve` caching** — fires once per block, result cached for all subsequent compositions

---

## Batch Export

Build hooks (operations) enable systematic batch export of massive composition spaces.

### Without build hooks

```
360K compositions → export all → one giant batch → one set of values
```

### With build hooks (operations)

```
360K compositions ÷ 729 per bucket = ~500 bucket-compositions

Export plan:
  All buckets × op: english        → 360K EN compositions
  All buckets × op: japanese       → 360K JP compositions
  Buckets 0-99 × op: client-acme   →  73K client-specific compositions
```

Each operation filename is the **variant family** name — it labels the batch. The export config specifies which buckets and which variant family.

---

## How the Layers Compose

Each layer is independent and optional:

| Layer | Config | Default | Effect |
|-------|--------|---------|--------|
| Wildcards | `wildcards:` in prompt | Required | Defines dimensions |
| ext_text | `ext_text:` in text blocks | Optional | Adds dimensions from themes |
| Buckets | `wildcards_max:` / `ext_text_max:` | 0 (no bucketing) | Windows the space |
| Editor hooks | Editor hook config | None | Enhance editing experience |
| Build hooks | `operations/*.yaml`, hook config | None | Transform the pipeline |
| Render hooks | Block annotations, hook config | None | React to resolved output |

### Example: Full pipeline

```yaml
# Prompt defines structure
- id: "sourcing-strategy"
  ext: "hiring"
  wildcards_max: 3
  text:
    - content: "Create a sourcing strategy for __channel__ recruitment"
    - ext_text: "hiring/roles"
      ext_text_max: 3
      after:
        - content: "For each role, suggest __count__ __approach__ outreach tactics"
  wildcards:
    - name: "channel"
      text: ["inbound", "outbound", "referral", "campus"]
    - name: "count"
      text: ["2", "3", "5"]
    - name: "approach"
      text: ["personalized", "automated", "hybrid"]
```

**Layer 1 (Wildcards):** 4 local wildcards: channel(4), count(3), approach(3), plus the prompt structure.

**Layer 2 (ext_text):** `ext_text: "hiring/roles"` adds 6 text values + seniority(5) wildcard from theme. Total dimensions: 6 × 4 × 3 × 3 × 5 = 1,080 compositions.

**Layer 3 (Buckets):** `wildcards_max: 3` reduces each dimension:
```
ext_text: ceil(6/3) = 2, channel: ceil(4/3) = 2, count: 1, approach: 1, seniority: ceil(5/3) = 2
Total: 2 x 2 x 1 x 1 x 2 = 8 bucket-compositions
```

**Layer 4 (Hooks):** Apply `operations/english-to-japan.yaml` (a build hook) to replace values in the current window. Editor hooks may have added UI widgets during editing. Render hooks fire per-composition for annotation alerts or validation.

**Output:** Generate 3 × 3 × 3 × 3 × 3 = 243 compositions per bucket, with hook-modified values.

---

## File Structure

```
project/
├── mods.yaml                      # Global mod definitions (stage, scope, filters)
├── mods/                          # Mod scripts (user extensions)
│   ├── error_logger.py            # Post-generation error logging
│   ├── prompt_translator.py       # Build+pre translation pattern
│   ├── config_injector.py         # Build-time metadata injection
│   └── favorites.py               # UI bookmark mod
├── jobs/
│   └── hiring-templates/
│       ├── jobs.yaml              # Prompt definitions (Layer 1) + per-prompt mod enable/disable
│       ├── hooks.yaml             # Job-level hook config (lifecycle scripts)
│       ├── operations/            # Build hooks: value replacement mappings
│       │   ├── english-to-japan.yaml
│       │   └── brand-acme.yaml
│       └── outputs/               # Generated files
│           └── composition/
│               ├── c00000.yaml    # Compositions 0-499
│               └── c00500.yaml    # Compositions 500-999
├── ext/                           # Reusable themes (Layer 1 + 2)
│   ├── hiring/
│   │   ├── roles.yaml            # 6 roles + seniority wildcard
│   │   └── frameworks.yaml       # 5 frameworks + evaluation wildcards
│   └── professional/
│       └── tones.yaml            # 4 tones + audience wildcard
├── src/
│   ├── hooks.py                   # HookPipeline — generation-time lifecycle engine
│   ├── jobs.py                    # build_jobs() — Cartesian product engine
│   ├── variant.py                 # build_variant_structure() — build orchestrator
│   └── segments.py                # SegmentRegistry — ext/wildcard lookups
└── webui/prompty/                 # Web UI
    └── js/
        ├── preview.js            # Odometer, bucketing, composition math
        ├── right-panel.js        # Wildcard display, navigation
        └── build-composition.js  # Shared computation, export
```

---

## Key Terminology

| Term | Meaning |
|------|---------|
| **Composition** | One specific combination of values across all wildcard dimensions |
| **Composition ID** | Numeric index (0-based) identifying a composition in the Cartesian product |
| **Odometer** | The algorithm that maps composition IDs to value indices (mixed-radix decomposition) |
| **Bucket** | A contiguous window of values within a wildcard dimension |
| **Bucket-composition** | A combination of bucket indices across all dimensions |
| **ext_text** | Extension text block — a list of text values loaded from a theme file |
| **Theme** | A YAML file in `ext/` providing text values and wildcards |
| **Theme wildcard** | A wildcard that comes from a theme file (not defined in the prompt) |
| **Editor hook** | A hook in the prompt editor — injects UI elements while writing (token counter, widgets, alerts) |
| **Build hook** | A hook in the build flow diagram — transforms the pipeline structure (operations, quality gates, filters) |
| **Render hook** | A hook on composition output — fires when a composition resolves (annotations, validation, A/B splits) |
| **Operation** | A type of build hook — a named value-replacement mapping applied to a bucket window |
| **Variant family** | The operation's filename/title — labels the output batch (e.g., `operations/english-to-japan.yaml` → variant family "english-to-japan") |
| **Window** | The slice of values visible in the current bucket (`[start, start + wcMax - 1]`) |
| **wcMax** | `wildcards_max` — the bucket size for wildcards |
| **extTextMax** | `ext_text_max` — the bucket size for extension text lists |
| **Hook** | A script configured in `hooks.yaml`. The engine is dumb: `execute_hook(name, ctx)` runs whatever's configured. Stage names (`pre`, `generate`, `post`) are conventions |
| **Mod** | A script configured in `mods.yaml`. Same execution path as hooks, but with guards (stage, scope, filters) checked before execution |
| **HookResult** | Return value from any hook/mod script: `{ status, data, modify_context, error, message }` |
| **parent_result** | (Planned) Context key containing parent block's `HookResult.data`, passed to child block hooks |
| **TreeExecutor** | (Planned) Block-aware depth-first execution engine. Replaces the flat job list with ordered per-block traversal |
