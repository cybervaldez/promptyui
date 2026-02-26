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
- **Hook**: Script declared per-job in `jobs.yaml` under `defaults.hooks` and `prompt.hooks`. The engine is dumb: `execute_hook(name, ctx)` runs whatever scripts are under that key. Stage names (`pre`, `generate`, `post`, `node_start`, etc.) are caller conventions, not engine code. Prompt-level hooks append to defaults; null sentinel removes a stage.
- **Artifact**: Output produced by a hook (text, image, data). Returned via `data.artifacts` in hook results. Consolidated into JSONL files per block on disk (`_artifacts/{mod_id}/{block_path}.jsonl`). Manifest at `_artifacts/manifest.json` indexes all artifacts.

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
| `src/hooks.py` | `HookPipeline` — generation-time lifecycle engine (`execute_hook(name, ctx)`) |
| `src/pipeline_runner.py` | `create_run()` — shared bootstrap for CLI + WebUI. `resolve_hooks()` — 3-layer hook merge |
| `src/event_stream.py` | `EventStream` — canonical event producer wrapping TreeExecutor. File lock, stage timing |
| `src/tree_executor.py` | `TreeExecutor` — depth-first block-aware execution with enriched hook context, JSONL artifact consolidation |
| `src/variant.py` | `build_variant_structure` — orchestrates the build pipeline |
| `build-job.py` | CLI entry point for building jobs |
| `webui/prompty/js/preview.js` | `compositionToIndices`, `bucketCompositionToIndices`, `computeEffectiveTotal` |
| `webui/prompty/js/right-panel.js` | Wildcard/Annotations tab switching, bucket navigation, annotations hierarchy overview |
| `webui/prompty/js/build-composition.js` | Quick Build slide-out panel, export controls |
| `webui/prompty/js/shared.js` | `getCompositionParams()`, `compositionToIndices()` — shared utilities used by Pipeline, Gallery, Quick Build |
| `webui/prompty/js/pipeline.js` | Pipeline View modal (block tree + SSE execution), artifact badges, Build dropdown menu |
| `webui/prompty/js/gallery.js` | Sampler Gallery modal — grid of sampled compositions with wildcard labels |
| `webui/prompty/js/annotations.js` | 3-layer annotation inheritance, resolve(), universals (`_comment`, `_priority`, `_draft`, `_token_limit`), async widget, defineUniversal() API |
| `webui/prompty/js/state.js` | `previewMode` — runtime state for composition, buckets, overrides, pipeline blockArtifacts |
| `webui/prompty/server/api/pipeline.py` | SSE endpoint — thin bridge from EventStream events to SSE wire format |
| `webui/prompty/server/api/artifacts.py` | Artifact API — manifest + JSONL line extraction (`?line=N`) |
| `jobs/hiring-templates/jobs.yaml` | Reference job exercising all features (ext_text, nesting, bucketing, stress test) |
| `jobs/test-fixtures/jobs.yaml` | Test fixture job with inline hooks, email-writer example, cross-block dependencies |
| `ext/hiring/roles.yaml` | Example theme: 6 roles + seniority wildcard + per-value meta |

## Architecture

```
jobs/*.yaml          ext/*.yaml          operations/*.yaml
    |                    |                       |
    v                    v                       v
pipeline_runner.py --> src/jobs.py ---------> src/hooks.py
(create_run)          (Cartesian product)     (HookPipeline)
    |                                              |
    v                                         Pure hook-based engine:
event_stream.py -----> TreeExecutor           execute_hook(name, ctx)
(canonical events)     (depth-first cursor)   Conventions: node_start → resolve →
    |                                          pre → generate → post → node_end
    |
    ├── CLI stdout    (src/cli/main.py --tree)
    └── WebUI SSE     (server/api/pipeline.py)

webui/prompty/js/ -----> Browser UI
(client-side odometer    (preview, navigate, export)
 mirrors the build math)
        (canvas)    (pipeline)  (output)
```

### Execution Flow

Both CLI and WebUI share the same execution path:

1. `pipeline_runner.create_run(job_dir, prompt_id)` — loads jobs.yaml, resolves hooks (3-layer merge), builds HookPipeline + tree_jobs
2. `EventStream(pipeline, tree_jobs, meta)` — wraps TreeExecutor, manages file lock, emits canonical events
3. Consumer callback receives typed events: `init`, `block_start`, `stage`, `composition_complete`, `artifact`, `artifact_consumed`, `block_complete`, `block_failed`, `block_blocked`, `run_complete`, `error`
4. CLI prints tagged lines (`[ART]`, `[BLOCK]`, etc.); WebUI bridges to SSE

### Hook Configuration (per-job in jobs.yaml)

Hooks are declared inline in `jobs.yaml`, not in a separate file:

```yaml
defaults:
  hooks:
    generate:
      - script: hooks/echo_generate.py    # runs for all prompts
    pre:
      - script: hooks/validator.py

prompts:
  - id: "email-writer"
    hooks:
      generate:                            # null sentinel would remove: generate: null
        - script: hooks/text_writer.py     # appended to defaults (both run)
```

Resolution: `defaults.hooks` + `prompt.hooks` via `resolve_hooks()`. Null sentinel removes a stage.

### Artifacts

Hooks return artifacts via `data.artifacts` in their result dict:

```python
return {
    'status': 'success',
    'data': {
        'artifacts': [{
            'name': 'email-0.0-0.txt',
            'type': 'text',
            'mod_id': 'text_writer',
            'preview': 'Subject line...',     # short preview for UI
            'content': 'Full email body...',  # full content for JSONL
        }]
    }
}
```

Disk layout (JSONL consolidation — prevents file explosion at scale):
```
_artifacts/
  manifest.json                    # v3, indexes all artifacts
  text_writer/0.0.jsonl            # one line per composition
  echo_generate/0.1.jsonl          # {composition_idx, name, content}
```

The WebUI re-implements the composition enumeration client-side so users can navigate, preview, and export without round-tripping to the server. Hooks extend the pipeline at three conceptual UI locations (editor, build, render). At generation time, `HookPipeline` orchestrates the actual lifecycle.

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
