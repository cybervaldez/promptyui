#!/usr/bin/env python3
"""
Config Injector Mod - Stage: build

Pre-computes metadata at build time and injects into prompt.json.
This demonstrates the "Config Injection" pattern for deterministic builds.

Use Cases:
- Hash computation for caching
- Expensive pre-computations
- Build-time configuration
"""

import hashlib
from datetime import datetime


def execute(context):
    """
    Runs ONCE per prompt during build-checkpoints.py.
    Modifies prompt_data to inject computed metadata.
    """
    hook = context.get('hook', '')
    
    if hook != 'mods_build':
        return {'status': 'skip', 'reason': 'Not build stage'}
    
    prompt_data = context.get('prompt_data', {})
    prompt_id = context.get('prompt_id', 'unknown')
    
    # Compute a hash of the prompt structure for cache validation
    prompt_str = str(prompt_data.get('checkpoints', []))
    prompt_hash = hashlib.md5(prompt_str.encode()).hexdigest()[:8]
    
    # Count configurations
    configs = prompt_data.get('configs', [])
    config_count = len(configs)
    
    # Count checkpoints
    checkpoints = prompt_data.get('checkpoints', [])
    checkpoint_count = len(checkpoints)
    
    # Inject metadata into prompt_data
    if 'mods' not in prompt_data:
        prompt_data['mods'] = {}
    
    prompt_data['mods']['config-injector'] = {
        'hash': prompt_hash,
        'computed_at': datetime.now().isoformat(),
        'config_count': config_count,
        'checkpoint_count': checkpoint_count,
        'version': '1.0.0'
    }
    
    return {
        'status': 'success',
        'modify_context': {'prompt_data': prompt_data},
        'data': {
            'hash': prompt_hash,
            'configs': config_count,
            'checkpoints': checkpoint_count
        }
    }
