"""Regression guards for smooth sidebar scroll; runtime pacing still needs Instruments."""

import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sidebar = (root / "astra/UI/Shell/BrowserSidebarControls.swift").read_text()
row = (root / "astra/UI/Tabs/BrowserTabRow.swift").read_text()
favourite = (root / "astra/UI/Tabs/BrowserFavouriteTile.swift").read_text()
fade = (root / "astra/UI/Shell/topVariableBlur.swift").read_text()

# Lazy children must live directly in the vertical scrolling stack rather than
# in a single tall eager VStack that realizes every tab on the first frame.
assert "ScrollView {\n\t\t\t\t\tLazyVStack(" in sidebar
assert "LazyVGrid(" in sidebar
assert "ForEach(ungroupedNormalTabs)" in sidebar
assert "Section {" in sidebar and ".reorderable(collectionID: SidebarTabCollection.todayGroup(group.id))" in sidebar
for area in ("favourite", "pinned", "normal"):
    assert f".reorderable(collectionID: SidebarTabCollection.{area})" in sidebar
assert ".reorderContainer(for: BrowserTab.self, in: SidebarTabCollection.self" in sidebar

# Global geometry changes during a wheel gesture must not mutate every
# non-hovered row's SwiftUI state.
assert re.search(r"if isHovered\s*(?:&&|,)\s*onSelectTab == nil \{", row)
assert re.search(r"if previewEnabled\s*(?:&&|,)\s*isHovered \{", favourite)
assert row.count(".onGeometryChange(for: CGRect.self)") == 1
assert favourite.count(".onGeometryChange(for: CGRect.self)") == 1
assert "hoverFrame = .zero" in row and "hoverFrame = .zero" in favourite
title = row.split("private struct TabTitleView: View {", 1)[1].split("private struct TabCloseButton", 1)[0]
assert "GeometryReader {" not in title
assert "titleFadeMask(width:" not in title
assert ".mask {" in title

# Low Power Mode retains opacity fading but drops expensive backdrop filters
# and full-subtree offscreen compositing.
assert "ProcessInfo.processInfo.isLowPowerModeEnabled" in fade
assert ".NSProcessInfoPowerStateDidChange" in fade
assert "if lowPowerMode || reduceTransparency" in fade
fast_path = fade.split("if lowPowerMode || reduceTransparency {", 1)[1].split("} else {", 1)[0]
assert "faded.clipShape(Rectangle())" in fast_path
assert "HazeEffect" not in fast_path and ".compositingGroup()" not in fast_path
assert "HazeEffect(" in fade and ".compositingGroup()" in fade

print("Sidebar lazy layout, hover-only geometry, and low-power fade checks passed")
