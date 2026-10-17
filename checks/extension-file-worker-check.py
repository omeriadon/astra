"""Ensure extension install/remove cannot block the main actor with archive IO."""
from pathlib import Path

source = Path("astra/Web/Extensions/BrowserExtensionManager.swift").read_text()
chrome = Path("astra/Web/Extensions/ChromeExtensionPackage.swift").read_text()
worker = source.split("private nonisolated enum BrowserExtensionFileWorker {", 1)[1].split("@MainActor\n@Observable", 1)[0]
install = source.split("func installArchive(from archive: URL", 1)[1].split("func installFromChromeStore(", 1)[0]
store = source.split("func installFromChromeStore(", 1)[1].split("func removeInstalled(", 1)[0]
remove = source.split("func removeInstalled(", 1)[1].split("private func archiveURL(", 1)[0]
assert "FileManager.default.copyItem(at: source, to: destination)" in worker
assert "try? FileManager.default.removeItem(at: destination)" in worker
assert "ChromeExtensionPackage.archive(from: Data(contentsOf: download))" in worker
assert "try archive.write(to: destination, options: .atomic)" in worker
assert "try await Task.detached(priority: .utility)" in install
assert "BrowserExtensionFileWorker.validateArchive(at: archive)" in install
assert "BrowserExtensionFileWorker.copyArchive(from: archive, to: destination)" in install
assert "BrowserExtensionFileWorker.remove(destination)" in install
assert "FileManager.default.copyItem" not in install
assert "Data(contentsOf: download)" not in store
assert "BrowserExtensionFileWorker.unpackChromeArchive(from: download, to: temporaryZIP)" in store
assert "BrowserExtensionFileWorker.remove(download)" in store
assert "BrowserExtensionFileWorker.remove(temporaryZIP)" in store
assert "BrowserExtensionFileWorker.remove(url)" in remove
assert "FileManager.default.removeItem" not in remove
assert "nonisolated enum PackageError: LocalizedError, Sendable" in chrome
print("Extension archive file operations are off-main and failure-cleaned")
