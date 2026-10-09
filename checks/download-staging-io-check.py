"""Guard asynchronous download startup and staging paths."""
from pathlib import Path

manager = Path("astra/Web/Downloads/BrowserDownloadManager.swift").read_text()
worker = Path("astra/Web/Downloads/BrowserDownloadFileWorker.swift").read_text()
tests = Path("checks/download-file-worker-check.swift").read_text()

init = manager.split("init(privateDataStore:", 1)[1].split("private func hydrateSelectedDownloadFolderName()", 1)[0]
assert "try? FileManager.default.createDirectory(at: directory" not in init
hydration = manager.split("private func hydrateItems()", 1)[1].split("private func preserveUnreadableDownloadCache", 1)[0]
assert "downloadHydrationTask = Task.detached(priority: .utility)" in hydration
assert "try? FileManager.default.createDirectory(" in hydration

destination = manager.split("func decideDestination", 1)[-1]
assert "await BrowserDownloadFileWorker.shared.prepareStagingDirectory(stagingDirectory)" in manager
assert "await BrowserDownloadFileWorker.shared.stagedFileExists(previousURL)" in manager
assert "items[currentIndex].fileURL == previousURL" in manager
assert "try FileManager.default.createDirectory(at: stagingDirectory" not in manager

assert "await BrowserDownloadFileWorker.shared.prepareEmptySegmentFile(" in manager
assert "FileManager.default.createFile(atPath: items[resumedIndex].fileURL.path" not in manager
assert "Task { await BrowserDownloadFileWorker.shared.removeFiles([cancelledStagingURL]) }" in manager
assert "Task { await BrowserDownloadFileWorker.shared.removeFiles([failedStagingURL]) }" in manager
assert "func prepareEmptySegmentFile(" in worker
assert 'file.pathExtension == "astradownload"' in worker
assert "FinalizationError.destinationUnavailable" in worker
assert "Task.checkCancellation()" in worker

for name in (
    "prepareStagingDirectory(newStage)",
    "stagedFileExists(segmentStagingURL)",
    "prepareEmptySegmentFile(",
    'preconditionFailure("Segment worker accepted a file outside owned staging")',
):
    assert name in tests, name
print("Download startup, staging and cancellation-safe IO guards passed")
