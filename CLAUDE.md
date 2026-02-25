# Cybervaldez Prompt Generator

Prompt templating system that generates Cartesian product of text blocks x wildcard values at scale.

## Composition Model (3 layers + hooks)

1. **Structure** (prompt YAML) — text blocks with `__wildcard__` placeholders + `ext_text` theme references
2. **Batching** (buckets via `wildcards_max`) — windows the Cartesian space into manageable chunks
3. **Hooks** — extensible interactions at three UI locations (editor, build, render) plus a generation-time lifecycle

The full pipeline: Structure -> Batching -> Hooks -> Cartesian product -> Output files.

See `docs/composition-model.md` for the complete reference.

## Key Concepts

- **Wildcard**: Template variable (`__tone__`) with multiple values. Dimensions of the Cartesian product.
- **ext_text**: Reusable text lists from `ext/` theme files. Each theme can bring its own wildcards and per-value metadata (`meta`).
- **Theme metadata (meta)**: Per-value facts on ext_text entries (e.g., `department: "engineering"`). Separate namespace from annotations — carries reference data ("what it IS") vs. annotations' intent ("what to DO"). Never merged with or overridden by block annotations. Flows into hook context as `ctx['meta']`.
- **Annotations**: 3-layer inheritance for user intent: `defaults.annotations` → `prompt.annotations` → `block.annotations`. Deeper wins. Null sentinel removes inherited keys. Flows into hook context as `ctx['annotations']` + `ctx['annotation_sources']`.
- **Bucket**: Contiguous window of values. `wildcards_max: 3` splits a 10-value wildcard into 4 buckets. Composition navigator moves between buckets (coarse), dropdowns pick within a bucket (fine).
- **Operation**: Named value-replacement mapping (a type of build hook) applied per-window, enabling localization, A/B testing, and cherry-picking. The operation's filename is its **variant family** name — it labels the output batch.
- **Composition ID**: Numeric index into the Cartesian product. Odometer algorithm decomposes ID into per-wildcard value indices.
- **Hook**: Script configured in `hooks.yaml` (per job). The engine is dumb: `execute_hook(name, ctx)` runs whatever scripts are under that key. Stage names (`pre`, `generate`, `post`, `node_start`, etc.) are caller conventions, not engine code.
- **Mod**: Script configured in `mods.yaml` (global). Same execution path as hooks, but with guards (stage, scope, filters) checked before execution. Priority: job disable > auto_run > job enable.

## Hook Locations

Hooks are named by **where they appear**, not when they execute. A beginner reads the name and knows exactly where to look.

| Hook | Where | When | What it does |
|------|-------|------|-------------|
| **Editor hook** | Prompt editor canvas | While editing blocks | Injects UI elements, live validation, token counters |
| **Build hook** | Build flow diagram | When assembling the pipeline | Operations, template injection, quality gates, filters |
| **Render hook** | Composition output | When a composition resolves | Annotation alerts, token budget checks, A/B variants |

```
  EDITOR HOOKS              BUILD HOOKS               RENDER HOOKS
  ────────────              ───────────               ────────────
  Prompt editor             Flow diagram modal        Composition output
  (while writing)    →      (pressing Build)    →     (navigating/exporting)

  Examples:                 Examples:                 Examples:
  • UI widgets              • Operations (value       • Annotation alerts
  • Token counter             replacement)            • Token budget check
  • Live preview            • Quality gates           • A/B variant split
  • Inline alerts           • Template merge          • Output validation
```

## Key Files

| File | Role |
|------|------|
| `src/jobs.py` | `build_text_variations` — Cartesian product engine, wildcard expansion |
| `src/hooks.py` | `HookPipeline` — generation-time lifecycle engine (hooks + mods) |
| `src/variant.py` | `build_variant_structure` — orchestrates the build pipeline |
| `build-job.py` | CLI entry point for building jobs |
| `mods/` | Mod scripts: `error_logger`, `prompt_translator`, `config_injector`, `favorites` |
| `webui/prompty/js/preview.js` | `compositionToIndices`, `bucketCompositionToIndices`, `computeEffectiveTotal` |
| `webui/prompty/js/right-panel.js` | Wildcard/Annotations tab switching, bucket navigation, annotations hierarchy overview |
| `webui/prompty/js/build-composition.js` | Quick Build slide-out panel, export controls |
| `webui/prompty/js/shared.js` | `getCompositionParams()`, `compositionToIndices()` — shared utilities used by Pipeline, Gallery, Quick Build |
| `webui/prompty/js/pipeline.js` | Pipeline View modal (block tree + SSE execution), Build dropdown menu |
| `webui/prompty/js/gallery.js` | Sampler Gallery modal — grid of sampled compositions with wildcard labels |
| `webui/prompty/js/annotations.js` | 3-layer annotation inheritance, resolve(), universals (`_comment`, `_priority`, `_draft`, `_token_limit`), async widget, defineUniversal() API |
| `webui/prompty/js/state.js` | `previewMode` — runtime state for composition, buckets, overrides |
| `src/tree_executor.py` | `TreeExecutor` — depth-first block-aware execution with enriched hook context |
| `webui/prompty/server/api/pipeline.py` | SSE endpoint for Pipeline View execution (`/api/pu/pipeline/run`) |
| `jobs/hiring-templates/jobs.yaml` | Reference job exercising all features (ext_text, nesting, bucketing) |
| `ext/hiring/roles.yaml` | Example theme: 6 roles + seniority wildcard + per-value meta |

## Architecture

```
jobs/*.yaml          ext/*.yaml          operations/*.yaml    mods.yaml
    |                    |                       |                |
    v                    v                       v                v
build-job.py -----> src/jobs.py ---------> src/hooks.py -----> output files
                    (Cartesian product)     (HookPipeline)
                         |                      |
                         v                 Pure hook-based engine:
webui/prompty/js/ -----> Browser UI        execute_hook(name, ctx)
(client-side odometer    (preview,          Conventions: node_start → resolve →
 mirrors the build math)  navigate,          pre → generate → post → node_end
                          export)
        (canvas)    (pipeline)  (output)
```

The WebUI re-implements the composition enumeration client-side so users can navigate, preview, and export without round-tripping to the server. Hooks extend the pipeline at three conceptual UI locations (editor, build, render). At generation time, `HookPipeline` orchestrates the actual lifecycle — hooks and mods use the same execution mechanism (`_execute_single_hook`).

## Conventions

- **Vanilla JS** — no frameworks, no build step
- **Flask backend** — API prefix `/api/pu`
- **E2E tests** — `tests/test_*.sh` using `agent-browser` + `curl`, shared lib at `tests/lib/test_utils.sh`
- **Server start** — `./start-prompty.sh` (port 8085). Never use raw python commands.
- **Python** — use `./venv/bin/python` or project-configured Python
- **Test fixture** — `test-fixtures` job for safe testing

## Development

| Skill | When to use |
|-------|-------------|
| `/ux-planner` | Plan a feature's interaction model |
| `/ui-planner` | Establish visual design (ASCII gallery -> HTML preview) |
| `/create-task` | Implement with built-in E2E tests |
| `/coding-guard` | Audit for convention violations |
| `/e2e` | Full end-to-end test run |
| `/team` | Expert panel for strategic decisions |
