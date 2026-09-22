import Defaults
import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class Browser {
	private(set) var tabs: [BrowserTab]
	private(set) var selectedTabID: UUID
	private(set) var recentlyUsedTabIDs: [UUID]
	private(set) var bookmarks: [Bookmark]
	private(set) var persistenceErrorDescription: String?
	private(set) var peeks: [BrowserPeek] = []

	@ObservationIgnored
	private let persistence: BrowserPersistence?

	@ObservationIgnored
	private var persistenceTask: Task<Void, Never>?

	var selectedTab: BrowserTab? {
		tabs.first { $0.id == selectedTabID }
	}

	init() {
		let loadedTabs: [BrowserTab]
		let loadedSelectedTabID: UUID
		let loadedBookmarks: [Bookmark]
		let loadedPersistence: BrowserPersistence?
		let loadedErrorDescription: String?

		do {
			let store = try BrowserPersistence()
			let savedTabs = try store.loadOpenTabs()
			let snapshot = try store.loadBrowserSnapshot()
			let bookmarks = try store.loadBookmarks()
			let restoredTabs = savedTabs.map {
				BrowserTab(
					id: $0.id,
					pageTitle: $0.pageTitle,
					customTitle: $0.customTitle,
					initialURL: $0.url,
					history: $0.history,
					historyIndex: $0.historyIndex
				)
			}
			let tabs = restoredTabs.isEmpty ? [BrowserTab()] : restoredTabs
			loadedTabs = tabs
			loadedSelectedTabID = tabs.first(where: { $0.id == snapshot?.selectedTabID })?.id ?? tabs[0].id
			loadedBookmarks = bookmarks
			loadedPersistence = store
			loadedErrorDescription = nil
		} catch {
			let tab = BrowserTab()
			loadedTabs = [tab]
			loadedSelectedTabID = tab.id
			loadedBookmarks = []
			loadedPersistence = nil
			loadedErrorDescription = error.localizedDescription
		}

		tabs = loadedTabs
		selectedTabID = loadedSelectedTabID
		recentlyUsedTabIDs = [loadedSelectedTabID]
		bookmarks = loadedBookmarks
		persistence = loadedPersistence
		persistenceErrorDescription = loadedErrorDescription
		persistenceTask = nil

		for tab in loadedTabs {
			configure(tab)
		}
	}

	@discardableResult
	func addTab() -> BrowserTab {
		let tab = BrowserTab()
		configure(tab)
		tabs.append(tab)
		recentlyUsedTabIDs.insert(tab.id, at: min(1, recentlyUsedTabIDs.count))
		selectTab(tab.id)
		return tab
	}

	func selectTab(_ id: UUID) {
		guard let tab = tabs.first(where: { $0.id == id }) else { return }
		if selectedTabID != id {
			peeks.removeAll()
		}
		selectedTabID = id
		recentlyUsedTabIDs.removeAll { $0 == id }
		recentlyUsedTabIDs.insert(id, at: 0)
		tab.controller.loadFaviconIfMissing()
		schedulePersistence()
	}

	func switchCandidates(forward: Bool, order: TabSwitchingOrder) -> [UUID] {
		guard tabs.count > 1, let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return [] }
		let ids: [UUID]
		if order == .visibleTabList {
			ids = tabs.map(\.id)
		} else {
			let validRecentIDs = recentlyUsedTabIDs.filter { id in
				tabs.contains { $0.id == id } && id != selectedTabID
			}
			ids = [selectedTabID] + validRecentIDs + tabs.map(\.id).filter {
				$0 != selectedTabID && !validRecentIDs.contains($0)
			}
		}
		let origin = ids.firstIndex(of: selectedTabID) ?? selectedIndex
		return (1 ... ids.count).map { offset in
			let direction = forward ? offset : ids.count - offset
			return ids[(origin + direction) % ids.count]
		}
	}

	func commitTabSwitch(to id: UUID) {
		selectTab(id)
	}

	var canBookmarkSelectedPage: Bool {
		guard let url = selectedTab?.controller.url else { return false }
		return !bookmarks.contains { $0.url == url }
	}

	func bookmarkSelectedPage() {
		guard let tab = selectedTab,
		      let url = tab.controller.url,
		      !bookmarks.contains(where: { $0.url == url })
		else { return }
		bookmarks.append(Bookmark(name: tab.title, url: url))
		schedulePersistence()
	}

	func openBookmark(_ bookmark: Bookmark) {
		selectedTab?.controller.load(bookmark.url)
	}

	func dismissPeek(_ id: UUID) {
		guard let index = peeks.firstIndex(where: { $0.id == id }) else { return }
		peeks.removeSubrange(index...)
	}

	func removeBookmark(_ id: UUID) {
		bookmarks.removeAll { $0.id == id }
		schedulePersistence()
	}

	func duplicateTab(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		let source = tabs[index]
		let tab = BrowserTab(
			pageTitle: source.pageTitle,
			customTitle: source.customTitle,
			initialURL: source.controller.url,
			history: source.controller.history,
			historyIndex: source.controller.historyIndex
		)
		configure(tab)
		tabs.insert(tab, at: index + 1)
		selectTab(tab.id)
	}

	func closeTab(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		let wasSelected = selectedTabID == id
		tabs.remove(at: index)
		recentlyUsedTabIDs.removeAll { $0 == id }

		if tabs.isEmpty {
			addTab()
			return
		}

		if wasSelected {
			selectedTabID = tabs[min(index, tabs.count - 1)].id
			recentlyUsedTabIDs.removeAll { $0 == selectedTabID }
			recentlyUsedTabIDs.insert(selectedTabID, at: 0)
		}
		schedulePersistence()
	}

	func closeTabsAbove(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }), index > 0 else { return }
		removeTabs(Set(tabs[..<index].map(\.id)), selecting: id)
	}

	func closeTabsBelow(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }), index < tabs.count - 1 else { return }
		removeTabs(Set(tabs[(index + 1)...].map(\.id)), selecting: id)
	}

	func closeOtherTabs(_ id: UUID) {
		guard tabs.contains(where: { $0.id == id }), tabs.count > 1 else { return }
		removeTabs(Set(tabs.lazy.map(\.id).filter { $0 != id }), selecting: id)
	}

	func flushPersistence() {
		persistenceTask?.cancel()
		persistenceTask = nil
		persist()
	}

	private func attachPersistence(to tab: BrowserTab) {
		tab.didChange = { [weak self] in
			self?.schedulePersistence()
		}
	}

	private func configure(_ tab: BrowserTab) {
		attachPersistence(to: tab)
		let controller = tab.controller
		controller.newWindowRequested = { [weak self, weak controller] url, source in
			guard let self, let controller else { return }
			if Defaults[.peekLevel] == .none {
				openNewTab(url)
				return
			}
			openPeek(
				url: url,
				source: source,
				depth: 1,
				parentZoom: controller.webView.pageZoom
			)
		}
	}

	private func openPeek(
		url: URL,
		source: UnitPoint,
		depth: Int,
		parentZoom: Double
	) {
		guard depth <= Defaults[.peekLevel].maximumDepth else {
			openNewTab(url)
			return
		}

		let peek = BrowserPeek(
			url: url,
			depth: depth,
			source: source,
			parentZoom: parentZoom,
			zoomsOut: Defaults[.zoomOutInPeeks]
		)
		peek.controller.newWindowRequested = { [weak self, weak peek] url, source in
			guard let self, let peek else { return }
			openPeek(
				url: url,
				source: source,
				depth: peek.depth + 1,
				parentZoom: peek.controller.webView.pageZoom
			)
		}
		peeks.append(peek)
	}

	private func openNewTab(_ url: URL) {
		let tab = addTab()
		tab.controller.load(url)
	}

	private func removeTabs(_ ids: Set<UUID>, selecting selectedID: UUID) {
		tabs.removeAll { ids.contains($0.id) }
		recentlyUsedTabIDs.removeAll { ids.contains($0) }
		selectedTabID = selectedID
		recentlyUsedTabIDs.removeAll { $0 == selectedID }
		recentlyUsedTabIDs.insert(selectedID, at: 0)
		schedulePersistence()
	}

	private func schedulePersistence() {
		guard persistence != nil else { return }
		persistenceTask?.cancel()
		persistenceTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(300))
			guard !Task.isCancelled, let self else { return }
			persist()
		}
	}

	private func persist() {
		guard let persistence else { return }
		do {
			try persistence.saveBookmarks(bookmarks)
			try persistence.saveOpenTabs(tabs.map(\.openTab))
			try persistence.saveBrowserSnapshot(BrowserSnapshot(selectedTabID: selectedTabID))
			persistenceErrorDescription = nil
		} catch {
			persistenceErrorDescription = error.localizedDescription
		}
	}
}
