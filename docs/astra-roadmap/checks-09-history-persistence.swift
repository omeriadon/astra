import Foundation

@main
struct HistoryPersistenceCheck {
	static func main() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("astra-history-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let persistence = BrowserPersistence(directory: directory)
		let tabID = UUID()
		let visit = BrowserVisit(url: URL(string: "https://example.com")!, title: "Example")
		let workspace = BrowserWorkspace.migrated(
			tabs: [OpenTab(id: tabID, url: visit.url)],
			selectedTabID: tabID,
			theme: BrowserTheme()
		)
		let initial = BrowserPersistedState(
			bookmarks: [],
			openTabs: [OpenTab(id: tabID, url: visit.url)],
			closedTabs: [],
			workspace: workspace,
			snapshot: BrowserSnapshot(selectedTabID: tabID),
			historyVisits: [visit]
		)
		try persistence.savePersistedState(initial)

		var deletedSnapshot = initial.snapshot
		deletedSnapshot.deletedVisitsAt[visit.id] = .now
		let deleted = BrowserPersistedState(
			bookmarks: initial.bookmarks,
			openTabs: initial.openTabs,
			closedTabs: initial.closedTabs,
			workspace: initial.workspace,
			snapshot: deletedSnapshot,
			historyVisits: []
		)
		try persistence.savePersistedState(deleted)
		try Data("corrupt".utf8).write(to: directory.appendingPathComponent("browser-state.json"))
		let loaded = try persistence.loadPersistedState()
		precondition(loaded?.historyVisits?.isEmpty == true)
		precondition(loaded?.snapshot.deletedVisitsAt[visit.id] != nil)

		let clearDirectory = directory.appendingPathComponent("clear", isDirectory: true)
		try FileManager.default.createDirectory(at: clearDirectory, withIntermediateDirectories: true)
		let clearPersistence = BrowserPersistence(directory: clearDirectory)
		let noHistory = BrowserPersistedState(
			bookmarks: [],
			openTabs: initial.openTabs,
			closedTabs: [],
			workspace: initial.workspace,
			snapshot: initial.snapshot,
			historyVisits: []
		)
		try clearPersistence.savePersistedState(noHistory)
		var clearSnapshot = noHistory.snapshot
		clearSnapshot.historyClearedAt = .now
		let cleared = BrowserPersistedState(
			bookmarks: noHistory.bookmarks,
			openTabs: noHistory.openTabs,
			closedTabs: noHistory.closedTabs,
			workspace: noHistory.workspace,
			snapshot: clearSnapshot,
			historyVisits: []
		)
		try clearPersistence.savePersistedState(cleared)
		try Data("corrupt".utf8).write(to: clearDirectory.appendingPathComponent("browser-state.json"))
		let clearLoaded = try clearPersistence.loadPersistedState()
		precondition(clearLoaded?.snapshot.historyClearedAt == clearSnapshot.historyClearedAt)
		print("09 history persistence checks passed")
	}
}
