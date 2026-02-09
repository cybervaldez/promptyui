#!/usr/bin/env python3
"""
Unified Notifier - Logs to CLI and sends toast to WebUI if available.

Usage in any hook/mod:
    from src.notify import notify
    
    notify("🚀 Job started!", "info")
    notify("✅ Generated image", "success")
    notify("⚠️ Warning message", "warning")
    notify("❌ Error occurred", "error")

The notifier will:
1. Always print to terminal with appropriate formatting
2. Try to send toast to WebUI if running (auto-detect port from env or common ports)
"""

import os
import sys
import requests
from typing import Optional
from datetime import datetime


# WebUI port detection order
DEFAULT_PORTS = [8082, 8083, 8080, 8084]

# Cache detected port to avoid repeated probing
_cached_webui_port: Optional[int] = None
_webui_checked = False


def _detect_webui_port() -> Optional[int]:
    """Try to detect running WebUI port."""
    global _cached_webui_port, _webui_checked
    
    if _webui_checked:
        return _cached_webui_port
    
    _webui_checked = True
    
    # Check environment variable first
    env_port = os.environ.get('WEBUI_PORT') or os.environ.get('PROMPT_GENERATOR_WEBUI_PORT')
    if env_port:
        try:
            port = int(env_port)
            if _check_webui_alive(port):
                _cached_webui_port = port
                return port
        except ValueError:
            pass
    
    # Try common ports
    for port in DEFAULT_PORTS:
        if _check_webui_alive(port):
            _cached_webui_port = port
            return port
    
    return None


def _check_webui_alive(port: int) -> bool:
    """Quick check if WebUI is responding on given port."""
    try:
        response = requests.get(
            f'http://localhost:{port}/api/config',
            timeout=0.5
        )
        return response.status_code == 200
    except:
        return False


def _send_toast(port: int, message: str, toast_type: str, duration: int) -> bool:
    """Send toast notification to WebUI."""
    try:
        response = requests.post(
            f'http://localhost:{port}/api/toast/push',
            json={
                'message': message,
                'type': toast_type,
                'duration': duration
            },
            timeout=1
        )
        return response.status_code == 200
    except:
        return False


def _format_cli_message(message: str, msg_type: str) -> str:
    """Format message for CLI output."""
    timestamp = datetime.now().strftime('%H:%M:%S')
    
    type_colors = {
        'info': '\033[94m',     # Blue
        'success': '\033[92m',  # Green
        'warning': '\033[93m',  # Yellow
        'error': '\033[91m',    # Red
    }
    
    type_icons = {
        'info': 'ℹ️ ',
        'success': '✓',
        'warning': '⚠️ ',
        'error': '✗',
    }
    
    reset = '\033[0m'
    color = type_colors.get(msg_type, '')
    icon = type_icons.get(msg_type, '')
    
    return f"{color}[{timestamp}] {icon} {message}{reset}"


def notify(
    message: str,
    msg_type: str = 'info',
    duration: int = 3000,
    cli_only: bool = False
) -> dict:
    """
    Send notification to CLI and WebUI (if available).
    
    Args:
        message: The message to display
        msg_type: One of 'info', 'success', 'warning', 'error'
        duration: Toast duration in milliseconds (default: 3000)
        cli_only: If True, skip WebUI toast attempt
    
    Returns:
        dict with 'cli' (always True) and 'webui' (True if toast sent)
    """
    result = {'cli': True, 'webui': False}
    
    # Always print to CLI
    print(_format_cli_message(message, msg_type))
    
    # Try WebUI if not cli_only
    if not cli_only:
        port = _detect_webui_port()
        if port:
            if _send_toast(port, message, msg_type, duration):
                result['webui'] = True
    
    return result


def notify_progress(
    current: int,
    total: int,
    message: str = '',
    msg_type: str = 'info'
) -> dict:
    """
    Send progress notification.
    
    Args:
        current: Current step
        total: Total steps
        message: Optional message
    """
    pct = int((current / total) * 100) if total > 0 else 0
    progress_msg = f"[{current}/{total}] {pct}% {message}".strip()
    
    return notify(progress_msg, msg_type)


# Convenience functions
def info(message: str, **kwargs):
    return notify(message, 'info', **kwargs)

def success(message: str, **kwargs):
    return notify(message, 'success', **kwargs)

def warning(message: str, **kwargs):
    return notify(message, 'warning', **kwargs)

def error(message: str, **kwargs):
    return notify(message, 'error', **kwargs)


if __name__ == "__main__":
    # Test the notifier
    print("Testing unified notifier...")
    info("This is an info message")
    success("This is a success message")
    warning("This is a warning message")
    error("This is an error message")
    notify_progress(5, 10, "Processing...")
