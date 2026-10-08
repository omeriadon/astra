"""Run with python3 checks/browser-controller-teardown-check.py."""

from pathlib import Path
import re
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
assert "weak var delegate:" in source[handler_start:]
handler_names_match = re.search(r"for name in \[(.*?)\]", stop, re.S)
assert handler_names_match is not None
handler_names = [
    "scrollPositionChanged", "topEdgeChanged", "zapFinished",
    "pageActivityChanged", "pictureInPictureChanged", "linkHoverChanged",
    "faviconChanged", "readerAvailabilityChanged",
]
for token in [
    "Self.scrollPositionMessageName",
    "Self.topEdgeMessageName",
    "Self.zapFinishedMessageName",
    '"pageActivityChanged"',
    '"pictureInPictureChanged"',
    '"linkHoverChanged"',
    '"faviconChanged"',
    '"readerAvailabilityChanged"',
]:
    assert token in handler_names_match.group(1)
swift_handler_names = ", ".join(f'"{name}"' for name in handler_names)

with tempfile.TemporaryDirectory(prefix="astra-teardown-check-") as directory:
    swift = Path(directory) / "main.swift"
    executable = Path(directory) / "check"
    swift.write_text(f"""
final class MockWebView {{
    var attached = true
    var handlers = Set<String>([{swift_handler_names}, "shared"])
    var stopped = false
    var scriptsRemoved = false
    var observationsInvalidated = false
    var mediaTaskCancelled = false
    var previewTaskCancelled = false
    func removeScriptMessageHandler(forName name: String) {{ handlers.remove(name) }}
    func removeAllUserScripts() {{ scriptsRemoved = true }}
    func removeFromSuperview() {{ attached = false }}
    func stopLoading() {{ stopped = true }}
}}

final class MockController {{
    var webView: MockWebView?
    var invalidated = false
    var snapshotGeneration = 0
    var snapshot: String?
    init() {{ webView = MockWebView() }}
    func stopForClose() {{
        guard !invalidated, let webView else {{ return }}
        invalidated = true
        webView.observationsInvalidated = true
        webView.mediaTaskCancelled = true
        webView.previewTaskCancelled = true
        webView.stopLoading()
        for name in [{swift_handler_names}] {{ webView.removeScriptMessageHandler(forName: name) }}
        webView.removeAllUserScripts()
        webView.removeFromSuperview()
        self.webView = nil
    }}
    func applySnapshot(_ value: String, generation: Int) {{
        guard generation == snapshotGeneration else {{ return }}
        snapshot = value
    }}
}}

let controller = MockController()
let view = controller.webView!
controller.applySnapshot("old", generation: 0)
controller.snapshotGeneration = 1
controller.stopForClose()
controller.stopForClose()
precondition(view.stopped && !view.attached)
precondition(view.handlers == ["shared"])
precondition(view.scriptsRemoved && view.observationsInvalidated)
precondition(view.mediaTaskCancelled && view.previewTaskCancelled)
precondition(controller.webView == nil)
controller.applySnapshot("stale", generation: 0)
precondition(controller.snapshot == "old")
print("Browser controller teardown executable mock passed")
""")
    subprocess.run(["swiftc", "-swift-version", "6", "-strict-concurrency=complete", str(swift), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

print("Browser controller teardown source checks passed")
