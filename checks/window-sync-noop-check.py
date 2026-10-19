"""Protect correctness-sensitive cross-window no-op and persistence guards."""
from pathlib import Path
import re

browser = Path("astra/Models/Core/Browser.swift").read_text()
sync = Path("astra/Models/Core/BrowserSyncDocument.swift").read_text()
received = browser.split("private func receiveSharedState(", 1)[1].split(
    "private func markWorkspaceStructureChanged()", 1
)[0]
assert "merged != capturedLocal" in received
assert "if documentChanged {\n\t\t\tapplyPreparedSyncDocument(result.document" in received
assert "closed != closedHistoryBeforeMerge" in received
assert "guard documentChanged || closedHistoryChanged else" in received
assert "browser.shared-state.no-op" in received
assert "scheduleUserDataPersistence()" in received
assert "persistenceTask?.cancel()" not in received, "No-op fanout must not drop local pending writes"
assert re.search(r"if\s+current\s*==\s*incoming\s*\{\s*return\s+current\s*\}", browser), "Identical closed-history entries must bypass expensive tie-break encoding"
assert "uniquingKeysWith: Self.preferredClosedHistoryRecord" in received
assert "let openIDs = Set(tabs.map(\\.id))" in received
assert re.search(r"if\s+first\s*==\s*second\s*\{\s*return\s+first\s*\}", sync), "Identical sync values must bypass stableData encoding"
assert "if self == other { return self }" not in sync, "Merge must retain canonicalization"
print("Cross-window synchronization no-op and data-preservation checks passed")

assert "Task.detached(priority: .utility)" in received
assert "guard syncRevision == generation" in received
assert "worker.cancel()" in received
