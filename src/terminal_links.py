#!/usr/bin/env python3
"""Terminal clickable links using ANSI OSC 8 escape codes.

This module provides utilities to create clickable hyperlinks in terminal output
using ANSI OSC 8 escape sequences. Modern terminals like iTerm2, GNOME Terminal,
KDE Konsole, Windows Terminal, and VS Code terminal support these links.

For terminals that don't support OSC 8, the links gracefully degrade to plain text.
"""

import os
from pathlib import Path
from typing import Optional, Tuple

# Import port detection from notify.py
from src.notify import _detect_webui_port

# Global setting for fallback mode (plain URLs instead of OSC 8)
# Set to True to force plain URL mode, or None for auto-detection
USE_PLAIN_URL_FALLBACK: Optional[bool] = None

# Cache for terminal detection
_terminal_supports_osc8: Optional[bool] = None


def detect_terminal_osc8_support() -> bool:
    """Detect if the current terminal likely supports OSC 8 hyperlinks.

    Checks environment variables to determine terminal type.
    Known terminals with OSC 8 support:
    - iTerm2, kitty, WezTerm, foot, Hyper
    - GNOME Terminal (VTE-based) 0.50+
    - Windows Terminal
    - VS Code terminal

    Returns:
        True if terminal likely supports OSC 8, False otherwise
    """
    global _terminal_supports_osc8

    if _terminal_supports_osc8 is not None:
        return _terminal_supports_osc8

    # Force fallback mode if set globally
    if USE_PLAIN_URL_FALLBACK is True:
        _terminal_supports_osc8 = False
        return False

    # Check TERM_PROGRAM (common on macOS and modern terminals)
    term_program = os.environ.get('TERM_PROGRAM', '').lower()
    if term_program in ('iterm.app', 'wezterm', 'hyper', 'vscode'):
        _terminal_supports_osc8 = True
        return True

    # Check for kitty
    if os.environ.get('KITTY_WINDOW_ID'):
        _terminal_supports_osc8 = True
        return True

    # Check for VTE-based terminals (GNOME Terminal, etc.)
    vte_version = os.environ.get('VTE_VERSION')
    if vte_version:
        try:
            # VTE 0.50+ supports OSC 8 (version 5000+)
            if int(vte_version) >= 5000:
                _terminal_supports_osc8 = True
                return True
        except (ValueError, TypeError):
            pass

    # Check for Windows Terminal
    if os.environ.get('WT_SESSION'):
        _terminal_supports_osc8 = True
        return True

    # Check TERM variable for known terminal types
    term = os.environ.get('TERM', '').lower()
    if 'kitty' in term or 'foot' in term:
        _terminal_supports_osc8 = True
        return True

    # Default to False for unknown terminals (safer fallback)
    # COSMIC terminal uses alacritty backend but may not be detected
    _terminal_supports_osc8 = False
    return False


def make_clickable_link(url: str, text: str, use_plain_url: bool = False) -> str:
    """Create ANSI OSC 8 clickable link or plain URL fallback.

    Args:
        url: Target URL (http://, file://, etc.)
        text: Display text shown in terminal
        use_plain_url: If True, return plain URL instead of OSC 8 escape codes

    Returns:
        Formatted string with ANSI escape codes for clickable link,
        or plain URL if use_plain_url=True or terminal doesn't support OSC 8.
        Format: ESC]8;;URL ESC\\ DISPLAY_TEXT ESC]8;; ESC\\

    Example:
        >>> make_clickable_link('https://example.com', 'Click me!')
        '\\033]8;;https://example.com\\033\\\\Click me!\\033]8;;\\033\\\\'
        >>> make_clickable_link('https://example.com', 'Click me!', use_plain_url=True)
        'https://example.com'
    """
    if use_plain_url or not detect_terminal_osc8_support():
        # Plain URL fallback - most terminals auto-detect these
        return url

    return f"\033]8;;{url}\033\\{text}\033]8;;\033\\"


def get_relative_output_path(absolute_path: Path) -> Optional[str]:
    """Convert absolute path to WebUI-relative path.

    The WebUI serves files from /outputs/ route. This function extracts
    the path components after 'outputs' directory to construct the WebUI URL.

    Args:
        absolute_path: Full path like /home/.../jobs/pixel-fantasy/outputs/c99/...

    Returns:
        Relative path like 'c99/default/prompt/image.png' or None if 'outputs'
        is not in the path.

    Example:
        >>> path = Path('/home/user/jobs/pixel-fantasy/outputs/c99/prompt/test.png')
        >>> get_relative_output_path(path)
        'c99/prompt/test.png'
    """
    try:
        parts = absolute_path.parts
        outputs_idx = parts.index('outputs')
        relative_parts = parts[outputs_idx + 1:]  # Everything after "outputs/"
        return '/'.join(relative_parts)
    except (ValueError, IndexError):
        return None


def format_image_link(
    image_path: Path,
    webui_port: Optional[int] = None,
    show_filename_only: bool = True
) -> str:
    """Format image path as clickable link(s).

    This function generates clickable links for terminal output:
    - HTTP link (when WebUI is running): Opens in browser via WebUI
    - File link (always): Opens in system default image viewer

    For terminals without OSC 8 support, falls back to plain URLs which
    most modern terminals will auto-detect and make clickable.

    Args:
        image_path: Absolute path to image file
        webui_port: WebUI port (auto-detected if None)
        show_filename_only: If True, display only filename; if False, show full path

    Returns:
        Formatted string with clickable link(s). Returns 'http_link | file_link'
        when WebUI is available, or just 'file_link' when offline.

    Example:
        With OSC 8 support and WebUI running:
        'image.png | image.png'  (both clickable, first opens browser, second opens viewer)

        With plain URL fallback and WebUI running:
        'http://localhost:8084/outputs/.../image.png | file:///path/to/image.png'

        Without WebUI:
        'image.png'  (clickable) or 'file:///path/to/image.png' (plain URL)
    """
    absolute_path = image_path.resolve()
    display_text = image_path.name if show_filename_only else str(image_path)

    # Detect if we should use plain URLs
    use_plain = not detect_terminal_osc8_support()

    # Always generate file:// link
    file_url = f"file://{absolute_path}"
    file_link = make_clickable_link(file_url, display_text, use_plain_url=use_plain)

    # Try to generate http:// link if WebUI is available
    if webui_port is None:
        webui_port = _detect_webui_port()

    if webui_port:
        relative_path = get_relative_output_path(absolute_path)
        if relative_path:
            http_url = f"http://localhost:{webui_port}/outputs/{relative_path}"
            http_link = make_clickable_link(http_url, display_text, use_plain_url=use_plain)
            # Show both links with separator
            return f"{http_link} | {file_link}"

    # Fallback: file:// link only
    return file_link


def format_image_saved_message(
    image_path: Path,
    generation_time: float,
    webui_port: Optional[int] = None
) -> str:
    """Format the '✅ Saved:' message with clickable links.

    This is the main function used by image_generator.py to format the
    success message after generating an image.

    Args:
        image_path: Absolute path to saved image
        generation_time: Generation time in seconds
        webui_port: WebUI port (auto-detected if None)

    Returns:
        Formatted message like: '      ✅ Saved: [link] | [link] (2.45s)'
        where [link] represents clickable text.

    Example:
        With WebUI running:
        '      ✅ Saved: image.png | image.png (2.45s)'
                         ↑http       ↑file

        Without WebUI:
        '      ✅ Saved: image.png (2.45s)'
                         ↑file
    """
    links = format_image_link(image_path, webui_port, show_filename_only=True)
    return f"      ✅ Saved: {links} ({generation_time:.2f}s)"


if __name__ == "__main__":
    # Test the terminal links
    import sys

    print("Testing terminal clickable links...")
    print()

    # Show detected terminal info
    print("Terminal detection:")
    print(f"  TERM: {os.environ.get('TERM', 'not set')}")
    print(f"  TERM_PROGRAM: {os.environ.get('TERM_PROGRAM', 'not set')}")
    print(f"  VTE_VERSION: {os.environ.get('VTE_VERSION', 'not set')}")
    supports_osc8 = detect_terminal_osc8_support()
    print(f"  OSC 8 support detected: {supports_osc8}")
    print(f"  Using fallback mode: {not supports_osc8}")
    print()

    # Test 1: Basic clickable link (both modes)
    print("Test 1: Basic clickable link")
    test_link = make_clickable_link('https://example.com', 'Click me!')
    print(f"  Current mode: {test_link}")
    test_link_plain = make_clickable_link('https://example.com', 'Click me!', use_plain_url=True)
    print(f"  Plain URL mode: {test_link_plain}")
    print()

    # Test 2: Path parsing
    print("Test 2: Path parsing")
    test_path = Path('/home/user/jobs/example/outputs/c99/prompt/image.png')
    relative = get_relative_output_path(test_path)
    print(f"  Absolute: {test_path}")
    print(f"  Relative: {relative}")
    print()

    # Test 3: Image link formatting (without WebUI)
    print("Test 3: Image link formatting (without WebUI)")
    test_image = Path('/home/user/test/outputs/c99/test.png')
    link = format_image_link(test_image, webui_port=None)
    print(f"  {link}")
    print()

    # Test 4: Full message formatting
    print("Test 4: Full message formatting")
    message = format_image_saved_message(test_image, 2.45)
    print(message)
    print()

    # Test 5: With WebUI port (simulated)
    print("Test 5: With WebUI running (simulated)")
    test_image2 = Path('/home/user/jobs/example/outputs/c99/test/image.png')
    link_with_webui = format_image_link(test_image2, webui_port=8084)
    print(f"  {link_with_webui}")
    print()

    print("Note: Links should be clickable in supported terminals.")
    print("      For COSMIC terminal, plain URLs (file://...) should auto-detect as clickable.")
