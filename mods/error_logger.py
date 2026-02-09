#!/usr/bin/env python3
"""
Error Logger Mod - Log failed tasks to UI sidebar.

This mod captures errors from image generation and displays them
in a dedicated UI container in the sidebar. It serves as a blueprint
for future UI-related mods.

Configuration in mods.yaml:
    error-logger:
        type: script
        execution_scope: image
        stage: post
        script: ./mods/error_logger.py
        params:
            max_items: 50

Or register it as an error hook in hooks.yaml:
    hooks:
        error:
            - script: ./mods/error_logger.py
"""

import sys
from pathlib import Path
from datetime import datetime

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.mod_events import log_error


def execute(context: dict, params: dict) -> dict:
    """
    Log errors to the mod UI container.
    
    This can be called in two ways:
    1. As an error hook (hooks.yaml) - receives error context directly
    2. As a post mod - checks for errors in the previous hook result
    
    Context expected (as error hook):
        - error_message: The error message
        - prompt_id: Prompt identifier
        - path: Path string
        - address_index: Image index (optional)
        - config_index: Config index (optional)
    """
    # Extract error info based on how we're called
    error_message = context.get('error_message')
    
    if not error_message:
        # Check if there's a last_hook_error in context (for post-mod usage)
        last_error = context.get('last_hook_error', {})
        error_message = last_error.get('message')
        
        if not error_message:
            return {'status': 'skip', 'message': 'No error to log'}
    
    prompt_id = context.get('prompt_id', 'unknown')
    path = context.get('path', context.get('path_string', 'unknown'))
    address_index = context.get('address_index', 1)
    config_index = context.get('config_index', 0)
    error_code = context.get('error_code', 'UNKNOWN')
    
    # Log to mod UI
    log_error(
        prompt_id=prompt_id,
        path=path,
        address_index=address_index,
        config_index=config_index,
        error_message=error_message,
        error_code=error_code
    )
    
    # Also log to terminal for visibility
    print(f"   ❌ Error logged: {path} i{address_index}c{config_index}: {error_message}")
    
    return {
        'status': 'success',
        'data': {
            'logged': True,
            'prompt_id': prompt_id,
            'path': path,
            'error': error_message
        }
    }


# Allow running as standalone for testing
if __name__ == "__main__":
    print("Error Logger Mod - Test Mode")
    
    # Test with sample context
    test_context = {
        'error_message': 'No resolved_prompt in context',
        'prompt_id': 'fashion-editorial',
        'path': 'outfits[1]/expression[1]~stance[1]/camera[1]',
        'address_index': 1,
        'config_index': 0
    }
    
    result = execute(test_context, {})
    print(f"Result: {result}")
