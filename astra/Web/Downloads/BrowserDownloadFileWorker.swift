import Foundation

/// Serializes destination publication across downloads and browser windows.
/// Filesystem work executes on this actor, never on BrowserDownloadManager's MainActor.
actor BrowserDownloadFileWorker {
	static let shared = BrowserDownloadFileWorker()
	/// Last committed index generation per destination. Coalesced progress
	/// writers may reach this actor out of order after cancellation; never
	/// replace a newer, durable index with an older snapshot.
	private var committedIndexRevisions: [String: UInt64] = [:]

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
		ownedStagingDirectory: URL,
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
			if !hasExistingAccess, let bookmark {
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
		// Persisted download records may be corrupt or tampered with. A
		// resumed finalizer is never permitted to delete arbitrary user files.
		let ownedRoot = ownedStagingDirectory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
		guard source.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(ownedRoot)
		else { throw FinalizationError.destinationUnavailable }

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

	/// Renames a finished download without crossing back to MainActor for
	/// collision checking or filesystem mutation. The serialized actor avoids
	/// two simultaneous rename/finalize operations claiming the same name.
	func renameExisting(
		source: URL,
		fileName: String,
		bookmark: Data?,
		hasExistingAccess: Bool
	) throws -> URL {
		var scope: URL?
		#if os(macOS)
			if !hasExistingAccess, let bookmark {
				var stale = false
				guard let folder = try? URL(
					resolvingBookmarkData: bookmark,
					options: [.withSecurityScope, .withoutUI],
					relativeTo: nil,
					bookmarkDataIsStale: &stale
				), folder.startAccessingSecurityScopedResource()
				else { throw FinalizationError.destinationUnavailable }
				scope = folder
			}
		#endif
		defer { scope?.stopAccessingSecurityScopedResource() }
		try Task.checkCancellation()
		let directory = source.deletingLastPathComponent()
		var destination = BrowserDownload.collisionFreeURL(fileName: fileName, in: directory, excluding: source)
		while true {
			try Task.checkCancellation()
			do {
				try FileManager.default.moveItem(at: source, to: destination)
				return destination
			} catch {
				let nsError = error as NSError
				guard nsError.domain == NSCocoaErrorDomain,
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
	}

	/// Deletes staging files on the worker, including after cancellation.
	/// Failure is reported so a download is not removed from the registry
	/// while its backing file remains unexpectedly on disk.
	func deleteTemporaryFiles(_ files: [URL], in ownedStagingDirectory: URL, bookmark: Data?, hasExistingAccess: Bool) throws {
		let root = ownedStagingDirectory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
		// Download-cache records can be stale or damaged. Never use their URLs
		// to delete arbitrary files outside Astra's temporary download area.
		guard files.allSatisfy({
			$0.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root)
		}) else {
			throw FinalizationError.destinationUnavailable
		}
		var scopedURL: URL?
		#if os(macOS)
			if !hasExistingAccess, let bookmark {
				var stale = false
				guard let url = try? URL(
					resolvingBookmarkData: bookmark,
					options: [.withSecurityScope, .withoutUI],
					relativeTo: nil,
					bookmarkDataIsStale: &stale
				), url.startAccessingSecurityScopedResource()
				else { throw FinalizationError.destinationUnavailable }
				scopedURL = url
			}
		#endif
		defer { scopedURL?.stopAccessingSecurityScopedResource() }
		for file in files {
			guard FileManager.default.fileExists(atPath: file.path) else { continue }
			try FileManager.default.removeItem(at: file)
		}
	}

	/// One serialized durability boundary for the download index, including
	/// shutdown. Encoding and atomic file publication never run on MainActor.
	func persistDownloadIndex(_ snapshot: [BrowserDownload], at url: URL, revision: UInt64 = 0) throws {
		try Task.checkCancellation()
		let key = url.standardizedFileURL.path
		if let committed = committedIndexRevisions[key], revision <= committed {
			// Legacy unversioned callers must never overwrite a versioned
			// checkpoint that reached this actor later in the process.
			return
		}
		let data = try JSONEncoder().encode(snapshot)
		try Task.checkCancellation()
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try Task.checkCancellation()
		try data.write(to: url, options: .atomic)
		if revision > 0 {
			committedIndexRevisions[key] = revision
		}
	}

	/// These staging operations may hit slow disks or disconnected volumes.
	/// Keep directory creation, existence probes and segment preparation off
	/// the AppKit main actor. No user-chosen final path is mutated here.
	func prepareStagingDirectory(_ directory: URL) throws {
		try Task.checkCancellation()
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}

	func stagedFileExists(_ file: URL) -> Bool {
		FileManager.default.fileExists(atPath: file.path)
	}

	func prepareEmptySegmentFile(_ file: URL, ownedStagingDirectory: URL) throws {
		try Task.checkCancellation()
		let root = ownedStagingDirectory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
		guard file.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath().path + "/" == root,
		      file.pathExtension == "astradownload" else {
			throw FinalizationError.destinationUnavailable
		}
		let manager = FileManager.default
		try manager.createDirectory(at: ownedStagingDirectory, withIntermediateDirectories: true)
		if manager.fileExists(atPath: file.path) {
			try manager.removeItem(at: file)
		}
		try Task.checkCancellation()
		guard manager.createFile(atPath: file.path, contents: nil) else {
			throw CocoaError(.fileWriteUnknown)
		}
	}

	func removeFiles(_ files: [URL]) {
		for file in files {
			try? FileManager.default.removeItem(at: file)
		}
	}
}
