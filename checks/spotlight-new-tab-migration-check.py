#!/usr/bin/env python3
"""Structural regression checks for durable, device-local New Tabs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def source(path: str) -> str:
    return (ROOT / path).read_text()

browser = source("astra/Models/Core/Browser.swift")
tabs = source("astra/Models/Tabs/OpenTab.swift")
cache = source("astra/Storage/BrowserLaunchCache.swift")
sync = source("astra/Models/Core/BrowserSyncDocument.swift")
settings = source("astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift")
content = source("astra/UI/Content/BrowserContentView.swift")
compact = source("astra/UI/Shell/CompactBrowserShell.swift")
urls = source("astra/Web/Navigation/BrowserInternalURL.swift")
actions = source("astra/Models/Search/BrowserSearchAction.swift")

# Cmd-T creates an actual tab, not a transient quick-search overlay.
request = browser.split("func requestNewTab() {", 1)[1].split("\n\tfunc ", 1)[0]
assert "_ = addTab()" in request
assert "browser.requestNewTab()" in compact
assert "browser.requestNewTab()" in urls
assert "browser.requestNewTab()" in actions
assert "NewTabView(browser: browser)" in content
assert "selectedTab.openTab.isDiscardableNewTab" in source("astra/Models/Search/BrowserSearch.swift")

# Empty New Tabs are serializable normal session entries.
assert "var isDiscardableNewTab: Bool" in tabs
assert "let savedTabs = tabs.map(\\.openTab)" in browser
assert "let savedTabs = loaded.tabs" in browser
assert "loaded.tabs.filter { !$0.isDiscardableNewTab }" not in browser
assert "tabs.map(\\.openTab).filter { !$0.isDiscardableNewTab }" not in browser
assert "openTabs: savedTabs" in browser
assert "savedWorkspace.reconcileMembership(existingTabIDs: savedIDs, unassignedTabIDs: [])" in browser
assert "let cachedTabs = launchCache?.tabs.sorted" in browser
assert "let leadingTabs = Array(tabs.prefix(BrowserLaunchCache.maximumTabs))" in cache
assert "let restorableTabs = tabs.filter" not in cache
assert "startupBehavior == .blank || newTabs.allSatisfy" not in browser
assert "if startupBehavior == .blank {" in browser

# A sync round-trip must not remove a local blank tab or upload it.
assert "tabs: tabs.map(\\.openTab)," in browser
assert "let changedTabs = document.tabs.compactMap" in browser
assert ".preservingLocalOnlyData(from: cached)" in browser
assert ".preservingLocalOnlyData(from: current)" in browser
assert "localWithoutBlankTabs.tabs.removeAll { $0.isDiscardableNewTab }" in browser
assert "merged.preservingLocalOnlyData(from: incomingState)" in browser
assert "$0.isDiscardableNewTab\n" in sync
assert "if isPortableSyncTab(tab)" in sync
assert "!tab.isDiscardableNewTab" in sync
assert "!tab.isDiscardableNewTab" in browser  # unchanged portable/closure semantics
assert "@Default(.newTabStyle)" not in settings

print("New Tab disk persistence and sync separation checks passed")
