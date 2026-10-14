#!/usr/bin/env python3
"""Structural regression guard for Spotlight-only new tabs and session cleanup."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text()


browser = source("astra/Models/Core/Browser.swift")
tabs = source("astra/Models/Tabs/OpenTab.swift")
cache = source("astra/Storage/BrowserLaunchCache.swift")
sync = source("astra/Models/Core/BrowserSyncDocument.swift")
defaults = source("astra/Storage/BrowserDefaults.swift")
settings = source("astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift")
content = source("astra/UI/Content/BrowserContentView.swift")
compact = source("astra/UI/Shell/CompactBrowserShell.swift")
urls = source("astra/Web/Navigation/BrowserInternalURL.swift")
actions = source("astra/Models/Search/BrowserSearchAction.swift")

# No choice of a dedicated New Tab page survives as a setting, including sync.
assert "newTabStyle" not in defaults
assert "BrowserNewTabStyle" not in settings
assert "Section(\"New Tab\")" not in settings
assert "Defaults[.newTabStyle]" not in browser

# Cmd-T, iOS toolbar, astra://new-tab and command palette all use Spotlight.
request = browser.split("func requestNewTab() {", 1)[1].split("\n\tfunc ", 1)[0]
assert "showsQuickSearch = true" in request
assert "addTab()" not in request
assert "browser.requestNewTab()" in compact
assert "browser.requestNewTab()" in urls
assert "browser.requestNewTab()" in actions
assert "selectedTab.openTab.isDiscardableNewTab" in source("astra/Models/Search/BrowserSearch.swift")
assert "NewTabView(browser: browser)" not in content

# URL-less legacy tabs are filtered at all restoration and persistence boundaries.
assert "var isDiscardableNewTab: Bool" in tabs
for guard in ("url == nil", "history.isEmpty", "peeks.isEmpty", "restorationState == nil",
              "fileAccessBookmark == nil", "internalPage == nil"):
    assert guard in tabs
assert "guard case .none = easel else { return false }" in tabs
assert "let savedTabs = loaded.tabs.filter { !$0.isDiscardableNewTab }" in browser
assert "let savedTabs = tabs.map(\\.openTab).filter { !$0.isDiscardableNewTab }" in browser
assert "openTabs: savedTabs" in browser
assert "savedWorkspace.reconcileMembership(existingTabIDs: savedIDs, unassignedTabIDs: [])" in browser
assert "savedTabs.first?.id" in browser
assert "restorableTabs = tabs.filter" in cache
assert "Array(restorableTabs.prefix(BrowserLaunchCache.maximumTabs - 1))" in cache
assert "!tab.isDiscardableNewTab" in sync
assert "projected.settings.removeValue(forKey: \"newTabStyle\")" in sync

# An empty restored session retains only its disposable in-memory anchor and
# automatically opens Spotlight. An old 'blank' startup preference does likewise.
assert "if newTabs.isEmpty {" in browser
assert "startupBehavior == .blank || newTabs.allSatisfy" in browser
assert "Text(\"Open Spotlight\")" in settings

print("Spotlight-only new-tab checks passed")
