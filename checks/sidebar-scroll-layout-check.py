"""Regression guards for smooth sidebar scroll; runtime pacing still needs Instruments."""

import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sidebar = (root / "astra/UI/Shell/BrowserSidebarControls.swift").read_text()
row = (root / "astra/UI/Tabs/BrowserTabRow.swift").read_text()
favourite = (root / "astra/UI/Tabs/BrowserFavouriteTile.swift").read_text()
fade = (root / "astra/UI/Shell/topVariableBlur.swift").read_text()

# The scroll viewport and cell virtualization are native on both platforms.
# A single NSHostingView around LazyVStack would make all rows eager.
native = (root / "astra/UI/Shell/NativeSidebar/BrowserSidebarScrollView.swift").read_text()
assert "BrowserSidebarScrollView(" in sidebar
assert "ScrollView {" not in sidebar and "LazyVStack(" not in sidebar
assert "NSScrollView()" in native and "NSCollectionView()" in native
assert "UICollectionView(frame:" in native and "UIHostingConfiguration" in native
assert "host.sizingOptions = []" in native
assert "if contentChanged, !structureChanged" in native
assert "visibleIndices(in:" in native
assert "prepareForReuse()" in native and "AnyView(EmptyView())" in native
for area in ("favourite", "pinned", "normal", "folder", "todayGroup"):
    assert f"collection: .{area}" in sidebar
assert "applyNativeReorder" in sidebar and "sourceIDs = sources" in sidebar
assert "sidebarSelection.tabIDs.count > 1" in sidebar

# Tab selection must never programmatically scroll, even to reveal off-screen tabs.
assert "ScrollViewReader" not in sidebar
assert "scrollTo(" not in sidebar
assert ".onChange(of: selectedID" not in sidebar

# Global geometry changes during a wheel gesture must not mutate every
# non-hovered row's SwiftUI state.
assert re.search(r"if isHovered\s*(?:&&|,)\s*onSelectTab == nil \{", row)
assert re.search(r"if previewEnabled\s*(?:&&|,)\s*isHovered \{", favourite)
assert "BrowserWindowFrameReader { updateHoveredFrame($0) }" in row
assert ".onGeometryChange(for: CGRect.self)" not in row
assert "BrowserWindowFrameReader { recordHoverFrame($0) }" in favourite
assert ".onGeometryChange(for: CGRect.self)" not in favourite
assert "hoverFrame = .zero" in row and "hoverFrame = .zero" in favourite
title = row.split("private struct TabTitleView: View {", 1)[1].split("private struct TabCloseButton", 1)[0]
assert "GeometryReader {" not in title
assert "titleFadeMask(width:" not in title
assert ".mask {" in title
assert "top: topMargin" in sidebar

# Keep variable-blur Haze in Low Power Mode without full-subtree
# compositing. Reduce Transparency still disables blur.
assert "ProcessInfo.processInfo.isLowPowerModeEnabled" in fade
assert ".NSProcessInfoPowerStateDidChange" in fade
assert "if reduceTransparency {" in fade and "} else if lowPowerMode {" in fade
low_power_path = fade.split("} else if lowPowerMode {", 1)[1].split("} else {", 1)[0]
assert ".modifier(SidebarScrollVariableBlurModifier(top: top, bottom: bottom))" in low_power_path
assert ".compositingGroup()" not in low_power_path
assert "HazeEffect(" in fade and ".compositingGroup()" in fade
assert "blurScale:" not in fade
assert "maxBlurRadius: 3, isolatesBackdrop: true" in fade
assert "maxBlurRadius: 2, isolatesBackdrop: true" in fade

print("Sidebar native virtualization, hover-only geometry, and low-power fade checks passed")
