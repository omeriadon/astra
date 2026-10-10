"""Guard asynchronous download startup and staging paths."""
from pathlib import Path

manager = Path("astra/Web/Downloads/BrowserDownloadManager.swift").read_text()
worker = Path("astra/Web/Downloads/BrowserDownloadFileWorker.swift").read_text()
tests = Path("checks/download-file-worker-check.swift").read_text()
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
assert manager.count("return await beginFolderScopedDownload(") == 3
assert manager.count("return await preferredDestination(") == 3
assert "private func beginFolderScopedDownload(" in manager
assert "private func preferredDestination(" in manager
assert "availableDownloadDestination(" in manager
assert "let destinationExists = await BrowserDownloadFileWorker.shared.stagedFileExists(url)" in manager
assert "let index = items.firstIndex(where: {" in manager
assert "FileManager.default.fileExists(atPath: saved.path)" not in manager
assert "BrowserDownload.collisionFreeURL(fileName: fileName, in: folder, reserved: reservations)" not in manager
assert "func availableDownloadDestination(" in worker
assert "BrowserDownload.collisionFreeURL(fileName: fileName, in: folder, reserved: reserved)" in worker
assert "reserved.contains(saved.standardizedFileURL)" in worker
assert 'precondition(firstChoice.lastPathComponent == "report (2).pdf")' in tests
assert 'precondition(reservedChoice.lastPathComponent == "report (3).pdf")' in tests

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
