"""Run with python3 checks/browser-controller-teardown-check.py."""

from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = (root / "astra/Web/Navigation/BrowserController.swift").read_text()

stop_start = source.index("\tfunc stopForClose()")
stop_end = source.index("\n\tfunc retainPanelUploadAccess", stop_start)
stop = source[stop_start:stop_end]

assert "createdWebView?.removeFromSuperview()" in stop
assert "createdWebView = nil" in stop
assert stop.index("removeAllUserScripts()") < stop.index("createdWebView = nil")
assert "currentNavigation = nil" in stop
assert "previewSnapshotRefreshTask?.cancel()" in stop
assert "createdWebView?.configuration.userContentController.removeAllScriptMessageHandlers()" not in source
assert "var canAutomaticallyHibernate: Bool" in source
assert "suppliedConfiguration == nil" in source
assert "!isOpeningExternalApplication" in source
assert "!isDownloadHandoff" in source
assert "pendingLifecycleOperations == 0" in source
assert "createdWebView?.window?.attachedSheet == nil" in source
assert "await webView.mediaPlaybackState()" in source
assert "playbackState == .suspended" in source
assert "_displayCaptureState" in source
assert "let videoPlaying = state[\"videoPlaying\"] as? Bool" in source
assert "Task { @MainActor [weak self, weak webView] in\n\t\t\t\tguard let webView, self?.owns(webView) == true else { return }\n\t\t\t\tdefer { self?.isOpeningExternalApplication = false }" in source

handler_start = source.index("private final class WeakScriptMessageHandler")
handler = source[handler_start:]
assert "weak var delegate:" in handler

with tempfile.TemporaryDirectory(prefix="astra-teardown-check-") as directory:
    swift = Path(directory) / "main.swift"
    executable = Path(directory) / "check"
    swift.write_text(
        """
final class MockWebView {
    var attached = true
    var handlers = Set<String>(["owned", "shared"])
    var stopped = false

    func removeOwnedHandler() { handlers.remove("owned") }
    func removeFromSuperview() { attached = false }
    func stopLoading() { stopped = true }
}

final class MockController {
    var webView: MockWebView?
    var operationCount = 0
    var snapshotGeneration = 0
    var snapshot: String?

    init() { webView = MockWebView() }

    func stopForClose() {
        guard let webView else { return }
        operationCount = 0
        webView.stopLoading()
        webView.removeOwnedHandler()
        webView.removeFromSuperview()
        self.webView = nil
    }

    func applySnapshot(_ value: String, generation: Int) {
        guard generation == snapshotGeneration else { return }
        snapshot = value
    }
}

let controller = MockController()
let view = controller.webView!
controller.applySnapshot("old", generation: 0)
controller.snapshotGeneration = 1
controller.stopForClose()
controller.stopForClose()
precondition(view.stopped && !view.attached)
precondition(view.handlers == ["shared"])
precondition(controller.webView == nil)
controller.applySnapshot("stale", generation: 0)
precondition(controller.snapshot == "old")
print("Browser controller teardown executable mock passed")
"""
    )
    subprocess.run(["swiftc", str(swift), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

print("Browser controller teardown source checks passed")
