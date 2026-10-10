"""Guard against reintroducing global tab scans and duplicate extension loads."""
from pathlib import Path

source = Path("astra/Web/Extensions/BrowserExtensionManager.swift").read_text()

def between(start: str, end: str) -> str:
    assert start in source and end in source, "Extension lifecycle markers missing"
    return source.split(start, 1)[1].split(end, 1)[0]

webview = between(
    "func webViewDidChange(for id: UUID, in browser: Browser)",
    "func loadedNames()",
)
assert "knownTabIDs[browser.windowID]?.contains(id)" in webview
assert "tabPropertiesDidChange(for: id, in: browser, forceWebViewRefresh: true)" in webview
assert webview.count("sync(browser)") == 1, "Only the unregistered fallback may use structural sync"

changes = between("func tabPropertiesDidChange(for id: UUID, in browser: Browser", "func selectionDidChange(")
assert "forceWebViewRefresh ? [.URL, .loading] : []" in changes
assert "guard !changed.isEmpty else { return }" in changes

prepare = between("private func prepareContext(for name: String)", "private func cacheDisplayName(")
assert "contextPreparationTasks[name]" in prepare
assert "return try await preparing.value" in prepare
assert "try Task.checkCancellation()" in prepare

enabling = between("func setEnabled(_ enabled: Bool, for name: String)", "private func archiveURL(") if "private func archiveURL(" in source.split("func setEnabled(_ enabled: Bool, for name: String)", 1)[1] else source.split("func setEnabled(_ enabled: Bool, for name: String)", 1)[1]
assert "enableIntentRevisions[name] == revision" in enabling
assert "setEnabled(true, for: name)" in enabling
print("WebExtension hot-path and preparation lifecycle checks passed")

# No extension controller is required simply to activate a cached startup window.
controller = between("lazy var controller: WKWebExtensionController", "private let bundledNames")
assert "for window in windows.values" in controller
assert "for browser in BrowserWindowRegistry.shared.openBrowsers" in controller
assert "self.sync(browser)" in controller
focus = between("func focus(_ browser: Browser)", "func webViewDidChange(")
assert "guard didInitializeController else { return }" in focus
sync = between("func sync(_ browser: Browser)", "func loadingDidChange(")
assert "guard didInitializeController else { return }" in sync
selection = between("func selectionDidChange(_ browser: Browser)", "private func selectionDidChange(")
assert "didInitializeController" in selection
print("WebExtension startup lazy-controller checks passed")
