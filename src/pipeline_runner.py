"""
Pipeline Runner — shared bootstrap for CLI and WebUI execution paths.

Single source of truth for building an execution context:
  load jobs.yaml → process_addons → resolve hooks → build HookPipeline
  → build_jobs → filter by prompt_id

Both CLI (--tree) and WebUI (SSE endpoint) call create_run() and then
attach their own consumer (stdout tags vs SSE events) to the EventStream.
"""

import yaml
from pathlib import Path

from src.hooks import HookPipeline
from src.jobs import build_jobs


def resolve_hooks(defaults_hooks: dict, prompt_hooks) -> dict:
    """
    3-layer hook resolution: defaults.hooks → prompt.hooks.

    Prompt-level hooks append to defaults. Null sentinel removes a stage entirely.

    Args:
        defaults_hooks: Hook config from defaults.hooks (stage → script list)
        prompt_hooks: Hook config from prompt.hooks (stage → script list or null)

    Returns:
        Merged hook config dict (stage → script list)
    """
    if not prompt_hooks:
        return dict(defaults_hooks) if defaults_hooks else {}

    merged = dict(defaults_hooks) if defaults_hooks else {}
    for stage, scripts in prompt_hooks.items():
        if scripts is None:
            # Null sentinel: remove this stage entirely
            merged.pop(stage, None)
        else:
            # Append prompt-level scripts after defaults
            merged[stage] = merged.get(stage, []) + scripts
    return merged


def load_hooks_from_yaml(task_conf: dict, prompt_id: str = None) -> dict:
    """
    Load hook configuration from jobs.yaml structure.

    Reads defaults.hooks and (if prompt_id given) prompt.hooks,
    then resolves via 3-layer merge.

    Args:
        task_conf: Parsed jobs.yaml content
        prompt_id: Optional prompt ID for prompt-level hooks

    Returns:
        Resolved hook config dict (stage → script list)
    """
    defaults = task_conf.get('defaults', {})
    defaults_hooks = defaults.get('hooks', {})

    if not prompt_id:
        return dict(defaults_hooks) if defaults_hooks else {}

    # Find prompt-level hooks
    prompts = task_conf.get('prompts', [])
    prompt_hooks = None
    for prompt in prompts:
        if prompt.get('id') == prompt_id:
            prompt_hooks = prompt.get('hooks')
            break

    return resolve_hooks(defaults_hooks, prompt_hooks)


def create_run(job_dir: Path, composition_id: int = 0, prompt_id: str = None,
               hooks_config: dict = None):
    """
    Bootstrap a ready-to-execute pipeline context.

    Single source of truth for the 6-step setup sequence that both CLI
    and WebUI previously duplicated.

    Args:
        job_dir: Path to the job directory (e.g., jobs/test-fixtures)
        composition_id: Composition index to build
        prompt_id: Optional prompt ID to filter to
        hooks_config: Pre-resolved hooks config (overrides YAML loading).
                      If None, loads from jobs.yaml inline hooks.
                      Pass result of load_hooks_config() for legacy hooks.yaml support.

    Returns:
        Tuple of (pipeline, tree_jobs, run_meta) where:
          pipeline: HookPipeline ready to execute hooks
          tree_jobs: Filtered list of job dicts for TreeExecutor
          run_meta: Dict with job_id, prompt_id, block_paths, total_jobs

    Raises:
        FileNotFoundError: If jobs.yaml doesn't exist
        ValueError: If prompt_id specified but no matching jobs found
    """
    jobs_yaml_path = job_dir / 'jobs.yaml'
    if not jobs_yaml_path.exists():
        raise FileNotFoundError(f'{jobs_yaml_path} not found')

    with open(jobs_yaml_path) as f:
        task_conf = yaml.safe_load(f)

    # Load extensions — auto-load from ext/{theme}/ (mirrors build-job.py)
    from src.extensions import process_addons
    from src.config import load_yaml as _load_yaml
    global_conf = {'ext': []}

    defaults = task_conf.get('defaults', {})
    if isinstance(defaults, list):
        defaults = defaults[0] if defaults else {}
    default_ext = defaults.get('ext', '')
    root_dir = job_dir.parent.parent  # jobs/{name}/ → project root

    if default_ext:
        ext_dir = root_dir / 'ext' / default_ext
        if ext_dir.exists():
            for ext_file in sorted(ext_dir.glob('*.yaml')):
                try:
                    ext_data = _load_yaml(ext_file)
                    if ext_data and 'id' in ext_data:
                        ext_data['_ext'] = default_ext
                        global_conf['ext'].append(ext_data)
                except Exception:
                    pass

    # Per-prompt ext overrides
    loaded_exts = {default_ext} if default_ext else set()
    for prompt in task_conf.get('prompts', []):
        prompt_ext = prompt.get('ext', '')
        if prompt_ext and prompt_ext not in loaded_exts:
            prompt_ext_dir = root_dir / 'ext' / prompt_ext
            if prompt_ext_dir.exists():
                for ext_file in sorted(prompt_ext_dir.glob('*.yaml')):
                    try:
                        ext_data = _load_yaml(ext_file)
                        if ext_data and 'id' in ext_data:
                            ext_data['_ext'] = prompt_ext
                            already = any(
                                e.get('id') == ext_data['id'] and e.get('_ext') == prompt_ext
                                for e in global_conf['ext']
                            )
                            if not already:
                                global_conf['ext'].append(ext_data)
                    except Exception:
                        pass
            loaded_exts.add(prompt_ext)

    try:
        process_addons(job_dir, global_conf)
    except Exception:
        pass  # Addons are optional

    # Resolve hooks: caller-provided > jobs.yaml inline > legacy hooks.yaml
    if hooks_config is None:
        hooks_config = load_hooks_from_yaml(task_conf, prompt_id)
        # Fallback: legacy hooks.yaml (for migration period)
        if not hooks_config:
            from src.hooks import load_hooks_config as load_legacy_hooks
            hooks_config = load_legacy_hooks(job_dir)

    pipeline = HookPipeline(job_dir, hooks_config)

    # Build jobs with block paths
    defaults = task_conf.get('defaults', {})
    tree_jobs = build_jobs(
        task_conf, Path('/dev/null'), 0.1, ' ', global_conf,
        composition_id=composition_id,
        wildcards_max=defaults.get('wildcards_max', 0),
        ext_text_max=defaults.get('ext_text_max', 0),
    )

    # Filter to requested prompt if specified
    if prompt_id:
        tree_jobs = [j for j in tree_jobs if j['prompt'].get('id') == prompt_id]
        if not tree_jobs:
            raise ValueError(f"No jobs found for prompt '{prompt_id}'")

    # Build run metadata
    block_paths = sorted(set(j['prompt'].get('_block_path', '0') for j in tree_jobs))
    run_meta = {
        'job_id': job_dir.name,
        'prompt_id': prompt_id,
        'block_paths': block_paths,
        'total_jobs': len(tree_jobs),
    }

    return pipeline, tree_jobs, run_meta
