#!/usr/bin/env python3
"""
webui_cli_events.py - WebUI/CLI Event Integration Module

This module provides:
1. High-level event helpers for common event types
2. Event verification utilities for tests
3. Agent-browser debugging documentation and utilities
4. Type-safe event data structures

USAGE IN CLI CODE:
    from src.webui_cli_events import push_job_start, push_image_complete

    push_job_start(batch_id='abc123', title='Build Covers', total=10,
                   source='cli', source_page={...})
    push_image_complete(filename='img.png', relative_path='/outputs/...',
                       prompt_id='pixel-wildcards', ...)

USAGE IN TESTS:
    from src.webui_cli_events import (
        read_events_log,
        get_events_by_type,
        wait_for_event,
        verify_agent_browser
    )

    events = read_events_log(job_dir)
    job_starts = get_events_by_type(events, 'job_start')
    assert len(job_starts) == 1

    # Wait for specific event with timeout
    event = wait_for_event(job_dir, 'image_complete', timeout=10)
    assert event is not None

AGENT-BROWSER DEBUGGING:
    When debugging WebUI/CLI event integration issues, use agent-browser
    to visually verify that events are being received and processed correctly.

    See: DEBUGGING_WITH_AGENT_BROWSER section below for comprehensive guide.
"""

from typing import Dict, List, Optional, Any
from pathlib import Path
from dataclasses import dataclass
import json
import time

# =============================================================================
# EVENT TYPE CONSTANTS
# =============================================================================

EVENT_JOB_START = 'job_start'
EVENT_JOB_END = 'job_end'
EVENT_STEP_START = 'step_start'
EVENT_STEP_COMPLETE = 'step_complete'
EVENT_IMAGE_STARTED = 'image_started'
EVENT_IMAGE_COMPLETE = 'image_complete'
EVENT_WORKER = 'worker'
EVENT_MOD_UI = 'mod_ui'

# =============================================================================
# EVENT DATA STRUCTURES
# =============================================================================

@dataclass
class EventRecord:
    """Single event record from events.log."""
    timestamp: float
    source: str  # 'cli', 'worker', 'mod', etc.
    event_type: str
    data: Dict[str, Any]

# =============================================================================
# HIGH-LEVEL EVENT HELPERS
# =============================================================================

def push_job_start(batch_id: str, title: str, total: int, source: str = 'cli',
                   source_page: Optional[Dict] = None) -> bool:
    """Push job_start event to WebUI.

    Returns True if event was pushed successfully, False otherwise.
    """
    try:
        from src.webui_events import push_event
        push_event(EVENT_JOB_START, {
            'batch_id': batch_id,
            'title': title,
            'total': total,
            'source': source,
            'source_page': source_page or {}
        })
        return True
    except ImportError:
        return False

def push_job_end(batch_id: str, success: bool = True) -> bool:
    """Push job_end event to WebUI."""
    try:
        from src.webui_events import push_event
        push_event(EVENT_JOB_END, {
            'batch_id': batch_id,
            'success': success
        })
        return True
    except ImportError:
        return False

def push_image_complete(filename: str, relative_path: str, image_url: str,
                       url: str, prompt_id: str, path_string: str,
                       address_index: int, config_index: int,
                       generation_time: float = 0.0,
                       batch_id: Optional[str] = None) -> bool:
    """Push image_complete event to WebUI."""
    try:
        from src.webui_events import push_event
        data = {
            'filename': filename,
            'relative_path': relative_path,
            'image_url': image_url,
            'url': url,
            'prompt_id': prompt_id,
            'path_string': path_string,
            'address_index': address_index,
            'config_index': config_index,
            'generation_time': generation_time
        }
        if batch_id:
            data['batch_id'] = batch_id
        push_event(EVENT_IMAGE_COMPLETE, data)
        return True
    except ImportError:
        return False

# =============================================================================
# EVENT VERIFICATION UTILITIES (FOR TESTS)
# =============================================================================

def read_events_log(job_dir: Path) -> List[EventRecord]:
    """Read all events from events.log file.

    Returns list of EventRecord objects sorted by timestamp.
    """
    events_file = job_dir / 'tmp' / 'events.log'
    if not events_file.exists():
        return []

    events = []
    with open(events_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                raw = json.loads(line)
                events.append(EventRecord(
                    timestamp=raw.get('ts', 0),
                    source=raw.get('src', 'unknown'),
                    event_type=raw.get('evt', ''),
                    data=raw.get('data', {})
                ))
            except json.JSONDecodeError:
                continue

    return sorted(events, key=lambda e: e.timestamp)

def get_events_by_type(events: List[EventRecord], event_type: str) -> List[EventRecord]:
    """Filter events by type."""
    return [e for e in events if e.event_type == event_type]

def get_events_by_source(events: List[EventRecord], source: str) -> List[EventRecord]:
    """Filter events by source."""
    return [e for e in events if e.source == source]

def wait_for_event(job_dir: Path, event_type: str, timeout: float = 10.0) -> Optional[EventRecord]:
    """Wait for specific event type to appear in events.log.

    Polls the events log file until the event appears or timeout is reached.
    Returns the first matching event, or None if timeout.
    """
    start_time = time.time()
    seen_count = 0

    while time.time() - start_time < timeout:
        events = read_events_log(job_dir)
        matches = get_events_by_type(events, event_type)

        if len(matches) > seen_count:
            return matches[-1]  # Return newest event

        time.sleep(0.1)

    return None

def verify_event_sequence(events: List[EventRecord], expected_types: List[str]) -> bool:
    """Verify events occur in expected order.

    Returns True if event types appear in the expected sequence (not necessarily consecutive).
    """
    event_types = [e.event_type for e in events]

    idx = 0
    for expected in expected_types:
        try:
            idx = event_types.index(expected, idx)
        except ValueError:
            return False

    return True

# =============================================================================
# AGENT-BROWSER DEBUGGING UTILITIES
# =============================================================================

def verify_agent_browser_available() -> bool:
    """Check if agent-browser is available for visual debugging."""
    import subprocess
    try:
        result = subprocess.run(['which', 'agent-browser'],
                              capture_output=True, timeout=2)
        return result.returncode == 0
    except Exception:
        return False

def capture_webui_state(port: int, output_dir: Path, prefix: str = 'debug') -> Dict[str, str]:
    """Capture WebUI state using agent-browser for debugging.

    Returns dict with paths to captured data:
    - 'screenshot': Path to screenshot PNG
    - 'snapshot': Path to interactive elements JSON
    - 'console': Path to console output
    - 'errors': Path to JavaScript errors

    Returns empty dict if agent-browser not available.
    """
    if not verify_agent_browser_available():
        return {}

    import subprocess
    output_dir.mkdir(parents=True, exist_ok=True)

    result = {}

    # Take screenshot
    screenshot_path = output_dir / f'{prefix}_screenshot.png'
    try:
        subprocess.run(['agent-browser', 'screenshot', str(screenshot_path)],
                      capture_output=True, timeout=10)
        if screenshot_path.exists():
            result['screenshot'] = str(screenshot_path)
    except Exception:
        pass

    # Capture console output
    console_path = output_dir / f'{prefix}_console.txt'
    try:
        proc = subprocess.run(['agent-browser', 'console'],
                            capture_output=True, text=True, timeout=5)
        console_path.write_text(proc.stdout)
        result['console'] = str(console_path)
    except Exception:
        pass

    # Capture errors
    errors_path = output_dir / f'{prefix}_errors.txt'
    try:
        proc = subprocess.run(['agent-browser', 'errors'],
                            capture_output=True, text=True, timeout=5)
        errors_path.write_text(proc.stdout)
        result['errors'] = str(errors_path)
    except Exception:
        pass

    # Capture interactive snapshot
    snapshot_path = output_dir / f'{prefix}_snapshot.txt'
    try:
        proc = subprocess.run(['agent-browser', 'snapshot', '-i'],
                            capture_output=True, text=True, timeout=5)
        snapshot_path.write_text(proc.stdout)
        result['snapshot'] = str(snapshot_path)
    except Exception:
        pass

    return result

# =============================================================================
# DEBUGGING WITH AGENT-BROWSER - COMPREHENSIVE GUIDE
# =============================================================================

"""
DEBUGGING WITH AGENT-BROWSER
=============================

Agent-browser is a powerful tool for visually debugging WebUI/CLI event
integration. Use it when stdout logs and events.log are insufficient.

## When to Use Agent-Browser

### HIGH-VALUE SCENARIOS:

1. **WebUI Connection Issues**
   - Visual: Verify server loaded in browser
   - Visual: Check port detection worked
   - Visual: Confirm no JavaScript errors in console

2. **Batch Registration Failures**
   - Visual: Verify batch appears in queue sidebar
   - Visual: Check batch title displays correctly
   - Visual: Confirm item count matches expected

3. **Event Stream Debugging**
   - Visual: Monitor browser console for SSE events
   - Visual: Check if toast notifications appear
   - Visual: Verify progress updates in real-time

4. **Source Page Highlighting Verification**
   - Visual: Confirm CSS selectors target correct elements
   - Visual: Check PRIMARY vs SECONDARY target styling
   - Visual: Verify background overlay appears during builds

5. **Test Failure Investigation**
   - Visual: Screenshot WebUI state when pattern matching fails
   - Visual: Inspect DOM to understand why expected elements missing
   - Visual: Check browser console for JavaScript errors

### MEDIUM-VALUE SCENARIOS:

6. **Queue Progress Updates**
   - Visual: Watch item count decrease as generation progresses
   - Visual: Verify status transitions (pending → generating → complete)

7. **Image Generation Verification**
   - Visual: Confirm images appear in gallery sidebar
   - Visual: Check image thumbnails render correctly

### LOW-VALUE SCENARIOS (use stdout/logs instead):

- Trace ID generation (already in stdout)
- Debug log file content (use Read tool)
- CLI argument parsing (--debug-images mode)
- Batch creation success (logged to events.log)

---

## Quick Start

# 1. Start WebUI server
./start-prompty.sh  # default port 8085

# 2. Run CLI with WebUI integration
python generate-cli.py pixel-fantasy -c 99 --build covers --webui --max 2

# 3. Verify in browser using agent-browser
agent-browser open http://localhost:8089
agent-browser errors                     # Check for JavaScript errors
agent-browser console | grep -i "sse"    # Monitor SSE events
agent-browser snapshot -i                # Get interactive elements
agent-browser screenshot /tmp/debug.png  # Take screenshot

---

## Debugging Examples

### EXAMPLE 1: Debug "No batch in queue" issue

**Symptom:** CLI creates batch but it doesn't appear in WebUI queue sidebar

**Steps:**
1. Keep server running and open WebUI:
   agent-browser open http://localhost:8089

2. Check if batch appears in queue sidebar:
   agent-browser snapshot -i | grep -i "batch"
   # Should show batch card with title

3. Check browser console for SSE events:
   agent-browser console | grep -i "job_start"
   # Should see: SSE event: job_start

4. If no events, check SSE connection status:
   agent-browser console | grep -i "eventsource"
   # Should see: EventSource opened

5. Check for JavaScript errors:
   agent-browser errors
   # Look for: initQueueSidebar not defined, fetch failed, etc.

6. Take diagnostic screenshot:
   agent-browser screenshot /tmp/queue-debug.png

**Common Causes:**
- WebUI server not running (connection test should catch this)
- JavaScript error preventing queue initialization
- SSE connection failed (check browser console)
- Event pushed before SSE connection established (timing issue)

---

### EXAMPLE 2: Debug "Images not appearing in gallery"

**Symptom:** image_complete event pushed but images don't show in gallery sidebar

**Steps:**
1. Navigate to the prompt page:
   agent-browser open http://localhost:8089/?prompt=pixel-wildcards&cfg=7

2. Wait for autoreload to trigger:
   agent-browser wait 2000

3. Check for images in gallery sidebar:
   agent-browser snapshot -i | grep -i "image"
   # Should show image thumbnails with @e refs

4. Check browser console for image load errors:
   agent-browser console
   # Look for: Failed to load resource, 404 on /outputs/...

5. Verify image_complete event was received:
   agent-browser console | grep -i "image_complete"
   # Should see: SSE event: image_complete

6. Check the relative_path in event data:
   # Compare with actual file path on disk
   # Common issue: URL encoding mismatch

**Common Causes:**
- Relative path in event doesn't match actual file location
- Image file exists but URL encoding is wrong
- Gallery not initialized (JavaScript error)
- Autoreload not triggered (no SSE event received)

---

### EXAMPLE 3: Debug source page highlighting not working

**Symptom:** CLI prints source_page selectors but UI elements don't highlight

**Steps:**
1. Navigate to page that should be highlighted:
   agent-browser open http://localhost:8089/?prompt=pixel-wildcards&path=mood[1]~pose[1]&cfg=7

2. Capture interactive elements snapshot:
   agent-browser snapshot -i
   # Compare selectors from CLI output with actual elements

3. Check if CSS classes are applied:
   agent-browser console
   # Look for: autoreload-pending, autoreload-generating classes

4. Verify selectors match actual DOM structure:
   # CLI output shows: .checkpoint-card[data-path="mood[1]~pose[1]"]
   # Browser snapshot should show matching element with @e ref

5. Check for CSS styling issues:
   agent-browser screenshot /tmp/highlight-state.png
   # Visual check: Is the element highlighted with yellow/blue background?

**Common Causes:**
- CSS selectors don't match actual DOM structure
- Selector syntax error (escaping issues)
- CSS classes not applied (JavaScript error)
- Element exists but styling not visible (CSS specificity issue)

---

### EXAMPLE 4: Debug SSE event stream issues

**Symptom:** Connection test passes but no events received in browser

**Steps:**
1. Open WebUI and monitor console:
   agent-browser open http://localhost:8089
   agent-browser console | grep -i "event"
   # Should see: SSE connected, EventSource opened

2. Trigger event from CLI:
   # In another terminal:
   python generate-cli.py pixel-fantasy -c 99 --build covers --webui --max 1

3. Watch browser console in real-time:
   agent-browser console | tail -20
   # Should see: SSE event: job_start, SSE event: image_complete

4. Check EventSource state:
   agent-browser console
   # Look for errors: EventSource failed, Reconnecting...

5. Verify server is pushing events:
   # Check events.log file:
   tail -f jobs/pixel-fantasy/tmp/events.log
   # Should see events being written

**Common Causes:**
- SSE endpoint not initialized (server issue)
- CORS issues (check browser console)
- EventSource connection dropped (network issue)
- Events pushed but not broadcast (event_manager issue)

---

## Agent-Browser Command Reference

### Navigation
agent-browser open <url>              # Open URL in browser
agent-browser reload                  # Reload current page
agent-browser wait <ms>               # Wait for specified milliseconds

### Inspection
agent-browser snapshot -i             # Get interactive elements with @e refs
agent-browser console                 # Get browser console output
agent-browser errors                  # Get JavaScript errors only

### Capture
agent-browser screenshot <path>       # Save screenshot to file

### Search
agent-browser snapshot -i | grep -i <term>     # Search for elements
agent-browser console | grep -i <term>         # Search console output

### Useful Patterns
# Monitor SSE events
agent-browser console | grep -i "sse event"

# Check for batch in queue
agent-browser snapshot -i | grep -i "batch"

# Verify images in gallery
agent-browser snapshot -i | grep -i "thumbnail"

# Watch for errors
agent-browser errors | grep -i "error"

---

## Integration with Tests

Use `capture_webui_state()` helper in test code:

```python
from src.webui_cli_events import capture_webui_state

# In test failure handler:
if not result.passed:
    debug_dir = job_dir / 'tmp' / 'debug'
    artifacts = capture_webui_state(port=8084, output_dir=debug_dir,
                                    prefix=result.debug_id)
    if artifacts:
        print(f"      Screenshot: {artifacts.get('screenshot')}")
        print(f"      Console: {artifacts.get('console')}")
```

---

## Related Documentation

- Agent-browser skill guide: `.claude/skills/agent-browser/SKILL.md`
- WebUI event system: `webui/prompty/js/` (SSE handling)
- Event pushing: `src/webui_events.py`
- Server: `webui/prompty/server/`
"""
