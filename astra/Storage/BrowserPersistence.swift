import Foundation

@MainActor
private func persistenceDirectory() throws -> URL {
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
	return directory
}

/// One value snapshot is committed atomically, including tab organization and selection.
struct BrowserPersistedState: Codable, @unchecked Sendable {
	var bookmarks: [Bookmark]
	var openTabs: [OpenTab]
	var closedTabs: [OpenTab]
	var workspace: BrowserWorkspace
	var snapshot: BrowserSnapshot
	var historyVisits: [BrowserVisit]? = nil
	var windowRecords: [BrowserWindowRecord]? = nil
}

struct BrowserWindowRecord: Codable, Equatable, Sendable {
	var version: Int
	var windowID: UUID
	var tabIDs: [UUID]
	var selectedTabID: UUID

	init(windowID: UUID, tabIDs: [UUID], selectedTabID: UUID) {
		version = 1
		self.windowID = windowID
		self.tabIDs = tabIDs
		self.selectedTabID = selectedTabID
	}
}

struct BrowserShutdownMetadata: Codable, Equatable, Sendable {
	var version: Int
	var clean: Bool
	var updatedAt: Date

	static func current(clean: Bool) -> Self {
		Self(version: 1, clean: clean, updatedAt: .now)
	}
}

enum BrowserPersistenceError: LocalizedError, Equatable {
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

final class BrowserPersistence: @unchecked Sendable {
	private let directory: URL

	private nonisolated struct Envelope: Codable {
		let version: Int
		let state: BrowserPersistedState
	}

	private nonisolated static let currentVersion = 3

	@MainActor
	init() throws {
		directory = try persistenceDirectory()
	}

	init(directory: URL) {
		self.directory = directory
	}

	@MainActor
	static func makeShared() throws -> BrowserPersistence {
		try BrowserPersistence()
	}

	nonisolated func loadPersistedState() throws -> BrowserPersistedState? {
		var hasSnapshot = false
		for name in ["browser-state.json", "browser-state.backup.json"] {
			let url = directory.appendingPathComponent(name)
			guard FileManager.default.fileExists(atPath: url.path) else { continue }
			hasSnapshot = true
			do {
				return try decodeSnapshot(Data(contentsOf: url))
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

	nonisolated func savePersistedState(_ state: BrowserPersistedState) throws {
		let currentURL = directory.appendingPathComponent("browser-state.json")
		if let currentData = try? Data(contentsOf: currentURL),
		   (try? decodeSnapshot(currentData)) == nil,
		   let header = try? JSONSerialization.jsonObject(with: currentData) as? [String: Any],
		   let version = header["version"] as? Int,
		   version > Self.currentVersion
		{
			throw BrowserPersistenceError.unsupportedVersion
		}
		var state = state
		if let oldState = try? loadPersistedState() {
			var records = Dictionary(uniqueKeysWithValues: (oldState.windowRecords ?? []).map { ($0.windowID, $0) })
			for record in state.windowRecords ?? [] {
				records[record.windowID] = record
			}
			state.windowRecords = records.values.sorted { $0.windowID.uuidString < $1.windowID.uuidString }
		}
		let data = try JSONEncoder().encode(Envelope(version: Self.currentVersion, state: state))
		_ = try decodeSnapshot(data)
		var historyWasRemoved = false
		if FileManager.default.fileExists(atPath: currentURL.path),
		   let previousData = try? Data(contentsOf: currentURL),
		   (try? decodeSnapshot(previousData)) != nil
		{
			let previous = try decodeSnapshot(previousData)
			let incomingIDs = Set((state.historyVisits ?? []).map(\.id))
			historyWasRemoved = (previous.historyVisits ?? []).contains { !incomingIDs.contains($0.id) }
				|| previous.openTabs.contains { old in
					old.recordsNavigationHistory && state.openTabs.first(where: { $0.id == old.id })?.recordsNavigationHistory == false
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
		if historyWasRemoved {
			try data.write(to: directory.appendingPathComponent("browser-state.backup.json"), options: .atomic)
		}
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
		guard Set(state.openTabs.map(\.id)).count == state.openTabs.count,
		      Set(state.bookmarks.map(\.id)).count == state.bookmarks.count,
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

	private nonisolated func read<Value: Decodable>(_ type: Value.Type, named fileName: String) throws -> Value? {
		let url = directory.appendingPathComponent(fileName)
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		return try JSONDecoder().decode(type, from: Data(contentsOf: url))
	}

	private nonisolated func write(_ value: some Encodable, named fileName: String) throws {
		let data = try JSONEncoder().encode(value)
		try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
	}
}
