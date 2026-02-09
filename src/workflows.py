#!/usr/bin/env python3
"""
Workflow Manager - Sequential Mod Execution

Workflows are saved presets of mods that run in sequence.
They use the direct mod execution API under the hood, chaining context
between mods via modify_context.

File structure:
    workflows/*.yaml         - Global workflows
    jobs/{job}/workflows/    - Job-level workflows (override global)

Workflow YAML format:
    name: Caption Workflow
    description: Generate captions for images
    mods:
      - id: caption-generator
        stage: post
    settings:
      requires_image_reload: false
"""

import yaml
import time
import importlib.util
import json
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional, Tuple


class Workflow:
    """Represents a workflow configuration."""
    
    def __init__(self, id: str, name: str, mods: List[Dict], 
                 description: str = "", settings: Dict = None, scope: str = "global"):
        self.id = id
        self.name = name
        self.description = description
        self.mods = mods  # List of {id, stage, config}
        self.settings = settings or {}
        self.scope = scope  # "global" or "job:{job_name}"
    
    def to_dict(self) -> Dict:
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'mods': [m['id'] for m in self.mods],
            'mods_detail': self.mods,
            'settings': self.settings,
            'scope': self.scope
        }


class WorkflowManager:
    """Manages workflow loading, saving, and execution."""
    
    def __init__(self, job_dir: Path):
        self.job_dir = job_dir
        self.project_root = job_dir.parent.parent
        self.workflows_dir = self.project_root / 'workflows'
        self.job_workflows_dir = job_dir / 'workflows'
        self.mods_dir = self.project_root / 'mods'
    
    def list_workflows(self) -> List[Workflow]:
        """List all available workflows (global + job-level).
        
        Job-level workflows with same ID override global ones.
        """
        workflows = {}
        
        # Load global workflows
        if self.workflows_dir.exists():
            for wf_file in self.workflows_dir.glob('*.yaml'):
                wf = self._load_workflow_file(wf_file, scope="global")
                if wf:
                    workflows[wf.id] = wf
        
        # Load job workflows (override global)
        if self.job_workflows_dir.exists():
            for wf_file in self.job_workflows_dir.glob('*.yaml'):
                wf = self._load_workflow_file(wf_file, scope=f"job:{self.job_dir.name}")
                if wf:
                    workflows[wf.id] = wf
        
        return list(workflows.values())
    
    def get_workflow(self, workflow_id: str) -> Optional[Workflow]:
        """Get a specific workflow by ID.
        
        Checks job-level first, then global.
        """
        # Check job-level first
        job_wf_path = self.job_workflows_dir / f"{workflow_id}.yaml"
        if job_wf_path.exists():
            return self._load_workflow_file(job_wf_path, scope=f"job:{self.job_dir.name}")
        
        # Check global
        global_wf_path = self.workflows_dir / f"{workflow_id}.yaml"
        if global_wf_path.exists():
            return self._load_workflow_file(global_wf_path, scope="global")
        
        return None
    
    def save_workflow(self, workflow: Workflow) -> Tuple[bool, str]:
        """Save a workflow to file.
        
        Returns (success, message).
        """
        if workflow.scope.startswith("job:"):
            target_dir = self.job_workflows_dir
        else:
            target_dir = self.workflows_dir
        
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / f"{workflow.id}.yaml"
        
        try:
            data = {
                'name': workflow.name,
                'description': workflow.description,
                'mods': workflow.mods,
                'settings': workflow.settings
            }
            with open(target_path, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            return True, str(target_path)
        except Exception as e:
            return False, str(e)
    
    def delete_workflow(self, workflow_id: str, scope: str = "global") -> bool:
        """Delete a workflow by ID."""
        if scope.startswith("job:"):
            target_path = self.job_workflows_dir / f"{workflow_id}.yaml"
        else:
            target_path = self.workflows_dir / f"{workflow_id}.yaml"
        
        if target_path.exists():
            target_path.unlink()
            return True
        return False
    
    def run_workflow(self, workflow_id: str, context: Dict, 
                     event_callback=None) -> Dict:
        """Execute a workflow on a given context.
        
        Args:
            workflow_id: ID of workflow to run
            context: Initial context (must include image_path)
            event_callback: Optional callback for SSE events
            
        Returns:
            {
                success: bool,
                workflow_id: str,
                steps: [{mod_id, status, duration, context_added}],
                total_duration: float,
                final_context: dict,
                error?: str
            }
        """
        workflow = self.get_workflow(workflow_id)
        if not workflow:
            return {
                'success': False,
                'workflow_id': workflow_id,
                'error': f"Workflow not found: {workflow_id}"
            }
        
        # Check image exists (build gating)
        image_path = Path(context.get('image_path', ''))
        if not image_path.exists():
            return {
                'success': False,
                'workflow_id': workflow_id,
                'error': 'build_required',
                'message': 'Image must be built before running workflow'
            }
        
        # Fire workflow_started event
        if event_callback:
            event_callback('workflow_started', {
                'workflow_id': workflow_id,
                'workflow_name': workflow.name,
                'steps_total': len(workflow.mods)
            })
        
        # Execute mods in sequence
        steps = []
        current_context = {**context}
        total_start = time.time()
        
        for i, mod_spec in enumerate(workflow.mods):
            mod_id = mod_spec['id']
            mod_stage = mod_spec.get('stage', 'post')
            mod_config = mod_spec.get('config', {})
            
            step_start = time.time()
            
            try:
                result = self._execute_mod(mod_id, current_context, mod_config)
                step_duration = time.time() - step_start
                
                if result.get('success'):
                    # Chain context
                    context_added = result.get('modify_context', {})
                    current_context.update(context_added)
                    
                    step_result = {
                        'mod_id': mod_id,
                        'status': 'success',
                        'duration': round(step_duration, 2),
                        'context_added': context_added
                    }
                    steps.append(step_result)
                    
                    # Fire step event
                    if event_callback:
                        event_callback('workflow_step', {
                            'workflow_id': workflow_id,
                            'step_index': i + 1,
                            'steps_total': len(workflow.mods),
                            **step_result
                        })
                else:
                    # Mod failed - stop workflow
                    error_msg = result.get('error', 'Unknown error')
                    steps.append({
                        'mod_id': mod_id,
                        'status': 'error',
                        'duration': round(step_duration, 2),
                        'error': error_msg
                    })
                    
                    if event_callback:
                        event_callback('workflow_error', {
                            'workflow_id': workflow_id,
                            'step_index': i + 1,
                            'mod_id': mod_id,
                            'error': error_msg
                        })
                    
                    return {
                        'success': False,
                        'workflow_id': workflow_id,
                        'error': f"{mod_id}: {error_msg}",
                        'error_at_step': i + 1,
                        'steps': steps,
                        'total_duration': round(time.time() - total_start, 2)
                    }
                    
            except Exception as e:
                step_duration = time.time() - step_start
                steps.append({
                    'mod_id': mod_id,
                    'status': 'error',
                    'duration': round(step_duration, 2),
                    'error': str(e)
                })
                
                if event_callback:
                    event_callback('workflow_error', {
                        'workflow_id': workflow_id,
                        'step_index': i + 1,
                        'mod_id': mod_id,
                        'error': str(e)
                    })
                
                return {
                    'success': False,
                    'workflow_id': workflow_id,
                    'error': f"{mod_id}: {str(e)}",
                    'error_at_step': i + 1,
                    'steps': steps,
                    'total_duration': round(time.time() - total_start, 2)
                }
        
        total_duration = round(time.time() - total_start, 2)
        
        # Fire workflow_complete event
        if event_callback:
            event_callback('workflow_complete', {
                'workflow_id': workflow_id,
                'success': True,
                'steps_completed': len(steps),
                'total_duration': total_duration
            })
        
        return {
            'success': True,
            'workflow_id': workflow_id,
            'steps': steps,
            'total_duration': total_duration,
            'final_context': current_context,
            'requires_image_reload': workflow.settings.get('requires_image_reload', False)
        }
    
    def _load_workflow_file(self, path: Path, scope: str) -> Optional[Workflow]:
        """Load a workflow from YAML file."""
        try:
            with open(path, 'r') as f:
                data = yaml.safe_load(f) or {}
            
            workflow_id = path.stem
            return Workflow(
                id=workflow_id,
                name=data.get('name', workflow_id),
                description=data.get('description', ''),
                mods=data.get('mods', []),
                settings=data.get('settings', {}),
                scope=scope
            )
        except Exception as e:
            print(f"Error loading workflow {path}: {e}")
            return None
    
    def _execute_mod(self, mod_id: str, context: Dict, mod_config: Dict = None) -> Dict:
        """Execute a single mod with the given context.
        
        Returns dict with 'success', 'modify_context', and optionally 'error'.
        """
        mod_filename = mod_id.replace('-', '_') + '.py'
        mod_file = self.mods_dir / mod_filename
        
        if not mod_file.exists():
            return {'success': False, 'error': f"Mod not found: {mod_id}"}
        
        try:
            spec = importlib.util.spec_from_file_location(mod_id, mod_file)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            
            if not hasattr(module, 'execute'):
                return {'success': False, 'error': 'Mod has no execute function'}
            
            # Execute mod
            params = mod_config or {}
            result = module.execute(context, params)
            
            if result.get('status') == 'success':
                return {
                    'success': True,
                    'modify_context': result.get('modify_context', {}),
                    'data': result.get('data', {})
                }
            else:
                error = result.get('message') or result.get('error', {}).get('message', 'Unknown')
                return {'success': False, 'error': error}
                
        except Exception as e:
            return {'success': False, 'error': str(e)}


def load_workflow_manager(job_dir: Path) -> WorkflowManager:
    """Factory function to create WorkflowManager."""
    return WorkflowManager(job_dir)
