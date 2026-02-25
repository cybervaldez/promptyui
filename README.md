# Cybervaldez Prompt Generator

Prompt templating system for generating content variations across domains.

## About This Project

This project demonstrates my approach to AI-assisted development:

- **CLI-first design** for AI debuggability
- **E2E testing** against real systems
- **Observable, maintainable code** from day one

For the full development methodology, see [Cybervaldez Playbook](https://github.com/cybervaldez/cybervaldez-playbook).

## What It Does

- **Generate prompt variations at scale** - Define templates with wildcards, get all combinations
- **Web UI for non-technical editing** - PromptyUI lets anyone edit and preview prompts
- **Block annotations** - 3-layer inheritance (defaults > prompt > block) with universal widgets, token counters, async checks
- **Pipeline View** - Block tree visualization with SSE-driven execution (Run/Stop/Resume)
- **Sampler Gallery** - Grid view of sampled compositions for pattern-spotting across the Cartesian space
- **Extensible architecture** - Reusable data packs (personas, tones, roles) across domains
- **Built for AI workflows** - CLI outputs designed for AI consumption and debugging
- **56+ E2E tests** - Comprehensive test suite via `agent-browser` + `curl`
- **[Composition Model](docs/composition-model.md)** - How wildcards, ext_text, buckets, and hooks work together

## Quick Start

```bash
./start-prompty.sh              # Start server
# Open http://localhost:8085
```

### CLI Usage

```bash
python build-job.py jobs/hiring-templates    # Build a job
python build-job.py --help                   # See all options
```

## Project Structure

```
cybervaldez-prompt-generator/
├── src/                  # Python backend - core generation engine
│   ├── cli/              # CLI tools and test modules
│   └── tree_executor.py  # Depth-first block-aware execution engine
├── webui/prompty/        # PromptyUI - web interface
│   ├── server/           # Flask API server + SSE pipeline endpoint
│   ├── js/               # Vanilla JS frontend (annotations, pipeline, gallery, etc.)
│   └── templates/        # HTML templates
├── jobs/                 # Prompt definitions by domain
│   ├── hiring-templates/
│   ├── investor-outreach/
│   ├── sales-content/
│   └── product-content/
├── ext/                  # Reusable extensions (wildcards)
│   ├── hiring/roles.yaml
│   ├── professional/tones.yaml
│   ├── fundraising/stages.yaml
│   ├── sales/personas.yaml
│   └── product/formats.yaml
├── mods/                 # Mod scripts (generation-time user extensions)
├── tests/                # E2E test suite (56+ test files)
│   ├── lib/test_utils.sh # Shared test utilities
│   ├── e2e-orchestrator.sh
│   ├── test_prompty_api.sh
│   ├── test_prompty_ui.sh
│   ├── test_annotations.sh
│   ├── test_async_widget.sh
│   ├── test_token_counter.sh
│   ├── test_pipeline_modal.sh
│   ├── test_gallery.sh
│   └── ...               # 40+ more test files
└── outputs/              # Generated output files
```

## Tech Stack

| Layer | Technology |
|-------|------------|
| Backend | Python 3.10+ |
| Frontend | Vanilla JavaScript |
| Server | Flask |
| Testing | Bash + agent-browser + curl |

No heavy frameworks. Intentionally simple for maintainability.

## Development Philosophy

| Principle | What It Means |
|-----------|---------------|
| CLI-First | AI can debug via text output, not screenshots |
| E2E Testing | Tests verify what users actually experience |
| Observable Code | State exposed at every step for verification |

These principles enable AI to assist effectively throughout development. Tests run against real systems, not mocks. Errors produce text that AI can analyze.

See [Cybervaldez Playbook](https://github.com/cybervaldez/cybervaldez-playbook) for the full methodology.

## Running Tests

```bash
./tests/e2e-orchestrator.sh       # Full E2E suite
./tests/test_prompty_api.sh       # API tests only
./tests/test_prompty_ui.sh        # UI tests only
./tests/test_annotations.sh       # Annotation system
./tests/test_async_widget.sh      # Async widget checks
./tests/test_token_counter.sh     # Token counter widget
./tests/test_pipeline_modal.sh    # Pipeline View modal
./tests/test_gallery.sh           # Sampler Gallery
./tests/test_shared_module.sh     # Shared utilities
```

## Development Workflow

This project uses the [Cybervaldez Playbook](https://github.com/cybervaldez/cybervaldez-playbook) for structured AI-assisted development.

### Available Skills

| Skill | Purpose |
|-------|---------|
| `/ux-planner` | Plan features with UX tradeoffs |
| `/ui-planner` | Establish visual identity |
| `/create-task` | Build with tests baked in |
| `/coding-guard` | Audit for anti-patterns |
| `/e2e` | End-to-end test verification |
| `/research` | Research new technologies |

See `.claude/skills/SKILL_INDEX.md` for full details.

### Workflow

1. `/ux-planner` — plan the feature
2. `/ui-planner` — design the visuals
3. `/create-task` — implement with tests
4. `/coding-guard` + `/e2e` — verify quality

## About Me

I build maintainable, AI-friendly systems for founders who need quality code that scales.

- [GitHub](https://github.com/cybervaldez)
- [Development Playbook](https://github.com/cybervaldez/cybervaldez-playbook)
