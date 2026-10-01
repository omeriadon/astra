"""Local-only browser-host fixture. No request URLs, headers, or bodies are logged."""
import argparse
import io
import json
import math
from pathlib import Path
import re
import ssl
import struct
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

ROOT = Path(__file__).parent
LARGE_SIZE = 256 * 1024 * 1024
CHUNK = b'A' * 65536


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def respond(self, data, content_type='text/plain', status=200, headers=None):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        if status != 304:
            self.send_header('Content-Length', str(len(data)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlsplit(self.path).path
        files = {'/': 'index.html', '/fixture.js': 'fixture.js', '/sw.js': 'sw.js'}
        if path in files:
            kind = 'text/html' if path == '/' else 'application/javascript'
            self.respond((ROOT / files[path]).read_bytes(), kind, headers={'Cache-Control': 'no-cache'})
        elif path == '/cache':
            if self.headers.get('If-None-Match') == '"fixture-v1"':
                self.respond(b'', status=304, headers={'ETag': '"fixture-v1"'})
            else:
                self.respond(b'Cached fixture resource', headers={'ETag': '"fixture-v1"', 'Cache-Control': 'max-age=60'})
        elif path == '/request-info':
            self.respond(json.dumps({'globalPrivacyControl': self.headers.get('Sec-GPC'), 'cookiePresent': bool(self.headers.get('Cookie'))}).encode(), 'application/json', headers={'Cache-Control': 'no-store'})
        elif path == '/popup':
            self.respond(b'<button onclick="window.close()">Close popup</button><script>if(window.opener)window.opener.postMessage({opener:true},location.origin)</script>', 'text/html')
        elif path == '/download':
            self.respond(b'Astra attachment fixture\n', headers={'Content-Disposition': 'attachment; filename="Astra Fixture.txt"'})
        elif path == '/large':
            self.large_download()
        elif path == '/tone.wav':
            data = io.BytesIO()
            with wave.open(data, 'wb') as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(44100)
                output.writeframes(b''.join(struct.pack('<h', int(2500 * math.sin(2 * math.pi * 440 * i / 44100))) for i in range(88200)))
            self.respond(data.getvalue(), 'audio/wav')
        else:
            self.respond(b'Not found', status=404)

    def large_download(self):
        value = self.headers.get('Range')
        start, end = 0, LARGE_SIZE - 1
        if value:
            match = re.fullmatch(r'bytes=(\d+)-(\d*)', value)
            if not match:
                self.respond(b'Invalid range', status=416)
                return
            start = int(match[1])
            end = int(match[2]) if match[2] else end
            if not (0 <= start <= end < LARGE_SIZE):
                self.respond(b'Invalid range', status=416)
                return
        self.send_response(206 if value else 200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Disposition', 'attachment; filename="Astra Range Fixture.bin"')
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('ETag', '"fixture-large-v1"')
        self.send_header('Content-Length', str(end - start + 1))
        if value:
            self.send_header('Content-Range', f'bytes {start}-{end}/{LARGE_SIZE}')
        self.end_headers()
        remaining = end - start + 1
        try:
            while remaining:
                size = min(remaining, len(CHUNK))
                self.wfile.write(CHUNK[:size])
                remaining -= size
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        if length < 0 or length > 1024 * 1024:
            self.respond(b'Body too large', status=413)
            return
        self.rfile.read(length)
        self.respond(b'<h1>POST received</h1><p>Use Back and Forward to test form resubmission behavior.</p><a href="/">Fixture</a>', 'text/html', headers={'Cache-Control': 'no-store'})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--cert')
    parser.add_argument('--key')
    args = parser.parse_args()
    if bool(args.cert) != bool(args.key):
        parser.error('--cert and --key must be supplied together')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    if args.cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.cert, args.key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f'Fixture: {"https" if args.cert else "http"}://localhost:{args.port}', flush=True)
    server.serve_forever()
