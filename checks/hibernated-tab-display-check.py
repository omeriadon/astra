"""Visible dormant tabs restore automatically without a hibernation interstitial."""
from pathlib import Path

browser = Path("astra/Models/Core/Browser.swift").read_text()
view = Path("astra/UI/Content/BrowserContentView.swift").read_text()
selection = browser.split("private func selectTab(_ id: UUID, inSpace requestedSpaceID: UUID?)", 1)[1].split("func wakeTabForDisplay", 1)[0]
# Publish a live controller in the first selected frame, including repeat clicks
# on a manually hibernated selected tab. Configuration follows ownership claim.
assert selection.index("let didWake = tab.isHibernated") < selection.index("tab.wake()") < selection.index("selectedTabID = id")
assert "Task {" not in selection
assert "await Task.yield()" not in selection
assert "selectedTabID == id, !tab.isHibernated" in selection
assert selection.index("claimSelectedTab(in: self)", selection.index("selectedTabID = id")) < selection.index("configure(tab)")
assert "schedulePersistence(fullState: didWake)" in selection

split = browser.split("func openSplit(_ id: UUID", 1)[1].split("func deleteEasel", 1)[0]
assert split.index("tab.wake()") < split.index("splitLeftTabID =")
assert "configure(tab)" in split

# Dormant tabs exposed by hydration/manual hibernation get the normal loading
# surface and an automatic wake, never a second action for the user to perform.
assert "HibernatedPlaceholder" not in view
assert '"Tab Hibernated"' not in view
assert '"Reopen Tab"' not in view
assert ".task(id: browser.isHydrationFinished) { browser.wakeTabForDisplay(tab.id) }" in view
wake = browser.split("func wakeTabForDisplay(_ id: UUID)", 1)[1].split("func switchCandidates", 1)[0]
assert "guard isHydrationFinished" in wake
assert "selectedTabID == id || (isShowingTabSplit && (splitLeftTabID == id || splitRightTabID == id))" in wake
assert "let tab = tab(withID: id), tab.isHibernated else { return }" in wake
assert wake.index("tab.wake()") < wake.index("configure(tab)")
assert "schedulePersistence(fullState: true)" in wake
print("Hibernated tab selection, split display, and automatic recovery checks passed")
