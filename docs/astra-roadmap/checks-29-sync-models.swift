import Foundation

@main
struct BrowserSyncModelCheck {
	static func main() throws {
		let now = Date(timeIntervalSince1970: 10000)
		let tabID = UUID()
		let oldTab = OpenTab(id: tabID, url: URL(string: "https://old.example")!, modifiedAt: now)
		let newTab = OpenTab(id: tabID, url: URL(string: "https://new.example")!, modifiedAt: now.addingTimeInterval(1))
		let space = BrowserSpace(id: BrowserSpace.firstID)
		let emptySnapshot = BrowserSnapshot(selectedTabID: tabID)
		let oldDoc = BrowserSyncDocument(tabs: [oldTab], workspace: BrowserWorkspace(spaces: [space], favouriteTabIDs: [], selectedSpaceID: space.id), bookmarks: [], browser: emptySnapshot, settings: [:])
		let newDoc = BrowserSyncDocument(tabs: [newTab], workspace: oldDoc.workspace!, bookmarks: [], browser: emptySnapshot, settings: [:])
		assert(oldDoc.merging(newDoc).tabs.first?.url == newTab.url)
		assert(newDoc.merging(oldDoc).tabs.first?.url == newTab.url)
		let restoredTab = OpenTab(id: tabID, url: oldTab.url, history: oldTab.history, historyIndex: oldTab.historyIndex, pageZoom: oldTab.pageZoom, scrollPosition: oldTab.scrollPosition)
		assert(oldTab.hasSameNavigationState(as: restoredTab))
		var retitledTab = restoredTab
		retitledTab.pageTitle = "Updated title"
		assert(oldTab.hasSameNavigationState(as: retitledTab))
		var scrolledTab = restoredTab
		scrolledTab.scrollPosition.y = 100
		assert(!oldTab.hasSameNavigationState(as: scrolledTab))
		var navigatedTab = restoredTab
		navigatedTab.url = URL(string: "https://different.example")
		assert(!oldTab.hasSameNavigationState(as: navigatedTab))
		assert(oldDoc.merging(newDoc) == newDoc.merging(oldDoc))
		assert(oldDoc.merging(newDoc).merging(newDoc) == oldDoc.merging(newDoc))

		let staleVisit = BrowserVisit(id: UUID(), url: URL(string: "https://stale-visit.example")!, title: "Stale", visitedAt: now, modifiedAt: now)
		let staleBookmark = Bookmark(id: UUID(), name: "Stale", url: URL(string: "https://stale-bookmark.example")!, modifiedAt: now)
		let staleSpace = BrowserSpace(id: UUID(), name: "Stale", modifiedAt: now)
		var currentMetadata = BrowserSnapshot(selectedTabID: tabID)
		currentMetadata.closedTabIDs.insert(tabID)
		currentMetadata.closedTabsAt[tabID] = now.addingTimeInterval(1)
		currentMetadata.deletedBookmarkIDs.insert(staleBookmark.id)
		currentMetadata.deletedBookmarksAt[staleBookmark.id] = now.addingTimeInterval(1)
		currentMetadata.deletedSpacesAt[staleSpace.id] = now.addingTimeInterval(1)
		currentMetadata.deletedVisitsAt[staleVisit.id] = now.addingTimeInterval(1)
		currentMetadata.historyClearedAt = now.addingTimeInterval(2)
		let currentWorkspace = BrowserWorkspace(spaces: [], favouriteTabIDs: [], selectedSpaceID: space.id, deletedSpaceIDs: [staleSpace.id], deletedSpacesAt: [staleSpace.id: now.addingTimeInterval(1)])
		let currentPeer = BrowserSyncDocument(tabs: [], workspace: currentWorkspace, bookmarks: [], browser: currentMetadata, settings: [:])
		let stalePeer = BrowserSyncDocument(tabs: [oldTab], workspace: BrowserWorkspace(spaces: [staleSpace], favouriteTabIDs: [], selectedSpaceID: staleSpace.id), bookmarks: [staleBookmark], history: [staleVisit], browser: emptySnapshot, settings: [:])
		let protectedPeerMerge = currentPeer.merging(stalePeer)
		assert(protectedPeerMerge.tabs.isEmpty && protectedPeerMerge.bookmarks.isEmpty && protectedPeerMerge.history.isEmpty)
		assert(protectedPeerMerge.browser.closedTabsAt[tabID] == currentMetadata.closedTabsAt[tabID])
		assert(protectedPeerMerge.browser.deletedBookmarksAt[staleBookmark.id] == currentMetadata.deletedBookmarksAt[staleBookmark.id])
		assert(protectedPeerMerge.browser.deletedSpacesAt[staleSpace.id] == currentMetadata.deletedSpacesAt[staleSpace.id])
		assert(protectedPeerMerge.browser.deletedVisitsAt[staleVisit.id] == currentMetadata.deletedVisitsAt[staleVisit.id])
		assert(protectedPeerMerge.browser.historyClearedAt == currentMetadata.historyClearedAt)

		let bootstrapWorkspace = BrowserWorkspace.migrated(tabs: [], selectedTabID: tabID, theme: BrowserTheme())
		assert(bootstrapWorkspace.modifiedAt == .distantPast)
		let remoteSpace = BrowserSpace(id: BrowserSpace.firstID, name: "Remote", modifiedAt: now)
		let remoteWorkspace = BrowserWorkspace(spaces: [remoteSpace], favouriteTabIDs: [], selectedSpaceID: remoteSpace.id, modifiedAt: now)
		let bootstrap = BrowserSyncDocument(tabs: [], workspace: bootstrapWorkspace, bookmarks: [], browser: emptySnapshot, settings: [:])
		let remote = BrowserSyncDocument(tabs: [], workspace: remoteWorkspace, bookmarks: [], browser: emptySnapshot, settings: [:])
		assert(bootstrap.merging(remote).workspace?.spaces.first?.name == "Remote")
		let tiedSpaceA = BrowserSpace(id: BrowserSpace.firstID, name: "Alpha", modifiedAt: now)
		let tiedSpaceB = BrowserSpace(id: BrowserSpace.firstID, name: "Zulu", modifiedAt: now)
		let tiedWorkspaceA = BrowserWorkspace(spaces: [tiedSpaceA], favouriteTabIDs: [], selectedSpaceID: tiedSpaceA.id, modifiedAt: now)
		let tiedWorkspaceB = BrowserWorkspace(spaces: [tiedSpaceB], favouriteTabIDs: [], selectedSpaceID: tiedSpaceB.id, modifiedAt: now)
		let tiedDocumentA = BrowserSyncDocument(tabs: [], workspace: tiedWorkspaceA, bookmarks: [], browser: emptySnapshot, settings: [:])
		let tiedDocumentB = BrowserSyncDocument(tabs: [], workspace: tiedWorkspaceB, bookmarks: [], browser: emptySnapshot, settings: [:])
		let tieForward = tiedDocumentA.merging(tiedDocumentB)
		let tieReverse = tiedDocumentB.merging(tiedDocumentA)
		assert(tieForward == tieReverse)

		let localFileTab = OpenTab(
			id: UUID(),
			url: URL(fileURLWithPath: "/tmp/local-page.html"),
			modifiedAt: now,
			restorationState: Data([1, 2, 3]),
			fileAccessBookmark: Data([4, 5, 6])
		)
		var localWorkspace = oldDoc.workspace!
		localWorkspace.favouriteTabIDs = [localFileTab.id, oldTab.id]
		localWorkspace.spaces[0].tabIDs = [localFileTab.id, oldTab.id]
		localWorkspace.spaces[0].pinnedTabIDs = [localFileTab.id]
		localWorkspace.spaces[0].pinnedFolders = [PinnedTabFolder(name: "Local files", tabIDs: [localFileTab.id])]
		let localFileBookmark = Bookmark(name: "Local file", url: URL(fileURLWithPath: "/tmp/bookmark.html"))
		let webBookmark = Bookmark(name: "Web", url: URL(string: "https://web.example")!)
		let localOnlyDocument = BrowserSyncDocument(
			tabs: [localFileTab, oldTab],
			workspace: localWorkspace,
			bookmarks: [localFileBookmark, webBookmark],
			browser: BrowserSnapshot(
				selectedTabID: localFileTab.id,
				selectedTabModifiedAt: now,
				closedTabIDs: [localFileTab.id],
				deletedBookmarkIDs: [localFileBookmark.id],
				deletedBookmarksAt: [localFileBookmark.id: now],
				closedTabsAt: [localFileTab.id: now]
			),
			settings: [:]
		)
		let outbound = localOnlyDocument.portableProjection()
		assert(!outbound.tabs.contains(where: { $0.id == localFileTab.id }))
		assert(outbound.tabs.contains(where: { $0.id == oldTab.id }))
		assert(!outbound.bookmarks.contains(where: { $0.id == localFileBookmark.id }))
		assert(outbound.bookmarks.contains(where: { $0.id == webBookmark.id }))
		assert(!outbound.workspace!.favouriteTabIDs.contains(localFileTab.id))
		assert(!outbound.browser.closedTabIDs.contains(localFileTab.id))
		assert(!outbound.browser.deletedBookmarkIDs.contains(localFileBookmark.id))
		assert(outbound.browser.closedTabsAt[localFileTab.id] == nil)
		assert(outbound.browser.deletedBookmarksAt[localFileBookmark.id] == nil)
		assert(!outbound.workspace!.spaces[0].tabIDs.contains(localFileTab.id))
		assert(!outbound.workspace!.spaces[0].pinnedFolders.contains(where: { $0.id == localWorkspace.spaces[0].pinnedFolders[0].id }))

		let applied = oldDoc.preservingLocalOnlyData(from: localOnlyDocument)
		let preservedFileTab = applied.tabs.first { $0.id == localFileTab.id }
		assert(preservedFileTab?.url?.isFileURL == true)
		assert(preservedFileTab?.restorationState == Data([1, 2, 3]))
		assert(preservedFileTab?.fileAccessBookmark == Data([4, 5, 6]))
		assert(applied.bookmarks.contains(where: { $0.id == localFileBookmark.id }))
		assert(applied.workspace!.favouriteTabIDs.contains(localFileTab.id))
		assert(applied.workspace!.spaces[0].tabIDs.contains(localFileTab.id))
		assert(applied.workspace!.spaces[0].pinnedTabIDs.contains(localFileTab.id))
		assert(applied.workspace!.spaces[0].pinnedFolders[0].tabIDs.contains(localFileTab.id))
		assert(applied.browser.selectedTabID == localFileTab.id)

		let localNavigation = OpenTab(
			id: tabID,
			pageTitle: "Local page title",
			customTitle: "Local custom title",
			url: URL(string: "https://same.example")!,
			history: [URL(string: "https://back.example")!, URL(string: "https://same.example")!],
			historyIndex: 1,
			pageZoom: 1.25,
			scrollPosition: BrowserScrollPosition(x: 5, y: 80),
			modifiedAt: now,
			restorationState: Data([7, 8])
		)
		let remoteMetadata = OpenTab(
			id: tabID,
			pageTitle: "Remote title",
			customTitle: "Remote custom title",
			url: localNavigation.url,
			history: [localNavigation.url!],
			historyIndex: 0,
			pageZoom: 1.5,
			modifiedAt: now.addingTimeInterval(1)
		)
		let updatedSameURL = localNavigation.applyingSynchronizedMetadata(from: remoteMetadata)
		assert(updatedSameURL.pageTitle == remoteMetadata.pageTitle)
		assert(updatedSameURL.customTitle == remoteMetadata.customTitle)
		assert(updatedSameURL.history == localNavigation.history)
		assert(updatedSameURL.historyIndex == localNavigation.historyIndex)
		assert(updatedSameURL.scrollPosition == localNavigation.scrollPosition)
		assert(updatedSameURL.restorationState == localNavigation.restorationState)
		assert(updatedSameURL.pageZoom == remoteMetadata.pageZoom)

		let ancientTab = OpenTab(id: UUID(), url: URL(string: "https://legacy.example")!, modifiedAt: .distantPast)
		let legacyLive = BrowserSyncDocument(tabs: [ancientTab], workspace: oldDoc.workspace!, bookmarks: [], browser: emptySnapshot, settings: [:])
		assert(legacyLive.merging(oldDoc).tabs.contains(where: { $0.id == ancientTab.id }))
		var legacyClose = BrowserSnapshot(selectedTabID: tabID)
		legacyClose.closedTabIDs.insert(ancientTab.id)
		let legacyClosed = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: legacyClose, settings: [:])
		assert(legacyLive.merging(legacyClosed).tabs.isEmpty)

		let distantRecordID = UUID()
		let ancientVisit = BrowserVisit(id: distantRecordID, url: URL(string: "https://ancient.example")!, title: "Ancient", visitedAt: .distantPast, modifiedAt: .distantPast)
		let ancientHistory = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], history: [ancientVisit], browser: emptySnapshot, settings: [:])
		assert(ancientHistory.merging(oldDoc).history.contains(where: { $0.id == distantRecordID }))

		let legacyBookmark = Bookmark(id: UUID(), name: "Old", url: URL(string: "https://bookmark.example")!, modifiedAt: .distantPast)
		let bookmarkDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [legacyBookmark], browser: emptySnapshot, settings: [:])
		assert(bookmarkDoc.merging(oldDoc).bookmarks.count == 1)
		var legacyBookmarkDelete = BrowserSnapshot(selectedTabID: tabID)
		legacyBookmarkDelete.deletedBookmarkIDs.insert(legacyBookmark.id)
		let bookmarkDeleteDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: legacyBookmarkDelete, settings: [:])
		assert(bookmarkDoc.merging(bookmarkDeleteDoc).bookmarks.isEmpty)

		var legacySpaceDelete = BrowserWorkspace(spaces: [], favouriteTabIDs: [], selectedSpaceID: space.id)
		legacySpaceDelete.deletedSpaceIDs.insert(space.id)
		let spaceDeleteDoc = BrowserSyncDocument(tabs: [], workspace: legacySpaceDelete, bookmarks: [], browser: emptySnapshot, settings: [:])
		assert(oldDoc.merging(spaceDeleteDoc).workspace?.spaces.isEmpty == true)

		let tieA = Bookmark(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "A", url: URL(string: "https://a.example")!, modifiedAt: now)
		let tieB = Bookmark(id: tieA.id, name: "B", url: URL(string: "https://b.example")!, modifiedAt: now)
		let left = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [tieA], browser: emptySnapshot, settings: [:])
		let right = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [tieB], browser: emptySnapshot, settings: [:])
		assert(left.merging(right) == right.merging(left))
		let localSetting = SyncedSetting(value: Data([1]), modifiedAt: now.addingTimeInterval(1))
		let remoteSetting = SyncedSetting(value: Data([2]), modifiedAt: now)
		let localSettingsDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: emptySnapshot, settings: ["tryHTTPSFirst": localSetting])
		let remoteSettingsDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: emptySnapshot, settings: ["tryHTTPSFirst": remoteSetting])
		assert(localSettingsDoc.merging(remoteSettingsDoc).settings["tryHTTPSFirst"] == localSetting)
		let oldSettingData = try PropertyListSerialization.data(fromPropertyList: ["value": true], format: .binary, options: 0)
		let newSettingData = try PropertyListSerialization.data(fromPropertyList: ["value": false], format: .binary, options: 0)
		let equalDateLocal = SyncedSetting(value: oldSettingData, modifiedAt: now)
		let equalDateRemote = SyncedSetting(value: newSettingData, modifiedAt: now)
		let equalLocalDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: emptySnapshot, settings: ["tryHTTPSFirst": equalDateLocal])
		let equalRemoteDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: emptySnapshot, settings: ["tryHTTPSFirst": equalDateRemote])
		let equalWinner = equalLocalDoc.merging(equalRemoteDoc).settings["tryHTTPSFirst"]!
		assert(equalWinner == equalRemoteDoc.merging(equalLocalDoc).settings["tryHTTPSFirst"]!)
		assert(equalWinner.shouldApply(over: oldSettingData, newerThan: now) == (equalWinner.value != oldSettingData))
		let resetSetting = SyncedSetting(value: nil, modifiedAt: now)
		let resetDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: emptySnapshot, settings: ["tryHTTPSFirst": resetSetting])
		let resetWinner = equalLocalDoc.merging(resetDoc).settings["tryHTTPSFirst"]!
		assert(resetWinner.shouldApply(over: oldSettingData, newerThan: now) == (resetWinner.value != oldSettingData))

		var removed = BrowserSnapshot(selectedTabID: tabID)
		removed.closedTabIDs.insert(tabID)
		removed.closedTabsAt[tabID] = now.addingTimeInterval(2)
		let deletion = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: removed, settings: [:])
		assert(oldDoc.merging(deletion).tabs.isEmpty)

		let visitID = UUID()
		let visit = BrowserVisit(id: visitID, url: URL(string: "https://history.example")!, title: "Page", visitedAt: now, modifiedAt: now)
		let historyDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], history: [visit], browser: emptySnapshot, settings: [:])
		var clear = BrowserSnapshot(selectedTabID: tabID)
		clear.historyClearedAt = now.addingTimeInterval(1)
		let clearDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: clear, settings: [:])
		assert(historyDoc.merging(clearDoc).history.isEmpty)
		var selectedLocal = BrowserSnapshot(selectedTabID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, selectedTabModifiedAt: now.addingTimeInterval(2))
		var selectedRemote = BrowserSnapshot(selectedTabID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, selectedTabModifiedAt: now)
		let selectedLocalDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: selectedLocal, settings: [:])
		let selectedRemoteDoc = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: selectedRemote, settings: [:])
		assert(selectedLocalDoc.merging(selectedRemoteDoc).browser.selectedTabID == selectedLocal.selectedTabID)
		selectedLocal.selectedTabModifiedAt = now
		selectedRemote.selectedTabModifiedAt = now
		let tiedSelectionLocal = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: selectedLocal, settings: [:])
		let tiedSelectionRemote = BrowserSyncDocument(tabs: [], workspace: oldDoc.workspace!, bookmarks: [], browser: selectedRemote, settings: [:])
		assert(tiedSelectionLocal.merging(tiedSelectionRemote) == tiedSelectionRemote.merging(tiedSelectionLocal))

		let encoded = try JSONEncoder().encode(historyDoc)
		var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
		legacy["version"] = 2
		legacy.removeValue(forKey: "history")
		let legacyData = try JSONSerialization.data(withJSONObject: legacy)
		let decoded = try JSONDecoder().decode(BrowserSyncDocument.self, from: legacyData)
		assert(decoded.version == 2 && decoded.history.isEmpty)
		var futureFormat = decoded
		futureFormat.version = 99
		assert(!futureFormat.hasSupportedVersion)

		let legacyVisit = try JSONDecoder().decode(BrowserVisit.self, from: Data("{\"id\":\"\(visitID.uuidString)\",\"url\":\"https://history.example\",\"title\":\"Page\",\"visitedAt\":0}".utf8))
		// Packet09 keeps missing update timestamps older than clear/tombstone clocks.
		assert(legacyVisit.modifiedAt == .distantPast)
		let relaunched = try JSONDecoder().decode(BrowserSyncDocument.self, from: JSONEncoder().encode(decoded))
		assert(relaunched == decoded)

		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("astra-sync-check-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let persistence = BrowserPersistence(directory: directory)
		let persisted = BrowserPersistedState(
			bookmarks: [],
			openTabs: [localFileTab],
			closedTabs: [],
			workspace: bootstrapWorkspace,
			snapshot: BrowserSnapshot(selectedTabID: localFileTab.id),
			historyVisits: [ancientVisit]
		)
		try persistence.savePersistedState(persisted)
		let stateURL = directory.appendingPathComponent("browser-state.json")
		var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
		assert(envelope["version"] as? Int == 3)
		envelope["version"] = 1
		try JSONSerialization.data(withJSONObject: envelope).write(to: stateURL)
		let migratedState = try persistence.loadPersistedState()
		assert(migratedState?.openTabs.first?.fileAccessBookmark == Data([4, 5, 6]))
		envelope["version"] = 99
		envelope["state"] = "not an envelope state"
		let unsupportedData = try JSONSerialization.data(withJSONObject: envelope)
		try unsupportedData.write(to: stateURL)
		do {
			_ = try persistence.loadPersistedState()
			assertionFailure("Future local envelope was accepted")
		} catch BrowserPersistenceError.unsupportedVersion {
			let preservedData = try Data(contentsOf: stateURL)
			assert(preservedData == unsupportedData)
		}
	}
}
