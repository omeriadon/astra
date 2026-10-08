"""Protect correctness-sensitive cross-window no-op and persistence guards."""
from pathlib import Path

browser = Path("astra/Models/Core/Browser.swift").read_text()
sync = Path("astra/Models/Core/BrowserSyncDocument.swift").read_text()
received = browser.split("private func receiveSharedState(", 1)[1].split(
    "private func markWorkspaceStructureChanged()", 1
)[0]
assert "let documentChanged = merged != localState" in received
assert "if documentChanged {\n\t\t\tapplySyncDocument(merged)" in received
assert "let closedHistoryChanged = mergedClosedHistory != closedHistoryTabs" in received
assert "guard documentChanged || closedHistoryChanged else" in received
assert "browser.shared-state.no-op" in received
assert "scheduleUserDataPersistence()" in received
assert "persistenceTask?.cancel()" not in received, "No-op fanout must not drop local pending writes"
assert "if current == incoming { return current }" in received
assert "let openIDs = Set(tabs.map(\\.id))" in received
assert "if first == second { return first }" in sync
assert "if self == other { return self }" not in sync, "Merge must retain canonicalization"
print("Cross-window synchronization no-op and data-preservation checks passed")
