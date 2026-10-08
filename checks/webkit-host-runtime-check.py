"""Run with python3 checks/webkit-host-runtime-check.py on macOS."""

from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = (root / "astra/Web/Navigation/BrowserWebView.swift").read_text()
start = source.index("\tfinal class BrowserWebViewHost: NSView {")
end = source.index("\n\t@MainActor\n\tfinal class BrowserDesktopPageGestures", start)
host = source[start:end]

program = r'''
import AppKit
import SwiftUI
import WebKit

struct EdgeInsets: Equatable {
    var top = CGFloat.zero
    var leading = CGFloat.zero
    var bottom = CGFloat.zero
    var trailing = CGFloat.zero
}

private extension EdgeInsets {
    var nsInsets: NSEdgeInsets {
        NSEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
    }
}

@MainActor
final class BrowserController: NSObject {
    let id = UUID()
    private var createdWebView: WKWebView?
    var displayWindowID: UUID?
    var windowMirrorSnapshot: NSImage?
    var previewSnapshot: NSImage?
    var requiresMediaTeardownConfirmation = false
    var isCapturing = false
    var isLoading = false
    var hasUnsavedChanges = false

    var shouldKeepWebViewAttached: Bool {
        requiresMediaTeardownConfirmation || isCapturing || isLoading || hasUnsavedChanges
    }

    init(protected: Bool = false) {
        requiresMediaTeardownConfirmation = protected
    }

    var webView: WKWebView {
        if let createdWebView { return createdWebView }
        let webView = WKWebView(frame: .zero)
        createdWebView = webView
        return webView
    }

    var webViewIfLoaded: WKWebView? { createdWebView }
    func refreshWindowMirrorSnapshot() async -> Bool { true }
}

struct BrowserWebView {
    let controller: BrowserController
    var windowID: UUID?
    var isVisible = true
    var obscuredInsets = EdgeInsets()
    var minimumViewportInsets = EdgeInsets()
    var maximumViewportInsets = EdgeInsets()
}

struct BrowserLog {
    enum Category { case webKit }
    static func clock() -> ContinuousClock.Instant { .now }
    static func duration(
        _: Category,
        _: String,
        since _: ContinuousClock.Instant,
        warnAboveMilliseconds _: Int,
        metadata _: [String: String]
    ) {}
    static let webKit = 0
    static func id(_ value: UUID) -> String { value.uuidString }
}

enum BrowserDesktopCommands {
    static func attachWebInspector(_: NSObject) {}
}

@MainActor
final class BrowserDesktopPageGestures {
    func attach(to _: BrowserController, in _: BrowserWebViewHost) {}
    func detach() {}
}

'''
program += host
program += r'''

@MainActor
private func assertMounted(_ controller: BrowserController, in host: BrowserWebViewHost) {
    assert(controller.webView.superview === host)
}

@main
struct WebKitHostRuntimeCheck {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let visibleController = BrowserController()
        let hiddenController = BrowserController()
        let protectedController = BrowserController(protected: true)
        let replacementController = BrowserController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        let visibleHost = BrowserWebViewHost(specification: BrowserWebView(controller: visibleController))
        window.contentView = visibleHost
        visibleHost.frame = window.contentView!.bounds
        visibleHost.layoutSubtreeIfNeeded()
        assertMounted(visibleController, in: visibleHost)
        let retainedWebView = visibleController.webView

        let warmSpecification = BrowserWebView(controller: visibleController, isVisible: false)
        visibleHost.update(specification: warmSpecification)
        assert(retainedWebView.superview == nil)
        visibleHost.update(specification: warmSpecification)
        assert(retainedWebView.superview == nil)
        assert(visibleController.webView === retainedWebView)

        visibleHost.update(specification: BrowserWebView(controller: visibleController))
        assertMounted(visibleController, in: visibleHost)
        assert(visibleController.webView === retainedWebView)

        let hiddenHost = BrowserWebViewHost(specification: BrowserWebView(controller: hiddenController, isVisible: false))
        window.contentView?.addSubview(hiddenHost)
        hiddenHost.frame = window.contentView!.bounds
        hiddenHost.layoutSubtreeIfNeeded()
        assert(hiddenController.webViewIfLoaded == nil)

        let protectedHost = BrowserWebViewHost(specification: BrowserWebView(controller: protectedController))
        window.contentView?.addSubview(protectedHost)
        protectedHost.frame = window.contentView!.bounds
        protectedHost.layoutSubtreeIfNeeded()
        assertMounted(protectedController, in: protectedHost)
        protectedHost.update(specification: BrowserWebView(controller: protectedController, isVisible: false))
        assert(protectedController.webView.superview === protectedHost)
        assert(protectedController.webView.isHidden)

        visibleHost.update(specification: BrowserWebView(controller: replacementController))
        assert(visibleController.webView.superview == nil)
        assertMounted(replacementController, in: visibleHost)

        let otherWindowID = UUID()
        visibleHost.update(specification: BrowserWebView(controller: replacementController, windowID: otherWindowID))
        assert(replacementController.webView.superview == nil)
        visibleHost.unmountWebView()
        visibleHost.unmountWebView()
        hiddenHost.unmountWebView()
        protectedHost.unmountWebView()
        window.contentView = nil
        print("WebKit host runtime check passed")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="astra-webkit-host-") as directory:
    test_source = Path(directory) / "Harness.swift"
    executable = Path(directory) / "webkit-host-runtime-check"
    test_source.write_text(program)
    subprocess.run(
        [
            "swiftc",
            "-O",
            "-parse-as-library",
            "-swift-version",
            "6",
            "-strict-concurrency=complete",
            "-framework",
            "AppKit",
            "-framework",
            "WebKit",
            str(test_source),
            "-o",
            str(executable),
        ],
        check=True,
    )
    subprocess.run([str(executable)], check=True)
