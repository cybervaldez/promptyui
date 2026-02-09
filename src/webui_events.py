#!/usr/bin/env python3
"""
WebUI Events - Helper module for hooks to push real-time updates to WebUI.

Hooks can import and use these functions to send events through the SSE stream.

Usage in hooks:
    from src.webui_events import push_toast, push_image_event
    
    def execute(context, params):
        push_toast("Processing started...", level="info")
        
        # ... do work ...
        
        push_image_event('image_complete', {
            'prompt': context['prompt_id'],
            'path': context['path'],
            'url': f"/outputs/{image_path}"
        })
        
        return {'status': 'success'}
"""

import requests
import os
import logging
from typing import Optional

# Create logger (only if WEBUI_DEBUG is set)
_debug = os.environ.get('WEBUI_DEBUG', '').lower() in ('1', 'true', 'yes')
_logger = logging.getLogger('webui_events') if _debug else None


def _get_webui_port() -> Optional[int]:
    """Get WebUI port from environment or default to 8084."""
    return int(os.environ.get('WEBUI_PORT', '8084'))


def _get_trace_id() -> Optional[str]:
    """Get trace-id from DEBUG_ID environment variable."""
    return os.environ.get('DEBUG_ID')


def test_webui_connection(port: int = None) -> tuple[bool, str]:
    """Test if WebUI server is reachable.

    Args:
        port: Port to test (if None, uses _get_webui_port())

    Returns:
        (is_connected, message)
            is_connected: True if server is reachable
            message: Status message describing the connection result
    """
    if port is None:
        port = _get_webui_port()

    try:
        response = requests.get(
            f'http://localhost:{port}/api/config',
            timeout=2
        )
        if response.status_code == 200:
            config = response.json()
            return True, f"Connected to WebUI on port {port} (job: {config.get('job', 'unknown')})"
        else:
            return False, f"WebUI responded with status {response.status_code}"
    except requests.exceptions.ConnectionError:
        return False, f"Connection refused - no server running on port {port}"
    except requests.exceptions.Timeout:
        return False, f"Connection timeout on port {port}"
    except Exception as e:
        return False, f"Connection failed: {str(e)}"


def push_toast(message: str, level: str = 'info', duration: int = 3000):
    """Push a toast notification to the WebUI.

    Args:
        message: Toast message text
        level: 'info', 'success', 'warning', or 'error'
        duration: Display duration in milliseconds
    """
    try:
        port = _get_webui_port()
        headers = {'Content-Type': 'application/json'}
        trace_id = _get_trace_id()
        if trace_id:
            headers['X-Trace-ID'] = trace_id
        requests.post(
            f'http://localhost:{port}/api/toast/push',
            json={
                'message': message,
                'type': level,
                'duration': duration
            },
            headers=headers,
            timeout=2  # Increased from 1 to 2 seconds for reliability
        )
    except:
        # Silently fail - WebUI events are non-critical
        pass


def push_image_event(event_type: str, data: dict):
    """Push an image-related event to the WebUI.

    Args:
        event_type: 'image_started', 'image_complete', or 'image_failed'
        data: Event data dict with prompt, path, url, etc.
    """
    try:
        # For now, image events go through the same mechanism
        # In the future, could have a dedicated endpoint
        port = _get_webui_port()
        headers = {'Content-Type': 'application/json'}
        trace_id = _get_trace_id()
        if trace_id:
            headers['X-Trace-ID'] = trace_id
        requests.post(
            f'http://localhost:{port}/api/event/push',
            json={
                'type': event_type,
                'data': data
            },
            headers=headers,
            timeout=2  # Increased from 1 to 2 seconds for reliability
        )
    except:
        # Silently fail - WebUI events are non-critical
        pass


def push_event(event_type: str, data: dict):
    """Push a generic event to the WebUI.

    Args:
        event_type: Event type identifier
        data: Event data dict
    """
    try:
        port = _get_webui_port()
        headers = {'Content-Type': 'application/json'}
        trace_id = _get_trace_id()
        if trace_id:
            headers['X-Trace-ID'] = trace_id
        response = requests.post(
            f'http://localhost:{port}/api/event/push',
            json={
                'type': event_type,
                'data': data
            },
            headers=headers,
            timeout=2  # Increased from 1 to 2 seconds for reliability
        )
        response.raise_for_status()

        if _logger:
            _logger.info(f"Event pushed: {event_type}")

    except Exception as e:
        # Log only if debug mode
        if _logger:
            _logger.warning(f"Failed to push event '{event_type}': {e}")
        # Still silently fail - non-critical
        pass
