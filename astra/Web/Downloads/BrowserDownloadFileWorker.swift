import Foundation

/// Serializes destination publication across downloads and browser windows.
/// Filesystem work executes on this actor, never on BrowserDownloadManager's MainActor.
actor BrowserDownloadFileWorker {
	static let shared = BrowserDownloadFileWorker()

	enum FinalizationError: LocalizedError {
		case destinationUnavailable

		var errorDescription: String? {
			switch self {
				case .destinationUnavailable:
					"The selected download destination is no longer accessible."
			}
		}
	}

	/// Copies through a unique file in the destination directory. The final
	/// path is published using a same-directory atomic rename, so readers never
	/// observe a half-copied cross-volume download.
	func commit(
		source: URL,
		proposed: URL,
		fileScoped: Bool,
		bookmark: Data?,
		hasExistingAccess: Bool,
		downloadURL: URL?,
		originURL: URL?
	) throws -> URL {
		let manager = FileManager.default
		var scopedURL: URL?
		#if os(macOS)
			if let bookmark {
				var stale = false
				guard let url = try? URL(
					resolvingBookmarkData: bookmark,
					options: [.withSecurityScope, .withoutUI],
					relativeTo: nil,
					bookmarkDataIsStale: &stale
				), url.startAccessingSecurityScopedResource()
				else { throw FinalizationError.destinationUnavailable }
				scopedURL = url
			} else if fileScoped && !hasExistingAccess {
				throw FinalizationError.destinationUnavailable
			}
		#endif
		defer { scopedURL?.stopAccessingSecurityScopedResource() }
		try Task.checkCancellation()

		guard source.standardizedFileURL != proposed.standardizedFileURL else {
			throw CocoaError(.fileWriteFileExists)
		}
		let directory = proposed.deletingLastPathComponent()
		// Never create the parent directory: disappearing or unplugged external
		// volumes must fail instead of writing somewhere unexpected.
		var isDirectory: ObjCBool = false
		guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
			throw FinalizationError.destinationUnavailable
		}

		#if os(macOS)
			try BrowserDownloadedFile.quarantine(source, downloadURL: downloadURL, sourceURL: originURL)
		#endif
		let staging = directory.appendingPathComponent(".astra-finalizing-\(UUID().uuidString)", isDirectory: false)
		defer { try? manager.removeItem(at: staging) }
		try manager.copyItem(at: source, to: staging)
		try Task.checkCancellation()
		#if os(macOS)
			try BrowserDownloadedFile.quarantine(staging, downloadURL: downloadURL, sourceURL: originURL)
		#endif

		var destination = fileScoped ? proposed : BrowserDownload.collisionFreeURL(
			fileName: proposed.lastPathComponent,
			in: directory,
			excluding: source
		)
		while true {
			try Task.checkCancellation()
			guard !manager.fileExists(atPath: destination.path) else {
				guard !fileScoped else { throw CocoaError(.fileWriteFileExists) }
				destination = BrowserDownload.collisionFreeURL(
					fileName: destination.lastPathComponent,
					in: directory,
					reserved: [destination.standardizedFileURL],
					excluding: source
				)
				continue
			}
			do {
				try manager.moveItem(at: staging, to: destination)
				break
			} catch {
				let nsError = error as NSError
				guard !fileScoped,
				      nsError.domain == NSCocoaErrorDomain,
				      nsError.code == CocoaError.fileWriteFileExists.rawValue
				else { throw error }
				destination = BrowserDownload.collisionFreeURL(
					fileName: destination.lastPathComponent,
					in: directory,
					reserved: [destination.standardizedFileURL],
					excluding: source
				)
			}
		}
		// Publication is committed: failure to remove a staging source must
		// never make an already-visible complete download look failed.
		try? manager.removeItem(at: source)
		return destination
	}

	func removeFiles(_ files: [URL]) {
		for file in files {
			try? FileManager.default.removeItem(at: file)
		}
	}
}
