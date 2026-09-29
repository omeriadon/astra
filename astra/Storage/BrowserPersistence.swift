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
	let bundleIdentifier = Bundle.main.bundleIdentifier ?? "browser"
	let directory = applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
	try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
	return directory
}

/// Value snapshot captured on MainActor, written off-main so tab
/// creation/selection never blocks on JSON + file IO.
struct BrowserPersistedState: @unchecked Sendable {
	var bookmarks: [Bookmark]
	var openTabs: [OpenTab]
	var closedTabs: [OpenTab]
	var workspace: BrowserWorkspace
	var snapshot: BrowserSnapshot
}

final class BrowserPersistence: @unchecked Sendable {
	private let directory: URL

	@MainActor
	init() throws {
		directory = try persistenceDirectory()
	}

	/// Background-thread init (directory pre-resolved on main).
	init(directory: URL) {
		self.directory = directory
	}

	@MainActor
	static func makeShared() throws -> BrowserPersistence {
		try BrowserPersistence()
	}

	func loadBookmarks() throws -> [Bookmark] {
		if let bookmarks = try read([Bookmark].self, named: "bookmarks.json") {
			return bookmarks
		}
		return try read([Bookmark].self, named: "favourites.json") ?? []
	}

	func saveBookmarks(_ bookmarks: [Bookmark]) throws {
		try write(bookmarks, named: "bookmarks.json")
	}

	func loadFavicons() throws -> [String: Data] {
		try read([String: Data].self, named: "favicons.json") ?? [:]
	}

	func saveFavicons(_ favicons: [String: Data]) throws {
		try write(favicons, named: "favicons.json")
	}

	func loadOpenTabs() throws -> [OpenTab] {
		try read([OpenTab].self, named: "open-tabs.json") ?? [OpenTab()]
	}

	func saveOpenTabs(_ tabs: [OpenTab]) throws {
		try write(tabs, named: "open-tabs.json")
	}

	func loadClosedTabs() throws -> [OpenTab] {
		try read([OpenTab].self, named: "closed-tabs.json") ?? []
	}

	func saveClosedTabs(_ tabs: [OpenTab]) throws {
		try write(tabs, named: "closed-tabs.json")
	}

	func loadWorkspace() throws -> BrowserWorkspace? {
		try read(BrowserWorkspace.self, named: "workspace.json")
	}

	func saveWorkspace(_ workspace: BrowserWorkspace) throws {
		try write(workspace, named: "workspace.json")
	}

	func loadBrowserSnapshot() throws -> BrowserSnapshot? {
		try read(BrowserSnapshot.self, named: "browser-snapshot.json")
	}

	func saveBrowserSnapshot(_ snapshot: BrowserSnapshot) throws {
		try write(snapshot, named: "browser-snapshot.json")
	}

	func savePersistedState(_ state: BrowserPersistedState, full: Bool) throws {
		if full {
			try write(state.bookmarks, named: "bookmarks.json")
			try write(state.openTabs, named: "open-tabs.json")
			try write(state.closedTabs, named: "closed-tabs.json")
		}
		try write(state.workspace, named: "workspace.json")
		try write(state.snapshot, named: "browser-snapshot.json")
	}

	private func read<Value: Decodable>(_ type: Value.Type, named fileName: String) throws -> Value? {
		let url = directory.appendingPathComponent(fileName)
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		return try JSONDecoder().decode(type, from: Data(contentsOf: url))
	}

	private func write(_ value: some Encodable, named fileName: String) throws {
		let data = try JSONEncoder().encode(value)
		try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
	}
}
