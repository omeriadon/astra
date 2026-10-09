import Foundation

@MainActor
private enum BrowserPersistenceDirectoryCache {
	static var url: URL?
}

@MainActor
private func persistenceDirectory() throws -> URL {
	if let cached = BrowserPersistenceDirectoryCache.url {
		return cached
	}
	let fileManager = FileManager.default
	let applicationSupport = try fileManager.url(
		for: .applicationSupportDirectory,
		in: .userDomainMask,
		appropriateFor: nil,
		create: true
	)
	let directory = applicationSupport.appendingPathComponent(
		Bundle.main.bundleIdentifier ?? "browser",
		isDirectory: true
	)
	try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
	BrowserPersistenceDirectoryCache.url = directory
	return directory
}

/// One value snapshot is committed atomically, including tab organization and selection.
nonisolated struct BrowserPersistedState: Codable, @unchecked Sendable {
	var bookmarks: [Bookmark]
	var readingList: [ReadingListItem] = []
	var openTabs: [OpenTab]
	var closedTabs: [OpenTab]
	var workspace: BrowserWorkspace
	var snapshot: BrowserSnapshot
	var historyVisits: [BrowserVisit]? = nil
	var windowRecords: [BrowserWindowRecord]? = nil

	private enum CodingKeys: String, CodingKey {
		case bookmarks, readingList, openTabs, closedTabs, workspace, snapshot, historyVisits, windowRecords
	}

	init(bookmarks: [Bookmark], readingList: [ReadingListItem] = [], openTabs: [OpenTab], closedTabs: [OpenTab], workspace: BrowserWorkspace, snapshot: BrowserSnapshot, historyVisits: [BrowserVisit]? = nil, windowRecords: [BrowserWindowRecord]? = nil) {
		self.bookmarks = bookmarks
		self.readingList = readingList
		self.openTabs = openTabs
		self.closedTabs = closedTabs
		self.workspace = workspace
		self.snapshot = snapshot
		self.historyVisits = historyVisits
		self.windowRecords = windowRecords
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		bookmarks = try values.decode([Bookmark].self, forKey: .bookmarks)
		readingList = try values.decodeIfPresent([ReadingListItem].self, forKey: .readingList) ?? []
		openTabs = try values.decode([OpenTab].self, forKey: .openTabs)
		closedTabs = try values.decode([OpenTab].self, forKey: .closedTabs)
		workspace = try values.decode(BrowserWorkspace.self, forKey: .workspace)
		snapshot = try values.decode(BrowserSnapshot.self, forKey: .snapshot)
		historyVisits = try values.decodeIfPresent([BrowserVisit].self, forKey: .historyVisits)
		windowRecords = try values.decodeIfPresent([BrowserWindowRecord].self, forKey: .windowRecords)
	}
}

nonisolated struct BrowserWindowRecord: Codable, Equatable, Sendable {
	var version: Int
	var windowID: UUID
	var tabIDs: [UUID]
	var selectedTabID: UUID
	var selectionModifiedAt: Date
	var frame: BrowserWindowFrame?

	init(windowID: UUID, tabIDs: [UUID], selectedTabID: UUID, selectionModifiedAt: Date = .distantPast, frame: BrowserWindowFrame? = nil) {
		version = 1
		self.windowID = windowID
		self.tabIDs = tabIDs
		self.selectedTabID = selectedTabID
		self.selectionModifiedAt = selectionModifiedAt
		self.frame = frame
	}

	private enum CodingKeys: String, CodingKey {
		case version, windowID, tabIDs, selectedTabID, selectionModifiedAt, frame
	}

	/// Older session envelopes have no per-window selection timestamp.
	nonisolated init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		version = try container.decode(Int.self, forKey: .version)
		windowID = try container.decode(UUID.self, forKey: .windowID)
		tabIDs = try container.decode([UUID].self, forKey: .tabIDs)
		selectedTabID = try container.decode(UUID.self, forKey: .selectedTabID)
		selectionModifiedAt = try container.decodeIfPresent(Date.self, forKey: .selectionModifiedAt) ?? .distantPast
		frame = try container.decodeIfPresent(BrowserWindowFrame.self, forKey: .frame)
	}

	func restoredSelection(availableTabIDs: Set<UUID>) -> UUID? {
		guard let selected = tabIDs.first(where: { $0 == selectedTabID && availableTabIDs.contains($0) }) else {
			return tabIDs.first(where: availableTabIDs.contains)
		}
		return selected
	}
}

nonisolated struct BrowserWindowFrame: Codable, Equatable, Sendable {
	var x: Double
	var y: Double
	var width: Double
	var height: Double

	var isValid: Bool {
		x.isFinite && y.isFinite
			&& width.isFinite && height.isFinite
			&& width > 0 && height > 0
			&& abs(x) <= 1_000_000 && abs(y) <= 1_000_000
			&& width <= 100_000 && height <= 100_000
	}

	func clamped(to visible: CGRect) -> Self {
		let visibleWidth = visible.size.width
		let visibleHeight = visible.size.height
		guard visibleWidth > 0, visibleHeight > 0 else { return self }
		let width = min(max(width, min(640, visibleWidth)), visibleWidth)
		let height = min(max(height, min(480, visibleHeight)), visibleHeight)
		return Self(
			x: min(max(x, visible.origin.x), visible.origin.x + visibleWidth - width),
			y: min(max(y, visible.origin.y), visible.origin.y + visibleHeight - height),
			width: width,
			height: height
		)
	}
}

nonisolated struct BrowserShutdownMetadata: Codable, Equatable, Sendable {
	var version: Int
	var clean: Bool
	var updatedAt: Date

	static func current(clean: Bool) -> Self {
		Self(version: 1, clean: clean, updatedAt: .now)
	}
}

/// Minimal durable selection update. No URLs, history, or private browsing data are stored here.
nonisolated struct BrowserSelectionUpdate: Codable, Sendable {
	let windowID: UUID
	let selectedTabID: UUID
	let selectedTabModifiedAt: Date
	let selectedSpaceID: UUID
}

nonisolated enum BrowserHomepage {
	static func validURL(_ value: String) -> URL? {
		guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
		      let scheme = components.scheme?.lowercased(),
		      ["http", "https"].contains(scheme),
		      let host = components.host, !host.isEmpty,
		      !host.unicodeScalars.contains(where: {
		      	CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
		      }),
		      components.user == nil,
		      components.password == nil,
		      components.port.map({ (1 ... 65535).contains($0) }) ?? true
		else { return nil }
		return components.url
	}
}

nonisolated enum BrowserPersistenceError: LocalizedError, Equatable {
	case unsupportedVersion
	case invalidSnapshot

	var errorDescription: String? {
		switch self {
			case .unsupportedVersion:
				"This saved session was created by a newer version of Astra."
			case .invalidSnapshot:
				"The saved session could not be read. The original files have been preserved."
		}
	}
}

final nonisolated class BrowserPersistence: @unchecked Sendable {
	private let directory: URL
	private var readingArchiveDirectory: URL {
		directory.appendingPathComponent("reading-list", isDirectory: true)
	}

	private static let maxReadingArchiveBytes = 32 * 1024 * 1024
	private static let maxReadingArchiveFileBytes = maxReadingArchiveBytes + 32 * 1024
	private static let maxReadingArchiveCount = 50
	private static let maxReadingArchiveTotalBytes = 256 * 1024 * 1024
	// ponytail: one process-wide lock keeps the archive caps exact across windows; per-directory locks only if contention matters.
	private nonisolated static let readingArchiveLock = NSLock()
	/// Serializes full-state commits and selection checkpoints across all windows.
	private nonisolated static let selectionJournalLock = NSLock()

	/// A volatile, memory-bounded process cache of the last committed primary
	/// checkpoint. The inode/size/mtime tuple is checked before every reuse:
	/// restores, external edits and atomic replacements cannot reuse stale data.
	/// The global selectionJournalLock serializes its callers.
	private nonisolated(unsafe) static let checkpointCache: NSCache<NSString, CachedCheckpoint> = {
		let cache = NSCache<NSString, CachedCheckpoint>()
		cache.countLimit = 2
		cache.totalCostLimit = 24 * 1024 * 1024
		return cache
	}()

	private nonisolated struct CheckpointSignature: Equatable, Codable {
		let fileNumber: UInt64
		let byteCount: UInt64
		let modifiedAt: Date

		init?(at url: URL) {
			guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
			      let fileNumber = attributes[.systemFileNumber] as? NSNumber,
			      let byteCount = attributes[.size] as? NSNumber,
			      let modifiedAt = attributes[.modificationDate] as? Date
			else { return nil }
			self.fileNumber = fileNumber.uint64Value
			self.byteCount = byteCount.uint64Value
			self.modifiedAt = modifiedAt
		}
	}

	private nonisolated struct OldTabPrivacy {
		let history: Set<URL>
		let recordsNavigationHistory: Bool
	}

	/// Only the fields needed to decide whether the backup would resurrect
	/// removed private data. Retaining the entire old 50k-visit model would
	/// double session memory between successive checkpoints.
	private nonisolated struct PrivacyDeletionIndex {
		let historyURLs: [UUID: URL]
		let bookmarkURLs: [UUID: URL]
		let readingURLs: [UUID: URL]
		let closedTabIDs: Set<UUID>
		let openTabPrivacy: [UUID: OldTabPrivacy]
		let deletedVisitsAt: [UUID: Date]
		let historyClearedAt: Date
		let containedCredentialURLs: Bool

		init(_ state: BrowserPersistedState) {
			historyURLs = Dictionary((state.historyVisits ?? []).map { ($0.id, $0.url) }, uniquingKeysWith: { old, _ in old })
			bookmarkURLs = Dictionary(state.bookmarks.map { ($0.id, $0.url) }, uniquingKeysWith: { old, _ in old })
			readingURLs = Dictionary(state.readingList.map { ($0.id, $0.url) }, uniquingKeysWith: { old, _ in old })
			closedTabIDs = Set(state.closedTabs.map(\.id))
			openTabPrivacy = Dictionary(
				state.openTabs.map { ($0.id, OldTabPrivacy(history: Set($0.history), recordsNavigationHistory: $0.recordsNavigationHistory)) },
				uniquingKeysWith: { old, _ in old }
			)
			deletedVisitsAt = state.snapshot.deletedVisitsAt
			historyClearedAt = state.snapshot.historyClearedAt
			containedCredentialURLs = state.openTabs.contains { tab in
				(tab.history + [tab.url].compactMap(\.self)).contains { $0.user != nil || $0.password != nil }
			} || state.bookmarks.contains { $0.url.user != nil || $0.url.password != nil }
				|| (state.historyVisits ?? []).contains { $0.url.user != nil || $0.url.password != nil }
		}

		func hasPrivacyRemoval(comparedTo state: BrowserPersistedState) -> Bool {
			let newHistory = Dictionary((state.historyVisits ?? []).map { ($0.id, $0.url) }, uniquingKeysWith: { old, _ in old })
			let newBookmarks = Dictionary(state.bookmarks.map { ($0.id, $0.url) }, uniquingKeysWith: { old, _ in old })
			let newReading = Dictionary(state.readingList.map { ($0.id, $0.url) }, uniquingKeysWith: { old, _ in old })
			let currentClosed = Set(state.closedTabs.map(\.id))
			let currentOpen = Dictionary(state.openTabs.map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
			if historyURLs.contains(where: { newHistory[$0.key] != $0.value }) {
				return true
			}
			if bookmarkURLs.contains(where: { newBookmarks[$0.key] != $0.value }) {
				return true
			}
			if readingURLs.contains(where: { newReading[$0.key] != $0.value }) {
				return true
			}
			if historyClearedAt < state.snapshot.historyClearedAt {
				return true
			}
			if !closedTabIDs.isSubset(of: currentClosed) {
				return true
			}
			for (id, previous) in openTabPrivacy {
				guard let updated = currentOpen[id] else { continue }
				if !previous.history.isSubset(of: Set(updated.history)) {
					return true
				}
				if previous.recordsNavigationHistory, !updated.recordsNavigationHistory {
					return true
				}
			}
			if deletedVisitsAt.contains(where: { id, date in
				state.snapshot.deletedVisitsAt[id].map { $0 > date } ?? false
			}) {
				return true
			}
			return containedCredentialURLs
		}
	}

	private final nonisolated class CachedCheckpoint {
		let signature: CheckpointSignature
		let backupSignature: CheckpointSignature?
		let originalData: Data?
		let privacy: PrivacyDeletionIndex

		init(signature: CheckpointSignature, backupSignature: CheckpointSignature?,
		     data: Data, privacy: PrivacyDeletionIndex)
		{
			self.signature = signature
			self.backupSignature = backupSignature
			// The backup bytes are convenient below 8 MiB. Keep no extra copy
			// of a large JSON payload; the privacy index still avoids decoding it.
			originalData = data.count <= 8 * 1024 * 1024 ? data : nil
			self.privacy = privacy
		}
	}

	private nonisolated struct SelectionJournal: Codable {
		let version: Int
		var updates: [String: BrowserSelectionUpdate]
		let writtenAt: Date
	}

	private nonisolated struct Envelope: Codable {
		let version: Int
		let state: BrowserPersistedState
	}

	/// Minimal launch-time projection. AppDelegate only needs window identities,
	/// selections, and frames to construct windows; decoding tabs/history/bookmarks
	/// here duplicated the Browser hydration decode and inflated cold-start work.
	private nonisolated struct WindowRecordsEnvelope: Decodable {
		let version: Int
		let state: WindowRecordsState
	}

	private nonisolated struct WindowRecordsState: Decodable {
		let windowRecords: [BrowserWindowRecord]?
	}

	/// Compact startup index, explicitly tied to the *primary* atomic
	/// checkpoint. A mismatched sidecar must never override backup recovery.
	private nonisolated struct WindowRecordsSidecar: Codable {
		let version: Int
		let signature: CheckpointSignature
		let records: [BrowserWindowRecord]
	}

	private nonisolated struct ReadingArchiveEnvelope: Codable {
		let generation: UUID
		let url: URL
		let data: Data
	}

	private nonisolated static let currentVersion = 3

	@MainActor
	init() throws {
		directory = try persistenceDirectory()
	}

	nonisolated func saveReadingArchive(_ data: Data, id: UUID, url: URL) throws -> UUID {
		BrowserLog.debug(.persistence, "reading-archive.save", metadata: ["id": BrowserLog.id(id), "url": BrowserLog.url(url), "bytes": String(data.count)])
		guard !data.isEmpty, data.count <= Self.maxReadingArchiveBytes else { throw BrowserUserData.ImportError.tooLarge }
		guard BrowserHomepage.validURL(url.absoluteString) != nil else { throw BrowserPersistenceError.invalidSnapshot }
		guard url.absoluteString.utf8.count <= 16384 else { throw BrowserUserData.ImportError.tooLarge }
		Self.readingArchiveLock.lock()
		defer { Self.readingArchiveLock.unlock() }
		let folder = readingArchiveDirectory
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
		let archives = files.filter { $0.pathExtension == "webarchive" }
		let destination = folder.appendingPathComponent(id.uuidString).appendingPathExtension("webarchive")
		let isReplacing = archives.contains { $0.lastPathComponent == destination.lastPathComponent }
		var currentSize = 0
		var previousSize = 0
		for file in archives {
			guard let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
				throw BrowserPersistenceError.invalidSnapshot
			}
			currentSize += fileSize
			if file.lastPathComponent == destination.lastPathComponent {
				previousSize = fileSize
			}
		}
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary
		let generation = UUID()
		let envelope = try encoder.encode(ReadingArchiveEnvelope(generation: generation, url: url, data: data))
		guard envelope.count <= Self.maxReadingArchiveFileBytes,
		      archives.count < Self.maxReadingArchiveCount || isReplacing,
		      currentSize - previousSize + envelope.count <= Self.maxReadingArchiveTotalBytes
		else { throw BrowserUserData.ImportError.tooLarge }
		try envelope.write(to: destination, options: .atomic)
		return generation
	}

	nonisolated func loadReadingArchive(id: UUID, url expectedURL: URL) throws -> Data? {
		BrowserLog.debug(.persistence, "reading-archive.load", metadata: ["id": BrowserLog.id(id), "url": BrowserLog.url(expectedURL)])
		Self.readingArchiveLock.lock()
		defer { Self.readingArchiveLock.unlock() }
		let folder = readingArchiveDirectory
		let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
		let archive = folder.appendingPathComponent(id.uuidString).appendingPathExtension("webarchive")
		guard let file = files.first(where: { $0.lastPathComponent == archive.lastPathComponent }) else { return nil }
		guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
		      size <= Self.maxReadingArchiveFileBytes else { throw BrowserPersistenceError.invalidSnapshot }
		let encoded = try Data(contentsOf: file)
		let envelope = try PropertyListDecoder().decode(ReadingArchiveEnvelope.self, from: encoded)
		guard envelope.url.absoluteString == expectedURL.absoluteString else { return nil }
		guard envelope.data.count <= Self.maxReadingArchiveBytes else { throw BrowserPersistenceError.invalidSnapshot }
		return envelope.data
	}

	nonisolated func removeReadingArchive(id: UUID, ifGeneration generation: UUID? = nil) throws {
		BrowserLog.debug(.persistence, "reading-archive.remove", metadata: ["id": BrowserLog.id(id), "generation": BrowserLog.id(generation)])
		Self.readingArchiveLock.lock()
		defer { Self.readingArchiveLock.unlock() }
		let folder = readingArchiveDirectory
		let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
		let archive = folder.appendingPathComponent(id.uuidString).appendingPathExtension("webarchive")
		guard let file = files.first(where: { $0.lastPathComponent == archive.lastPathComponent }) else { return }
		if let generation {
			guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
			      size <= Self.maxReadingArchiveFileBytes else { throw BrowserPersistenceError.invalidSnapshot }
			let encoded = try Data(contentsOf: file)
			let envelope = try PropertyListDecoder().decode(ReadingArchiveEnvelope.self, from: encoded)
			guard envelope.generation == generation else { return }
		}
		try FileManager.default.removeItem(at: file)
	}

	init(directory: URL) {
		self.directory = directory
	}

	@MainActor
	static func makeShared() throws -> BrowserPersistence {
		try BrowserPersistence()
	}

	nonisolated func loadPersistedState() throws -> BrowserPersistedState? {
		let logStarted = BrowserLog.clock()
		BrowserLog.debug(.persistence, "state.load.begin", metadata: ["directory": BrowserLog.path(directory)])
		var hasSnapshot = false
		for name in ["browser-state.json", "browser-state.backup.json"] {
			let url = directory.appendingPathComponent(name)
			guard FileManager.default.fileExists(atPath: url.path) else { continue }
			hasSnapshot = true
			do {
				let state = try applyingSelectionUpdates(to: decodeSnapshot(Data(contentsOf: url)), loadedFrom: url)
				BrowserLog.duration(.persistence, "state.load.end", since: logStarted, warnAboveMilliseconds: 250, metadata: ["source": name, "tabs": String(state.openTabs.count), "bookmarks": String(state.bookmarks.count)])
				return state
			} catch BrowserPersistenceError.unsupportedVersion {
				throw BrowserPersistenceError.unsupportedVersion
			} catch {
				continue
			}
		}
		if hasSnapshot {
			throw BrowserPersistenceError.invalidSnapshot
		}
		return nil
	}

	nonisolated func loadWindowRecords() throws -> [BrowserWindowRecord] {
		let logStarted = BrowserLog.clock()
		let primaryURL = directory.appendingPathComponent("browser-state.json")
		if let signature = CheckpointSignature(at: primaryURL) {
			let sidecarURL = directory.appendingPathComponent("browser-windows.json")
			if let byteCount = try? sidecarURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
			   byteCount <= 256 * 1024,
			   let bytes = try? Data(contentsOf: sidecarURL), bytes.count <= 256 * 1024,
			   let sidecar = try? JSONDecoder().decode(WindowRecordsSidecar.self, from: bytes),
			   sidecar.version == 1, sidecar.signature == signature,
			   (try? validateWindowRecords(sidecar.records)) != nil
			{
				let records = applyingWindowSelectionUpdates(sidecar.records, loadedFrom: primaryURL)
				BrowserLog.duration(.persistence, "window-records.load.end",
				                    since: logStarted, warnAboveMilliseconds: 100,
				                    metadata: ["source": "sidecar", "windows": String(records.count)])
				return records
			}
		}
		var hasSnapshot = false
		for name in ["browser-state.json", "browser-state.backup.json"] {
			let url = directory.appendingPathComponent(name)
			guard FileManager.default.fileExists(atPath: url.path) else { continue }
			hasSnapshot = true
			do {
				let data = try Data(contentsOf: url)
				guard data.count <= 64 * 1024 * 1024 else {
					throw BrowserPersistenceError.invalidSnapshot
				}
				let envelope = try JSONDecoder().decode(WindowRecordsEnvelope.self, from: data)
				guard (1 ... Self.currentVersion).contains(envelope.version) else {
					throw BrowserPersistenceError.unsupportedVersion
				}
				let recorded = envelope.state.windowRecords ?? []
				try validateWindowRecords(recorded)
				let records = applyingWindowSelectionUpdates(recorded, loadedFrom: url)
				BrowserLog.duration(
					.persistence,
					"window-records.load.end",
					since: logStarted,
					warnAboveMilliseconds: 100,
					metadata: ["source": name, "windows": String(records.count)]
				)
				return records
			} catch BrowserPersistenceError.unsupportedVersion {
				throw BrowserPersistenceError.unsupportedVersion
			} catch {
				continue
			}
		}
		if hasSnapshot {
			throw BrowserPersistenceError.invalidSnapshot
		}
		return []
	}

	private nonisolated func applyingWindowSelectionUpdates(
		_ original: [BrowserWindowRecord], loadedFrom url: URL
	) -> [BrowserWindowRecord] {
		var records = original
		if let journal = try? selectionUpdates(newerThan: url) {
			for index in records.indices {
				guard let update = journal.updates[records[index].windowID.uuidString],
				      update.selectedTabModifiedAt > records[index].selectionModifiedAt,
				      records[index].tabIDs.contains(update.selectedTabID) else { continue }
				records[index].selectedTabID = update.selectedTabID
				records[index].selectionModifiedAt = update.selectedTabModifiedAt
			}
		}
		return records
	}

	nonisolated func loadBookmarks() throws -> [Bookmark] {
		if let bookmarks = try loadPersistedState()?.bookmarks {
			return bookmarks
		}
		return try read([Bookmark].self, named: "bookmarks.json")
			?? read([Bookmark].self, named: "favourites.json")
			?? []
	}

	nonisolated func loadFavicons() throws -> [String: Data] {
		try read([String: Data].self, named: "favicons.json") ?? [:]
	}

	nonisolated func saveFavicons(_ favicons: [String: Data]) throws {
		try write(favicons, named: "favicons.json")
	}

	nonisolated func loadOpenTabs() throws -> [OpenTab] {
		if let tabs = try loadPersistedState()?.openTabs {
			return tabs
		}
		return try read([OpenTab].self, named: "open-tabs.json") ?? []
	}

	nonisolated func loadClosedTabs() throws -> [OpenTab] {
		if let tabs = try loadPersistedState()?.closedTabs {
			return tabs
		}
		return try read([OpenTab].self, named: "closed-tabs.json") ?? []
	}

	nonisolated func loadWorkspace() throws -> BrowserWorkspace? {
		if let workspace = try loadPersistedState()?.workspace {
			return workspace
		}
		return try read(BrowserWorkspace.self, named: "workspace.json")
	}

	nonisolated func loadBrowserSnapshot() throws -> BrowserSnapshot? {
		if let snapshot = try loadPersistedState()?.snapshot {
			return snapshot
		}
		return try read(BrowserSnapshot.self, named: "browser-snapshot.json")
	}

	/// Writes a tiny, versioned selection checkpoint without reading or serializing
	/// tabs, history, bookmarks, favicons, or webview state.
	nonisolated func saveSelectionUpdate(_ update: BrowserSelectionUpdate) throws {
		let started = BrowserLog.clock()
		Self.selectionJournalLock.lock()
		defer { Self.selectionJournalLock.unlock() }
		var updates = try readSelectionJournal()?.updates ?? [:]
		let key = update.windowID.uuidString
		if let previous = updates[key], previous.selectedTabModifiedAt >= update.selectedTabModifiedAt {
			return
		}
		updates[key] = update
		guard updates.count <= 256 else { throw BrowserPersistenceError.invalidSnapshot }
		let journal = SelectionJournal(version: 1, updates: updates, writtenAt: .now)
		let data = try JSONEncoder().encode(journal)
		guard data.count <= 512 * 1024 else { throw BrowserPersistenceError.invalidSnapshot }
		try data.write(to: directory.appendingPathComponent("browser-selection.json"), options: .atomic)
		BrowserLog.duration(.persistence, "selection.save.end", since: started, warnAboveMilliseconds: 40, metadata: ["bytes": String(data.count)])
	}

	private nonisolated func readSelectionJournal() throws -> SelectionJournal? {
		let url = directory.appendingPathComponent("browser-selection.json")
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		let data = try Data(contentsOf: url)
		guard data.count <= 512 * 1024 else { throw BrowserPersistenceError.invalidSnapshot }
		// Inspect the schema version before decoding the shape: a future
		// version may intentionally have incompatible fields.
		guard let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let version = header["version"] as? Int
		else {
			throw BrowserPersistenceError.invalidSnapshot
		}
		guard version == 1 else { throw BrowserPersistenceError.unsupportedVersion }
		return try JSONDecoder().decode(SelectionJournal.self, from: data)
	}

	private nonisolated func selectionUpdates(newerThan snapshotURL: URL) throws -> SelectionJournal? {
		Self.selectionJournalLock.lock()
		defer { Self.selectionJournalLock.unlock() }
		guard let journal = try readSelectionJournal() else { return nil }
		let snapshotTime = (try? snapshotURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
		return journal.writtenAt > snapshotTime ? journal : nil
	}

	private nonisolated func applyingSelectionUpdates(
		to original: BrowserPersistedState,
		loadedFrom snapshotURL: URL
	) throws -> BrowserPersistedState {
		guard let journal = try? selectionUpdates(newerThan: snapshotURL) else { return original }
		var state = original
		mergeSelectionUpdates(journal, into: &state)
		return state
	}

	/// Called both when loading a pending checkpoint and before committing a
	/// full snapshot. A full save in window A must not erase window B's more
	/// recent selection just because it persisted another structural mutation.
	private nonisolated func mergeSelectionUpdates(
		_ journal: SelectionJournal,
		into state: inout BrowserPersistedState
	) {
		let available = Set(state.openTabs.map(\.id))
		for index in (state.windowRecords ?? []).indices {
			guard let update = journal.updates[state.windowRecords![index].windowID.uuidString],
			      update.selectedTabModifiedAt > state.windowRecords![index].selectionModifiedAt,
			      available.contains(update.selectedTabID),
			      state.windowRecords![index].tabIDs.contains(update.selectedTabID) else { continue }
			state.windowRecords![index].selectedTabID = update.selectedTabID
			state.windowRecords![index].selectionModifiedAt = update.selectedTabModifiedAt
		}
		let newerUpdates = journal.updates.values
			.filter { $0.selectedTabModifiedAt > state.snapshot.selectedTabModifiedAt }
			.sorted(by: { $0.selectedTabModifiedAt > $1.selectedTabModifiedAt })
		guard let update = newerUpdates.first(where: { update in
			guard available.contains(update.selectedTabID),
			      let spaceIndex = state.workspace.spaces.firstIndex(where: { $0.id == update.selectedSpaceID })
			else { return false }
			return state.workspace.favouriteTabIDs.contains(update.selectedTabID)
				|| state.workspace.spaces[spaceIndex].tabIDs.contains(update.selectedTabID)
		}), let spaceIndex = state.workspace.spaces.firstIndex(where: { $0.id == update.selectedSpaceID })
		else { return }
		state.snapshot.selectedTabID = update.selectedTabID
		state.snapshot.selectedTabModifiedAt = update.selectedTabModifiedAt
		state.workspace.selectedSpaceID = update.selectedSpaceID
		state.workspace.selectionModifiedAt = update.selectedTabModifiedAt
		state.workspace.modifiedAt = max(state.workspace.modifiedAt, update.selectedTabModifiedAt)
		state.workspace.spaces[spaceIndex].selectedTabID = update.selectedTabID
		state.workspace.spaces[spaceIndex].modifiedAt = max(
			state.workspace.spaces[spaceIndex].modifiedAt, update.selectedTabModifiedAt
		)
	}

	nonisolated func savePersistedState(_ state: BrowserPersistedState) throws {
		Self.selectionJournalLock.lock()
		defer { Self.selectionJournalLock.unlock() }
		// Never silently overwrite a checkpoint written by a newer release.
		// A corrupt checkpoint can be ignored: the full snapshot is authoritative.
		let selectionJournal: SelectionJournal?
		do {
			selectionJournal = try readSelectionJournal()
		} catch BrowserPersistenceError.unsupportedVersion {
			throw BrowserPersistenceError.unsupportedVersion
		} catch {
			selectionJournal = nil
		}
		let logStarted = BrowserLog.clock()
		BrowserLog.debug(.persistence, "state.save.begin", metadata: ["tabs": String(state.openTabs.count), "bookmarks": String(state.bookmarks.count), "reading_list": String(state.readingList.count), "history": String(state.historyVisits?.count ?? 0)])
		try validateWindowRecords(state.windowRecords ?? [])
		let currentURL = directory.appendingPathComponent("browser-state.json")
		let backupURL = directory.appendingPathComponent("browser-state.backup.json")
		let previousReadStarted = BrowserLog.clock()
		// A full-state save needs the old state to detect privacy deletions.
		// Decode it once; do not reread and decode the same 50,000-visit JSON
		// document during schema checking and again for backup comparison.
		let cacheKey = currentURL.standardizedFileURL.path as NSString
		let currentSignature = CheckpointSignature(at: currentURL)
		let cached = currentSignature.flatMap { signature -> CachedCheckpoint? in
			guard let candidate = Self.checkpointCache.object(forKey: cacheKey),
			      candidate.signature == signature else { return nil }
			return candidate
		}
		// A cold start or an externally replaced checkpoint still receives the
		// original full schema/privacy validation. Normal consecutive saves
		// reuse only the confirmed prior checkpoint's compact privacy index.
		let previousData = cached?.originalData ?? (try? Data(contentsOf: currentURL))
		let previousIndex: PrivacyDeletionIndex?
		if let cached {
			previousIndex = cached.privacy
			BrowserLog.trace(.persistence, "state.previous-cache.hit")
		} else if let previousData {
			do {
				previousIndex = try PrivacyDeletionIndex(decodeSnapshot(previousData))
			} catch BrowserPersistenceError.unsupportedVersion {
				throw BrowserPersistenceError.unsupportedVersion
			} catch {
				previousIndex = nil
			}
		} else {
			previousIndex = nil
		}
		// A backup already validated by the most recent successful commit
		// needs only an inode/size/mtime check. Unknown or externally replaced
		// backups are read and schema-checked before any files are overwritten.
		let backupSignature = CheckpointSignature(at: backupURL)
		let knownBackupUnchanged = cached != nil && cached?.backupSignature == backupSignature
		let backupData = knownBackupUnchanged ? nil : (try? Data(contentsOf: backupURL))
		if let backupData {
			try rejectUnsupportedEnvelopeVersion(backupData)
		}
		let backupPrevious: PrivacyDeletionIndex? = if previousIndex == nil, let backupData {
			(try? decodeSnapshot(backupData)).map(PrivacyDeletionIndex.init)
		} else {
			nil
		}
		BrowserLog.duration(.persistence, "state.previous-decode.end",
		                    since: previousReadStarted,
		                    warnAboveMilliseconds: 125,
		                    metadata: ["recovery_baseline": String(backupPrevious != nil)])
		let encodeStarted = BrowserLog.clock()
		var state = state
		if let selectionJournal {
			mergeSelectionUpdates(selectionJournal, into: &state)
		}
		state.windowRecords = (state.windowRecords ?? []).sorted { $0.windowID.uuidString < $1.windowID.uuidString }
		try validatePersistedState(state)
		let data = try JSONEncoder().encode(Envelope(version: Self.currentVersion, state: state))
		guard data.count <= 64 * 1024 * 1024 else { throw BrowserPersistenceError.invalidSnapshot }
		BrowserLog.duration(.persistence, "state.encode.end",
		                    since: encodeStarted,
		                    warnAboveMilliseconds: 125,
		                    metadata: ["bytes": String(data.count)])
		let previousPrimaryWasUnavailable = previousIndex == nil
		var privateDataWasRemoved = false
		if let previous = previousIndex ?? backupPrevious {
			privateDataWasRemoved = previous.hasPrivacyRemoval(comparedTo: state)
			if privateDataWasRemoved {
				// If we restored from the backup because the primary was
				// damaged, repair the primary first: never remove the last
				// recoverable copy until another valid one is committed.
				if previousPrimaryWasUnavailable, backupPrevious != nil,
				   let backupData
				{
					try backupData.write(to: currentURL, options: .atomic)
				}
				// Keep a valid current snapshot while removing any stale backup.
				// Once deletion is committed, restoration can never fall back
				// to a backup that resurrects the removed private information.
				if FileManager.default.fileExists(atPath: backupURL.path) {
					try FileManager.default.removeItem(at: backupURL)
				}
			} else if let previousData, previousPrimaryWasUnavailable == false {
				try previousData.write(to: backupURL, options: .atomic)
			}
		}
		let commitStarted = BrowserLog.clock()
		try data.write(to: currentURL, options: .atomic)
		// The full snapshot includes all window selections captured at commit time.
		// A crash before this cleanup is safe: loader ignores older journals.
		try? FileManager.default.removeItem(at: directory.appendingPathComponent("browser-selection.json"))
		if privateDataWasRemoved {
			try data.write(to: backupURL, options: .atomic)
		}
		// Write the small projection only after the primary checkpoint has
		// committed. Failure here cannot invalidate a successful full save;
		// the startup loader falls back to the original state envelope.
		if let signature = CheckpointSignature(at: currentURL) {
			let sidecar = WindowRecordsSidecar(
				version: 1, signature: signature, records: state.windowRecords ?? []
			)
			if let sidecarBytes = try? JSONEncoder().encode(sidecar),
			   sidecarBytes.count <= 256 * 1024
			{
				do {
					try sidecarBytes.write(
						to: directory.appendingPathComponent("browser-windows.json"),
						options: .atomic
					)
				} catch {
					BrowserLog.warning(.persistence, "window-records.sidecar-write-failed",
					                   metadata: ["error": BrowserLog.errorDescription(error)])
				}
			}
		}
		BrowserLog.duration(.persistence, "state.commit.end",
		                    since: commitStarted,
		                    warnAboveMilliseconds: 125,
		                    metadata: ["bytes": String(data.count), "private_data_removed": String(privateDataWasRemoved)])
		BrowserLog.duration(.persistence, "state.save.end", since: logStarted, warnAboveMilliseconds: 250, metadata: ["bytes": String(data.count), "private_data_removed": String(privateDataWasRemoved)])
		for name in ["bookmarks.json", "favourites.json", "open-tabs.json", "closed-tabs.json", "workspace.json", "browser-snapshot.json"] {
			let legacyURL = directory.appendingPathComponent(name)
			if FileManager.default.fileExists(atPath: legacyURL.path) {
				try FileManager.default.removeItem(at: legacyURL)
			}
		}
		if let signature = CheckpointSignature(at: currentURL) {
			let cacheCost = min(
				Int.max / 2,
				data.count + (state.historyVisits?.count ?? 0) * 144
					+ state.openTabs.count * 512 + state.bookmarks.count * 128
					+ state.readingList.count * 128
			)
			if cacheCost <= 24 * 1024 * 1024 {
				Self.checkpointCache.setObject(
					CachedCheckpoint(
						signature: signature, backupSignature: CheckpointSignature(at: backupURL),
						data: data, privacy: PrivacyDeletionIndex(state)
					),
					forKey: cacheKey,
					cost: cacheCost
				)
			} else {
				Self.checkpointCache.removeObject(forKey: cacheKey)
			}
		}
	}

	nonisolated func saveShutdownMetadata(clean: Bool) throws {
		try write(BrowserShutdownMetadata.current(clean: clean), named: "browser-shutdown.json")
	}

	nonisolated func loadShutdownMetadata() throws -> BrowserShutdownMetadata? {
		try read(BrowserShutdownMetadata.self, named: "browser-shutdown.json")
	}

	private nonisolated struct EnvelopeVersionOnly: Decodable {
		let version: Int
	}

	private nonisolated func rejectUnsupportedEnvelopeVersion(_ data: Data) throws {
		guard data.count <= 64 * 1024 * 1024,
		      let header = try? JSONDecoder().decode(EnvelopeVersionOnly.self, from: data)
		else { return }
		guard (1 ... Self.currentVersion).contains(header.version) else {
			throw BrowserPersistenceError.unsupportedVersion
		}
	}

	/// Validate the decoded document or the in-memory snapshot before encoding.
	/// Avoid immediately decoding our own JSON output just to repeat these
	/// semantic checks a second time.
	private nonisolated func validatePersistedState(_ state: BrowserPersistedState) throws {
		try validateWindowRecords(state.windowRecords ?? [])
		guard Set(state.openTabs.map(\.id)).count == state.openTabs.count,
		      state.bookmarks.count <= 100_000,
		      Set(state.bookmarks.map(\.id)).count == state.bookmarks.count,
		      state.bookmarks.allSatisfy({ bookmark in
		      	bookmark.name.utf8.count <= 16384
		      		&& bookmark.folder.utf8.count <= 4096
		      		&& (bookmark.order == Int.min || (0 ... 100_000).contains(bookmark.order))
		      }),
		      state.readingList.count <= 100_000,
		      Set(state.readingList.map(\.id)).count == state.readingList.count,
		      state.readingList.allSatisfy({ item in
		      	BrowserHomepage.validURL(item.url.absoluteString) != nil
		      		&& item.url.absoluteString.utf8.count <= 16384
		      		&& item.title.utf8.count <= 16384
		      }),
		      Set(state.workspace.spaces.map(\.id)).count == state.workspace.spaces.count,
		      state.openTabs.allSatisfy({ $0.pageZoom.isFinite && (0.25 ... 5).contains($0.pageZoom) }),
		      state.workspace.spaces.allSatisfy({ space in
		      	Set(space.pinnedFolders.map(\.id)).count == space.pinnedFolders.count
		      })
		else {
			throw BrowserPersistenceError.invalidSnapshot
		}
	}

	private nonisolated func decodeSnapshot(_ data: Data) throws -> BrowserPersistedState {
		guard data.count <= 64 * 1024 * 1024 else {
			throw BrowserPersistenceError.invalidSnapshot
		}
		guard let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let version = header["version"] as? Int
		else { throw BrowserPersistenceError.invalidSnapshot }
		guard (1 ... Self.currentVersion).contains(version) else {
			throw BrowserPersistenceError.unsupportedVersion
		}
		let envelope = try JSONDecoder().decode(Envelope.self, from: data)
		let state = envelope.state
		try validatePersistedState(state)
		return state
	}

	private nonisolated func validateWindowRecords(_ records: [BrowserWindowRecord]) throws {
		var windowIDs = Set<UUID>()
		for record in records {
			guard record.version <= 1 else {
				throw BrowserPersistenceError.unsupportedVersion
			}
			guard record.version == 1,
			      windowIDs.insert(record.windowID).inserted,
			      Set(record.tabIDs).count == record.tabIDs.count,
			      record.tabIDs.contains(record.selectedTabID),
			      record.frame.map(\.isValid) ?? true
			else {
				throw BrowserPersistenceError.invalidSnapshot
			}
		}
	}

	private nonisolated func read<Value: Decodable>(_ type: Value.Type, named fileName: String) throws -> Value? {
		BrowserLog.trace(.persistence, "json.read", metadata: ["file": fileName])
		let url = directory.appendingPathComponent(fileName)
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		return try JSONDecoder().decode(type, from: Data(contentsOf: url))
	}

	private nonisolated func write(_ value: some Encodable, named fileName: String) throws {
		BrowserLog.trace(.persistence, "json.write", metadata: ["file": fileName])
		let data = try JSONEncoder().encode(value)
		try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
	}
}
