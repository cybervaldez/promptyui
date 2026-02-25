#!/usr/bin/env python3
"""
Hooks Engine - Pure hook-based pipeline for executing lifecycle scripts.

ARCHITECTURE:
  The engine is dumb: execute_hook(name, ctx) → look up config → run scripts.
  Stage names are CALLER CONVENTIONS, not engine code. The engine doesn't know
  or care what the names mean — it just executes whatever scripts are configured
  under that key in hooks.yaml/mods.yaml.

  Mods are hooks with guards (stage, scope, filters). Guards are checked at
  config level before execution — no if/elif branching in the engine.

HOOK LIFECYCLE (conventions — defined by the caller, not the engine):
  Block-level (fire once):   node_start → resolve (cached)
  Per-composition:           pre → generate → post
  Block-level (fire once):   node_end
  Job-level:                 job_start (before all), job_end (after all), error (on failure)

  'generate' is where a user-supplied script runs (e.g., ComfyUI workflow,
  API caller, file copier). It's not built-in — just a hook name.

  'pre' and 'post' are where mods (hooks with guards) typically run:
  translator, validator, error_logger, quality check, etc.

CONFIG:
  hooks.yaml (per job) — system lifecycle scripts
  mods.yaml (global) — user extension scripts with guards:
    - stage: pre | post | both | build (build = build-checkpoints.py, not generation-time)
    - execution_scope: checkpoint | image
    - filters: config_index, address_index
    - Enable/disable per prompt in jobs.yaml

PLANNED (TreeExecutor + Enriched Context):
  - Depth-first single-cursor execution: one composition at a time, depth-first block order
  - parent_result: context key with parent block's HookResult.data for child hooks
  - _block_path: new field in build_jobs() output for block identity (e.g., "0", "0.0")
  - Path-scoped failure: block failure skips remaining compositions, blocks children
  - 'resolve' caching: fire once per block, cache for all compositions
  See webui/prompty/previews/preview-build-flow-diagram.html for the visual model.

  Enriched hook context (Strategy D — namespace separation):
    ctx = {
      # Identity
      'block_path', 'parent_path', 'is_leaf', 'block_depth',
      # Composition
      'composition_index', 'composition_total', 'wildcards', 'wildcard_indices',
      # Operations
      'operation', 'operation_mappings',
      # Annotations (user intent — "what to DO")
      'annotations', 'annotation_sources',
      # Theme metadata (reference facts — "what it IS", separate namespace)
      'meta', 'ext_text_source',
      # Inheritance
      'parent_result', 'parent_annotations',
      # Content
      'resolved_text', 'prompt_id', 'job',
    }

  Key design decision: `meta` (from ext_text theme values) and `annotations`
  (from block/prompt/defaults) are SEPARATE namespaces. Theme metadata carries
  reference facts that are never overridden by block annotations. Hooks receive
  both independently. See docs/composition-model.md "Theme Metadata (meta)".
"""

import sys
import json
import subprocess
import importlib.util
from pathlib import Path
from typing import Dict, List, Optional, Any, Callable
from datetime import datetime


# Status codes
STATUS_SUCCESS = 'success'
STATUS_ERROR = 'error'
STATUS_SKIP = 'skip'
STATUS_STREAMING = 'streaming'


class HookResult:
    """Result of a hook execution."""
    
    def __init__(self, status: str, data: dict = None, error: dict = None, 
                 modify_context: dict = None, message: str = None):
        self.status = status
        self.data = data or {}
        self.error = error
        self.modify_context = modify_context or {}
        self.message = message
    
    @property
    def success(self) -> bool:
        return self.status in (STATUS_SUCCESS, STATUS_SKIP)
    
    def to_dict(self) -> dict:
        return {
            'status': self.status,
            'data': self.data,
            'error': self.error,
            'modify_context': self.modify_context,
            'message': self.message
        }


class HookPipeline:
    """
    Orchestrates hook and mod execution throughout the job lifecycle.
    
    Usage:
        pipeline = HookPipeline(job_dir, hooks_config, mods_config)
        pipeline.execute_hook('job_start', context)
        # ... traverse nodes ...
        pipeline.execute_hook('job_end', context)
    """
    
    def __init__(self, job_dir: Path, hooks_config: dict = None, mods_config: dict = None):
        self.job_dir = Path(job_dir)
        self.hooks_config = hooks_config or {}
        self.mods_config = mods_config or {}
        self._loaded_scripts = {}
    
    def execute_hook(self, hook_name: str, context: dict) -> HookResult:
        """
        Execute all scripts configured under a hook name.

        The engine is dumb — it looks up hooks_config[hook_name] and mods_config,
        merges them, checks guards, and executes. No knowledge of stage semantics.

        Args:
            hook_name: Any string key (e.g., 'pre', 'generate', 'post', 'node_start').
                       Convention, not enforced by the engine.
            context: Execution context data

        Returns:
            HookResult with status and any modifications
        """
        import os
        debug = os.environ.get('WEBUI_DEBUG') == '1'

        # Add hook name to context
        ctx = {**context, 'hook': hook_name}

        # Debug: Log hook point entry
        if debug:
            print(f"\n{'='*60}")
            print(f"HOOK: {hook_name}")
            print(f"{'='*60}")

        execution_order = 0
        last_data = {}  # Track data from last hook execution

        # 1. Execute system hooks from hooks.yaml
        system_hooks = self.hooks_config.get(hook_name, [])
        for hook_conf in system_hooks:
            execution_order += 1
            script_path = hook_conf.get('script', 'unknown')

            if debug:
                print(f"\n  #{execution_order} HOOK: {Path(script_path).name}")
                print(f"     Path: {script_path}")

            result = self._execute_single_hook(hook_conf, ctx)

            if debug:
                status_icon = '✅' if result.status == STATUS_SUCCESS else '❌' if result.status == STATUS_ERROR else '⏭️'
                print(f"     {status_icon} Status: {result.status}")
                if result.data:
                    print(f"     Data: {result.data}")
                if result.modify_context:
                    print(f"     Modified: {list(result.modify_context.keys())}")

            if result.status == STATUS_ERROR:
                self._handle_error(hook_name, result, ctx)
                return result
            # Apply context modifications
            if result.modify_context:
                ctx.update(result.modify_context)
            # Preserve data from hook result
            if result.data:
                last_data = result.data

        # 2. Execute mods from mods.yaml (hooks with guards)
        # Mods self-filter via guards — the engine just runs them all
        enabled_mods = ctx.get('enabled_mods', [])
        if enabled_mods:
            result = self._execute_mods(enabled_mods, hook_name, ctx, execution_order, debug)
            if result.status == STATUS_ERROR:
                return result
            ctx.update(result.modify_context or {})

        if debug:
            print(f"{'='*60}\n")

        return HookResult(STATUS_SUCCESS, data=last_data, modify_context=ctx)
    
    def _execute_mods(self, mod_names: List[str], hook_name: str, context: dict,
                       start_order: int = 0, debug: bool = False) -> HookResult:
        """Execute user mods, checking guards against the current hook name.

        Mods self-filter: each mod's 'stage' guard is checked against hook_name.
        No special-casing of any hook name in the engine.
        """
        ctx = {**context}
        execution_order = start_order

        for mod_name in mod_names:
            mod_conf = self.mods_config.get(mod_name)
            if not mod_conf:
                continue

            execution_order += 1

            # Guard: stage match (mod declares which hook names it runs at)
            mod_stage = mod_conf.get('stage', 'both')
            if isinstance(mod_stage, list):
                stage_match = hook_name in mod_stage or 'both' in mod_stage
            else:
                stage_match = mod_stage == 'both' or mod_stage == hook_name

            if not stage_match:
                if debug:
                    print(f"\n  #{execution_order} MOD: {mod_name}")
                    print(f"     SKIPPED: stage={mod_stage} but hook={hook_name}")
                continue

            # Guard: execution scope
            scope = mod_conf.get('execution_scope', 'checkpoint')
            is_checkpoint_execution = ctx.get('is_checkpoint_execution', False)

            if scope == 'checkpoint' and not is_checkpoint_execution:
                if debug:
                    print(f"\n  #{execution_order} MOD: {mod_name}")
                    print(f"     SKIPPED: scope=checkpoint but is_checkpoint_execution=False")
                continue
            if scope == 'image' and is_checkpoint_execution:
                if debug:
                    print(f"\n  #{execution_order} MOD: {mod_name}")
                    print(f"     SKIPPED: scope=image but is_checkpoint_execution=True")
                continue

            # Guard: filters
            if not self._check_filters(mod_conf, ctx):
                if debug:
                    print(f"\n  #{execution_order} MOD: {mod_name}")
                    print(f"     SKIPPED: filter check failed")
                continue

            if debug:
                print(f"\n  #{execution_order} MOD: {mod_name}")
                print(f"     Hook: {hook_name} | Scope: {scope}")
                print(f"     Guards passed")
                print(f"     Path: {mod_conf.get('script', 'unknown')}")

            # Execute mod (same path as any hook)
            result = self._execute_single_hook(mod_conf, ctx)

            if debug:
                status_icon = '✅' if result.status == STATUS_SUCCESS else '❌' if result.status == STATUS_ERROR else '⏭️'
                print(f"     {status_icon} Status: {result.status}")
                if result.data:
                    print(f"     Data: {result.data}")
                if result.modify_context:
                    print(f"     Modified: {list(result.modify_context.keys())}")

            if result.status == STATUS_ERROR:
                return result
            if result.status == STATUS_SKIP:
                continue

            # Apply context modifications
            if result.modify_context:
                ctx.update(result.modify_context)

        return HookResult(STATUS_SUCCESS, modify_context=ctx)
    
    def _check_filters(self, mod_conf: dict, context: dict) -> bool:
        """Check if mod passes its configured filters."""
        filters = mod_conf.get('filters', {})
        
        # config_index filter
        if 'config_index' in filters:
            allowed = filters['config_index']
            current = context.get('config_index')
            if current is not None and current not in allowed:
                return False
        
        # address_index filter
        if 'address_index' in filters:
            allowed = filters['address_index']
            current = context.get('address_index')
            if current is not None and current not in allowed:
                return False
        
        return True
    
    def _execute_single_hook(self, hook_conf: dict, context: dict) -> HookResult:
        """Execute a single hook/mod script."""
        script_path = hook_conf.get('script')
        params = hook_conf.get('params', {})
        
        if not script_path:
            return HookResult(STATUS_SUCCESS)
        
        # Resolve script path - check job dir first, then project root
        full_path = self.job_dir / script_path
        if not full_path.exists():
            # Try project root (parent of jobs dir)
            project_root = self.job_dir.parent.parent
            full_path = project_root / script_path.lstrip('./')
            
        if not full_path.exists():
            return HookResult(STATUS_ERROR, error={
                'code': 'SCRIPT_NOT_FOUND',
                'message': f'Hook script not found: {script_path}'
            })
        
        # Execute script
        try:
            result = self._run_script(full_path, context, params)
            return result
        except Exception as e:
            return HookResult(STATUS_ERROR, error={
                'code': 'SCRIPT_EXCEPTION',
                'message': str(e)
            })
    
    def _run_script(self, script_path: Path, context: dict, params: dict) -> HookResult:
        """Run a Python script and return its result."""
        # Try to import as module first (faster for repeated calls)
        if str(script_path) in self._loaded_scripts:
            module = self._loaded_scripts[str(script_path)]
        else:
            spec = importlib.util.spec_from_file_location("hook_module", script_path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            self._loaded_scripts[str(script_path)] = module
        
        # Call execute function
        if hasattr(module, 'execute'):
            result = module.execute(context, params)
            
            if isinstance(result, dict):
                return HookResult(
                    status=result.get('status', STATUS_SUCCESS),
                    data=result.get('data'),
                    error=result.get('error'),
                    modify_context=result.get('modify_context'),
                    message=result.get('message')
                )
            else:
                return HookResult(STATUS_SUCCESS)
        else:
            return HookResult(STATUS_ERROR, error={
                'code': 'NO_EXECUTE_FUNC',
                'message': f'Script has no execute() function: {script_path}'
            })
    
    def _handle_error(self, hook_name: str, result: HookResult, context: dict):
        """Handle an error by executing error hooks."""
        error_ctx = {
            **context,
            'hook': 'error',
            'error_type': 'HookError',
            'error_message': result.error.get('message', 'Unknown error'),
            'error_code': result.error.get('code', 'UNKNOWN'),
            'hook_name': hook_name,
            'timestamp': datetime.now().isoformat()
        }
        
        # Always emit error to mod UI (built-in error logging)
        try:
            from src.mod_events import log_error
            log_error(
                prompt_id=context.get('prompt_id', 'unknown'),
                path=context.get('path', context.get('path_string', 'unknown')),
                address_index=context.get('address_index', 1),
                config_index=context.get('config_index', 0),
                error_message=result.error.get('message', 'Unknown error'),
                error_code=result.error.get('code', 'UNKNOWN')
            )
        except ImportError:
            pass  # mod_events not available
        
        # Execute error hooks from config
        error_hooks = self.hooks_config.get('error', [])
        for hook_conf in error_hooks:
            try:
                self._execute_single_hook(hook_conf, error_ctx)
            except Exception:
                pass  # Don't let error handlers crash


def load_hooks_config(job_dir: Path) -> dict:
    """Load hooks.yaml from job directory."""
    hooks_file = job_dir / 'hooks.yaml'
    if hooks_file.exists():
        import yaml
        with open(hooks_file) as f:
            data = yaml.safe_load(f) or {}
            return data.get('hooks', {})
    return {}


def load_mods_config(job_dir: Path) -> dict:
    """
    Load mod configurations from global /mods.yaml.
    
    The global mods.yaml at project root is the source of truth for mod definitions.
    Job-level activation (on/off) is handled separately via get_enabled_mods().
    
    Args:
        job_dir: Job directory path (e.g., jobs/andrea-fashion)
    
    Returns:
        Dict of mod_name -> mod_config from global mods.yaml
    """
    import yaml
    
    # Global mods.yaml at project root
    project_root = job_dir.parent.parent
    global_mods_file = project_root / 'mods.yaml'
    
    if global_mods_file.exists():
        with open(global_mods_file) as f:
            data = yaml.safe_load(f) or {}
            return data.get('mods', {})
    
    return {}


def get_enabled_mods(job_dir: Path, prompt_id: str = None) -> list:
    """
    Get list of enabled mods for a prompt, applying priority resolution.
    
    Priority: job.yaml off > global auto_run > job.yaml on
    
    Args:
        job_dir: Job directory path
        prompt_id: Optional prompt ID to get prompt-specific overrides
    
    Returns:
        List of mod names that should be executed
    """
    import yaml
    
    project_root = job_dir.parent.parent
    
    # 1. Load global mods config
    global_mods_file = project_root / 'mods.yaml'
    global_mods = {}
    global_defaults = {}
    
    if global_mods_file.exists():
        with open(global_mods_file) as f:
            data = yaml.safe_load(f) or {}
            global_mods = data.get('mods', {})
            global_defaults = data.get('defaults', {})
    
    default_auto_run = global_defaults.get('auto_run', False)
    
    # 2. Load job-level overrides from jobs.yaml
    jobs_file = job_dir / 'jobs.yaml'
    prompt_on = []
    prompt_off = []
    
    if jobs_file.exists() and prompt_id:
        with open(jobs_file) as f:
            jobs_data = yaml.safe_load(f) or {}
        
        prompts = jobs_data.get('prompts', [])
        for prompt in prompts:
            if prompt.get('id') == prompt_id:
                mods_config = prompt.get('mods', {})
                prompt_on = mods_config.get('enable', [])
                prompt_off = mods_config.get('disable', [])
                break
    
    # 3. Apply priority resolution
    enabled_mods = []
    
    for mod_name, mod_config in global_mods.items():
        # Check if explicitly disabled by job
        if mod_name in prompt_off:
            continue  # job off wins
        
        # Check if explicitly enabled by job
        if mod_name in prompt_on:
            enabled_mods.append(mod_name)
            continue
        
        # Fall back to global auto_run
        mod_auto_run = mod_config.get('auto_run', default_auto_run)
        if mod_auto_run:
            enabled_mods.append(mod_name)
    
    return enabled_mods

