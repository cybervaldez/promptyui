#!/usr/bin/env python3
"""
Mod Events - Helper module for mods to emit UI events via SSE.

This module provides a simple API for mods to communicate with the WebUI
by emitting events that update dynamic UI containers in the sidebar.

Usage in a mod script:
    from src.mod_events import emit_mod_event
    
    emit_mod_event('error-log', 'append', {
        'title': '⚠️ Errors',
        'item': {
            'id': 'unique-item-id',
            'html': '<div>Error message</div>',
            'class': 'error'
        }
    })

Event Types:
    mod_ui: Updates a mod's UI container
    
Actions:
    append: Add an item to the container's list
    replace: Replace entire container content
    clear: Clear all items from container
    remove_item: Remove a specific item by id
"""

import json
import time
from pathlib import Path
from typing import Dict, Any, Optional


# Global reference to event manager (set by start.py)
_event_manager = None


def set_event_manager(manager):
    """Set the global event manager (called by start.py on init)."""
    global _event_manager
    _event_manager = manager


def emit_mod_event(mod_id: str, action: str, data: Dict[str, Any]) -> bool:
    """
    Emit a mod UI event via SSE.
    
    Args:
        mod_id: Unique identifier for the mod's UI container.
                This becomes the DOM id: #mod-{mod_id}
        action: One of 'append', 'replace', 'clear', 'remove_item'
        data: Payload specific to the action:
            - append: {title?, item: {id, html, class?}, max_items?}
            - replace: {title?, html}
            - clear: {}
            - remove_item: {item_id}
    
    Returns:
        True if event was sent, False if no event manager available
    """
    if _event_manager is None:
        # Fallback: Try to write to a shared file for later pickup
        _write_pending_event(mod_id, action, data)
        return False
    
    event_data = {
        'mod_id': mod_id,
        'action': action,
        'payload': data,
        'ts': time.time()
    }
    
    _event_manager.push('mod_ui', event_data)
    return True


def _write_pending_event(mod_id: str, action: str, data: Dict[str, Any]):
    """Write event to a pending file for pickup by start.py."""
    # This allows mods running in separate processes (like run_job.py)
    # to still emit events that the WebUI can pick up
    pending_dir = Path('/tmp/prompt-generator-mod-events')
    pending_dir.mkdir(exist_ok=True)
    
    event = {
        'mod_id': mod_id,
        'action': action,
        'payload': data,
        'ts': time.time()
    }
    
    # Use timestamp for unique filename
    event_file = pending_dir / f'{int(time.time() * 1000)}.json'
    with open(event_file, 'w') as f:
        json.dump(event, f)


def collect_pending_events() -> list:
    """Collect and clear pending events from disk."""
    pending_dir = Path('/tmp/prompt-generator-mod-events')
    if not pending_dir.exists():
        return []
    
    events = []
    for event_file in sorted(pending_dir.glob('*.json')):
        try:
            with open(event_file, 'r') as f:
                events.append(json.load(f))
            event_file.unlink()  # Clean up after reading
        except Exception:
            pass
    
    return events


# Convenience functions for common patterns

def log_error(prompt_id: str, path: str, address_index: int, config_index: int, 
              error_message: str, error_code: str = 'UNKNOWN'):
    """Log an error to the error-log mod container."""
    item_id = f"{prompt_id}/{path}/i{address_index}/c{config_index}"
    
    emit_mod_event('error-log', 'append', {
        'title': '⚠️ Errors',
        'item': {
            'id': item_id,
            'html': f'''
                <div class="mod-error-item" 
                     data-prompt-id="{prompt_id}" 
                     data-path="{path}" 
                     data-address-index="{address_index}" 
                     data-config-index="{config_index}">
                    <div class="error-path">{prompt_id}/{path} i{address_index} c{config_index}</div>
                    <div class="error-msg">{error_code}: {error_message}</div>
                    <button class="btn-retry btn-icon" onclick="retryErroredItem(this)" title="Retry">🔄</button>
                </div>
            ''',
            'class': 'error'
        },
        'max_items': 50
    })


def clear_errors():
    """Clear the error log."""
    emit_mod_event('error-log', 'clear', {})


def artifacts_updated(prompt_id: str, path: str, address_index: int, config_index: int,
                      mod_id: str = None):
    """Notify UI that artifacts were updated for a node.
    
    Call this after saving artifacts to trigger UI refresh.
    Works in both WebUI context and CLI (run_job.py) context.
    
    Args:
        prompt_id: Prompt ID
        path: Path string (checkpoint path)
        address_index: Image address index
        config_index: Config index  
        mod_id: Optional mod ID that created the artifacts
    """
    emit_mod_event('artifacts', 'refresh', {
        'prompt_id': prompt_id,
        'path': path,
        'address': address_index,
        'config': config_index,
        'mod_id': mod_id
    })
