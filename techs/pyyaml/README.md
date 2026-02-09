# PyYAML

PyYAML is a full-featured YAML 1.1 parser and emitter for Python, used for reading and writing YAML configuration files, data serialization, and structured document processing. In this project, PyYAML is the primary serialization layer -- used across 19 import sites to load/save job configurations, variant definitions, wildcard data, workflow specs, extension configs, segment definitions, and hook settings. All reading uses `yaml.safe_load()` and all writing uses `yaml.dump()` with explicit formatting options (`default_flow_style=False`, `allow_unicode=True`, `sort_keys=False`). The centralized `load_yaml()` / `save_yaml()` helpers in `src/config.py` enforce consistent patterns across the codebase.

## Domain Classification

| Domain | Applies |
|--------|---------|
| State Management | No |
| UI Components | No |
| Data Fetching | No |
| Form Handling | No |
| Animation | No |
| Routing | No |
| Testing Tools | No |
| Build Tools | Yes |
| Styling | No |
| Auth | No |

> **Note:** PyYAML is an infrastructure/serialization library. It most closely fits "Build Tools" because it is the configuration and data pipeline backbone -- every build job, workflow, and config file flows through YAML parsing. It does not fit UI-centric domains.

## Pipeline Impact

| Skill | Impact | Reason |
|-------|--------|--------|
| coding-guard | High | Must flag `yaml.load()` (unsafe) vs `yaml.safe_load()` (safe). Must flag missing error handling around YAML parse calls. Must flag the Norway Problem (unquoted `yes`/`no`/`on`/`off` interpreted as booleans). |
| create-task | Medium | YAML is the file format for all config/data files. Tasks involving new config schemas, new job types, or new extension definitions must follow existing YAML structure conventions. |
| cli-first | Low | YAML files are human-readable and can be verified via CLI (`cat`, `diff`, `python -c "import yaml; ..."`). No special exposure patterns needed. |
| e2e | Low | WebUI server startup/config depends on YAML files loading correctly. Corrupted YAML would block the server. |
| e2e-guard | Low | Test data fixtures may use YAML format. |
| e2e-investigate | Low | YAML parse errors produce `yaml.YAMLError` with line/column info useful for debugging. |
| ux-planner | None | No UI impact. |
| ui-planner | None | No visual design impact. |
| ui-review | None | No visual design impact. |
| ux-review | None | No visual design impact. |

## Core Concepts

- **safe_load / safe_dump**: The secure API surface. `safe_load()` only constructs basic Python types (str, int, float, list, dict, bool, None). `safe_dump()` only serializes basic types. Never use `yaml.load()` without `Loader=SafeLoader`.
- **Loaders hierarchy**: `BaseLoader` (strings only) < `SafeLoader` (basic types) < `FullLoader` (most types, limited objects) < `UnsafeLoader`/`Loader` (arbitrary Python objects -- dangerous).
- **Representers and Constructors**: Extension points for custom type serialization. Not used in this project (all data is basic dicts/lists/strings).
- **Multi-document streams**: YAML supports multiple documents in one file separated by `---`. This project uses single-document files exclusively.
- **YAML 1.1 vs 1.2**: PyYAML implements YAML 1.1. In 1.1, `yes`/`no`/`on`/`off` are booleans. YAML 1.2 restricts booleans to `true`/`false` only. This matters for config values that might contain these words.

## Common Patterns

**Centralized load/save (this project's pattern):**
```python
# src/config.py -- all YAML I/O goes through these
def load_yaml(path):
    with open(path, "r") as f:
        return yaml.safe_load(f)

def save_yaml(path, data):
    with open(path, "w") as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
```

**Defensive loading with fallback:**
```python
# Pattern used throughout src/hooks.py, src/workflows.py, etc.
data = yaml.safe_load(f) or {}  # Handle empty YAML files (safe_load returns None)
```

**Consistent dump options:**
```python
# default_flow_style=False  -- block style (human-readable), not inline JSON-like
# allow_unicode=True         -- preserve Unicode chars, don't escape to \uXXXX
# sort_keys=False            -- preserve insertion order (important for config readability)
yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
```

**Deterministic hashing via YAML:**
```python
# src/config.py -- uses sort_keys=True for deterministic hash input
yaml_str = yaml.dump(hash_config, sort_keys=True, default_flow_style=False)
```

## Anti-Patterns & Gotchas

**CRITICAL -- Unsafe loading (Remote Code Execution):**
```python
# BAD: yaml.load() without SafeLoader can execute arbitrary Python code
data = yaml.load(f)                    # RCE vulnerability
data = yaml.load(f, Loader=Loader)     # Still unsafe

# GOOD: Always use safe_load
data = yaml.safe_load(f)               # Only constructs basic types
```

**The Norway Problem (implicit boolean coercion):**
```yaml
# BAD: These are silently parsed as booleans in YAML 1.1
country: no        # Parsed as False, not the string "no"
enabled: yes       # Parsed as True, not the string "yes"

# GOOD: Quote string values that could be confused with booleans
country: "no"
enabled: "yes"
```

**Empty file returns None, not empty dict:**
```python
# BAD: Crashes if YAML file is empty
data = yaml.safe_load(f)
for key in data:           # TypeError: NoneType is not iterable

# GOOD: Default to empty dict
data = yaml.safe_load(f) or {}
```

**Losing key order with sort_keys default:**
```python
# BAD: sort_keys defaults to True, scrambles intentional ordering
yaml.dump(data, f)

# GOOD: Preserve insertion order
yaml.dump(data, f, sort_keys=False)
```

## Testing Considerations

- **Fixture files**: Test YAML files should be valid and use `safe_load()` exclusively. Include edge cases: empty files, Unicode content, nested structures, lists of dicts.
- **Round-trip fidelity**: Test that `load_yaml(path)` followed by `save_yaml(path, data)` preserves data integrity. Note: comments are stripped by PyYAML.
- **Error messages**: `yaml.YAMLError` includes line and column numbers. Tests should verify that malformed YAML produces actionable error messages.
- **Boolean gotcha in test data**: If test YAML contains values like `yes`, `no`, `on`, `off`, verify they parse as intended type (string vs boolean).

## Resources

- Official docs: https://pyyaml.org/wiki/PyYAMLDocumentation
- GitHub: https://github.com/yaml/pyyaml
- PyPI: https://pypi.org/project/PyYAML/
- Security advisory (yaml.load deprecation): https://github.com/yaml/pyyaml/wiki/PyYAML-yaml.load(input)-Deprecation
