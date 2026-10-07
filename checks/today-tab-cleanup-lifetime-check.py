# Run: python3 checks/today-tab-cleanup-lifetime-check.py
# Source guard for task ownership; this does not exercise SwiftUI scrolling.
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sidebar = (root / "astra/UI/Shell/BrowserShellControls.swift").read_text()
sidebar = sidebar[:sidebar.index("\nprivate struct PinnedFolderRow")]
divider = (root / "astra/UI/Chrome/BrowserAITabDivider.swift").read_text()

assert ".task(" not in divider, "Scrolling a lazy divider must not cancel cleanup"
assert "@State private var cleanupAction" in sidebar
assert "@Binding var action" in divider
assert '\n\t\t.task(id:' in sidebar, "Cleanup must be attached to the sidebar root"
assert "await performTabCleanup(in: space, tabs: normalTabs)" in sidebar
assert "browser.workspace.spaces.first(where: { $0.id == self.space.id })" in sidebar
assert sidebar.count(".matchedGeometryEffect(id: tab.id, in: sidebarTransitions") == 2
assert ".animation(reduceMotion ? nil : .smooth(duration: 0.35), value: space.todayTabGroups)" in sidebar
print("Today tab cleanup lifetime source checks passed")
