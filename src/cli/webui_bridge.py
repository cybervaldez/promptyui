"""
src/cli/webui_bridge.py - WebUI Integration

All WebUI-specific code including:
- Source page generation for UI highlighting
- Debug output for source pages
- WebUI connection testing
- Port detection

Debug relevance: When WebUI shows wrong state
"""

import json
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple


def get_source_page_for_build(build_action: str, prompt_id: str = None,
                               path: str = None, config_index: int = 0,
                               address_index: int = 1) -> Dict:
    """Generate source_page with ui_config.targets array (frontend-compatible).

    Returns structure that works with AutoreloadManager's multi-target iteration.
    Enables WebUI source highlighting for CLI-triggered builds.

    Args:
        build_action: 'covers', 'configs', 'variations', 'all'
        prompt_id: Prompt ID (optional for covers/all)
        path: Checkpoint path (required for configs/variations)
        config_index: Config index
        address_index: Address index

    Returns:
        dict: source_page object with ui_config.targets array
    """
    if build_action == 'covers':
        return {
            'type': 'homegrid',
            'prompt_id': prompt_id,
            'cfg': config_index,
            'source_section': 'checkpoints-grid',
            'ui_config': {
                'targets': [
                    {
                        'container_selector': '#checkpoints-grid',
                        'item_selector': '.checkpoint-card[data-path="{path}"]'
                    }
                ],
                'pending_class': 'autoreload-pending',
                'generating_class': 'autoreload-generating',
                'complete_class': 'autoreload-complete'
            }
        }

    elif build_action == 'all':
        return {
            'type': 'homegrid',
            'prompt_id': prompt_id,
            'action': 'build_all',
            'source_section': 'config-panel',
            'ui_config': {
                'targets': [
                    {
                        'container_selector': '#config-panel',
                        'item_selector': '.config-item[data-config-idx="{config}"]'
                    }
                ],
                'pending_class': 'autoreload-pending',
                'generating_class': 'autoreload-generating',
                'complete_class': 'autoreload-complete'
            }
        }

    elif build_action == 'configs':
        # Modal with TWO targets: primary (styles) + secondary orange (variations)
        return {
            'type': 'modal',
            'prompt_id': prompt_id,
            'path': path,
            'cfg': config_index,
            'img': address_index,
            'source_section': 'related-styles-container',
            'ui_config': {
                'targets': [
                    {
                        'container_selector': '#related-images-styles',
                        'item_selector': '.related-image-thumb[data-config-idx="{config}"]'
                    },
                    {
                        'container_selector': '#related-images-variations',
                        'item_selector': '.related-image-thumb[data-index="{address}"]',
                        'use_orange': True
                    }
                ],
                'pending_class': 'autoreload-pending',
                'generating_class': 'autoreload-generating',
                'complete_class': 'autoreload-complete'
            }
        }

    elif build_action == 'variations':
        # Modal with TWO targets: primary (variations) + secondary orange (styles)
        return {
            'type': 'modal',
            'prompt_id': prompt_id,
            'path': path,
            'cfg': config_index,
            'img': address_index,
            'source_section': 'related-variations-container',
            'ui_config': {
                'targets': [
                    {
                        'container_selector': '#related-images-variations',
                        'item_selector': '.related-image-thumb[data-index="{address}"]'
                    },
                    {
                        'container_selector': '#related-images-styles',
                        'item_selector': '.related-image-thumb[data-config-idx="{config}"]',
                        'use_orange': True
                    }
                ],
                'pending_class': 'autoreload-pending',
                'generating_class': 'autoreload-generating',
                'complete_class': 'autoreload-complete'
            }
        }

    else:
        # Fallback: minimal source_page
        return {
            'type': 'cli',
            'build_action': build_action,
            'source_section': 'unknown'
        }


def print_source_page_debug(source_page: dict, items: list = None) -> None:
    """Print verbose source_page info showing targets array for CLI debugging.

    Displays:
    - type and source_section (where background overlay applies)
    - TARGETS array with PRIMARY/SECONDARY labels
    - Sample selectors computed from items

    Args:
        source_page: The source_page dict to print
        items: Optional list of items to compute sample selectors
    """
    print("\n" + "=" * 65)
    print("SOURCE_PAGE (for WebUI highlighting)")
    print("=" * 65)
    print(f"  type:           {source_page.get('type', 'N/A')}")
    print(f"  source_section: {source_page.get('source_section', 'N/A')}")
    print(f"  prompt_id:      {source_page.get('prompt_id', 'N/A')}")
    if source_page.get('path'):
        print(f"  path:           {source_page.get('path')}")
    print(f"  cfg:            {source_page.get('cfg', 0)}")
    if source_page.get('img') is not None:
        print(f"  img:            {source_page.get('img')}")

    # Print targets array
    ui_config = source_page.get('ui_config', {})
    targets = ui_config.get('targets', [])
    source_section = source_page.get('source_section', '')

    print()
    print(f"  TARGETS ({len(targets)} container{'s' if len(targets) != 1 else ''}):")

    for i, target in enumerate(targets):
        container = target.get('container_selector', 'N/A')
        selector = target.get('item_selector', 'N/A')
        use_orange = target.get('use_orange', False)

        # Determine if primary (first target is always primary by convention)
        is_primary = (i == 0)

        if is_primary:
            label = "PRIMARY"
        elif use_orange:
            label = "SECONDARY (orange)"
        else:
            label = "SECONDARY"

        print(f"    [{i}] {label}: {container}")
        print(f"        selector: {selector}")

        # Show sample selectors if items provided
        if items:
            print("        samples:")
            for item in items[:2]:
                sample = selector
                sample = sample.replace('{path}', item.get('path', item.get('path_string', '')))
                sample = sample.replace('{config}', str(item.get('config_index', 0)))
                sample = sample.replace('{address}', str(item.get('address_index', 1)))
                print(f"          -> {sample}")

    print("=" * 65 + "\n")


def detect_webui_port(job: str, composition: int, explicit_port: int = None) -> int:
    """Detect WebUI port from config file or use explicit/default.

    Priority:
    1. Explicit --port flag
    2. Port from .prompt-generator.config.json (if job/composition match)
    3. Default 8084

    Args:
        job: Job name
        composition: Composition ID
        explicit_port: Port from --port flag (if provided)

    Returns:
        Port number to use
    """
    # Priority 1: Explicit flag
    if explicit_port is not None:
        return explicit_port

    # Priority 2: Read from config file
    config_file = Path.cwd() / '.prompt-generator.config.json'
    if config_file.exists():
        try:
            with open(config_file) as f:
                config = json.load(f)

            # Check last_run section
            last_run = config.get('last_run', {})
            if (last_run.get('job') == job and
                last_run.get('composition') == composition and
                'port' in last_run):
                detected_port = last_run['port']
                print(f"   Detected WebUI port from config: {detected_port}")
                return detected_port
        except (json.JSONDecodeError, KeyError):
            pass

    # Priority 3: Default
    return 8084


def auto_detect_webui_server(job: str, composition: int, explicit_port: int = None) -> Tuple[bool, int]:
    """Auto-detect if a WebUI server is running and return its port.

    This allows CLI to work with WebUI without requiring --webui flag.
    When a server is detected, WebUI integration is enabled automatically.

    Args:
        job: Job name
        composition: Composition ID
        explicit_port: Port from --port flag (if provided)

    Returns:
        (is_running, port): Tuple of (server is running, port number)
    """
    import requests

    # Get the likely port from config
    port = detect_webui_port(job, composition, explicit_port)

    # Test connection
    try:
        response = requests.get(
            f'http://localhost:{port}/api/config',
            timeout=1
        )
        if response.status_code == 200:
            config = response.json()
            server_job = config.get('job', '')
            if server_job == job:
                return True, port
    except:
        pass

    # Try common fallback ports
    fallback_ports = [8089, 8082, 8083, 8080, 8084]
    for fallback_port in fallback_ports:
        if fallback_port == port:
            continue  # Already tried
        try:
            response = requests.get(
                f'http://localhost:{fallback_port}/api/config',
                timeout=0.5
            )
            if response.status_code == 200:
                config = response.json()
                server_job = config.get('job', '')
                if server_job == job:
                    return True, fallback_port
        except:
            continue

    return False, port
