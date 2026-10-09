"""Control-Tab active-session invalidation must not enumerate tabs on each body."""
from pathlib import Path
browser = Path("astra/Models/Core/Browser.swift").read_text()
root = Path("astra/UI/Content/BrowserRootView.swift").read_text()
switcher = Path("astra/UI/Tabs/ControlTabSwitcher.swift").read_text()

assert "private(set) var visibleTabMembershipRevision = 0" in browser
tabs = browser.split("private(set) var tabs: [BrowserTab]", 1)[1].split("@ObservationIgnored", 1)[0]
assert "visibleTabMembershipRevision &+= 1" in tabs
workspace = browser.split("private(set) var workspace: BrowserWorkspace", 1)[1].split("private(set) var spaceSwitchDirection", 1)[0]
assert "didSet { visibleTabMembershipRevision &+= 1 }" in workspace
assert ".onChange(of: browser.visibleTabMembershipRevision)" in root
assert ".onChange(of: browser.visibleTabs.map(\\.id))" not in root
changed = switcher.split("func tabsDidChange()", 1)[1].split("func select(", 1)[0]
assert changed.index("guard !candidateIDs.isEmpty else { return }") < changed.index("browser.visibleTabs")
assert "candidateIDs.removeAll" in changed
print("Control-Tab scalar Observation and idle-session guarding checks passed")
