#!/usr/bin/env python3
"""Loopback-only deterministic browser fixture. Not a browser or MCP mock."""
import argparse
import hashlib
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

BINARY = bytes(range(256)) * 64
ROOT = Path(__file__).resolve().parent

class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, port=0):
        super().__init__(("127.0.0.1", port), Handler)
        self.states = {}
        self.lock = threading.Lock()
        self.peer_port = None

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Do not record form/password/query contents.
    def respond(self, status, data, content_type="application/json", headers=None):
        if not isinstance(data, bytes):
            data = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
    def do_GET(self):
        target = urlsplit(self.path)
        query = parse_qs(target.query)
        run = query.get("run", ["default"])[0]
        if target.path == "/health":
            self.respond(200, {"ready": True, "sha256": hashlib.sha256(BINARY).hexdigest()})
        elif target.path.startswith("/state/"):
            with self.server.lock:
                state = dict(self.server.states.get(target.path.removeprefix("/state/"), {}))
            self.respond(200, state)
        elif target.path == "/redirect":
            self.respond(302, b"", headers={"Location": "/?run=" + run})
        elif target.path in ("/download", "/slow-download"):
            if target.path == "/slow-download":
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(BINARY)))
                self.send_header("Content-Disposition", 'attachment; filename="astra-slow-fixture.bin"')
                self.end_headers()
                try:
                    for offset in range(0, len(BINARY), 1024):
                        self.wfile.write(BINARY[offset:offset + 1024])
                        self.wfile.flush()
                        time.sleep(.5)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            else:
                self.respond(200, BINARY, "application/octet-stream", {"Content-Disposition": 'attachment; filename="astra-fixture.bin"'})
        elif target.path == "/authenticated":
            authenticated = "astra_fixture_session=fixture-user" in self.headers.get("Cookie", "")
            self.respond(200 if authenticated else 401, {"authenticated": authenticated, "user": "fixture-user" if authenticated else None})
        elif target.path == "/failed-request":
            self.respond(503, {"fixture": "failure"})
        elif target.path in ("/frame", "/nested-frame"):
            prefix = "nested" if target.path == "/nested-frame" else "frame"
            html = f'<html><body><button id="{prefix}-button">{prefix} semantic button</button><input aria-label="{prefix} field"></body></html>'
            self.respond(200, html.encode(), "text/html; charset=utf-8")
        elif target.path == "/":
            html = (ROOT / "index.html").read_text()
            html = html.replace("__PEER_PORT__", str(self.server.peer_port)).replace("__FRAME__", "true" if target.path != "/" else "false")
            self.respond(200, html.encode(), "text/html; charset=utf-8")
        else:
            self.respond(404, {"error": "not_found"})
    def do_POST(self):
        target = urlsplit(self.path)
        size = int(self.headers.get("Content-Length", "0"))
        if size > 2 * 1024 * 1024:
            self.respond(413, {"error": "too_large"})
            return
        body = self.rfile.read(size)
        if target.path == "/login":
            fields = parse_qs(body.decode())
            if fields.get("username") == ["fixture-user"] and fields.get("password") == ["fixture-password"]:
                self.respond(303, b"", headers={"Set-Cookie": "astra_fixture_session=fixture-user; HttpOnly; SameSite=Lax; Path=/", "Location": "/authenticated"})
            else:
                self.respond(401, {"error": "invalid_fixture_credentials"})
        elif target.path.startswith("/state/"):
            payload = json.loads(body)
            if not isinstance(payload, dict):
                self.respond(400, {"error": "object_required"})
                return
            # No password values are ever recorded in fixture state.
            payload.pop("password", None)
            with self.server.lock:
                self.server.states.setdefault(target.path.removeprefix("/state/"), {}).update(payload)
            self.respond(200, {"saved": True})
        elif target.path.startswith("/upload/"):
            with self.server.lock:
                self.server.states.setdefault(target.path.removeprefix("/upload/"), {})["upload"] = {"length": len(body), "sha256": hashlib.sha256(body).hexdigest()}
            self.respond(200, {"uploaded": True})
        else:
            self.respond(404, {"error": "not_found"})

def launch():
    primary, peer = FixtureServer(), FixtureServer()
    primary.peer_port = peer.server_port
    peer.peer_port = primary.server_port
    threads = [threading.Thread(target=server.serve_forever, daemon=True) for server in (primary, peer)]
    for thread in threads:
        thread.start()
    return primary, peer

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready-file", type=Path, required=True)
    args = parser.parse_args()
    primary, peer = launch()
    args.ready_file.write_text(json.dumps({"url": f"http://127.0.0.1:{primary.server_port}", "crossOrigin": f"http://127.0.0.1:{peer.server_port}", "downloadSHA256": hashlib.sha256(BINARY).hexdigest()}))
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        pass
    finally:
        primary.shutdown()
        peer.shutdown()
