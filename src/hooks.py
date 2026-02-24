#!/usr/bin/env python3
"""
Hooks Engine - Core pipeline for executing lifecycle hooks and mods.

This is the generation-time hook infrastructure. For the conceptual
hook locations in the UI (editor/build/render), see docs/composition-model.md.

LIFECYCLE STAGES (per block):
  1. JOB_START           - once per job
  2. NODE_START          - once per block (first visit)
  3. ANNOTATIONS_RESOLVE - once per block (cached for all compositions)
     Context: { prompt_id, text, annotations }
     Can modify: annotations (dict), text (string)
  4. MODS_PRE            - per composition (user mods, stage=pre)
  5. IMAGE_GENERATION    - per composition (user-supplied script)
  6. MODS_POST           - per composition (user mods, stage=post)
  7. NODE_END            - once per block (after last composition)
  8. JOB_END             - once per job
  9. ERROR               - on any failure

HOOKS vs MODS:
  Both use the same execution mechanism (_execute_single_hook → execute(context, params)).
  - Hooks: system lifecycle scripts in hooks.yaml (per job). Fire at specific stages.
  - Mods:  user extension scripts in mods.yaml (global). Two invocation paths:
           1. Generation-time: MODS_PRE/MODS_POST (stage: pre/post/both)
           2. Build-time: mods_build (stage: build), runs once per prompt in build-checkpoints.py
           Guards: execution_scope (checkpoint/image), filters (config_index, address_index).
           Enable/disable per prompt in jobs.yaml.

  IMAGE_GENERATION is just a hook point — it's not built-in. A user-supplied script
  (e.g., Stable Diffusion wrapper, API caller, file copier) does the actual work.

PLANNED (TreeExecutor):
  - Depth-first single-cursor execution: one composition at a time, depth-first block order
  - parent_result: context key with parent block's HookResult.data for child hooks
  - _block_path: new field in build_jobs() output for block identity (e.g., "0", "0.0")
  - Path-scoped failure: block failure skips remaining compositions, blocks children
  - annotations_resolve caching: fire once per block, cache for all compositions
  See webui/prompty/previews/preview-build-flow-diagram.html for the visual model.
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
    
    def execute_hook(self, hook_name: str, context: dict, 
                     node_mods: List[str] = None) -> HookResult:
        """
        Execute a lifecycle hook.
        
        Args:
            hook_name: One of job_start, node_start, mods_pre, image_generation, 
                       mods_post, node_end, job_end, error
            context: Execution context data
            node_mods: List of mod names to execute (for mods_pre, mods_post)
        
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
            print(f"🔧 HOOK POINT: {hook_name}")
            print(f"{'='*60}")
        
        execution_order = 0
        last_data = {}  # Track data from last hook execution
        
        # Execute system hooks for this point
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
                    print(f"     📦 Data: {result.data}")
                if result.modify_context:
                    print(f"     🔄 Modified: {list(result.modify_context.keys())}")
            
            if result.status == STATUS_ERROR:
                self._handle_error(hook_name, result, ctx)
                return result
            # Apply context modifications
            if result.modify_context:
                ctx.update(result.modify_context)
            # Preserve data from hook result
            if result.data:
                last_data = result.data
        
        # For mods_pre and mods_post, also execute user mods
        if hook_name == 'mods_pre' and node_mods:
            result = self._execute_mods(node_mods, 'pre', ctx, execution_order, debug)
            if result.status == STATUS_ERROR:
                return result
            ctx.update(result.modify_context)
        
        elif hook_name == 'mods_post' and node_mods:
            result = self._execute_mods(node_mods, 'post', ctx, execution_order, debug)
            if result.status == STATUS_ERROR:
                return result
            ctx.update(result.modify_context)
        
        if debug:
            print(f"{'='*60}\n")
        
        return HookResult(STATUS_SUCCESS, data=last_data, modify_context=ctx)
    
    def _execute_mods(self, mod_names: List[str], stage: str, context: dict, 
                       start_order: int = 0, debug: bool = False) -> HookResult:
        """Execute user mods for a given stage."""
        ctx = {**context}
        execution_order = start_order
        
        for mod_name in mod_names:
            mod_conf = self.mods_config.get(mod_name)
            if not mod_conf:
                continue
            
            execution_order += 1
            
            # Check stage (supports string or list)
            mod_stage = mod_conf.get('stage', 'both')
            if isinstance(mod_stage, list):
                # List of stages: check if current stage is in the list
                stage_match = stage in mod_stage or 'both' in mod_stage
            else:
                # Single stage: exact match or 'both'
                stage_match = mod_stage == 'both' or mod_stage == stage
            
            if not stage_match:
                if debug:
                    print(f"\n  #{execution_order} MOD: {mod_name}")
                    print(f"     ⏭️  SKIPPED: stage={mod_stage} but executing={stage}")
                continue
            
            # Check execution scope
            scope = mod_conf.get('execution_scope', 'checkpoint')
            is_checkpoint_execution = ctx.get('is_checkpoint_execution', False)
            
            if scope == 'checkpoint' and not is_checkpoint_execution:
                if debug:
                    print(f"\n  #{execution_order} MOD: {mod_name}")
                    print(f"     ⏭️  SKIPPED: scope=checkpoint but is_checkpoint_execution=False")
                continue
            if scope == 'image' and is_checkpoint_execution:
                if debug:
                    print(f"\n  #{execution_order} MOD: {mod_name}")
                    print(f"     ⏭️  SKIPPED: scope=image but is_checkpoint_execution=True")
                continue
            
            # Check filters
            if not self._check_filters(mod_conf, ctx):
                if debug:
                    print(f"\n  #{execution_order} MOD: {mod_name}")
                    print(f"     ⏭️  SKIPPED: filter check failed")
                continue
            
            if debug:
                print(f"\n  #{execution_order} MOD: {mod_name}")
                print(f"     Stage: {stage} | Scope: {scope}")
                print(f"     ✓ Filters passed")
                print(f"     Path: {mod_conf.get('script', 'unknown')}")
            
            # Execute mod
            result = self._execute_single_hook(mod_conf, ctx)
            
            if debug:
                status_icon = '✅' if result.status == STATUS_SUCCESS else '❌' if result.status == STATUS_ERROR else '⏭️'
                print(f"     {status_icon} Status: {result.status}")
                if result.data:
                    print(f"     📦 Data: {result.data}")
                if result.modify_context:
                    print(f"     🔄 Modified: {list(result.modify_context.keys())}")
            
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

