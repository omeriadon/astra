# Run: python3 checks/hover-preview-loading-check.py
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess, tempfile, threading, time

ROOT = Path(__file__).resolve().parents[1]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/slow-image':
            time.sleep(4)
            body = b''
            content_type = 'image/png'
        else:
            body = b'<html><head><title>Readable Guide</title></head><body><main><h1>Readable Guide</h1><p>This guide explains Swift optionals, value types, and structured concurrency. The main article is available immediately and does not depend on its image loading.</p><img src="/slow-image"></main></body></html>'
            if self.path == '/empty':
                body = b'<html><body><img src="/slow-image"></body></html>'
            if self.path == '/dynamic':
                body = b'<html><body><nav>Navigation before article</nav><main></main><img src="/slow-image"><script>setTimeout(() => { document.querySelector("main").innerHTML = "<h1>Dynamic Guide</h1><p>This dynamic article explains Swift optionals, value types, and structured concurrency after the page shell has loaded.</p>"; }, 300);</script></body></html>'
            content_type = 'text/html'
        self.send_response(200)
        self.send_header('Content-Type',content_type)
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError): pass
    def log_message(self,*args): pass
server = ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
with tempfile.TemporaryDirectory(prefix='astra-loader-check-') as working:
    harness = Path(working)/'LoadingTiming.swift'
    harness.write_text('''import AppKit
import Foundation
import WebKit
@MainActor
final class BrowserController {
    var navigationIdentifier = 0
    var webViewIfLoaded: WKWebView?
}
nonisolated enum BrowserAIError: Error {
    case pageUnavailable
}
nonisolated enum BrowserAddress {
    static func withoutCredentials(_ url: URL) -> URL {
        url
    }
}
@main
struct LoadingTiming {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let url = URL(string: CommandLine.arguments[1])!
        let started = ContinuousClock.now
        let page = try await BrowserAIPageLoader().page(at: url, forPreview: true)
        let elapsed = started.duration(to: .now)
        print("readable_page=\\(page.text.contains(\"Swift optionals\")) elapsed=\\(elapsed)")
        fflush(stdout)
        guard elapsed < .seconds(3), page.text.contains("Swift optionals") else {
            exit(1)
        }
        let dynamicURL = URL(string: "/dynamic", relativeTo: url)!.absoluteURL
        let dynamicStarted = ContinuousClock.now
        let dynamic = try await BrowserAIPageLoader().page(at: dynamicURL, forPreview: true)
        guard dynamic.text.contains("This dynamic article"), dynamicStarted.duration(to: .now) < .seconds(3) else {
            print("Dynamic article was extracted before its content was ready")
            fflush(stdout)
            exit(1)
        }
        let fullStarted = ContinuousClock.now
        _ = try await BrowserAIPageLoader().page(at: url)
        precondition(fullStarted.duration(to: .now) >= .seconds(4))
        let text = String(repeating: "界", count: 30_000)
        let bounded = BrowserAIPageText(title: "Guide", url: url, text: text).previewContext
        precondition(bounded.text == String(text.prefix(26_000)))
        precondition(bounded.title == "Guide" && bounded.url == url)
        precondition(page.previewContext.text == page.text)
        let cancelStarted = ContinuousClock.now
        let request = Task {
            try await BrowserAIPageLoader().page(at: URL(string: "/empty", relativeTo: url)!.absoluteURL, forPreview: true)
        }
        try await Task.sleep(for: .milliseconds(100))
        request.cancel()
        do {
            _ = try await request.value
            exit(1)
        } catch is CancellationError {
            precondition(cancelStarted.duration(to: .now) < .seconds(3))
        }
        print("Preview loading, excerpt, and cancellation checks passed")
    }
}
''')
    binary=Path(working)/'loading-timing'
    subprocess.run(['swiftc',str(ROOT/'astra/AI/BrowserAIPageText.swift'),str(harness),'-o',str(binary)],check=True)
    run=subprocess.run([str(binary),'http://127.0.0.1:'+str(server.server_port)+'/page'],timeout=35,capture_output=True,text=True)
    print(run.stdout,flush=True)
    print('return_code='+str(run.returncode),flush=True)
    if run.returncode:
        print(run.stderr[:500],flush=True)
        raise SystemExit(run.returncode)
server.shutdown()
