# Composition Model

How prompts, wildcards, ext_text, buckets, and operations work together to generate prompt variations at scale.

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

The composition model solves this with **three independent layers** that each reduce or reshape the space:

```
STRUCTURE ──> BATCHING ──> TRANSFORMS ──> CARTESIAN PRODUCT ──> OUTPUT
(what)        (how much)   (which values)  (enumerate)          (files)
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

## Layer 4: Operations (Value Transforms)

> **Status: Planned** — Operations are designed but not yet implemented.

Operations are **named YAML files** that replace wildcard values within a bucket window. They're applied after bucketing, before the Cartesian product.

### The problem operations solve

With buckets, your window is always a **contiguous range** of values. But sometimes you want non-contiguous selections:

```
seniority values: [Junior, Mid-level, Senior, Staff, Principal]
You want: [Junior, Senior, Principal]  — not contiguous!
```

Filtering (selecting/deselecting individual values) creates a second mental model layered on top of buckets. Operations keep the bucket as the only model by **replacing** values within a window.

### How operations work

```
Window (wcMax=3): [Junior, Mid-level, Senior]

Operation "senior-focus":
  Mid-level → Staff
  Senior → Principal

Effective window: [Junior, Staff, Principal]
```

The composition count stays the same (3 values in the window). Only the content changes.

### Operation YAML

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

### The three-layer pipeline with operations

```
Prompt YAML          Buckets              Operation            Output
┌─────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ tone(5)     │    │ window [0:3] │    │ map:         │    │ 3 x 4 = 12  │
│ audience(4) │ →  │ tone: 3 vals │ →  │ formal→丁寧  │ →  │ compositions │
│ ext_text(6) │    │ aud: 4 vals  │    │ casual→普通  │    │ with Japanese │
│             │    │ ext: 3 vals  │    │              │    │ tone values   │
└─────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
   STRUCTURE          BATCHING           TRANSFORM           PRODUCT
```

### Variant families

An operation's filename is its **variant family** name. Applying different operations to the same prompt produces distinct variant families:

```
operations/english.yaml       → variant family "english"       → 12 EN compositions
operations/japanese.yaml      → variant family "japanese"      → 12 JP compositions
operations/formal-only.yaml   → variant family "formal-only"   → 12 FO compositions
```

The variant family name labels the output batch, making exports self-describing and diffable.

### Operation use cases

| Use case | Operation name | What it does |
|----------|---------------|--------------|
| Localization | `english-to-japan` | Translates wildcard values |
| Brand voice | `brand-acme-corp` | Replaces generic tones with brand-specific language |
| A/B testing | `devil-advocate` | Inverts intent to test prompt robustness |
| Client customization | `client-globex` | Swaps industry/audience values for a specific client |
| Cherry-picking | `senior-focus` | Replaces junior values with senior ones |

Operations are saved in an `operations/` folder, git-tracked, and diffable. They compose with any prompt — write the structure once, apply unlimited operations.

---

## Batch Export

Operations enable systematic batch export of massive composition spaces.

### Without operations

```
360K compositions → export all → one giant batch → one set of values
```

### With operations

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
| Operations | `operations/*.yaml` | None (raw values) | Transforms values |

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

**Layer 1 (Structure):** 4 local wildcards + 1 theme wildcard (seniority) + 6 ext_text values

**Layer 2 (Batching):** `wildcards_max: 3` reduces each dimension:
```
ext_text: ceil(6/3) = 2, channel: ceil(4/3) = 2, count: 1, approach: 1, seniority: ceil(5/3) = 2
Total: 2 x 2 x 1 x 1 x 2 = 8 bucket-compositions
```

**Layer 3 (Transforms):** Apply `operations/english-to-japan.yaml` to replace values in the current window.

**Layer 4 (Product):** Generate 3 x 3 x 3 x 3 x 3 = 243 compositions per bucket, with operation-modified values.

---

## File Structure

```
project/
├── jobs/
│   └── hiring-templates/
│       ├── jobs.yaml              # Prompt definitions (Layer 1)
│       ├── operations/            # Value transforms (Layer 3, planned)
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
| **Operation** | A named value-replacement mapping applied to a bucket window |
| **Variant family** | The operation's filename/title — labels the output batch (e.g., `operations/english-to-japan.yaml` → variant family "english-to-japan") |
| **Window** | The slice of values visible in the current bucket (`[start, start + wcMax - 1]`) |
| **wcMax** | `wildcards_max` — the bucket size for wildcards |
| **extTextMax** | `ext_text_max` — the bucket size for extension text lists |
