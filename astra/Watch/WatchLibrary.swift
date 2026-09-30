import Foundation

struct WatchLibrary: Codable, Equatable, Sendable {
	var updatedAt: Date = .distantPast
	var spaces: [WatchSpace] = []
	var bookmarks: [WatchLink] = []
}

#if os(iOS)
	extension WatchLibrary {
		init(browser: Browser) {
			let links = browser.tabs.reduce(into: [UUID: WatchLink]()) { result, tab in
				let saved = tab.openTab
				guard saved.internalPage == nil, let url = saved.url else { return }
				let link = WatchLink(id: saved.id, title: saved.customTitle ?? saved.pageTitle, url: url)
				guard link.canOpen else { return }
				result[saved.id] = link
			}
			let favourites = browser.workspace.favouriteTabIDs.compactMap { links[$0] }
			spaces = browser.workspace.spaces.map { space in
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
			bookmarks = browser.bookmarks.map {
				WatchLink(id: $0.id, title: $0.name, url: $0.url)
			}.filter(\.canOpen)
		}
	}
#endif
