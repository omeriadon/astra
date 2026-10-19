"""Static regressions for the SwiftUI/Observation performance audit."""

import re
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
assert "cached.structureRevision == structureRevision" in sidebar
assert 'BrowserLog.duration(.performance, "sidebar.projection.resolve"' in sidebar
assert "cached.tabIDs == space.tabIDs" not in sidebar
assert re.search(r"BrowserSidebarScrollView(?:<[^\n]+>)?\(", sidebar)
assert "SidebarContentRevision(" in sidebar
assert "guard resizeStartWidth == nil else { return }" in split
assert re.search(r"if isHovered\s*(?:&&|,)\s*onSelectTab == nil", row)
assert re.search(r"if previewEnabled\s*(?:&&|,)\s*isHovered", favourite)
assert "BrowserWindowFrameReader { updateHoveredFrame" in row
assert "BrowserWindowFrameReader { recordHoverFrame" in favourite
assert "lastPublished" in chat and ".milliseconds(85)" in chat
assert "BrowserAIOutput.completedObjects(in: snapshot)" not in chat
assert "preview = turn.response" in chat
assert "guard lastReportedWidth != width else { return }" in split
assert ".onChange(of: resizeStartWidth)" in split
assert "tabCollectionRevision &+= 1" in browser
assert "sidebarStructureRevision &+= 1" in browser
assert "chromeSummaryRevision != itemsRevision" in Path("astra/Web/Downloads/BrowserDownloadManager.swift").read_text()
assert re.search(r"if membershipChanged\s*\{\s*visibleTabMembershipRevision &\+= 1\s*\}", browser)
assert "BrowserReaderScript.prewarm()" in Path("astra/UI/Content/BrowserRootView.swift").read_text()
assert "BrowserReaderScript.prewarm()" in Path("astra/App/browserApp.swift").read_text()
reader = Path("astra/Web/Reader/BrowserReaderScript.swift").read_text()
assert "Task.detached(priority: .utility)" in reader
assert "cachedSource = readSource(resourceURLs())" in reader
assert "guard urls.count == 3 else { return nil }" in reader
assert "hasCompetingNormalWindow(for browser: Browser)" in Path("astra/Models/Core/BrowserWindowRegistry.swift").read_text()
assert "registry.hasCompetingNormalWindow(for: browser)" in Path("astra/UI/Content/BrowserContentView.swift").read_text()
fade = Path("astra/UI/Shell/topVariableBlur.swift").read_text()
assert "SidebarScrollVariableBlurModifier" in fade
assert "accessibilityReduceTransparency" in fade
assert "SidebarScrollAlphaGradient: View, Equatable" in fade
assert "SidebarScrollAlphaGradient(" in fade
print("SwiftUI Observation/performance structural regression checks passed")
