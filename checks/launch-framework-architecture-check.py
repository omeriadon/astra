"""Guard against accidental pre-main framework linkage in Astra on macOS.

The macOS build workflow additionally verifies the compiled Mach-O images with
otool. This fast check catches Xcode project and source regressions immediately.
"""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
raw = (root / "astra.xcodeproj/project.xcproj").read_text()
project = json.loads(re.sub(r",\s*([}\]])", r"\1", raw))
targets = {t["name"]: t for t in project["targets"]}
host = targets["astra"]
website = targets["AstraWebsiteAppRuntime"]
updater = targets["AstraUpdaterRuntime"]
assert "EXCLUDED_SOURCE_FILE_NAMES[sdk=macosx*]" not in host["build-settings"]
assert host["build-settings"]["SWIFT_OBJC_BRIDGING_HEADER[sdk=macosx*]"]
assert "-Wl,-dead_strip_dylibs" in host["build-settings"]["OTHER_LDFLAGS[sdk=macosx*]"]
assert "AstraUpdaterRuntime" in host["dependencies"]
assert "AstraWebsiteAppRuntime" in host["dependencies"]
products = next(x for x in project["files"] if x.get("name") == "Products")
for name in ("AstraWebsiteAppRuntime", "AstraUpdaterRuntime"):
    product = next(x for x in products["children"] if x.get("path") == f"<PRODUCTS>/{name}.framework")
    phases = [m["build-phase"] for m in product["target-membership"]]
    assert "astra/frameworks" not in phases, f"{name} linked eagerly"
    assert "astra/copy/Embed Frameworks" in phases, f"{name} not embedded"
website_member = next(x for x in project["files"] if x.get("kind") == "folder" and x.get("path") == "astra")
runtime_excluded = set(next(x["exclusions"] for x in website_member["membership-exceptions"] if x["target"] == "AstraWebsiteAppRuntime"))
assert {
    "App/AppDelegate.swift",
    "App/BrowserAuthenticationSessionHandler.swift",
    "App/browserApp.swift",
    "UI/Shell/BrowserWindowController.swift",
    "App/BrowserDataTransfer.swift",
    "App/BrowserDiagnostics.swift",
    "App/BrowserWebsiteAppMenuIntegration.swift",
    "UI/Content/ContentView.swift",
    "UI/Content/BrowserRootView.swift",
    "UI/Shell/DesktopBrowserShell.swift",
    "UI/Shell/CompactBrowserShell.swift",
    "UI/Shell/BrowserSplitView.swift",
    "UI/Shell/PrivateBrowserSidebar.swift",
    "UI/Shell/BrowserSpacePager.swift",
    "UI/Shell/MiniAstraWindowController.swift",
    "UI/Shell/MiniAstraView.swift",
    "UI/Shell/MiniAstraOpeningAnimation.swift",
    "UI/Tabs/ControlTabSwitcher.swift",
    "UI/Tabs/ControlTabSwitcherPreview.swift",
    "UI/Tabs/ControlTabSwitcherCandidateView.swift",
}.issubset(runtime_excluded)
assert not (runtime_excluded & {
    "UI/Shell/BrowserWebsiteAppView.swift",
    "UI/Shell/BrowserWebsiteAppWindowController.swift",
    "UI/Shell/BrowserContentHostView.swift",
    "UI/Content/BrowserPageView.swift",
    "UI/Shell/BrowserShellControls.swift",
    "Models/Core/Browser.swift",
    "Web/Navigation/BrowserController.swift",
}), "Website-app rendering or navigation sources accidentally excluded"
extensions = (root / "astra/Web/Extensions/BrowserExtensionManager.swift").read_text()
assert "#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME" in extensions
shell = (root / "astra/UI/Shell/BrowserShellControls.swift").read_text()
assert "struct ShellTopBarView: View" in shell
assert "struct ShellSidebarListView" not in shell
assert "struct ShellDownloadsBarView" not in shell
assert "struct ShellSidebarListView: View" in (root / "astra/UI/Shell/BrowserSidebarControls.swift").read_text()
assert "struct ShellDownloadsBarView: View" in (root / "astra/UI/Shell/BrowserDownloadsBarView.swift").read_text()
assert "final class BrowserTabHoverPreviewCoordinator" in (root / "astra/UI/Tabs/BrowserTabHoverPreviewCoordinator.swift").read_text()
assert "final class BrowserTabHoverPreviewCoordinator" not in (root / "astra/UI/Tabs/BrowserTabRow.swift").read_text()
for name in ("UI/Shell/BrowserSpaceScrollState.swift", "Web/Navigation/BrowserDesktopCommands.swift", "Web/Navigation/BrowserDesktopCommands+ExportFormat.swift", "UI/Content/BrowserSourceViewer.swift"):
    assert name not in runtime_excluded, f"Required website-app utility excluded: {name}"
for name in ("UI/Shell/BrowserSidebarControls.swift", "UI/Shell/BrowserDownloadsBarView.swift", "UI/Tabs/BrowserTabRow.swift"):
    assert name in runtime_excluded, f"Sidebar UI leaked into website runtime: {name}"

assert not any(x.get("product-name") == "Sparkle" for x in website["package-product-members"])
assert any(x.get("product-name") == "Sparkle" for x in updater["package-product-members"])
browser = (root / "astra/App/browserApp.swift").read_text()
website_main = (root / "AstraWebsiteAppRuntime/AstraWebsiteAppRuntime.swift").read_text()
updater_main = (root / "AstraUpdaterRuntime/AstraUpdaterRuntime.swift").read_text()
manager = (root / "astra/App/UpdateManager.swift").read_text()
assert "@main" in browser
assert "AstraBrowserMain" not in website_main
assert '"AstraWebsiteAppMain"' in website_main
assert '"AstraUpdaterRuntimeStart"' in updater_main
assert 'DeferredUpdaterImage.open(at: path)' in manager
assert "Task.detached(priority: .utility)" in manager
assert "import Sparkle" not in manager
for path in (root / "astra").rglob("*.swift"):
    assert "import Sparkle" not in path.read_text(), f"Sparkle imported by browser: {path}"
print("Astra launch framework isolation invariants passed")
