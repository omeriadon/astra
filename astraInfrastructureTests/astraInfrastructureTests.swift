@testable import astra
import Foundation
import Testing
import WebKit

@MainActor
struct AstraInfrastructureTests {
	private func state(title: String) -> BrowserPersistedState {
		let tab = OpenTab(pageTitle: title, url: URL(string: "https://example.test")!)
		return BrowserPersistedState(
			bookmarks: [Bookmark(name: title, url: URL(string: "https://example.test")!)],
			openTabs: [tab],
			closedTabs: [],
			workspace: .migrated(tabs: [tab], selectedTabID: tab.id, theme: BrowserTheme()),
			snapshot: BrowserSnapshot(selectedTabID: tab.id),
			historyVisits: [BrowserVisit(url: URL(string: "https://example.test")!, title: title)]
		)
	}

	#if os(macOS)
		@Test func desktopLinkGesturesChooseTabActivation() {
			#expect(BrowserController.linkTabInBackground(navigationType: .linkActivated, modifiers: .command, buttonNumber: 1) == true)
			#expect(BrowserController.linkTabInBackground(navigationType: .linkActivated, modifiers: [.command, .shift], buttonNumber: 1) == false)
			#expect(BrowserController.linkTabInBackground(navigationType: .linkActivated, modifiers: [], buttonNumber: 4) == true)
			#expect(BrowserController.linkTabInBackground(navigationType: .linkActivated, modifiers: .shift, buttonNumber: 4) == false)
			#expect(BrowserController.linkTabInBackground(navigationType: .linkActivated, modifiers: .shift, buttonNumber: 1) == nil)
			#expect(BrowserController.linkTabInBackground(navigationType: .linkActivated, modifiers: [], buttonNumber: 2) == nil)
			#expect(BrowserController.linkTabInBackground(navigationType: .formSubmitted, modifiers: .command, buttonNumber: 1) == nil)
			#expect(BrowserController.linkTabInBackground(navigationType: .other, modifiers: .command, buttonNumber: 4) == nil)
		}
	#endif

	@Test func snapshotRecoversLastGoodGeneration() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let store = BrowserPersistence(directory: directory)
		try store.savePersistedState(state(title: "First"))
		try store.savePersistedState(state(title: "Second"))
		try Data("invalid".utf8).write(to: directory.appendingPathComponent("browser-state.json"))
		let restored = try #require(try store.loadPersistedState())
		#expect(restored.openTabs.first?.pageTitle == "First")
		#expect(restored.bookmarks.first?.name == "First")
		#expect(restored.workspace.selectedSpaceID == restored.workspace.spaces.first?.id)
	}

	@Test func invalidSnapshotsArePreserved() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("browser-state.json")
		let invalid = Data("invalid".utf8)
		try invalid.write(to: url)
		#expect(throws: BrowserPersistenceError.invalidSnapshot) {
			try BrowserPersistence(directory: directory).loadPersistedState()
		}
		#expect(try Data(contentsOf: url) == invalid)
	}

	@Test func closingControllerInvalidatesPendingDocumentRequests() {
		let controller = BrowserController(session: BrowserWebSession(isPrivate: true))
		let documentID = controller.navigationIdentifier
		controller.stopForClose()
		#expect(controller.navigationIdentifier != documentID)
	}

	@Test func clearingTabHistoryKeepsTheLiveController() throws {
		let first = try #require(URL(string: "https://example.test/first"))
		let second = try #require(URL(string: "https://example.test/second"))
		let tab = BrowserTab(initialURL: second, history: [first, second], historyIndex: 1)
		let controller = tab.controller
		tab.clearRecordedHistory()
		#expect(tab.controller === controller)
		#expect(tab.openTab.history == [second])
		#expect(tab.openTab.historyIndex == 0)
		#expect(!tab.openTab.recordsNavigationHistory)
		#expect(tab.openTab.restorationState == nil)
	}

	@Test func deletingHistoryRemovesBackupHistory() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let store = BrowserPersistence(directory: directory)
		var value = state(title: "History")
		try store.savePersistedState(value)
		value.historyVisits = []
		try store.savePersistedState(value)
		try Data("invalid".utf8).write(to: directory.appendingPathComponent("browser-state.json"))
		#expect(try store.loadPersistedState()?.historyVisits?.isEmpty == true)
	}

	@Test func unsupportedSnapshotDoesNotFallBackToOlderData() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let store = BrowserPersistence(directory: directory)
		try store.savePersistedState(state(title: "First"))
		try store.savePersistedState(state(title: "Second"))
		let url = directory.appendingPathComponent("browser-state.json")
		var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
		object["version"] = 99
		try JSONSerialization.data(withJSONObject: object).write(to: url)
		#expect(throws: BrowserPersistenceError.unsupportedVersion) {
			try store.loadPersistedState()
		}
	}

	@Test func privateWindowsHaveIndependentStoresAndPermissions() {
		let first = BrowserWebSession(isPrivate: true)
		let second = BrowserWebSession(isPrivate: true)
		#expect(!first.dataStore.isPersistent)
		#expect(first.dataStore !== second.dataStore)
		#expect(first.downloads !== second.downloads)
		first.permissions.set(true, origin: "https://example.test", topOrigin: "https://example.test", capability: .camera)
		#expect(second.permissions.entries.isEmpty)
	}

	@Test func permissionOriginsKeepPortsAndRejectLocalFiles() throws {
		#expect(try BrowserSitePermissions.origin(for: #require(URL(string: "https://example.test:443/path"))) == "https://example.test")
		#expect(try BrowserSitePermissions.origin(for: #require(URL(string: "https://example.test:8443/path"))) == "https://example.test:8443")
		#expect(try BrowserSitePermissions.origin(for: #require(URL(string: "file:///tmp/page.html"))) == nil)
	}

	@Test func htmlBookmarksRoundTripAndRejectExecutableURLs() throws {
		let bookmark = try Bookmark(name: "Docs <A> & B", url: #require(URL(string: "https://example.test/?a=1&b=2")))
		let document = BrowserUserData(bookmarks: [bookmark], history: [])
		let restored = try BrowserUserData.decode(document.encodedHTML(), isHTML: true)
		#expect(restored.bookmarks.first?.name == bookmark.name)
		#expect(restored.bookmarks.first?.url == bookmark.url)
		let hostile = Data(#"<A HREF="javascript:alert(1)">Bad</A>"#.utf8)
		#expect(try BrowserUserData.decode(hostile, isHTML: true).bookmarks.isEmpty)
	}

	@Test func syncTombstonesPreventClosedTabsReturning() {
		let local = state(title: "Tab")
		let id = local.openTabs[0].id
		let first = BrowserSyncDocument(
			tabs: local.openTabs, workspace: local.workspace, bookmarks: [],
			browser: local.snapshot, settings: [:]
		)
		let second = BrowserSyncDocument(
			tabs: [], workspace: local.workspace, bookmarks: [],
			browser: BrowserSnapshot(selectedTabID: id, closedTabIDs: [id]), settings: [:]
		)
		#expect(first.merging(second).tabs.isEmpty)
	}

	@Test func retentionUsesVisitDatesAndCanKeepAllHistory() throws {
		let now = Date(timeIntervalSince1970: 2_000_000)
		let old = try BrowserVisit(url: #require(URL(string: "https://old.test")), title: "Old", visitedAt: now.addingTimeInterval(-8 * 86400))
		let recent = try BrowserVisit(url: #require(URL(string: "https://recent.test")), title: "Recent", visitedAt: now)
		#expect(BrowserVisit.retained([old, recent], days: 7, now: now) == [recent])
		#expect(BrowserVisit.retained([old, recent], days: 0, now: now) == [old, recent])
	}

	@Test func syncRejectsLocalFilesAndRestorationBlobs() {
		let local = state(title: "Tab")
		var document = BrowserSyncDocument(tabs: local.openTabs, workspace: local.workspace, bookmarks: [], browser: local.snapshot, settings: [:])
		#expect(document.hasValidStructure)
		document.tabs[0].restorationState = Data([1, 2, 3])
		#expect(!document.hasValidStructure)
		document.tabs[0].restorationState = nil
		document.tabs[0].url = URL(fileURLWithPath: "/tmp/private.html")
		#expect(!document.hasValidStructure)
	}

	@Test func savedAddressesDoNotContainCredentials() throws {
		let original = try #require(URL(string: "https://user:secret@example.test/path?q=1"))
		#expect(BrowserAddress.withoutCredentials(original).absoluteString == "https://example.test/path?q=1")
	}
}
