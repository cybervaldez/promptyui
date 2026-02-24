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
- **ext_text**: Reusable text lists from `ext/` theme files. Each theme can bring its own wildcards.
- **Bucket**: Contiguous window of values. `wildcards_max: 3` splits a 10-value wildcard into 4 buckets. Composition navigator moves between buckets (coarse), dropdowns pick within a bucket (fine).
- **Operation**: Named value-replacement mapping (a type of build hook) applied per-window, enabling localization, A/B testing, and cherry-picking. The operation's filename is its **variant family** name — it labels the output batch.
- **Composition ID**: Numeric index into the Cartesian product. Odometer algorithm decomposes ID into per-wildcard value indices.
- **Hook**: System lifecycle script (`hooks.yaml`, per job). Fires at a specific stage: JOB_START → NODE_START → ANNOTATIONS_RESOLVE → IMAGE_GENERATION → NODE_END → JOB_END. IMAGE_GENERATION is just a hook point — a user-supplied script does the actual work.
- **Mod**: User extension script (`mods.yaml`, global). Same execution mechanism as hooks (`_execute_single_hook`), but fires at MODS_PRE/MODS_POST with stage, scope, and filter guards. Priority: job disable > auto_run > job enable.

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
| `webui/prompty/js/right-panel.js` | Wildcard chips, bucket navigation, per-slot editing |
| `webui/prompty/js/build-composition.js` | `_getCompositionParams` — shared composition space computation |
| `webui/prompty/js/state.js` | `previewMode` — runtime state for composition, buckets, overrides |
| `jobs/hiring-templates/jobs.yaml` | Reference job exercising all features (ext_text, nesting, bucketing) |
| `ext/hiring/roles.yaml` | Example theme: 6 roles + seniority wildcard |

## Architecture

```
jobs/*.yaml          ext/*.yaml          operations/*.yaml    mods.yaml
    |                    |                       |                |
    v                    v                       v                v
build-job.py -----> src/jobs.py ---------> src/hooks.py -----> output files
                    (Cartesian product)     (HookPipeline)
                         |                      |
                         v                 Generation-time lifecycle:
webui/prompty/js/ -----> Browser UI        JOB_START → NODE_START →
(client-side odometer    (preview,          ANNOTATIONS_RESOLVE →
 mirrors the build math)  navigate,          MODS_PRE → IMAGE_GENERATION →
                          export)             MODS_POST → NODE_END → JOB_END
                         |
              ┌──────────┼──────────┐
              v          v          v
         Editor       Build      Render       (conceptual UI locations)
         hooks        hooks      hooks
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
