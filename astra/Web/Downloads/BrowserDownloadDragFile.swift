import Foundation

nonisolated struct BrowserDownloadDragCopy: Sendable {
	let fileURL: URL
	let renewedBookmark: Data?
}

nonisolated final class BrowserDownloadDragFile: @unchecked Sendable {
	private let lock = NSLock()
	private var directories: [URL] = []

	func copy(_ source: URL, named name: String, bookmark: Data?) throws -> BrowserDownloadDragCopy {
		guard URL(fileURLWithPath: name).lastPathComponent == name,
		      name != ".",
		      name != ".."
		else {
			throw CocoaError(.fileWriteInvalidFileName)
		}
		#if os(macOS)
			var scopedURL: URL?
			var bookmarkIsStale = false
			if let bookmark {
				guard let resolved = try? URL(
					resolvingBookmarkData: bookmark,
					options: [.withSecurityScope, .withoutUI],
					relativeTo: nil,
					bookmarkDataIsStale: &bookmarkIsStale
				), resolved.startAccessingSecurityScopedResource() else {
					throw CocoaError(.fileReadNoPermission)
				}
				scopedURL = resolved
			}
			defer { scopedURL?.stopAccessingSecurityScopedResource() }
		#endif
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("AstraDownloadDrag-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let destination = directory.appendingPathComponent(name)
		do {
			try FileManager.default.copyItem(at: source, to: destination)
			lock.lock()
			directories.append(directory)
			lock.unlock()
			#if os(macOS)
				let renewedBookmark = bookmarkIsStale
					? scopedURL.flatMap {
						try? $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
					}
					: nil
				return BrowserDownloadDragCopy(fileURL: destination, renewedBookmark: renewedBookmark)
			#else
				return BrowserDownloadDragCopy(fileURL: destination, renewedBookmark: nil)
			#endif
		} catch {
			try? FileManager.default.removeItem(at: directory)
			throw error
		}
	}

	func discard(_ file: URL) {
		let directory = file.deletingLastPathComponent()
		lock.lock()
		directories.removeAll { $0 == directory }
		lock.unlock()
		try? FileManager.default.removeItem(at: directory)
	}

	deinit {
		lock.lock()
		let directories = directories
		self.directories.removeAll()
		lock.unlock()
		for directory in directories {
			try? FileManager.default.removeItem(at: directory)
		}
	}
}
