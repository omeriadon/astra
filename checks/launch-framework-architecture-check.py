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
}.issubset(runtime_excluded)
extensions = (root / "astra/Web/Extensions/BrowserExtensionManager.swift").read_text()
assert "#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME" in extensions
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
