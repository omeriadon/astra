#!/usr/bin/env python3
"""Statically verify ownership and registration of the macOS automation layer."""
from __future__ import annotations
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "astra.xcodeproj/project.xcproj"
project = json.loads(re.sub(r",(\s*[}\]])", r"\1", PROJECT.read_text()))
application = next(target for target in project["targets"] if target["name"] == "astra")
packages = {package["path"] for package in project["packages"] if package["kind"] == "local"}
assert "Packages/AstraAutomationCore" in packages
assert any(member.get("product-name") == "AstraAutomationCore"
           for member in application["package-product-members"])

astra_sources = next(file for file in project["files"] if file.get("path") == "astra")
runtime = next(exc for exc in astra_sources["membership-exceptions"]
               if exc["target"] == "AstraWebsiteAppRuntime")
automation = {
    "Automation/AstraSystemActions.swift",
    "Automation/Intents/AstraBrowserIntents.swift",
    "Automation/Intents/AstraAdvancedIntents.swift",
    "Automation/Services/AstraServicesProvider.swift",
    "Automation/Spotlight/AstraSpotlightIndexer.swift",
}
assert automation.issubset(set(runtime["exclusions"])), "Automation leaked into website runtime"
for path in automation:
    assert (ROOT / "astra" / path).is_file(), path

plist = plistlib.loads((ROOT / "astra/Special/Info.plist").read_bytes())
services = {item["NSMessage"] for item in plist["NSServices"]}
assert services == {"searchInAstra", "openInAstra", "openInMiniAstra",
                    "saveToAstraReadingList", "createAstraEasel"}
assert any("astra" in entry.get("CFBundleURLSchemes", [])
           for entry in plist["CFBundleURLTypes"])

core = ROOT / "Packages/AstraAutomationCore"
assert (core / "Package.swift").is_file()
for source in (core / "Sources").rglob("*.swift"):
    code = source.read_text()
    for forbidden in ("import AppKit", "import WebKit", "BrowserWindowRegistry"):
        assert forbidden not in code, f"{source}: {forbidden}"

print("Astra native automation: target ownership, Services and deep links OK")
