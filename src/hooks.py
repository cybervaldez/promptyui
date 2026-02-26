#!/usr/bin/env python3
"""
Hooks Engine - Pure hook-based pipeline for executing lifecycle scripts.

ARCHITECTURE:
  The engine is dumb: execute_hook(name, ctx) → look up config → run scripts.
  Stage names are CALLER CONVENTIONS, not engine code. The engine doesn't know
  or care what the names mean — it just executes whatever scripts are configured
  under that key.

HOOK LIFECYCLE (conventions — defined by the caller, not the engine):
  Block-level (fire once):   node_start → resolve (cached)
  Per-composition:           pre → generate → post
  Block-level (fire once):   node_end
  Job-level:                 job_start (before all), job_end (after all), error (on failure)

  'generate' is where a user-supplied script runs (e.g., ComfyUI workflow,
  API caller, file copier). It's not built-in — just a hook name.

  'pre' and 'post' are where mods typically run: translator, validator,
  error_logger, quality check, etc. Mods are just hook scripts declared
  per-job in jobs.yaml — no separate config or guard system needed.

CONFIG:
  All hooks are declared in jobs.yaml per-job:
    defaults.hooks:  Job-wide default scripts (run for all prompts)
    prompt.hooks:    Per-prompt scripts (appended to defaults, null sentinel removes)

  Resolution: defaults.hooks → prompt.hooks (3-layer merge via pipeline_runner.resolve_hooks)

HOOK CONTEXT (Strategy D — namespace separation):
  Each hook receives an enriched context dict:
    Identity:     block_path, parent_path, is_leaf, block_depth
    Composition:  composition_index, composition_total, wildcards, wildcard_indices
    Annotations:  annotations, annotation_sources  (user intent — "what to DO")
    Meta:         meta, ext_text_source             (theme facts — "what it IS")
    Inheritance:  parent_result, parent_annotations
    Content:      resolved_text, prompt_id, job
    Cross-block:  upstream_artifacts, block_states, block_completed

  `meta` and `annotations` are SEPARATE namespaces. Theme metadata (from ext_text
  values) is never overridden by block annotations. Hooks receive both independently.
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
    Orchestrates hook execution throughout the job lifecycle.

    Usage:
        pipeline = HookPipeline(job_dir, hooks_config)
        pipeline.execute_hook('job_start', context)
        # ... traverse nodes ...
        pipeline.execute_hook('job_end', context)
    """
    
    def __init__(self, job_dir: Path, hooks_config: dict = None):
        self.job_dir = Path(job_dir)
        self.hooks_config = hooks_config or {}
        self._loaded_scripts = {}
    
    def execute_hook(self, hook_name: str, context: dict) -> HookResult:
        """
        Execute all scripts configured under a hook name.

        The engine is dumb — it looks up hooks_config[hook_name] and executes.
        No knowledge of stage semantics.

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

        if debug:
            print(f"{'='*60}\n")

        return HookResult(STATUS_SUCCESS, data=last_data, modify_context=ctx)
    
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
    """Load hooks.yaml from job directory (legacy — prefer pipeline_runner.load_hooks_from_yaml)."""
    hooks_file = job_dir / 'hooks.yaml'
    if hooks_file.exists():
        import yaml
        with open(hooks_file) as f:
            data = yaml.safe_load(f) or {}
            return data.get('hooks', {})
    return {}


def load_mods_config(job_dir: Path) -> dict:
    """Deprecated — mods are now declared as hooks in jobs.yaml. Returns empty dict."""
    return {}

