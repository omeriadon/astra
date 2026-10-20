#!/usr/bin/env python3
"""Verify actual Xcode target/runtime relationships instead of Swift source spelling.

The Release archive separately validates the compiled application and embedded
frameworks. This check is for project structure and isolation only.
"""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
raw = (root / "astra.xcodeproj/project.xcproj").read_text()
project = json.loads(re.sub(r",\s*([}\]])", r"\1", raw))
targets = {target["name"]: target for target in project["targets"]}
expected = {"astra", "AstraWebsiteAppRuntime", "AstraUpdaterRuntime"}
assert expected.issubset(targets), f"Missing runtime targets: {expected - set(targets)}"
host, website, updater = (targets[name] for name in ("astra", "AstraWebsiteAppRuntime", "AstraUpdaterRuntime"))
assert {"AstraWebsiteAppRuntime", "AstraUpdaterRuntime"}.issubset(set(host["dependencies"])), "Browser must depend on runtime bundles"

products = next(entry for entry in project["files"] if entry.get("name") == "Products")
for name in ("AstraWebsiteAppRuntime", "AstraUpdaterRuntime"):
    entry = next(item for item in products["children"] if item.get("path") == f"<PRODUCTS>/{name}.framework")
    phases = {member["build-phase"] for member in entry["target-membership"]}
    assert "astra/frameworks" not in phases, f"{name} linked eagerly"
    assert "astra/copy/Embed Frameworks" in phases, f"{name} missing from embedded frameworks"

assert not any(item.get("product-name") == "Sparkle" for item in website["package-product-members"]), "Website app depends on Sparkle"
assert any(item.get("product-name") == "Sparkle" for item in updater["package-product-members"]), "Updater lost Sparkle"
assert not any(item.get("product-name") == "MarkdownView" for item in website["package-product-members"]), "Website app depends on browser-only UI"

astra_folder = next(item for item in project["files"] if item.get("kind") == "folder" and item.get("path") == "astra")
excluded = set(next(item["exclusions"] for item in astra_folder["membership-exceptions"] if item["target"] == "AstraWebsiteAppRuntime"))
browser_only = {
    "App/AppDelegate.swift", "App/browserApp.swift", "AI/BrowserAIChat.swift",
    "UI/Shell/BrowserSidebarControls.swift", "UI/Shell/MiniAstraWindowController.swift",
}
present = {path for path in browser_only if (root / "astra" / path).is_file()}
assert present.issubset(excluded), f"Browser-only files leaked into website runtime: {present - excluded}"
website_required = {
    "UI/Shell/BrowserWebsiteAppView.swift", "UI/Shell/BrowserWebsiteAppWindowController.swift",
    "Models/Core/Browser.swift", "Web/Navigation/BrowserController.swift",
}
assert not website_required.intersection(excluded), f"Website app missing runtime sources: {website_required & excluded}"
print("Xcode runtime embedding, dependency and target membership verified")
