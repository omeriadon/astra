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
	var frame: BrowserWindowFrame?

	init(windowID: UUID, tabIDs: [UUID], selectedTabID: UUID, frame: BrowserWindowFrame? = nil) {
		version = 1
		self.windowID = windowID
		self.tabIDs = tabIDs
		self.selectedTabID = selectedTabID
		self.frame = frame
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
				var records = envelope.state.windowRecords ?? []
				try validateWindowRecords(records)
				let journal = try? selectionUpdates(newerThan: url)
				if let journal {
					for index in records.indices {
						guard let update = journal.updates[records[index].windowID.uuidString],
						      records[index].tabIDs.contains(update.selectedTabID) else { continue }
						records[index].selectedTabID = update.selectedTabID
					}
				}
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
		      let version = header["version"] as? Int else {
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
		let available = Set(state.openTabs.map(\.id))
		for index in (state.windowRecords ?? []).indices {
			guard let update = journal.updates[state.windowRecords![index].windowID.uuidString],
			      available.contains(update.selectedTabID),
			      state.windowRecords![index].tabIDs.contains(update.selectedTabID) else { continue }
			state.windowRecords![index].selectedTabID = update.selectedTabID
		}
		guard let update = journal.updates.values
			.filter({ $0.selectedTabModifiedAt > state.snapshot.selectedTabModifiedAt })
			.max(by: { $0.selectedTabModifiedAt < $1.selectedTabModifiedAt }),
		      available.contains(update.selectedTabID),
		      let spaceIndex = state.workspace.spaces.firstIndex(where: { $0.id == update.selectedSpaceID }),
		      state.workspace.favouriteTabIDs.contains(update.selectedTabID)
		      	|| state.workspace.spaces[spaceIndex].tabIDs.contains(update.selectedTabID)
		else { return state }
		state.snapshot.selectedTabID = update.selectedTabID
		state.snapshot.selectedTabModifiedAt = update.selectedTabModifiedAt
		state.workspace.selectedSpaceID = update.selectedSpaceID
		state.workspace.selectionModifiedAt = update.selectedTabModifiedAt
		state.workspace.modifiedAt = max(state.workspace.modifiedAt, update.selectedTabModifiedAt)
		state.workspace.spaces[spaceIndex].selectedTabID = update.selectedTabID
		state.workspace.spaces[spaceIndex].modifiedAt = max(
			state.workspace.spaces[spaceIndex].modifiedAt, update.selectedTabModifiedAt
		)
		return state
	}

	nonisolated func savePersistedState(_ state: BrowserPersistedState) throws {
		Self.selectionJournalLock.lock()
		defer { Self.selectionJournalLock.unlock() }
		// Never silently overwrite a checkpoint written by a newer release.
		// A corrupt checkpoint can be ignored: the full snapshot is authoritative.
		do {
			_ = try readSelectionJournal()
		} catch BrowserPersistenceError.unsupportedVersion {
			throw BrowserPersistenceError.unsupportedVersion
		} catch {}
		let logStarted = BrowserLog.clock()
		BrowserLog.debug(.persistence, "state.save.begin", metadata: ["tabs": String(state.openTabs.count), "bookmarks": String(state.bookmarks.count), "reading_list": String(state.readingList.count), "history": String(state.historyVisits?.count ?? 0)])
		try validateWindowRecords(state.windowRecords ?? [])
		for name in ["browser-state.json", "browser-state.backup.json"] {
			let url = directory.appendingPathComponent(name)
			guard let currentData = try? Data(contentsOf: url) else { continue }
			do {
				_ = try decodeSnapshot(currentData)
			} catch BrowserPersistenceError.unsupportedVersion {
				throw BrowserPersistenceError.unsupportedVersion
			} catch {
				continue
			}
		}
		var state = state
		state.windowRecords = (state.windowRecords ?? []).sorted { $0.windowID.uuidString < $1.windowID.uuidString }
		let data = try JSONEncoder().encode(Envelope(version: Self.currentVersion, state: state))
		_ = try decodeSnapshot(data)
		let currentURL = directory.appendingPathComponent("browser-state.json")
		var privateDataWasRemoved = false
		if FileManager.default.fileExists(atPath: currentURL.path),
		   let previousData = try? Data(contentsOf: currentURL),
		   let previous = try? decodeSnapshot(previousData)
		{
			let incomingIDs = Set((state.historyVisits ?? []).map(\.id))
			// Membership checks run on every state save, including sessions with
			// thousands of visits or tabs. Build hash indexes once per snapshot.
			let readingListIDs = Set(state.readingList.map(\.id))
			let closedTabIDs = Set(state.closedTabs.map(\.id))
			let openTabsByID = Dictionary(
				state.openTabs.map { ($0.id, $0) },
				uniquingKeysWith: { first, _ in first }
			)
			privateDataWasRemoved = (previous.historyVisits ?? []).contains { !incomingIDs.contains($0.id) }
				|| previous.readingList.contains { !readingListIDs.contains($0.id) }
				|| previous.snapshot.historyClearedAt < state.snapshot.historyClearedAt
				|| previous.closedTabs.contains { !closedTabIDs.contains($0.id) }
				|| previous.openTabs.contains { old in
					guard let updated = openTabsByID[old.id] else { return false }
					let updatedHistory = Set(updated.history)
					return old.history.contains { !updatedHistory.contains($0) }
				}
				|| previous.snapshot.deletedVisitsAt.contains { id, date in
					state.snapshot.deletedVisitsAt[id].map { $0 > date } ?? false
				}
				|| previous.openTabs.contains { old in
					old.recordsNavigationHistory && openTabsByID[old.id]?.recordsNavigationHistory == false
				}
				|| previous.openTabs.contains { tab in
					(tab.history + [tab.url].compactMap(\.self)).contains { $0.user != nil || $0.password != nil }
				}
				|| previous.bookmarks.contains { $0.url.user != nil || $0.url.password != nil }
				|| (previous.historyVisits ?? []).contains { $0.url.user != nil || $0.url.password != nil }
			try previousData.write(
				to: directory.appendingPathComponent("browser-state.backup.json"),
				options: .atomic
			)
		}
		try data.write(to: currentURL, options: .atomic)
		// The full snapshot includes all window selections captured at commit time.
		// A crash before this cleanup is safe: loader ignores older journals.
		try? FileManager.default.removeItem(at: directory.appendingPathComponent("browser-selection.json"))
		if privateDataWasRemoved {
			try data.write(to: directory.appendingPathComponent("browser-state.backup.json"), options: .atomic)
		}
		BrowserLog.duration(.persistence, "state.save.end", since: logStarted, warnAboveMilliseconds: 250, metadata: ["bytes": String(data.count), "private_data_removed": String(privateDataWasRemoved)])
		for name in ["bookmarks.json", "favourites.json", "open-tabs.json", "closed-tabs.json", "workspace.json", "browser-snapshot.json"] {
			let legacyURL = directory.appendingPathComponent(name)
			if FileManager.default.fileExists(atPath: legacyURL.path) {
				try FileManager.default.removeItem(at: legacyURL)
			}
		}
	}

	nonisolated func saveShutdownMetadata(clean: Bool) throws {
		try write(BrowserShutdownMetadata.current(clean: clean), named: "browser-shutdown.json")
	}

	nonisolated func loadShutdownMetadata() throws -> BrowserShutdownMetadata? {
		try read(BrowserShutdownMetadata.self, named: "browser-shutdown.json")
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
