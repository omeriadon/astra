import Foundation

@main
struct BrowserWindowRestorationCheck {
	static func main() throws {
		let visible = CGRect(origin: CGPoint(x: -1440, y: 0), size: CGSize(width: 1440, height: 900))
		let restored = BrowserWindowFrame(x: 900, y: -200, width: 1800, height: 1100).clamped(to: visible)
		assert(restored == BrowserWindowFrame(x: -1440, y: 0, width: 1440, height: 900))
		assert(restored.clamped(to: visible) == restored)
		assert(!BrowserWindowFrame(x: .infinity, y: 0, width: 640, height: 480).isValid)

		let selectedID = UUID()
		let fallbackID = UUID()
		let record = BrowserWindowRecord(windowID: UUID(), tabIDs: [selectedID, fallbackID], selectedTabID: selectedID)
		assert(record.restoredSelection(availableTabIDs: [selectedID, fallbackID]) == selectedID)
		assert(record.restoredSelection(availableTabIDs: [fallbackID]) == fallbackID)
		assert(record.restoredSelection(availableTabIDs: []) == nil)

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let persistence = BrowserPersistence(directory: directory)
		let tab = OpenTab()
		let space = BrowserSpace(id: BrowserSpace.firstID)
		var state = BrowserPersistedState(
			bookmarks: [],
			openTabs: [tab],
			closedTabs: [],
			workspace: BrowserWorkspace(spaces: [space], favouriteTabIDs: [], selectedSpaceID: space.id),
			snapshot: BrowserSnapshot(selectedTabID: tab.id),
			windowRecords: [BrowserWindowRecord(windowID: record.windowID, tabIDs: [tab.id], selectedTabID: tab.id, frame: restored)]
		)
		try persistence.savePersistedState(state)
		let saved = try persistence.loadPersistedState()
		assert(saved?.windowRecords?.first?.frame == restored)
		state.windowRecords = []
		try persistence.savePersistedState(state)
		let closed = try persistence.loadPersistedState()
		assert(closed?.windowRecords?.isEmpty == true)
		state.windowRecords = [BrowserWindowRecord(
			windowID: record.windowID,
			tabIDs: [tab.id],
			selectedTabID: tab.id,
			frame: BrowserWindowFrame(x: 0, y: 0, width: 100_001, height: 480)
		)]
		do {
			try persistence.savePersistedState(state)
			assertionFailure("Invalid window geometry was accepted")
		} catch BrowserPersistenceError.invalidSnapshot {}
	}
}
