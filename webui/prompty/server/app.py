"""
PromptyUI Server Application

HTTP server for the PromptyUI UI.
Runs on port 8085 (started via ./start-prompty.sh).
"""

import http.server
import json
import socketserver
import urllib.parse
import argparse
import re
from pathlib import Path
from functools import partial


class PUHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler for PromptyUI API and static files."""

    # Class attributes
    port = 8085

    def __init__(self, *args, directory=None, **kwargs):
        self.jm_dir = Path(__file__).parent.parent
        super().__init__(*args, directory=str(self.jm_dir), **kwargs)

    def send_json(self, data, status=200):
        """Send JSON response."""
        body = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format, *args):
        """Custom log format."""
        print(f"[PU] {args[0]} - {args[1]}")

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        """Handle GET requests."""
        from .api import jobs, extensions, operations, session, pipeline, artifacts

        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = dict(urllib.parse.parse_qsl(parsed.query))

        # API routes — order matters (more specific first)
        # Pipeline: /api/pu/job/{id}/pipeline/run or /api/pu/job/{id}/pipeline/stop
        pipeline_run_match = re.match(r'^/api/pu/job/([^/]+)/pipeline/run$', path)
        pipeline_stop_match = re.match(r'^/api/pu/job/([^/]+)/pipeline/stop$', path)
        # Session: /api/pu/job/{id}/session
        session_match = re.match(r'^/api/pu/job/([^/]+)/session$', path)
        # Artifacts: /api/pu/job/{id}/artifacts or /api/pu/job/{id}/artifacts/{mod_id}/{filename}
        artifacts_list_match = re.match(r'^/api/pu/job/([^/]+)/artifacts$', path)
        artifacts_file_match = re.match(r'^/api/pu/job/([^/]+)/artifacts/([^/]+)/(.+)$', path)
        # Operations: /api/pu/job/{id}/operations or /api/pu/job/{id}/operation/{name}
        op_match = re.match(r'^/api/pu/job/([^/]+)/operations$', path)
        op_get_match = re.match(r'^/api/pu/job/([^/]+)/operation/([^/]+)$', path)

        if pipeline_run_match:
            job_id = urllib.parse.unquote(pipeline_run_match.group(1))
            prompt_id = params.get('prompt_id', '')
            pipeline.handle_pipeline_run(self, job_id, prompt_id)
        elif pipeline_stop_match:
            job_id = urllib.parse.unquote(pipeline_stop_match.group(1))
            pipeline.handle_pipeline_stop(self, job_id)
        elif session_match:
            job_id = urllib.parse.unquote(session_match.group(1))
            session.handle_session_get(self, job_id)
        elif artifacts_list_match:
            job_id = urllib.parse.unquote(artifacts_list_match.group(1))
            artifacts.handle_artifacts_list(self, job_id)
        elif artifacts_file_match:
            job_id = urllib.parse.unquote(artifacts_file_match.group(1))
            mod_id = urllib.parse.unquote(artifacts_file_match.group(2))
            filename = urllib.parse.unquote(artifacts_file_match.group(3))
            artifacts.handle_artifact_file(self, job_id, mod_id, filename)
        elif op_match:
            job_id = urllib.parse.unquote(op_match.group(1))
            operations.handle_operations_list(self, job_id)
        elif op_get_match:
            job_id = urllib.parse.unquote(op_get_match.group(1))
            op_name = urllib.parse.unquote(op_get_match.group(2))
            operations.handle_operation_get(self, job_id, op_name)
        elif path == '/api/pu/jobs':
            jobs.handle_jobs_list(self, params)
        elif path.startswith('/api/pu/job/'):
            job_id = urllib.parse.unquote(path[12:])
            jobs.handle_job_get(self, job_id, params)
        elif path == '/api/pu/extensions':
            extensions.handle_extensions_list(self, params)
        elif path.startswith('/api/pu/extension/'):
            ext_path = urllib.parse.unquote(path[18:])
            extensions.handle_extension_get(self, ext_path, params)
        elif path == '/' or path == '/index.html':
            self.serve_index()
        elif path == '/demo' or path == '/demo.html':
            self.serve_template('demo.html')
        else:
            # Serve static files
            super().do_GET()

    def do_POST(self):
        """Handle POST requests."""
        from .api import preview, export, extensions, operations, session, move_to_theme

        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # Read body
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        params = json.loads(body) if body else {}

        # Session save: /api/pu/job/{id}/session
        session_save_match = re.match(r'^/api/pu/job/([^/]+)/session$', path)
        # Operations save: /api/pu/job/{id}/operation/{name}
        op_save_match = re.match(r'^/api/pu/job/([^/]+)/operation/([^/]+)$', path)

        if session_save_match:
            job_id = urllib.parse.unquote(session_save_match.group(1))
            session.handle_session_save(self, job_id, params)
        elif op_save_match:
            job_id = urllib.parse.unquote(op_save_match.group(1))
            op_name = urllib.parse.unquote(op_save_match.group(2))
            operations.handle_operation_save(self, job_id, op_name, params)
        elif path == '/api/pu/preview':
            preview.handle_preview(self, params)
        elif path == '/api/pu/validate':
            export.handle_validate(self, params)
        elif path == '/api/pu/export':
            export.handle_export(self, params)
        elif path == '/api/pu/extension/save':
            extensions.handle_extension_save(self, params)
        elif path == '/api/pu/extension/push-wildcards':
            extensions.handle_extension_push_wildcards(self, params)
        elif path == '/api/pu/move-to-theme':
            move_to_theme.handle_move_to_theme(self, params)
        else:
            self.send_json({'error': 'Not found'}, 404)

    def serve_index(self):
        """Serve the main HTML page."""
        self.serve_template('index.html')

    def serve_template(self, filename):
        """Serve an HTML template with cache busting."""
        template_path = self.jm_dir / 'templates' / filename

        if template_path.exists():
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()

            try:
                content = template_path.read_text()

                # Add cache busters to JS files
                def add_cache_buster(match):
                    src = match.group(1)
                    js_file = self.jm_dir / src.split('?')[0]
                    if js_file.exists():
                        mtime = int(js_file.stat().st_mtime)
                        base_src = src.split('?')[0]
                        return f'src="{base_src}?v={mtime}"'
                    return match.group(0)

                content = re.sub(r'src="(js/[^"]+)"', add_cache_buster, content)
                self.wfile.write(content.encode())
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            self.send_error(404, f"{filename} not found")


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """Handle requests in separate threads."""
    allow_reuse_address = True


def create_app(port=8085):
    """Create and return the server."""
    PUHandler.port = port
    handler = PUHandler
    server = ThreadedHTTPServer(('', port), handler)
    return server


def _kill_running_instances(port: int):
    """Kill all running server instances on the given port."""
    import psutil
    import signal
    import socket
    import time

    print(f"\n🔍 Checking for running instances on port {port}...")
    killed_count = 0

    for proc in psutil.process_iter(['pid', 'name']):
        try:
            # Get connections for this process (must be fetched separately)
            connections = proc.connections(kind='inet')
            if not connections:
                continue

            for conn in connections:
                if hasattr(conn, 'laddr') and conn.laddr.port == port:
                    print(f"   🔴 Found process PID {proc.pid} ({proc.info['name']}) on port {port}")
                    try:
                        proc.send_signal(signal.SIGTERM)
                        proc.wait(timeout=2)
                        killed_count += 1
                    except psutil.TimeoutExpired:
                        # Force kill if it didn't terminate
                        proc.kill()
                        killed_count += 1
                    break
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    if killed_count > 0:
        print(f"   ✅ Killed {killed_count} instance(s)")

        # Wait for port to be released (retry up to 5 seconds)
        port_free = False
        for i in range(10):  # 10 attempts, 0.5s each = 5s max
            test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                test_socket.bind(('127.0.0.1', port))
                test_socket.close()
                port_free = True
                break
            except OSError:
                time.sleep(0.5)

        if not port_free:
            print(f"   ⚠️  Warning: Port {port} still in use after killing processes")
    else:
        print(f"   ✅ No running instances found")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='PromptyUI Server')
    parser.add_argument('--port', type=int, default=8085, help='Port to run on (default: 8085)')
    args = parser.parse_args()

    # Always kill running instances on startup (prevents port conflicts)
    _kill_running_instances(args.port)

    server = create_app(args.port)

    print(f"""
╔═══════════════════════════════════════════════════════════════╗
║                      PROMPTYUI                             ║
╠═══════════════════════════════════════════════════════════════╣
║  URL: http://localhost:{args.port:<5}                              ║
║                                                               ║
║  API Endpoints:                                               ║
║    GET  /api/pu/jobs           - List all jobs                ║
║    GET  /api/pu/job/{{id}}       - Get job details              ║
║    GET  /api/pu/extensions     - List extensions              ║
║    GET  /api/pu/extension/{{p}}  - Get extension content        ║
║    POST /api/pu/preview        - Preview variations           ║
║    POST /api/pu/validate       - Validate job                 ║
║    POST /api/pu/export         - Export job                   ║
║                                                               ║
║  Press Ctrl+C to stop                                         ║
╚═══════════════════════════════════════════════════════════════╝
""")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down PromptyUI...")
        server.shutdown()


if __name__ == '__main__':
    main()
