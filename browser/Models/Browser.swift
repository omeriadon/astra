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
	private(set) var closedTabIDs: Set<UUID>
	private(set) var deletedBookmarkIDs: Set<UUID>
	private(set) var persistenceErrorDescription: String?

	@ObservationIgnored
	private let persistence: BrowserPersistence?

	@ObservationIgnored
	private var persistenceTask: Task<Void, Never>?

	var selectedTab: BrowserTab? {
		tabs.first { $0.id == selectedTabID }
	}

	private var webTabs: [BrowserTab] {
		tabs.filter { $0.internalPage == nil }
	}

	private var persistedSelectedTabID: UUID {
		selectedTab?.internalPage == nil ? selectedTabID : webTabs.first?.id ?? selectedTabID
	}

	init() {
		let loadedTabs: [BrowserTab]
		let loadedSelectedTabID: UUID
		let loadedBookmarks: [Bookmark]
		let loadedClosedTabIDs: Set<UUID>
		let loadedDeletedBookmarkIDs: Set<UUID>
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
					historyIndex: $0.historyIndex,
					openPeeks: $0.peeks,
					pageZoom: $0.pageZoom,
					scrollPosition: $0.scrollPosition,
					isHibernated: $0.isHibernated,
					modifiedAt: $0.modifiedAt
				)
			}
			let tabs = restoredTabs.isEmpty ? [BrowserTab()] : restoredTabs
			loadedTabs = tabs
			loadedSelectedTabID = tabs.first(where: { $0.id == snapshot?.selectedTabID })?.id ?? tabs[0].id
			loadedBookmarks = bookmarks
			loadedClosedTabIDs = snapshot?.closedTabIDs ?? []
			loadedDeletedBookmarkIDs = snapshot?.deletedBookmarkIDs ?? []
			loadedPersistence = store
			loadedErrorDescription = nil
		} catch {
			let tab = BrowserTab()
			loadedTabs = [tab]
			loadedSelectedTabID = tab.id
			loadedBookmarks = []
			loadedClosedTabIDs = []
			loadedDeletedBookmarkIDs = []
			loadedPersistence = nil
			loadedErrorDescription = error.localizedDescription
		}

		tabs = loadedTabs
		selectedTabID = loadedSelectedTabID
		recentlyUsedTabIDs = [loadedSelectedTabID]
		bookmarks = loadedBookmarks
		closedTabIDs = loadedClosedTabIDs
		deletedBookmarkIDs = loadedDeletedBookmarkIDs
		persistence = loadedPersistence
		persistenceErrorDescription = loadedErrorDescription
		persistenceTask = nil

		for tab in loadedTabs {
			configure(tab)
		}
		if let selectedTab = loadedTabs.first(where: { $0.id == loadedSelectedTabID }),
		   selectedTab.isHibernated
		{
			selectedTab.wake()
			configure(selectedTab)
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

	func openInternalPage(_ page: BrowserInternalPage) {
		if let existing = tabs.first(where: { $0.internalPage == page }) {
			selectTab(existing.id)
			return
		}
		let tab = BrowserTab(internalPage: page)
		tabs.append(tab)
		selectTab(tab.id)
	}

	func selectTab(_ id: UUID) {
		guard let tab = tabs.first(where: { $0.id == id }) else { return }
		if tab.isHibernated {
			tab.wake()
			configure(tab)
		}
		selectedTabID = id
		recentlyUsedTabIDs.removeAll { $0 == id }
		recentlyUsedTabIDs.insert(id, at: 0)
		tab.controller?.loadFaviconIfMissing()
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
		guard let url = selectedTab?.currentURL else { return false }
		return !bookmarks.contains { $0.url == url }
	}

	func bookmarkSelectedPage() {
		guard let tab = selectedTab,
		      let url = tab.currentURL,
		      !bookmarks.contains(where: { $0.url == url })
		else { return }
		bookmarks.append(Bookmark(name: tab.title, url: url))
		schedulePersistence()
	}

	func openBookmark(_ bookmark: Bookmark) {
		guard let tab = selectedTab else { return }
		if tab.isHibernated {
			tab.wake()
			configure(tab)
		}
		tab.controller?.load(bookmark.url)
	}

	func removeBookmark(_ id: UUID) {
		bookmarks.removeAll { $0.id == id }
		deletedBookmarkIDs.insert(id)
		schedulePersistence()
	}

	func duplicateTab(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		let source = tabs[index]
		guard source.internalPage == nil else { return }
		let sourceSnapshot = source.openTab
		let tab = BrowserTab(
			pageTitle: source.pageTitle,
			customTitle: source.customTitle,
			initialURL: sourceSnapshot.url,
			history: sourceSnapshot.history,
			historyIndex: sourceSnapshot.historyIndex,
			openPeeks: sourceSnapshot.peeks,
			pageZoom: sourceSnapshot.pageZoom,
			scrollPosition: sourceSnapshot.scrollPosition
		)
		configure(tab)
		tabs.insert(tab, at: index + 1)
		selectTab(tab.id)
	}

	func closeTab(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		let wasSelected = selectedTabID == id
		let wasInternal = tabs[index].internalPage != nil
		tabs.remove(at: index)
		if !wasInternal {
			closedTabIDs.insert(id)
		}
		recentlyUsedTabIDs.removeAll { $0 == id }

		if tabs.isEmpty {
			addTab()
			return
		}

		if wasSelected {
			selectedTabID = wasInternal
				? recentlyUsedTabIDs.first(where: { recentID in tabs.contains { $0.id == recentID } }) ?? tabs[0].id
				: tabs[min(index, tabs.count - 1)].id
			recentlyUsedTabIDs.removeAll { $0 == selectedTabID }
			recentlyUsedTabIDs.insert(selectedTabID, at: 0)
		}
		schedulePersistence()
	}

	func hibernateTab(_ id: UUID) {
		guard let tab = tabs.first(where: { $0.id == id }), !tab.isHibernated else { return }
		tab.hibernate()
		schedulePersistence()
	}

	func promotePeek(in source: BrowserTab, id: UUID) {
		guard let peek = source.peeks.last, peek.id == id else { return }
		let tab = BrowserTab(
			pageTitle: peek.controller.webView.title ?? "New Tab",
			existingController: peek.controller
		)
		source.dismissPeek(id)
		configure(tab)
		tabs.append(tab)
		selectTab(tab.id)
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
		guard let controller = tab.controller else { return }
		controller.escapeRequested = { [weak tab] in
			tab?.requestPeekDismissal()
		}
		controller.newWindowRequested = { [weak self, weak controller, weak tab] url, source in
			guard let self, let controller, let tab else { return }
			if Defaults[.peekLevel] == .none {
				openNewTab(url)
				return
			}
			openPeek(
				in: tab,
				url: url,
				source: source,
				depth: 1,
				parentZoom: controller.webView.pageZoom
			)
		}
		for peek in tab.peeks {
			configure(peek, in: tab)
		}
	}

	private func openPeek(
		in tab: BrowserTab,
		url: URL,
		source: UnitPoint,
		depth: Int,
		parentZoom: Double
	) {
		guard depth <= Defaults[.peekLevel].maximumDepth,
		      depth == tab.peeks.count + 1
		else {
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
		configure(peek, in: tab)
		tab.addPeek(peek)
	}

	private func configure(_ peek: BrowserPeek, in tab: BrowserTab) {
		peek.controller.escapeRequested = { [weak tab] in
			tab?.requestPeekDismissal()
		}
		peek.controller.newWindowRequested = { [weak self, weak peek, weak tab] url, source in
			guard let self, let peek, let tab else { return }
			openPeek(
				in: tab,
				url: url,
				source: source,
				depth: peek.depth + 1,
				parentZoom: peek.controller.webView.pageZoom
			)
		}
	}

	private func openNewTab(_ url: URL) {
		let tab = addTab()
		tab.controller?.load(url)
	}

	private func removeTabs(_ ids: Set<UUID>, selecting selectedID: UUID) {
		let closedWebIDs = Set(tabs.filter { ids.contains($0.id) && $0.internalPage == nil }.map(\.id))
		tabs.removeAll { ids.contains($0.id) }
		closedTabIDs.formUnion(closedWebIDs)
		recentlyUsedTabIDs.removeAll { ids.contains($0) }
		selectedTabID = selectedID
		recentlyUsedTabIDs.removeAll { $0 == selectedID }
		recentlyUsedTabIDs.insert(selectedID, at: 0)
		schedulePersistence()
	}

	func syncDocument(settings: [String: SyncedSetting]) -> BrowserSyncDocument {
		BrowserSyncDocument(
			tabs: webTabs.map(\.openTab),
			bookmarks: bookmarks,
			browser: BrowserSnapshot(
				selectedTabID: persistedSelectedTabID,
				closedTabIDs: closedTabIDs,
				deletedBookmarkIDs: deletedBookmarkIDs
			),
			settings: settings
		)
	}

	func applySyncDocument(_ document: BrowserSyncDocument) {
		let currentTabs = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
		let changedTabs = document.tabs.map { saved -> BrowserTab in
			if let current = currentTabs[saved.id], current.openTab == saved {
				return current
			}
			let tab = BrowserTab(
				id: saved.id,
				pageTitle: saved.pageTitle,
				customTitle: saved.customTitle,
				initialURL: saved.url,
				history: saved.history,
				historyIndex: saved.historyIndex,
				openPeeks: saved.peeks,
				pageZoom: saved.pageZoom,
				scrollPosition: saved.scrollPosition,
				isHibernated: saved.isHibernated,
				modifiedAt: saved.modifiedAt
			)
			configure(tab)
			return tab
		}
		if changedTabs.isEmpty {
			let tab = BrowserTab()
			configure(tab)
			tabs = [tab] + tabs.filter { $0.internalPage != nil }
		} else {
			tabs = changedTabs + tabs.filter { $0.internalPage != nil }
		}
		closedTabIDs = document.browser.closedTabIDs
		deletedBookmarkIDs = document.browser.deletedBookmarkIDs
		bookmarks = document.bookmarks
		if !tabs.contains(where: { $0.id == selectedTabID }) {
			selectedTabID = tabs[0].id
		}
		if let selectedTab, selectedTab.isHibernated {
			selectedTab.wake()
			configure(selectedTab)
		}
		recentlyUsedTabIDs = recentlyUsedTabIDs.filter { id in
			tabs.contains { $0.id == id }
		}
		if !recentlyUsedTabIDs.contains(selectedTabID) {
			recentlyUsedTabIDs.insert(selectedTabID, at: 0)
		}
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
			try persistence.saveOpenTabs(webTabs.map(\.openTab))
			try persistence.saveBrowserSnapshot(
				BrowserSnapshot(
					selectedTabID: persistedSelectedTabID,
					closedTabIDs: closedTabIDs,
					deletedBookmarkIDs: deletedBookmarkIDs
				)
			)
			persistenceErrorDescription = nil
			BrowserSync.shared.scheduleSync()
		} catch {
			persistenceErrorDescription = error.localizedDescription
		}
	}
}
