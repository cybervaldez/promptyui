# Cybervaldez Prompt Generator

Prompt templating system that generates Cartesian product of text blocks x wildcard values at scale.

## Composition Model (3 layers)

1. **Structure** (prompt YAML) — text blocks with `__wildcard__` placeholders + `ext_text` theme references
2. **Batching** (buckets via `wildcards_max`) — windows the Cartesian space into manageable chunks
3. **Transforms** (operations) — named YAML files that replace values within a bucket window (planned)

The full pipeline: Structure -> Batching -> Transforms -> Cartesian product -> Output files.

See `docs/composition-model.md` for the complete reference.

## Key Concepts

- **Wildcard**: Template variable (`__tone__`) with multiple values. Dimensions of the Cartesian product.
- **ext_text**: Reusable text lists from `ext/` theme files. Each theme can bring its own wildcards.
- **Bucket**: Contiguous window of values. `wildcards_max: 3` splits a 10-value wildcard into 4 buckets. Composition navigator moves between buckets (coarse), dropdowns pick within a bucket (fine).
- **Operation**: Named value-replacement mapping applied per-window, enabling localization, A/B testing, and cherry-picking without a separate filter layer. The operation's filename is its **variant family** name — it labels the output batch. (Planned)
- **Composition ID**: Numeric index into the Cartesian product. Odometer algorithm decomposes ID into per-wildcard value indices.

## Key Files

| File | Role |
|------|------|
| `src/jobs.py` | `build_text_variations` — Cartesian product engine, wildcard expansion |
| `src/variant.py` | `build_variant_structure` — orchestrates the build pipeline |
| `build-job.py` | CLI entry point for building jobs |
| `webui/prompty/js/preview.js` | `compositionToIndices`, `bucketCompositionToIndices`, `computeEffectiveTotal` |
| `webui/prompty/js/right-panel.js` | Wildcard chips, bucket navigation, per-slot editing |
| `webui/prompty/js/build-composition.js` | `_getCompositionParams` — shared composition space computation |
| `webui/prompty/js/state.js` | `previewMode` — runtime state for composition, buckets, overrides |
| `jobs/hiring-templates/jobs.yaml` | Reference job exercising all features (ext_text, nesting, bucketing) |
| `ext/hiring/roles.yaml` | Example theme: 6 roles + seniority wildcard |

## Architecture

```
jobs/*.yaml          ext/*.yaml          operations/*.yaml (planned)
    |                    |                       |
    v                    v                       v
build-job.py -----> src/jobs.py ---------> output YAML files
                    (Cartesian product)
                         |
                         v
webui/prompty/js/ -----> Browser UI
(client-side odometer    (preview, navigate, export)
 mirrors the build math)
```

The WebUI re-implements the composition enumeration client-side so users can navigate, preview, and export without round-tripping to the server.

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
