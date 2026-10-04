import Foundation

private final class ConcurrentArchiveResults: @unchecked Sendable {
	private let lock = NSLock()
	private var successfulSaves = 0
	private var rejectedSaves = 0
	private var unexpectedErrors = 0

	func recordSuccess() {
		lock.lock()
		successfulSaves += 1
		lock.unlock()
	}

	func recordRejection() {
		lock.lock()
		rejectedSaves += 1
		lock.unlock()
	}

	func recordUnexpectedError() {
		lock.lock()
		unexpectedErrors += 1
		lock.unlock()
	}

	var result: (successes: Int, rejections: Int, unexpectedErrors: Int) {
		lock.lock()
		defer { lock.unlock() }
		return (successfulSaves, rejectedSaves, unexpectedErrors)
	}
}

@main
struct BookmarkReadingListCheck {
	static func main() throws {
		let legacyID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
		let legacyJSON = Data("{\"id\":\"\(legacyID.uuidString)\",\"name\":\"Legacy\",\"url\":\"https://legacy.example\"}".utf8)
		let legacy = try JSONDecoder().decode(Bookmark.self, from: legacyJSON)
		assert(legacy.folder.isEmpty && !legacy.isFavorite && legacy.order == Int.min)
		assert(legacy.modifiedAt == .distantPast)
		let secondID = UUID()
		let secondJSON = Data("{\"id\":\"\(secondID.uuidString)\",\"name\":\"Second\",\"url\":\"https://second.example\"}".utf8)
		let secondLegacy = try JSONDecoder().decode(Bookmark.self, from: secondJSON)
		let migrated = Bookmark.preservingLegacyOrder([legacy, secondLegacy])
		assert(migrated.map(\.order) == [0, 1])
		assert(migrated.allSatisfy { $0.modifiedAt == .distantPast })

		let folder = "Research & <Notes>"
		let bookmark = Bookmark(name: "A \"quoted\" & <title>", url: URL(string: "https://example.com/?a=1&b=2")!, folder: folder, isFavorite: true, order: 3)
		let source = BrowserUserData(bookmarks: [bookmark], history: [])
		let json = try JSONEncoder().encode(source)
		let decodedJSON = try BrowserUserData.decode(json, isHTML: false)
		assert(decodedJSON.bookmarks.first?.name == bookmark.name)
		assert(decodedJSON.bookmarks.first?.folder == folder)
		assert(decodedJSON.bookmarks.first?.isFavorite == true)
		let duplicateReadingID = UUID()
		let duplicateReading = ReadingListItem(id: duplicateReadingID, url: URL(string: "https://one.example")!, title: "One")
		let duplicateDocument = BrowserUserData(bookmarks: [], history: [], readingList: [duplicateReading, ReadingListItem(id: duplicateReadingID, url: URL(string: "https://two.example")!, title: "Two")])
		do {
			_ = try BrowserUserData.decode(JSONEncoder().encode(duplicateDocument), isHTML: false)
			assertionFailure("duplicate reading list IDs were accepted")
		} catch BrowserUserData.ImportError.invalidFile {
		} catch {
			assertionFailure("unexpected duplicate import error: \(error)")
		}
		let decodedHTML = try BrowserUserData.decode(source.encodedHTML(), isHTML: true)
		assert(decodedHTML.bookmarks.first?.name == bookmark.name)
		assert(decodedHTML.bookmarks.first?.folder == folder)
		assert(decodedHTML.bookmarks.first?.url == bookmark.url)
		let emptyNetscape = BrowserUserData(bookmarks: [], history: []).encodedHTML()
		let decodedEmpty = try BrowserUserData.decode(emptyNetscape, isHTML: true)
		assert(decodedEmpty.bookmarks.isEmpty)
		do {
			_ = try BrowserUserData.decode(Data("<html><body>nothing</body></html>".utf8), isHTML: true)
			assertionFailure("unrecognized empty HTML was accepted as bookmarks")
		} catch BrowserUserData.ImportError.invalidFile {
		} catch {
			assertionFailure("unexpected empty HTML import error: \(error)")
		}
		let nestedHTML = Data(#"<DL><p><DT><H3>Group &amp; &#x42;</H3><DL><p><DT><A HREF="https://nested.example/&#x61;">N&#x61;me</A></DL><p><DT><A HREF="https://root.example">Root</A></DL>"#.utf8)
		let nested = try BrowserUserData.decode(nestedHTML, isHTML: true).bookmarks
		assert(nested[0].folder == "Group & B" && nested[0].name == "Name")
		assert(nested[0].url.absoluteString == "https://nested.example/a")
		assert(nested[1].folder.isEmpty)
		let commentedHTML = Data(#"<!-- <A HREF="javascript:alert(1)">ignored</A> --><A HREF="https://real.example">real</A>"#.utf8)
		let commentResult = try BrowserUserData.decode(commentedHTML, isHTML: true).bookmarks.map(\.name)
		assert(commentResult == ["real"])
		let malformedHTML = Data(#"<A HREF="https://valid.example">valid</A><A HREF="javascript:alert(1)">"#.utf8)
		do {
			_ = try BrowserUserData.decode(malformedHTML, isHTML: true)
			assertionFailure("malformed mixed import was partially accepted")
		} catch BrowserUserData.ImportError.invalidFile {
		} catch {
			assertionFailure("unexpected malformed import error: \(error)")
		}

		let timestamp = Date(timeIntervalSince1970: 10000)
		let workspace = BrowserWorkspace(spaces: [BrowserSpace(id: BrowserSpace.firstID)], favouriteTabIDs: [], selectedSpaceID: BrowserSpace.firstID)
		let itemID = UUID()
		let older = ReadingListItem(id: itemID, url: URL(string: "https://read.example")!, title: "Old", addedAt: timestamp, modifiedAt: timestamp)
		assert(ReadingListItem.admitsOfflineOpen(older, id: itemID, url: older.url, isPrivate: false))
		assert(!ReadingListItem.admitsOfflineOpen(older, id: itemID, url: URL(string: "https://other.example")!, isPrivate: false))
		assert(!ReadingListItem.admitsOfflineOpen(older, id: itemID, url: older.url, isPrivate: true))
		assert(!ReadingListItem.admitsOfflineOpen(older, id: UUID(), url: older.url, isPrivate: false))
		assert(!ReadingListItem.admitsOfflineOpen(older, id: itemID, url: URL(string: "file:///tmp/page.html")!, isPrivate: false))
		assert(!ReadingListItem.admitsOfflineOpen(older, id: itemID, url: URL(string: "https://user:secret@read.example")!, isPrivate: false))
		let newer = ReadingListItem(id: itemID, url: older.url, title: "New", addedAt: timestamp, modifiedAt: timestamp.addingTimeInterval(1), isRead: true)
		let olderBookmark = Bookmark(id: legacyID, name: "Old", url: bookmark.url, modifiedAt: timestamp, folder: "Old folder")
		let newerBookmark = Bookmark(id: legacyID, name: "New", url: bookmark.url, modifiedAt: timestamp.addingTimeInterval(1), folder: "New folder", isFavorite: true, order: 4)
		let emptySnapshot = BrowserSnapshot()
		let oldPersistedState = BrowserPersistedState(bookmarks: [], openTabs: [], closedTabs: [], workspace: workspace, snapshot: emptySnapshot)
		var persistedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldPersistedState)) as! [String: Any]
		persistedObject.removeValue(forKey: "readingList")
		let migratedPersistedState = try JSONDecoder().decode(BrowserPersistedState.self, from: JSONSerialization.data(withJSONObject: persistedObject))
		assert(migratedPersistedState.readingList.isEmpty)
		let legacyDocument = BrowserSyncDocument(tabs: [], workspace: workspace, bookmarks: [legacy, secondLegacy], browser: emptySnapshot, settings: [:])
		var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyDocument)) as! [String: Any]
		var legacyBookmarks = legacyObject["bookmarks"] as! [[String: Any]]
		for index in legacyBookmarks.indices {
			legacyBookmarks[index].removeValue(forKey: "order")
			legacyBookmarks[index].removeValue(forKey: "folder")
			legacyBookmarks[index].removeValue(forKey: "isFavorite")
		}
		legacyObject["bookmarks"] = legacyBookmarks
		let decodedLegacySync = try JSONDecoder().decode(BrowserSyncDocument.self, from: JSONSerialization.data(withJSONObject: legacyObject))
		assert(decodedLegacySync.bookmarks.map(\.id) == [legacy.id, secondLegacy.id])
		assert(decodedLegacySync.bookmarks.map(\.order) == [0, 1])
		let stalePeer = BrowserSyncDocument(tabs: [], workspace: workspace, bookmarks: [olderBookmark], readingList: [older], browser: emptySnapshot, settings: [:])
		let currentPeer = BrowserSyncDocument(tabs: [], workspace: workspace, bookmarks: [newerBookmark], readingList: [newer], browser: emptySnapshot, settings: [:])
		assert(currentPeer.merging(stalePeer).bookmarks.first == newerBookmark)
		assert(currentPeer.merging(stalePeer).readingList.first == newer)
		assert(currentPeer.portableProjection().readingList.first == newer)
		var credentialed = newer
		credentialed.url = URL(string: "https://person:secret@read.example")!
		let credentialProjection = BrowserSyncDocument(tabs: [], workspace: workspace, bookmarks: [], readingList: [credentialed], browser: emptySnapshot, settings: [:]).portableProjection()
		assert(credentialProjection.readingList.first?.url.user == nil && credentialProjection.readingList.first?.url.password == nil)
		var deleted = BrowserSnapshot()
		deleted.deletedReadingListAt[itemID] = timestamp.addingTimeInterval(2)
		let deletionPeer = BrowserSyncDocument(tabs: [], workspace: workspace, bookmarks: [], readingList: [], browser: deleted, settings: [:])
		assert(currentPeer.merging(deletionPeer).readingList.isEmpty)
		let restored = ReadingListItem(id: itemID, url: older.url, title: "Restored", addedAt: timestamp, modifiedAt: timestamp.addingTimeInterval(3))
		let restoredPeer = BrowserSyncDocument(tabs: [], workspace: workspace, bookmarks: [], readingList: [restored], browser: emptySnapshot, settings: [:])
		assert(restoredPeer.merging(deletionPeer).readingList.first == restored)
		let futureEdit = BrowserUserDataMutation.nextDate(after: timestamp.addingTimeInterval(100), deletion: timestamp.addingTimeInterval(200))
		assert(futureEdit > timestamp.addingTimeInterval(200))
		let futureDelete = BrowserUserDataMutation.nextDate(after: timestamp, deletion: timestamp.addingTimeInterval(300))
		assert(futureDelete > timestamp.addingTimeInterval(300))

		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let persistence = BrowserPersistence(directory: directory)
		let secondPersistence = BrowserPersistence(directory: directory)
		let archiveID = UUID()
		let archiveURL = URL(string: "https://archive.example/page")!
		let firstGeneration = try persistence.saveReadingArchive(Data([1, 2, 3]), id: archiveID, url: archiveURL)
		let loadedArchive = try persistence.loadReadingArchive(id: archiveID, url: archiveURL)
		let mismatchedArchive = try persistence.loadReadingArchive(id: archiveID, url: URL(string: "https://changed.example")!)
		assert(loadedArchive == Data([1, 2, 3]))
		assert(mismatchedArchive == nil)
		let replacementURL = URL(string: "https://archive.example/replacement")!
		let replacementGeneration = try secondPersistence.saveReadingArchive(Data([4, 5, 6]), id: archiveID, url: replacementURL)
		assert(replacementGeneration != firstGeneration)
		let oldURLArchive = try persistence.loadReadingArchive(id: archiveID, url: archiveURL)
		let replacementArchive = try persistence.loadReadingArchive(id: archiveID, url: replacementURL)
		assert(oldURLArchive == nil)
		assert(replacementArchive == Data([4, 5, 6]))
		try persistence.removeReadingArchive(id: archiveID, ifGeneration: firstGeneration)
		let afterStaleRemoval = try persistence.loadReadingArchive(id: archiveID, url: replacementURL)
		assert(afterStaleRemoval == Data([4, 5, 6]))
		do {
			_ = try persistence.saveReadingArchive(Data(repeating: 0, count: 32 * 1024 * 1024 + 1), id: archiveID, url: archiveURL)
			assertionFailure("oversized replacement was accepted")
		} catch BrowserUserData.ImportError.tooLarge {}
		let afterFailedReplace = try persistence.loadReadingArchive(id: archiveID, url: replacementURL)
		assert(afterFailedReplace == Data([4, 5, 6]))
		try persistence.removeReadingArchive(id: archiveID)
		let removedArchive = try persistence.loadReadingArchive(id: archiveID, url: archiveURL)
		assert(removedArchive == nil)
		for _ in 0 ..< 49 {
			_ = try persistence.saveReadingArchive(Data([1]), id: UUID(), url: archiveURL)
		}
		let results = ConcurrentArchiveResults()
		let raceIDs = [UUID(), UUID()]
		DispatchQueue.concurrentPerform(iterations: raceIDs.count) { index in
			do {
				_ = try (index == 0 ? persistence : secondPersistence).saveReadingArchive(Data([2]), id: raceIDs[index], url: archiveURL)
				results.recordSuccess()
			} catch BrowserUserData.ImportError.tooLarge {
				results.recordRejection()
			} catch {
				results.recordUnexpectedError()
			}
		}
		assert(results.result.successes == 1)
		assert(results.result.rejections == 1)
		assert(results.result.unexpectedErrors == 0)

		let quotaDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		defer { try? FileManager.default.removeItem(at: quotaDirectory) }
		let quotaFolder = quotaDirectory.appendingPathComponent("reading-list", isDirectory: true)
		try FileManager.default.createDirectory(at: quotaFolder, withIntermediateDirectories: true)
		for _ in 0 ..< 7 {
			let sparseFile = quotaFolder.appendingPathComponent(UUID().uuidString).appendingPathExtension("webarchive")
			guard FileManager.default.createFile(atPath: sparseFile.path, contents: Data()) else {
				throw BrowserPersistenceError.invalidSnapshot
			}
			let handle = try FileHandle(forWritingTo: sparseFile)
			try handle.truncate(atOffset: 32 * 1024 * 1024)
			try handle.close()
		}
		let quotaStore = BrowserPersistence(directory: quotaDirectory)
		let quotaID = UUID()
		let quotaURL = URL(string: "https://quota.example")!
		_ = try quotaStore.saveReadingArchive(Data([9]), id: quotaID, url: quotaURL)
		do {
			_ = try quotaStore.saveReadingArchive(Data(repeating: 0, count: 32 * 1024 * 1024), id: quotaID, url: quotaURL)
			assertionFailure("total archive quota was not enforced")
		} catch BrowserUserData.ImportError.tooLarge {}
		let quotaSnapshot = try quotaStore.loadReadingArchive(id: quotaID, url: quotaURL)
		assert(quotaSnapshot == Data([9]))

		let blockedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		defer { try? FileManager.default.removeItem(at: blockedDirectory) }
		try FileManager.default.createDirectory(at: blockedDirectory, withIntermediateDirectories: true)
		try Data([1]).write(to: blockedDirectory.appendingPathComponent("reading-list"))
		let blockedPersistence = BrowserPersistence(directory: blockedDirectory)
		do {
			_ = try blockedPersistence.loadReadingArchive(id: UUID(), url: archiveURL)
			assertionFailure("unreadable archive directory was treated as empty")
		} catch {}

		let hostileHTML = Data(#"<DT><A HREF="javascript:alert(1)">bad</A>"#.utf8)
		do {
			_ = try BrowserUserData.decode(hostileHTML, isHTML: true)
			assertionFailure("executable URL was accepted")
		} catch BrowserUserData.ImportError.invalidFile {
		} catch {
			assertionFailure("unexpected hostile import error: \(error)")
		}

		let privateNetworkJSON = Data("{\"version\":1,\"bookmarks\":[{\"id\":\"\(legacyID.uuidString)\",\"name\":\"Bad\",\"url\":\"file:///etc/passwd\"}],\"history\":[]}".utf8)
		do {
			_ = try BrowserUserData.decode(privateNetworkJSON, isHTML: false)
			assertionFailure("privileged URL was accepted")
		} catch BrowserUserData.ImportError.invalidFile {
		} catch {
			assertionFailure("unexpected JSON import error: \(error)")
		}
		let hostileHistoryJSON = Data("{\"version\":1,\"bookmarks\":[],\"history\":[{\"id\":\"\(legacyID.uuidString)\",\"url\":\"https://user:secret@history.example\",\"title\":\"private\"}]}".utf8)
		do {
			_ = try BrowserUserData.decode(hostileHistoryJSON, isHTML: false)
			assertionFailure("credential-bearing history URL was accepted")
		} catch BrowserUserData.ImportError.invalidFile {
		} catch {
			assertionFailure("unexpected history import error: \(error)")
		}
	}
}
