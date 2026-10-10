"""Scroll-only persistence must not serialize the full session or lose peek state."""
from pathlib import Path
persistence = Path("astra/Storage/BrowserPersistence.swift").read_text()
browser = Path("astra/Models/Core/Browser.swift").read_text()
tab = Path("astra/Models/Tabs/BrowserTab.swift").read_text()
tests = Path("docs/astra-roadmap/checks-03-persistence.swift").read_text()

assert "nonisolated struct BrowserScrollUpdate: Codable, Sendable" in persistence
assert "private nonisolated struct ScrollJournal: Codable" in persistence
write = persistence.split("nonisolated func saveScrollUpdates(", 1)[1].split("private nonisolated func readScrollJournal()", 1)[0]
assert "Self.selectionJournalLock.lock()" in write
assert "CheckpointSignature(at: primary)" in write
assert "old.modifiedAt > change.modifiedAt" in write
assert "encoded.count <= 512 * 1024" in write
assert 'directory.appendingPathComponent("browser-scroll.json")' in write
assert "savePersistedState(" not in write
restore = persistence.split("private nonisolated func mergeScrollUpdates(", 1)[1].split("private nonisolated func selectionUpdates(", 1)[0]
assert "tab.url == update.url" in restore
assert "tab.historyIndex == update.historyIndex" in restore
assert "update.modifiedAt >= tab.modifiedAt" in restore
full = persistence.split("nonisolated func savePersistedState(", 1)[1].split("nonisolated func saveShutdownMetadata()", 1)[0]
assert "mergeScrollUpdates(scrollJournal, into: &state)" in full
assert full.index("mergeScrollUpdates(scrollJournal, into: &state)") < full.index("JSONEncoder().encode(Envelope(")
assert full.index('try data.write(to: currentURL, options: .atomic)') < full.index('removeItem(at: directory.appendingPathComponent("browser-scroll.json"))')
handler = browser.split("tab.didScrollChange =", 1)[1].split("func prepareSelectedTabDisplayOwner()", 1)[0]
assert "if isPeek" in handler
assert "schedulePersistence(fullState: true, syncExtensions: false)" in handler
assert "scheduleScrollPersistence(for: id)" in handler
quick = browser.split("private func persistScrollOnly()", 1)[1].split("private func persistSelectionOnly()", 1)[0]
assert "tabs.map(\\.openTab)" not in quick
assert "BrowserPersistedState(" not in quick
assert "saveScrollUpdates(updates)" in quick
assert "controller.scrollPosition" in quick
assert "historyIndex: tab.scrollHistoryIndex" in quick
assert "var scrollHistoryIndex: Int" in tab
assert "historyIndex: tab.openTab.historyIndex" not in quick
assert "didScrollChange: (@MainActor (_ isPeek: Bool) -> Void)?" in tab
assert "markModifiedForScroll(isPeek: true)" in tab
for marker in (
    "precondition(scrollRestored?.openTabs[0].scrollPosition == scrollPosition)",
    "precondition(mergedScroll?.openTabs[0].scrollPosition == scrollPosition)",
    "precondition(navigatedResult?.openTabs[0].scrollPosition == .zero)",
    "Future scroll journal was overwritten",
):
    assert marker in tests, marker
print("Scroll journal, URL isolation, peek fallback, crash/replay invariants passed")
