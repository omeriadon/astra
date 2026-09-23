import Foundation

struct BrowserSyncDocument: Codable, Equatable {
	var version: Int = 1
	var tabs: [OpenTab]
	var bookmarks: [Bookmark]
	var browser: BrowserSnapshot
	var settings: [String: SyncedSetting]

	func merging(_ other: Self) -> Self {
		var merged = self
		merged.browser.closedTabIDs.formUnion(other.browser.closedTabIDs)
		merged.browser.deletedBookmarkIDs.formUnion(other.browser.deletedBookmarkIDs)

		var tabsByID = tabs.reduce(into: [UUID: OpenTab]()) { $0[$1.id] = $1 }
		for tab in other.tabs {
			if let existing = tabsByID[tab.id], existing.modifiedAt >= tab.modifiedAt {
				continue
			}
			tabsByID[tab.id] = tab
		}
		let closedTabIDs = merged.browser.closedTabIDs
		merged.tabs = (tabs.map(\.id) + other.tabs.map(\.id))
			.uniqued()
			.compactMap { tabsByID[$0] }
			.filter { !closedTabIDs.contains($0.id) }

		var bookmarksByID = bookmarks.reduce(into: [UUID: Bookmark]()) { $0[$1.id] = $1 }
		for bookmark in other.bookmarks where bookmarksByID[bookmark.id] == nil {
			bookmarksByID[bookmark.id] = bookmark
		}
		let deletedBookmarkIDs = merged.browser.deletedBookmarkIDs
		merged.bookmarks = (bookmarks.map(\.id) + other.bookmarks.map(\.id))
			.uniqued()
			.compactMap { bookmarksByID[$0] }
			.filter { !deletedBookmarkIDs.contains($0.id) }

		for (key, setting) in other.settings {
			if let existing = merged.settings[key], existing.modifiedAt >= setting.modifiedAt {
				continue
			}
			merged.settings[key] = setting
		}
		return merged
	}
}

struct SyncedSetting: Codable, Equatable {
	var value: Data?
	var modifiedAt: Date
}

private extension Sequence where Element: Hashable {
	func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
