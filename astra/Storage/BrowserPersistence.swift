import Foundation

@MainActor
final class BrowserPersistence {
	private let directory: URL
	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()

	init() throws {
		let fileManager = FileManager.default
		let applicationSupport = try fileManager.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true
		)
		let bundleIdentifier = Bundle.main.bundleIdentifier ?? "browser"
		directory = applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
		try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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

	func loadBrowserSnapshot() throws -> BrowserSnapshot? {
		try read(BrowserSnapshot.self, named: "browser-snapshot.json")
	}

	func saveBrowserSnapshot(_ snapshot: BrowserSnapshot) throws {
		try write(snapshot, named: "browser-snapshot.json")
	}

	private func read<Value: Decodable>(_ type: Value.Type, named fileName: String) throws -> Value? {
		let url = directory.appendingPathComponent(fileName)
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		return try decoder.decode(type, from: Data(contentsOf: url))
	}

	private func write(_ value: some Encodable, named fileName: String) throws {
		let data = try encoder.encode(value)
		try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
	}
}
