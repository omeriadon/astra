import Foundation

struct WatchLibrary: Codable, Equatable, Sendable {
	var spaces: [WatchSpace] = []
	var bookmarks: [WatchLink] = []

	init(document: BrowserSyncDocument?) {
		guard let document else { return }
		let links = document.tabs.reduce(into: [UUID: WatchLink]()) { result, tab in
			guard !document.browser.closedTabIDs.contains(tab.id),
			      tab.internalPage == nil, let url = tab.url else { return }
			let link = WatchLink(id: tab.id, title: tab.customTitle ?? tab.pageTitle, url: url)
			guard link.canOpen else { return }
			result[tab.id] = link
		}
		let workspace = document.workspace ?? BrowserWorkspace.migrated(
			tabs: document.tabs,
			selectedTabID: document.browser.selectedTabID,
			theme: BrowserTheme()
		)
		let favourites = workspace.favouriteTabIDs.compactMap { links[$0] }
		spaces = workspace.spaces.filter { !workspace.deletedSpaceIDs.contains($0.id) }.map { space in
			let pinnedIDs = Set(space.pinnedTabIDs)
			return WatchSpace(
				id: space.id,
				name: space.name,
				symbol: space.symbol,
				theme: space.theme,
				pinned: space.pinnedTabIDs.compactMap { links[$0] },
				favourites: favourites,
				today: space.tabIDs.filter { !pinnedIDs.contains($0) }.compactMap { links[$0] }
			)
		}
		bookmarks = document.bookmarks.filter { !document.browser.deletedBookmarkIDs.contains($0.id) }.map {
			WatchLink(id: $0.id, title: $0.name, url: $0.url)
		}.filter(\.canOpen)
	}
}
