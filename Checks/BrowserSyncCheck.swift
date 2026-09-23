import Foundation

// Run: swiftc browser/Models/Bookmark.swift browser/Models/BrowserScrollPosition.swift browser/Models/OpenPeek.swift browser/Models/OpenTab.swift browser/Models/BrowserSnapshot.swift browser/Models/BrowserSyncDocument.swift Checks/BrowserSyncCheck.swift -o /tmp/browser-sync-check && /tmp/browser-sync-check
@main
struct BrowserSyncCheck {
	static func main() throws {
		let closedID = UUID()
		let sharedID = UUID()
		let remoteID = UUID()
		let local = BrowserSyncDocument(
			tabs: [
				OpenTab(id: sharedID, pageTitle: "Old", modifiedAt: Date(timeIntervalSince1970: 1)),
				OpenTab(id: closedID),
			],
			bookmarks: [],
			browser: BrowserSnapshot(selectedTabID: sharedID, closedTabIDs: [closedID]),
			settings: [:]
		)
		let remote = BrowserSyncDocument(
			tabs: [
				OpenTab(id: sharedID, pageTitle: "New", modifiedAt: Date(timeIntervalSince1970: 2)),
				OpenTab(id: remoteID, scrollPosition: BrowserScrollPosition(x: 0, y: 520)),
			],
			bookmarks: [],
			browser: BrowserSnapshot(selectedTabID: remoteID),
			settings: [:]
		)
		let merged = local.merging(remote)
		assert(merged.tabs.map(\.id) == [sharedID, remoteID])
		assert(merged.tabs[0].pageTitle == "New")
		assert(merged.tabs[1].scrollPosition.y == 520)
		assert(merged.browser.closedTabIDs.contains(closedID))
		let encoded = try JSONEncoder().encode(merged)
		let decoded = try JSONDecoder().decode(BrowserSyncDocument.self, from: encoded)
		assert(decoded == merged)
		print("PASS: tab merge, close markers, scroll position, and sync coding")
	}
}
