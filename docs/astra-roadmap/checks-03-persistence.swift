import Dispatch
import Foundation

@main
struct BrowserPersistenceCheck {
	static func main() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let persistence = BrowserPersistence(directory: directory)
		let tab = OpenTab(url: URL(string: "https://example.com")!)
		let space = BrowserSpace(id: BrowserSpace.firstID)
		let state = BrowserPersistedState(
			bookmarks: [],
			openTabs: [tab],
			closedTabs: [],
			workspace: BrowserWorkspace(spaces: [space], favouriteTabIDs: [], selectedSpaceID: space.id),
			snapshot: BrowserSnapshot(selectedTabID: tab.id),
			windowRecords: [BrowserWindowRecord(windowID: UUID(), tabIDs: [tab.id], selectedTabID: tab.id)]
		)
		try persistence.savePersistedState(state)
		// Explicit capture revisions protect against out-of-order task completion.
		// Local persistence has no networking/power dependency.
		let orderedDirectory = directory.appendingPathComponent("revision-order", isDirectory: true)
		try FileManager.default.createDirectory(at: orderedDirectory, withIntermediateDirectories: true)
		let orderedPersistence = BrowserPersistence(directory: orderedDirectory)
		var latest = state
		latest.bookmarks = [Bookmark(name: "Newest", url: URL(string: "https://newest.example")!)]
		try orderedPersistence.savePersistedState(latest, revision: 30)
		try orderedPersistence.savePersistedState(state, revision: 10)
		let orderedRestored = try orderedPersistence.loadPersistedState()
		precondition(orderedRestored?.bookmarks.first?.name == "Newest")
		// Equal revisions are idempotent and cannot replace the committed state.
		try orderedPersistence.savePersistedState(state, revision: 30)
		let equalRestored = try orderedPersistence.loadPersistedState()
		precondition(equalRestored?.bookmarks.first?.name == "Newest")
		var burst = latest
		for revision in 31 ... 60 {
			burst.bookmarks[0].name = "Revision \(revision)"
			try orderedPersistence.savePersistedState(burst, revision: UInt64(revision))
		}
		let burstRestored = try orderedPersistence.loadPersistedState()
		precondition(burstRestored?.bookmarks.first?.name == "Revision 60")
		// Race full-state commits from separate instances, as multiple windows do.
		// The maximum capture revision must win regardless of lock arrival order.
		let concurrentDirectory = directory.appendingPathComponent("concurrent-revisions", isDirectory: true)
		try FileManager.default.createDirectory(at: concurrentDirectory, withIntermediateDirectories: true)
		let concurrentBase = latest
		DispatchQueue.concurrentPerform(iterations: 64) { index in
			let writer = BrowserPersistence(directory: concurrentDirectory)
			var snapshot = concurrentBase
			snapshot.bookmarks[0].name = "Concurrent \(index)"
			do {
				try writer.savePersistedState(snapshot, revision: UInt64(index))
			} catch {
				preconditionFailure("Concurrent checkpoint failed: \(error)")
			}
		}
		let concurrentReader = BrowserPersistence(directory: concurrentDirectory)
		let concurrentRestored = try concurrentReader.loadPersistedState()
		precondition(concurrentRestored?.bookmarks.first?.name == "Concurrent 63")
		// A failed transaction must release the mutex and preserve the last
		// committed revision, allowing a valid retry with that same revision.
		var invalidConcurrent = concurrentBase
		invalidConcurrent.windowRecords = [BrowserWindowRecord(
			windowID: UUID(), tabIDs: [], selectedTabID: tab.id
		)]
		do {
			try concurrentReader.savePersistedState(invalidConcurrent, revision: 64)
			preconditionFailure("Invalid window checkpoint accepted")
		} catch BrowserPersistenceError.invalidSnapshot {}
		try concurrentReader.savePersistedState(concurrentBase, revision: 64)
		let retriedConcurrent = try concurrentReader.loadPersistedState()
		precondition(retriedConcurrent?.bookmarks.first?.name == "Newest")
		let windowSidecar = directory.appendingPathComponent("browser-windows.json")
		precondition(FileManager.default.fileExists(atPath: windowSidecar.path))
		let indexedRecords = try persistence.loadWindowRecords()
		precondition(indexedRecords == (state.windowRecords ?? []))
		// Missing or unreadable sidecars must fall back to the full envelope.
		try Data("invalid-sidecar".utf8).write(to: windowSidecar)
		let fallbackRecords = try persistence.loadWindowRecords()
		precondition(fallbackRecords == (state.windowRecords ?? []))
		let restored = try persistence.loadPersistedState()
		assert(restored?.openTabs.map(\.id) == [tab.id])
		assert(restored?.windowRecords?.first?.tabIDs == [tab.id])
		// URL-less New Tabs must survive a full atomic disk round-trip with
		// their IDs, order, selected tab and workspace membership intact.
		let emptyTab = OpenTab()
		let anotherEmptyTab = OpenTab()
		let newTabDirectory = directory.appendingPathComponent("durable-new-tabs", isDirectory: true)
		try FileManager.default.createDirectory(at: newTabDirectory, withIntermediateDirectories: true)
		let newTabPersistence = BrowserPersistence(directory: newTabDirectory)
		let newTabIDs = [tab.id, emptyTab.id, anotherEmptyTab.id]
		let newTabWindowID = UUID()
		let newTabState = BrowserPersistedState(
			bookmarks: [],
			openTabs: [tab, emptyTab, anotherEmptyTab],
			closedTabs: [],
			workspace: BrowserWorkspace(
				spaces: [BrowserSpace(
					id: BrowserSpace.firstID,
					tabIDs: newTabIDs,
					selectedTabID: emptyTab.id
				)],
				favouriteTabIDs: [],
				selectedSpaceID: BrowserSpace.firstID
			),
			snapshot: BrowserSnapshot(selectedTabID: emptyTab.id),
			windowRecords: [BrowserWindowRecord(
				windowID: newTabWindowID,
				tabIDs: newTabIDs,
				selectedTabID: emptyTab.id
			)]
		)
		try newTabPersistence.savePersistedState(newTabState)
		let restoredNewTabs = try newTabPersistence.loadPersistedState()
		precondition(restoredNewTabs?.openTabs.map(\.id) == newTabIDs)
		precondition(restoredNewTabs?.openTabs[1].url == nil)
		precondition(restoredNewTabs?.openTabs[2].url == nil)
		precondition(restoredNewTabs?.snapshot.selectedTabID == emptyTab.id)
		precondition(restoredNewTabs?.workspace.spaces[0].tabIDs == newTabIDs)
		precondition(restoredNewTabs?.windowRecords?[0].selectedTabID == emptyTab.id)
		// Closing a blank tab must commit its removal rather than resurrect it.
		var afterClosingNewTab = newTabState
		afterClosingNewTab.openTabs.removeAll { $0.id == emptyTab.id }
		afterClosingNewTab.workspace.spaces[0].tabIDs.removeAll { $0 == emptyTab.id }
		afterClosingNewTab.workspace.spaces[0].selectedTabID = anotherEmptyTab.id
		afterClosingNewTab.snapshot.selectedTabID = anotherEmptyTab.id
		afterClosingNewTab.windowRecords = [BrowserWindowRecord(
			windowID: newTabWindowID,
			tabIDs: [tab.id, anotherEmptyTab.id],
			selectedTabID: anotherEmptyTab.id
		)]
		try newTabPersistence.savePersistedState(afterClosingNewTab)
		let savedAfterClose = try newTabPersistence.loadPersistedState()
		precondition(savedAfterClose?.openTabs.map(\.id) == [tab.id, anotherEmptyTab.id])

		for value in ["https://example.com", "http://localhost:8080/path"] {
			assert(BrowserHomepage.validURL(value) != nil)
		}
		for value in [
			"https://user:secret@example.com",
			"https://exa%20mple.com",
			"https://example.com:0",
			"https://example.com:65536",
			"https://example.com:abc",
		] {
			assert(BrowserHomepage.validURL(value) == nil)
		}
		let currentURL = directory.appendingPathComponent("browser-state.json")
		let firstGeneration = try Data(contentsOf: currentURL)

		var nextState = state
		nextState.openTabs = [OpenTab(url: URL(string: "https://second.example")!)]
		try persistence.savePersistedState(nextState)
		try Data("corrupt".utf8).write(to: currentURL)
		let backupState = try persistence.loadPersistedState()
		assert(backupState?.openTabs.first?.id == tab.id)

		var legacy = try JSONSerialization.jsonObject(with: firstGeneration) as! [String: Any]
		legacy["version"] = 2
		if var legacyState = legacy["state"] as? [String: Any] {
			legacyState.removeValue(forKey: "windowRecords")
			legacy["state"] = legacyState
		}
		try JSONSerialization.data(withJSONObject: legacy).write(to: currentURL)
		let legacyState = try persistence.loadPersistedState()
		assert(legacyState?.openTabs.first?.id == tab.id)
		var duplicateRecordState = state
		let duplicateRecord = BrowserWindowRecord(
			windowID: state.windowRecords![0].windowID,
			tabIDs: [tab.id],
			selectedTabID: tab.id
		)
		duplicateRecordState.windowRecords = [state.windowRecords![0], duplicateRecord]
		do {
			try persistence.savePersistedState(duplicateRecordState)
			assertionFailure("Duplicate window records were accepted")
		} catch BrowserPersistenceError.invalidSnapshot {}
		var futureRecordState = state
		var futureRecord = state.windowRecords![0]
		futureRecord.version = 2
		futureRecordState.windowRecords = [futureRecord]
		do {
			try persistence.savePersistedState(futureRecordState)
			assertionFailure("Future window record was accepted")
		} catch BrowserPersistenceError.unsupportedVersion {}

		let future = Data(#"{"version":99,"state":{"unknown":true}}"#.utf8)
		try future.write(to: currentURL)
		do {
			try persistence.savePersistedState(state)
			assertionFailure("Future snapshot was overwritten")
		} catch BrowserPersistenceError.unsupportedVersion {}
		let preservedFuture = try Data(contentsOf: currentURL)
		assert(preservedFuture == future)

		// A tab click in window B must survive a subsequent unrelated full
		// snapshot from window A. Full-session writes consume the checkpoint
		// under the same lock, not simply delete it.
		let multiWindowDirectory = directory.appendingPathComponent("multiwindow", isDirectory: true)
		try FileManager.default.createDirectory(at: multiWindowDirectory, withIntermediateDirectories: true)
		let multiPersistence = BrowserPersistence(directory: multiWindowDirectory)
		let secondTab = OpenTab(url: URL(string: "https://second.example")!)
		let otherSpace = BrowserSpace(
			id: BrowserSpace.firstID,
			tabIDs: [tab.id, secondTab.id],
			selectedTabID: tab.id
		)
		let firstWindow = UUID()
		let secondWindow = UUID()
		let windowTime = Date.now
		let multiState = BrowserPersistedState(
			bookmarks: [],
			openTabs: [tab, secondTab],
			closedTabs: [],
			workspace: BrowserWorkspace(
				spaces: [otherSpace], favouriteTabIDs: [],
				selectedSpaceID: otherSpace.id
			),
			snapshot: BrowserSnapshot(
				selectedTabID: tab.id,
				selectedTabModifiedAt: .distantPast
			),
			windowRecords: [
				BrowserWindowRecord(
					windowID: firstWindow, tabIDs: [tab.id, secondTab.id],
					selectedTabID: tab.id, selectionModifiedAt: .distantPast
				),
				BrowserWindowRecord(
					windowID: secondWindow, tabIDs: [tab.id, secondTab.id],
					selectedTabID: tab.id, selectionModifiedAt: .distantPast
				),
			]
		)
		try multiPersistence.savePersistedState(multiState)
		try multiPersistence.saveSelectionUpdate(BrowserSelectionUpdate(
			windowID: secondWindow, selectedTabID: secondTab.id,
			selectedTabModifiedAt: windowTime, selectedSpaceID: otherSpace.id
		))
		try multiPersistence.savePersistedState(multiState)
		let merged = try multiPersistence.loadPersistedState()
		precondition(merged?.windowRecords?.first(where: { $0.windowID == secondWindow })?.selectedTabID == secondTab.id)
		precondition(merged?.windowRecords?.first(where: { $0.windowID == secondWindow })?.selectionModifiedAt == windowTime)
		precondition(merged?.snapshot.selectedTabID == secondTab.id)
		precondition(!FileManager.default.fileExists(
			atPath: multiWindowDirectory.appendingPathComponent("browser-selection.json").path
		))

		// Multiple full saves exercise the warm primary/backup cache. Removing
		// a history visit must invalidate the old backup: corruption recovery
		// must never resurrect a deleted browsing record.
		let privacyDirectory = directory.appendingPathComponent("warm-privacy", isDirectory: true)
		try FileManager.default.createDirectory(at: privacyDirectory, withIntermediateDirectories: true)
		let privacyPersistence = BrowserPersistence(directory: privacyDirectory)
		let privateVisit = BrowserVisit(url: URL(string: "https://sensitive.example/session")!, title: "Sensitive")
		var withPrivateHistory = state
		withPrivateHistory.historyVisits = [privateVisit]
		try privacyPersistence.savePersistedState(withPrivateHistory)
		try privacyPersistence.savePersistedState(withPrivateHistory)
		var withoutPrivateHistory = withPrivateHistory
		withoutPrivateHistory.historyVisits = []
		withoutPrivateHistory.snapshot.deletedVisitsAt[privateVisit.id] = .now
		try privacyPersistence.savePersistedState(withoutPrivateHistory)
		let privacyPrimary = privacyDirectory.appendingPathComponent("browser-state.json")
		try Data("corrupt".utf8).write(to: privacyPrimary)
		let privacyRecovered = try privacyPersistence.loadPersistedState()
		precondition(privacyRecovered?.historyVisits?.isEmpty == true)
		precondition(privacyRecovered?.snapshot.deletedVisitsAt[privateVisit.id] != nil)

		// Atomic replacement of a valid cached checkpoint by a future schema
		// must be detected, even if its JSON happens to have similar length.
		let futureVersion = Data(#"{"version":99,"state":{"unknown":true}}"#.utf8)
		try futureVersion.write(to: privacyPrimary, options: .atomic)
		do {
			try privacyPersistence.savePersistedState(withoutPrivateHistory)
			preconditionFailure("Warm cache allowed newer schema to be overwritten")
		} catch BrowserPersistenceError.unsupportedVersion {}
		let preservedFutureVersion = try Data(contentsOf: privacyPrimary)
		precondition(preservedFutureVersion == futureVersion)

		// Scroll journal durability, stale snapshot merge, and navigation
		// invalidation without rebuilding the full session for every scroll.
		let scrollDirectory = directory.appendingPathComponent("scroll-journal", isDirectory: true)
		try FileManager.default.createDirectory(at: scrollDirectory, withIntermediateDirectories: true)
		let scrollPersistence = BrowserPersistence(directory: scrollDirectory)
		try scrollPersistence.savePersistedState(state)
		let scrollPosition = BrowserScrollPosition(x: 18, y: 450)
		let update = BrowserScrollUpdate(
			tabID: tab.id, url: tab.url, historyIndex: tab.historyIndex,
			position: scrollPosition,
			modifiedAt: max(.now, tab.modifiedAt.addingTimeInterval(1))
		)
		try scrollPersistence.saveScrollUpdates([update])
		let scrollRestored = try scrollPersistence.loadPersistedState()
		precondition(scrollRestored?.openTabs[0].scrollPosition == scrollPosition)
		// Full saves from another window must absorb a newer scroll journal
		// even when that window captured its full snapshot earlier.
		try scrollPersistence.savePersistedState(state)
		let mergedScroll = try scrollPersistence.loadPersistedState()
		precondition(mergedScroll?.openTabs[0].scrollPosition == scrollPosition)
		precondition(!FileManager.default.fileExists(
			atPath: scrollDirectory.appendingPathComponent("browser-scroll.json").path
		))
		// URL and back/forward changes cannot replay the old scroll coordinate.
		var navigated = state
		navigated.openTabs[0].url = URL(string: "https://navigated.example")!
		try scrollPersistence.saveScrollUpdates([update])
		try scrollPersistence.savePersistedState(navigated)
		let navigatedResult = try scrollPersistence.loadPersistedState()
		precondition(navigatedResult?.openTabs[0].url == navigated.openTabs[0].url)
		precondition(navigatedResult?.openTabs[0].scrollPosition == .zero)
		// Future journal versions are never silently overwritten.
		let futureScroll = Data(#"{"version":99,"baseSignature":{},"updates":{}}"#.utf8)
		try futureScroll.write(to: scrollDirectory.appendingPathComponent("browser-scroll.json"), options: .atomic)
		do {
			try scrollPersistence.saveScrollUpdates([update])
			preconditionFailure("Future scroll journal was overwritten")
		} catch BrowserPersistenceError.unsupportedVersion {}

		try persistence.saveShutdownMetadata(clean: false)
		let uncleanShutdown = try persistence.loadShutdownMetadata()
		assert(uncleanShutdown?.clean == false)
		try persistence.saveShutdownMetadata(clean: true)
		let cleanShutdown = try persistence.loadShutdownMetadata()
		assert(cleanShutdown?.clean == true)
		// Closed payload compaction preserves complete navigation and permissions,
		// while the resident/persisted index carries only display metadata.
		let closedDirectory = directory.appendingPathComponent("closed-payloads", isDirectory: true)
		try FileManager.default.createDirectory(at: closedDirectory, withIntermediateDirectories: true)
		let closedStore = BrowserPersistence(directory: closedDirectory)
		var closed = tab
		closed.history = [URL(string: "https://one.example")!, URL(string: "https://two.example")!]
		closed.historyIndex = 1
		closed.restorationState = Data(repeating: 42, count: 1024 * 1024)
		closed.fileAccessBookmark = Data([1, 2, 3])
		let compacted = try closedStore.compactClosedTabs([closed])
		assert(compacted[0].closedArchiveID != nil && compacted[0].history.isEmpty && compacted[0].restorationState == nil)
		let restoredClosed = try closedStore.loadClosedTab(compacted[0])
		assert(restoredClosed == closed)
		var closedState = state
		closedState.closedTabs = compacted
		closedState.openTabs = []
		try closedStore.savePersistedState(closedState)
		let lazyClosed = try closedStore.loadPersistedState()
		assert(lazyClosed?.closedTabs.first?.closedArchiveID == compacted[0].closedArchiveID)
		closedState.closedTabs = []
		try closedStore.savePersistedState(closedState)
		let payloads = try FileManager.default.contentsOfDirectory(at: closedDirectory.appendingPathComponent("closed-tab-payloads"), includingPropertiesForKeys: nil)
		assert(payloads.isEmpty, "Deleted closed-tab payload survived a privacy-safe checkpoint")
	}
}
