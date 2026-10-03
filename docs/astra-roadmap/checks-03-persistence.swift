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
		let restored = try persistence.loadPersistedState()
		assert(restored?.openTabs.map(\.id) == [tab.id])
		assert(restored?.windowRecords?.first?.tabIDs == [tab.id])
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

		try persistence.saveShutdownMetadata(clean: false)
		let uncleanShutdown = try persistence.loadShutdownMetadata()
		assert(uncleanShutdown?.clean == false)
		try persistence.saveShutdownMetadata(clean: true)
		let cleanShutdown = try persistence.loadShutdownMetadata()
		assert(cleanShutdown?.clean == true)
	}
}
