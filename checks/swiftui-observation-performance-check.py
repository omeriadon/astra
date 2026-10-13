"""Static regressions for the SwiftUI/Observation performance audit."""

from pathlib import Path

navigation = Path("astra/UI/Chrome/BrowserNavigationControls.swift").read_text()
sidebar = Path("astra/UI/Shell/BrowserSidebarControls.swift").read_text()
row = Path("astra/UI/Tabs/BrowserTabRow.swift").read_text()
favourite = Path("astra/UI/Tabs/BrowserFavouriteTile.swift").read_text()
chat = Path("astra/AI/BrowserAIChat.swift").read_text()
split = Path("astra/UI/Shell/BrowserSplitView.swift").read_text()
browser = Path("astra/Models/Core/Browser.swift").read_text()

assert ".id(controller.history)" not in navigation
assert ".id(controller.historyIndex)" not in navigation
assert "projectionCache.resolve(" in sidebar
assert "cached.tabIDs == space.tabIDs" in sidebar
assert "LazyVStack(spacing: 2)" in sidebar
assert "if isHovered && onSelectTab == nil" in row
assert "if previewEnabled && isHovered" in favourite
assert "onAppear { updateHoveredFrame" in row
assert "onAppear { recordHoverFrame" in favourite
assert "lastActionScanAt" in chat
assert "for call in turn.actions where seen.count < 5" in chat
assert "if preview != turn.response" in chat
assert "abs(width - lastReportedWidth) < 8" in split
assert "tabCollectionRevision &+= 1" in browser
assert "chromeSummaryRevision != itemsRevision" in Path("astra/Web/Downloads/BrowserDownloadManager.swift").read_text()
assert "if membershipChanged { visibleTabMembershipRevision &+= 1 }" in browser
assert "BrowserReaderScript.prewarm()" in Path("astra/UI/Content/BrowserRootView.swift").read_text()
assert "Task.detached(priority: .utility)" in Path("astra/Web/Reader/BrowserReaderScript.swift").read_text()
assert "hasCompetingNormalWindow(for browser: Browser)" in Path("astra/Models/Core/BrowserWindowRegistry.swift").read_text()
assert "registry.hasCompetingNormalWindow(for: browser)" in Path("astra/UI/Content/BrowserContentView.swift").read_text()
fade = Path("astra/UI/Shell/topVariableBlur.swift").read_text()
assert "SidebarScrollVariableBlurModifier" in fade
assert "accessibilityReduceTransparency" in fade
print("SwiftUI Observation/performance structural regression checks passed")
