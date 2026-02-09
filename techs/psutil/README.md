# psutil

psutil (process and system utilities) is a cross-platform Python library for retrieving information on running processes and system utilization (CPU, memory, disks, network, sensors). In this project, psutil is used in exactly one location -- `webui/prompty/server/app.py` -- to find and kill existing server instances occupying a given port before starting a new WebUI server. It iterates over system processes via `psutil.process_iter()`, inspects their network connections to find port matches, and sends SIGTERM/SIGKILL signals to free the port. The server itself is Python's built-in `http.server` (ThreadedHTTPServer), not Flask.

## Domain Classification

| Domain | Applies |
|--------|---------|
| State Management | No |
| UI Components | No |
| Data Fetching | No |
| Form Handling | No |
| Animation | No |
| Routing | No |
| Testing Tools | No |
| Build Tools | Yes |
| Styling | No |
| Auth | No |

> **Note:** psutil is a system infrastructure library. It most closely fits "Build Tools" because it supports the development server lifecycle (port management, process cleanup). It is not a UI-centric technology.

## Pipeline Impact

| Skill | Impact | Reason |
|-------|--------|--------|
| coding-guard | Medium | Must flag missing exception handling around `process_iter()` and `proc.connections()` calls. Race conditions are common -- processes can disappear between iteration and action. Must catch `NoSuchProcess`, `AccessDenied`, `ZombieProcess`. |
| e2e | Medium | WebUI server startup depends on psutil successfully freeing the port. If port cleanup fails, server won't start and all E2E tests fail. |
| e2e-investigate | Medium | When server fails to start, psutil-related errors (permission denied, zombie processes, port still occupied) are common root causes. |
| e2e-guard | Low | Tests should verify server startup/shutdown lifecycle including port cleanup. |
| create-task | Low | Tasks involving server management should follow the existing `_kill_running_instances()` pattern. |
| cli-first | Low | Port status can be verified via CLI: `python -c "import psutil; print([c for c in psutil.net_connections() if c.laddr.port == 8085])"` |
| ux-planner | None | No UI impact. |
| ui-planner | None | No visual design impact. |
| ui-review | None | No visual design impact. |
| ux-review | None | No visual design impact. |

## Core Concepts

- **process_iter(attrs, ad_value)**: Iterator over all running processes. Accepts `attrs` list to pre-fetch process info via `as_dict()`, avoiding per-attribute race conditions.
- **Process object**: Wraps a PID. Key methods: `.connections(kind)`, `.send_signal()`, `.terminate()` (SIGTERM), `.kill()` (SIGKILL), `.wait(timeout)`. PID reuse is guarded internally.
- **Connections**: `proc.connections(kind='inet')` returns named tuples with `laddr` (local address as `(ip, port)`) and `raddr` (remote address).
- **Exception hierarchy**: `Error` > `NoSuchProcess`, `AccessDenied`, `ZombieProcess`. Always catch all three around process operations.

## Common Patterns

**Find and kill process by port (this project's pattern):**
```python
def _kill_running_instances(port: int):
    import psutil
    import signal

    for proc in psutil.process_iter(['pid', 'name']):
        try:
            connections = proc.connections(kind='inet')
            for conn in connections:
                if hasattr(conn, 'laddr') and conn.laddr.port == port:
                    proc.send_signal(signal.SIGTERM)
                    proc.wait(timeout=2)
        except psutil.TimeoutExpired:
            proc.kill()  # Escalate to SIGKILL
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass  # Process already gone or inaccessible
```

## Anti-Patterns & Gotchas

**Missing exception handling (race condition):**
```python
# BAD: Process can disappear between process_iter and connections()
for proc in psutil.process_iter():
    conns = proc.connections()  # Raises NoSuchProcess if process died

# GOOD: Wrap in try/except
for proc in psutil.process_iter(['pid', 'name']):
    try:
        conns = proc.connections(kind='inet')
    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
        continue
```

**Not escalating from SIGTERM to SIGKILL:**
```python
# BAD: Process may ignore SIGTERM and port stays occupied
proc.terminate()

# GOOD: Terminate with timeout, then force kill
proc.terminate()
try:
    proc.wait(timeout=3)
except psutil.TimeoutExpired:
    proc.kill()
```

## Testing Considerations

- **Mocking psutil**: For unit tests, mock `psutil.process_iter()` to return fake process objects. Mock `.connections()`, `.terminate()`, `.kill()`, `.wait()` methods individually.
- **Race condition simulation**: Test behavior when process disappears between `process_iter()` and `.connections()` by mocking `NoSuchProcess` raises.
- **Cleanup**: Any test that starts a server process must ensure cleanup in teardown, or subsequent test runs will hit port conflicts.

## Resources

- Official docs: https://psutil.readthedocs.io/
- GitHub: https://github.com/giampaolo/psutil
- PyPI: https://pypi.org/project/psutil/
