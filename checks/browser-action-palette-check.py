#!/usr/bin/env python3
"""Portable wiring checks for the action-only Spotlight-style chooser.

Native SwiftUI appearance and event delivery still require a macOS run.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = lambda path: (root / path).read_text()
overlay = source("astra/UI/Content/BrowserQuickSearchOverlay.swift")
menu = source("astra/App/AppDelegate.swift")
browser = source("astra/Models/Core/Browser.swift")
shell = source("astra/UI/Shell/DesktopBrowserShell.swift")
actions = source("astra/Models/Search/BrowserSearchAction.swift")
chat = source("astra/UI/Chrome/BrowserAIChatSidebar.swift")

assert 'key: "p", modifiers: [.command, .shift]' in menu
assert 'browser.showsActionPalette.toggle()' in menu
assert 'if browser.showsActionPalette {' in shell
assert 'var showsActionPalette = false' in browser
assert '@State private var query = ""' in overlay
assert 'newTabSearchText' not in overlay
assert 'NewTabView(' not in overlay
assert '.fetch(' not in overlay and 'submitNewTabSearch' not in overlay
assert 'paletteCatalogue(for: browser)' in overlay
assert 'terms.allSatisfy' in overlay and 'localizedStandardContains' in overlay
for key in ('downArrow', 'upArrow', 'escape'):
    assert f'.onKeyPress(.{key})' in overlay
assert '.onSubmit' in overlay
assert '(index + delta + results.count) % results.count' in overlay
perform = overlay.split('private func perform(', 1)[1]
assert perform.index('showsActionPalette = false') < perform.index('action.perform()')

# Match the old Spotlight shell and quick-search header geometry exactly.
for fragment in (
    'min(640, max(0, geometry.size.width - 32))',
    'min(440, max(0, geometry.size.height - 48))',
    'RoundedRectangle(cornerRadius: 30)',
    'min(80, geometry.size.height * 0.12)',
    'Color.black.opacity(0.15)', '.listStyle(.sidebar)',
    '.scrollContentBackground(.hidden)', 'HStack(spacing: 10)',
    '.padding(14)', '.padding(.horizontal, 24)',
    '.padding(.top, 16)', '.padding(.bottom, 16)',
    'cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar',
):
    assert fragment in overlay, fragment

for operation in (
    'browser.closeTab(browser.selectedTabID)', 'browser.requestNewTab()',
    'browser.openInternalPage(page)', 'browser.sidebarShown.toggle()',
    'browser.showsAISidebar.toggle()', '.toggleBrowserTopBar',
    'controller.zoomIn()', 'controller.zoomOut()', 'controller.resetZoom()',
    'browser.openSplit(current.id, beside: other.id, onLeft: false)',
    'NSApp.terminate(nil)',
):
    assert operation in actions, operation
assert '!browser.isPrivate, !browser.isMini,' in actions
assert 'browser.pendingPageSummary = true' in actions
assert 'var pendingPageSummary = false' in browser
assert 'browser.pendingPageSummary' in chat
assert 'guard isVisible, browser.pendingPageSummary else { return }' in chat
assert 'browser.pendingPageSummary = false' in chat
assert 'chat.includeCurrentTab(in: browser)' in chat
assert 'chat.draft = "Summarise the current page."' in chat
assert 'await chat.send(in: browser, activationScreenPoint:' in chat
assert '.task(id: "\\(requestID?.uuidString' in chat
print("Action palette isolation, keyboard/menu routing, legacy geometry, and action wiring checks passed")
