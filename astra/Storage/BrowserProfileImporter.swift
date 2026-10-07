import Foundation
import SQLite3

nonisolated enum BrowserProfileImporter {
	struct Preview: Sendable {
		let document: BrowserUserData
		let warnings: [String]
	}

	static func profiles(for source: BrowserImportSource, in directory: URL? = nil) throws -> [BrowserImportProfile] {
		BrowserLog.info(.persistence, "profile-import.scan", metadata: ["source": String(describing: source), "directory": BrowserLog.path(directory)])
		let root = directory ?? FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/" + source.libraryPath)
		let sidebarRoot = root.lastPathComponent == "User Data" ? root.deletingLastPathComponent() : root
		let sidebarURL = sidebarRoot.appendingPathComponent("StorableSidebar.json")
		let sidebar = source == .arc && FileManager.default.fileExists(atPath: sidebarURL.path) ? sidebarURL : nil
		if source == .safari {
			return [BrowserImportProfile(source: source, directory: root, name: "Safari", sidebar: nil)]
		}
		func hasData(_ folder: URL) -> Bool {
			let names = source == .firefox ? ["places.sqlite"] : ["Bookmarks", "History"]
			return names.contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
		}
		if hasData(root) {
			return [BrowserImportProfile(source: source, directory: root, name: root.lastPathComponent, sidebar: sidebar)]
		}
		var profileRoot = root
		if source == .arc || source == .dia {
			let nested = root.appendingPathComponent("User Data")
			if FileManager.default.fileExists(atPath: nested.path) {
				profileRoot = nested
			}
		}
		let folders = try FileManager.default.contentsOfDirectory(at: profileRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
		let localState = profileRoot.appendingPathComponent("Local State")
		let metadata = (try? JSONSerialization.jsonObject(with: Data(contentsOf: localState))) as? [String: Any]
		let info = (metadata?["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]]
		let results = folders.filter(hasData).map { folder in
			let label = info?[folder.lastPathComponent]?["name"] as? String
			return BrowserImportProfile(source: source, directory: folder, name: label.map { "\($0) (\(folder.lastPathComponent))" } ?? folder.lastPathComponent, sidebar: sidebar)
		}.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		if results.isEmpty, let sidebar {
			return [BrowserImportProfile(source: source, directory: profileRoot, name: "Arc Sidebar", sidebar: sidebar)]
		}
		return results
	}

	static func read(_ profile: BrowserImportProfile, scope: BrowserImportScope) throws -> Preview {
		BrowserLog.info(.persistence, "profile-import.read.begin", metadata: ["source": String(describing: profile.source), "profile": BrowserLog.value(profile.name), "directory": BrowserLog.path(profile.directory)])
		var bookmarks: [Bookmark] = []
		var history: [BrowserVisit] = []
		var warnings: [String] = []
		if scope.includesBookmarks {
			do {
				switch profile.source {
					case .safari:
						bookmarks = try safariBookmarks(readFile(profile.directory.appendingPathComponent("Bookmarks.plist")))
					case .firefox:
						bookmarks = try firefoxBookmarks(profile.directory.appendingPathComponent("places.sqlite"))
					default:
						let file = profile.directory.appendingPathComponent("Bookmarks")
						if FileManager.default.fileExists(atPath: file.path) {
							bookmarks = try chromiumBookmarks(readFile(file))
						} else if profile.sidebar == nil {
							throw BrowserUserData.ImportError.invalidFile
						}
				}
			} catch {
				warnings.append("Bookmarks could not be read: \(error.localizedDescription)")
			}
			if profile.source == .arc, let sidebar = profile.sidebar {
				do {
					bookmarks += try arcBookmarks(readFile(sidebar))
				} catch {
					warnings.append("Arc sidebar could not be read: \(error.localizedDescription)")
				}
			}
		}
		if scope.includesHistory {
			do {
				let query: String
				let filename: String
				let epoch: Double
				let divisor: Double
				switch profile.source {
					case .safari:
						filename = "History.db"
						query = "SELECT i.url, COALESCE(v.title, ''), v.visit_time FROM history_visits v JOIN history_items i ON i.id = v.history_item ORDER BY v.visit_time DESC"
						epoch = 978_307_200
						divisor = 1
					case .firefox:
						filename = "places.sqlite"
						query = "SELECT p.url, COALESCE(p.title, ''), v.visit_date FROM moz_historyvisits v JOIN moz_places p ON p.id = v.place_id ORDER BY v.visit_date DESC"
						epoch = 0
						divisor = 1_000_000
					default:
						filename = "History"
						query = "SELECT u.url, COALESCE(u.title, ''), v.visit_time FROM visits v JOIN urls u ON u.id = v.url ORDER BY v.visit_time DESC"
						epoch = -11_644_473_600
						divisor = 1_000_000
				}
				try rows(in: profile.directory.appendingPathComponent(filename), query: query) { statement in
					guard let url = portableURL(string(statement, 0)) else { return }
					let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2) / divisor + epoch)
					guard date.timeIntervalSince1970.isFinite, date >= Date(timeIntervalSince1970: -2_208_988_800), date <= Date.now.addingTimeInterval(300) else { return }
					history.append(BrowserVisit(url: url, title: String(string(statement, 1).prefix(4096)), visitedAt: date, modifiedAt: .now))
				}
			} catch {
				history = []
				warnings.append("History could not be read: \(error.localizedDescription)")
			}
		}
		guard warnings.isEmpty || !bookmarks.isEmpty || !history.isEmpty else {
			throw ReadError.unavailable(warnings.joined(separator: "\n"))
		}
		let document = BrowserUserData(bookmarks: bookmarks, history: history)
		let validated = try BrowserUserData.decode(JSONEncoder().encode(document), isHTML: false)
		BrowserLog.info(.persistence, "profile-import.read.end", metadata: ["bookmarks": String(validated.bookmarks.count), "history": String(validated.history.count), "warnings": String(warnings.count)])
		return Preview(document: validated, warnings: warnings)
	}

	static func readFile(_ url: URL) throws -> Data {
		BrowserLog.trace(.persistence, "profile-import.read-file", metadata: ["file": BrowserLog.path(url)])
		let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
		guard size <= 16 * 1024 * 1024 else { throw BrowserUserData.ImportError.tooLarge }
		return try Data(contentsOf: url)
	}

	static func chromiumBookmarks(_ data: Data) throws -> [Bookmark] {
		guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let roots = root["roots"] as? [String: [String: Any]] else { throw BrowserUserData.ImportError.invalidFile }
		var results: [Bookmark] = []
		func visit(_ node: [String: Any], path: [String], depth: Int) throws {
			guard depth < 64 else { throw BrowserUserData.ImportError.tooLarge }
			if node["type"] as? String == "url" {
				if let url = portableURL(node["url"] as? String ?? "") {
					try appendBookmark(to: &results, url: url, title: node["name"] as? String ?? "", path: path)
				}
			} else if let children = node["children"] as? [[String: Any]] {
				let name = node["name"] as? String ?? ""
				for child in children {
					try visit(child, path: path + (name.isEmpty ? [] : [name]), depth: depth + 1)
				}
			}
		}
		for key in roots.keys.sorted() {
			if let node = roots[key] {
				try visit(node, path: [], depth: 0)
			}
		}
		return results
	}

	static func safariBookmarks(_ data: Data) throws -> [Bookmark] {
		guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
		      root["Children"] is [[String: Any]] else { throw BrowserUserData.ImportError.invalidFile }
		var results: [Bookmark] = []
		func visit(_ node: [String: Any], path: [String], depth: Int) throws {
			guard depth < 64 else { throw BrowserUserData.ImportError.tooLarge }
			if let address = node["URLString"] as? String, let url = portableURL(address) {
				let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""
				try appendBookmark(to: &results, url: url, title: title, path: path)
			} else if let children = node["Children"] as? [[String: Any]] {
				let title = node["Title"] as? String ?? ""
				if title == "com.apple.ReadingList" {
					return
				}
				for child in children {
					try visit(child, path: path + (title.isEmpty ? [] : [title]), depth: depth + 1)
				}
			}
		}
		try visit(root, path: [], depth: 0)
		return results
	}

	static func firefoxBookmarks(_ url: URL) throws -> [Bookmark] {
		var nodes: [Int64: (parent: Int64, title: String, isTags: Bool)] = [:]
		var links: [(parent: Int64, title: String, url: URL)] = []
		try rows(in: url, query: "SELECT b.id, b.parent, COALESCE(b.title, ''), COALESCE(p.url, ''), b.type, b.guid FROM moz_bookmarks b LEFT JOIN moz_places p ON p.id = b.fk ORDER BY b.position, b.id") { statement in
			let parent = sqlite3_column_int64(statement, 1)
			let title = string(statement, 2)
			if sqlite3_column_int(statement, 4) == 2 {
				nodes[sqlite3_column_int64(statement, 0)] = (parent, title, string(statement, 5) == "tags________")
			} else if let address = portableURL(string(statement, 3)) {
				links.append((parent, title, address))
			}
		}
		var results: [Bookmark] = []
		for link in links {
			var path: [String] = []
			var parent = link.parent
			var seen: Set<Int64> = []
			var isTag = false
			while let node = nodes[parent] {
				guard seen.insert(parent).inserted, seen.count < 64 else { throw BrowserUserData.ImportError.invalidFile }
				if node.isTags {
					isTag = true
					break
				}
				if !node.title.isEmpty {
					path.insert(node.title, at: 0)
				}
				parent = node.parent
			}
			if !isTag {
				try appendBookmark(to: &results, url: link.url, title: link.title, path: path)
			}
		}
		return results
	}

	static func arcBookmarks(_ data: Data) throws -> [Bookmark] {
		let root = try JSONSerialization.jsonObject(with: data)
		func findArray(_ value: Any, key: String, depth: Int = 0) -> [Any]? {
			guard depth < 64 else { return nil }
			if let dictionary = value as? [String: Any] {
				if let array = dictionary[key] as? [Any] {
					return array
				}
				for child in dictionary.values {
					if let found = findArray(child, key: key, depth: depth + 1) {
						return found
					}
				}
			} else if let array = value as? [Any] {
				for child in array {
					if let found = findArray(child, key: key, depth: depth + 1) {
						return found
					}
				}
			}
			return nil
		}
		guard let containers = findArray(root, key: "containers") else { throw BrowserUserData.ImportError.invalidFile }
		var results: [Bookmark] = []
		var foundItems = false
		for container in containers {
			guard let rawItems = findArray(container, key: "items") else { continue }
			let items = rawItems.compactMap { $0 as? [String: Any] }
			foundItems = true
			guard items.count <= 100_000 else { throw BrowserUserData.ImportError.tooLarge }
			let nodes = Dictionary(items.compactMap { item -> (String, [String: Any])? in
				guard let id = item["id"] as? String else { return nil }
				return (id, item)
			}, uniquingKeysWith: { first, _ in first })
			var spaces: [String: String] = [:]
			func collectRoots(_ value: Any, title: String, depth: Int = 0) {
				guard depth < 64 else { return }
				if let dictionary = value as? [String: Any] {
					for (key, child) in dictionary {
						if key.lowercased().contains("itemcontainer") || key.lowercased().hasPrefix("root") {
							if let id = child as? String {
								spaces[id] = title
							}
							if let ids = child as? [String] {
								for id in ids {
									spaces[id] = title
								}
							}
						}
						collectRoots(child, title: title, depth: depth + 1)
					}
				}
			}
			for space in (findArray(container, key: "spaces") ?? []).compactMap({ $0 as? [String: Any] }) {
				collectRoots(space, title: space["title"] as? String ?? space["name"] as? String ?? "Space")
			}
			for item in items {
				guard let payload = item["data"] as? [String: Any],
				      let tab = payload["tab"] as? [String: Any],
				      let address = tab["savedURL"] as? String,
				      let url = portableURL(address) else { continue }
				var path: [String] = []
				var node = item
				var seen: Set<String> = []
				while let id = node["id"] as? String {
					guard seen.insert(id).inserted, seen.count < 64 else { throw BrowserUserData.ImportError.invalidFile }
					if let space = spaces[id] {
						path.insert(space, at: 0)
						break
					}
					guard let parent = node["parentID"] as? String ?? node["parentId"] as? String,
					      let ancestor = nodes[parent] else { break }
					let title = ancestor["title"] as? String ?? ""
					if !title.isEmpty {
						path.insert(title, at: 0)
					}
					node = ancestor
				}
				let title = item["title"] as? String ?? tab["savedTitle"] as? String ?? ""
				try appendBookmark(to: &results, url: url, title: title, path: ["Arc"] + path)
			}
		}
		guard foundItems else { throw BrowserUserData.ImportError.invalidFile }
		return results
	}

	private static func appendBookmark(to results: inout [Bookmark], url: URL, title: String, path: [String]) throws {
		let folder = path.joined(separator: "/")
		guard results.count < 100_000, title.utf8.count <= 16384, folder.utf8.count <= 4096 else { throw BrowserUserData.ImportError.tooLarge }
		results.append(Bookmark(name: title.isEmpty ? url.host ?? url.absoluteString : title, url: url, folder: folder, order: results.count))
	}

	private static func portableURL(_ address: String) -> URL? {
		guard address.utf8.count <= 16384, let url = URL(string: address),
		      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      BrowserVisit.isEligible(url), components.user == nil, components.password == nil else { return nil }
		return url
	}

	private static func string(_ statement: OpaquePointer, _ column: Int32) -> String {
		sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
	}

	private static func rows(in url: URL, query: String, read: (OpaquePointer) throws -> Void) throws {
		var database: OpaquePointer?
		guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
			let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
			if let database {
				sqlite3_close(database)
			}
			throw ReadError.unavailable(message + ". Close the source browser and check file access.")
		}
		defer { sqlite3_close(database) }
		sqlite3_busy_timeout(database, 1500)
		// One read transaction includes committed WAL rows without modifying source records.
		var statement: OpaquePointer?
		guard sqlite3_prepare_v2(database, query + " LIMIT 100001", -1, &statement, nil) == SQLITE_OK, let statement else {
			throw ReadError.unavailable(String(cString: sqlite3_errmsg(database)))
		}
		defer { sqlite3_finalize(statement) }
		var count = 0
		var step = sqlite3_step(statement)
		while step == SQLITE_ROW {
			count += 1
			guard count <= 100_000 else { throw BrowserUserData.ImportError.tooLarge }
			try read(statement)
			step = sqlite3_step(statement)
		}
		guard step == SQLITE_DONE else { throw ReadError.unavailable(String(cString: sqlite3_errmsg(database))) }
	}

	enum ReadError: LocalizedError {
		case unavailable(String)

		var errorDescription: String? {
			switch self {
				case let .unavailable(message): message
			}
		}
	}
}
