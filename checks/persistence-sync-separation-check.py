"""Persistence revisions and remote scheduling are independent."""
from pathlib import Path
browser = Path("astra/Models/Core/Browser.swift").read_text()
persistence = Path("astra/Storage/BrowserPersistence.swift").read_text()
full = browser.split("private func persist()", 1)[1].split("private func persistLaunchCache()", 1)[0]
assert "scheduleSync" not in full
assert "await previousWrite?.value" in full
assert "Task.detached(priority: .utility)" in full
assert "savePersistedState(state, revision: revision)" in full
schedule = browser.split("private func schedulePersistence(fullState:", 1)[1].split("private func schedulePersistence()", 1)[0]
assert schedule.index("syncRevision &+= 1") < schedule.index("guard persistence != nil")
assert schedule.index("BrowserSync.shared.scheduleSync()") < schedule.index("Task {")
assert "@ObservationIgnored private(set) var syncRevision: UInt64" in browser
capture = browser.split("func captureSyncDocument", 1)[1].split("private func completeLocalSyncDocument", 1)[0]
assert "portableProjection()" not in capture
save = persistence.split("nonisolated func savePersistedState", 1)[1].split("nonisolated func saveShutdownMetadata", 1)[0]
assert save.index("Self.selectionJournalLock.lock()") < save.index("revision <= committed")
assert save.index("revision <= committed") < save.index("JSONEncoder().encode")
assert save.index("try data.write(to: currentURL, options: .atomic)") < save.index("Self.committedRevisions[revisionKey] = revision")
assert "sync" not in save.lower()
print("Persistence/sync independence, immutable capture, serial off-main IO and revision ordering passed")
