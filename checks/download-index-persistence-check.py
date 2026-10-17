"""Guard post-debounce snapshots and revision-ordered download durability."""
from pathlib import Path

manager = Path("astra/Web/Downloads/BrowserDownloadManager.swift").read_text()
worker = Path("astra/Web/Downloads/BrowserDownloadFileWorker.swift").read_text()
start = manager.index("private func persistSoon()")
end = manager.index("private func flushDownloads()", start)
scheduled = manager[start:end]
assert "downloadPersistRevision &+= 1" in scheduled
assert scheduled.index("Task.sleep(for: .milliseconds(500))") < scheduled.index(
    "let snapshot = items"
), "An eager COW snapshot must not run before the debounce completes"
assert "persistDownloadIndex(" in scheduled
assert "JSONEncoder().encode(snapshot)" not in scheduled
assert "Task.detached" not in scheduled
assert "committedIndexRevisions" in worker
assert "revision <= committed" in worker
assert "try Task.checkCancellation()" in worker
print("Download-index delayed-snapshot and revision-order checks passed")
