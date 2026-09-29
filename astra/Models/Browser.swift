import Defaults
import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class Browser {
	let windowID = UUID()
	private(set) var tabs: [BrowserTab]
	private(set) var selectedTabID: UUID
	private(set) var workspace: BrowserWorkspace
	private(set) var spaceSwitchDirection = 1
	private(set) var recentlyUsedTabIDs: [UUID]
	private(set) var bookmarks: [Bookmark]
	private(set) var closedHistoryTabs: [OpenTab]
	private(set) var closedTabIDs: Set<UUID>
	private(set) var deletedBookmarkIDs: Set<UUID>
	private(set) var persistenceErrorDescription: String?

	var isAboutToQuit: Bool = false
	var addressFocusRequest = 0
	var sidebarShown: Bool {
		get {
			access(keyPath: \.sidebarShown)
			return Defaults[.sidebarShown]
		}
		set {
			withMutation(keyPath: \.sidebarShown) {
				Defaults[.sidebarShown] = newValue
			}
		}
	}

	@ObservationIgnored
	private let persistence: BrowserPersistence?

	@ObservationIgnored
	private var persistenceTask: Task<Void, Never>?

	var selectedTab: BrowserTab? {
		tabs.first { $0.id == selectedTabID }
	}

	var selectedSpace: BrowserSpace {
		workspace.spaces.first { $0.id == workspace.selectedSpaceID } ?? workspace.spaces[0]
	}

	var theme: BrowserTheme {
		selectedSpace.theme
	}

	var favouriteTabs: [BrowserTab] {
		workspace.favouriteTabIDs.compactMap { id in tabs.first { $0.id == id } }
	}

	var pinnedTabs: [BrowserTab] {
		selectedSpace.pinnedTabIDs.compactMap { id in tabs.first { $0.id == id } }
	}

	var normalTabs: [BrowserTab] {
		selectedSpace.tabIDs
			.filter { !selectedSpace.pinnedTabIDs.contains($0) }
			.compactMap { id in tabs.first { $0.id == id } }
	}

	var visibleTabs: [BrowserTab] {
		favouriteTabs + pinnedTabs + normalTabs
	}

	func createSpace() {
		let space = BrowserSpace()
		spaceSwitchDirection = 1
		workspace.spaces.append(space)
		workspace.selectedSpaceID = space.id
		openInternalPage(.themeEditor)
		schedulePersistence()
	}

	func deleteSpace(_ id: UUID) {
		guard workspace.spaces.count > 1,
		      let removed = workspace.spaces.first(where: { $0.id == id }),
		      let destinationIndex = workspace.spaces.firstIndex(where: { $0.id != id })
		else { return }
		let destinationID = workspace.spaces[destinationIndex].id
		let destinationTabIDs = Set(workspace.spaces[destinationIndex].tabIDs)
		let destinationPinnedIDs = Set(workspace.spaces[destinationIndex].pinnedTabIDs)
		workspace.spaces[destinationIndex].tabIDs.append(contentsOf: removed.tabIDs.filter { !destinationTabIDs.contains($0) })
		workspace.spaces[destinationIndex].pinnedTabIDs.append(contentsOf: removed.pinnedTabIDs.filter { !destinationPinnedIDs.contains($0) })
		if removed.tabIDs.contains(selectedTabID) {
			workspace.spaces[destinationIndex].selectedTabID = selectedTabID
		}
		workspace.spaces[destinationIndex].modifiedAt = .now
		workspace.spaces.removeAll { $0.id == id }
		workspace.deletedSpaceIDs.insert(id)
		if workspace.selectedSpaceID == id {
			selectSpace(destinationID)
		}
		schedulePersistence()
	}

	func selectSpace(_ id: UUID) {
		guard let nextIndex = workspace.spaces.firstIndex(where: { $0.id == id }) else { return }
		if let currentIndex = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) {
			spaceSwitchDirection = nextIndex >= currentIndex ? 1 : -1
		}
		workspace.selectedSpaceID = id
		let space = selectedSpace
		if let tabID = space.selectedTabID,
		   space.tabIDs.contains(tabID) || workspace.favouriteTabIDs.contains(tabID)
		{
			selectTab(tabID)
		} else if let tabID = space.tabIDs.first ?? workspace.favouriteTabIDs.first {
			selectTab(tabID)
		} else {
			addTab()
		}
		schedulePersistence()
	}

	func renameSelectedSpace(_ name: String) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) else { return }
		workspace.spaces[index].name = name
		workspace.spaces[index].modifiedAt = .now
		schedulePersistence()
	}

	func setSelectedSpaceSymbol(_ symbol: String) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) else { return }
		workspace.spaces[index].symbol = symbol
		workspace.spaces[index].modifiedAt = .now
		schedulePersistence()
	}

	func setSelectedSpaceTheme(_ theme: BrowserTheme) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) else { return }
		workspace.spaces[index].theme = theme
		workspace.spaces[index].modifiedAt = .now
		schedulePersistence()
	}

	enum TabArea {
		case favourite
		case pinned
		case normal
	}

	func moveTab(_ id: UUID, to area: TabArea, in spaceID: UUID? = nil, before targetID: UUID? = nil) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		let wasFavourite = workspace.favouriteTabIDs.contains(id)
		workspace.favouriteTabIDs.removeAll { $0 == id }
		for index in workspace.spaces.indices {
			if workspace.spaces[index].tabIDs.contains(id) {
				workspace.spaces[index].modifiedAt = .now
			}
			workspace.spaces[index].tabIDs.removeAll { $0 == id }
			workspace.spaces[index].pinnedTabIDs.removeAll { $0 == id }
		}
		if area == .favourite {
			let index = targetID.flatMap { workspace.favouriteTabIDs.firstIndex(of: $0) } ?? workspace.favouriteTabIDs.endIndex
			workspace.favouriteTabIDs.insert(id, at: index)
			workspace.favouritesModifiedAt = .now
		} else if let index = workspace.spaces.firstIndex(where: { $0.id == (spaceID ?? workspace.selectedSpaceID) }) {
			let insertion = targetID.flatMap { workspace.spaces[index].tabIDs.firstIndex(of: $0) } ?? workspace.spaces[index].tabIDs.endIndex
			workspace.spaces[index].tabIDs.insert(id, at: insertion)
			if area == .pinned {
				let pinnedInsertion = targetID.flatMap { workspace.spaces[index].pinnedTabIDs.firstIndex(of: $0) }
					?? workspace.spaces[index].pinnedTabIDs.endIndex
				workspace.spaces[index].pinnedTabIDs.insert(id, at: pinnedInsertion)
			}
			workspace.spaces[index].modifiedAt = .now
			if wasFavourite {
				workspace.favouritesModifiedAt = .now
			}
		} else {
			return
		}
		if selectedTabID == id,
		   area != .favourite,
		   let spaceID,
		   workspace.selectedSpaceID != spaceID
		{
			workspace.selectedSpaceID = spaceID
			selectTab(id)
		}
		schedulePersistence()
	}

	private var webTabs: [BrowserTab] {
		tabs.filter { $0.internalPage == nil }
	}

	private var persistedSelectedTabID: UUID {
		selectedTab?.internalPage == nil ? selectedTabID : webTabs.first?.id ?? selectedTabID
	}

	init() {
		BrowserWindowRegistry.shared.activeBrowser?.flushPersistence()
		let loadedTabs: [BrowserTab]
		let loadedSelectedTabID: UUID
		let loadedWorkspace: BrowserWorkspace
		let loadedBookmarks: [Bookmark]
		let loadedClosedHistoryTabs: [OpenTab]
		let loadedClosedTabIDs: Set<UUID>
		let loadedDeletedBookmarkIDs: Set<UUID>
		let loadedPersistence: BrowserPersistence?
		let loadedErrorDescription: String?

		do {
			let store = try BrowserPersistence()
			let savedTabs = try store.loadOpenTabs()
			let snapshot = try store.loadBrowserSnapshot()
			let savedWorkspace = try? store.loadWorkspace()
			let bookmarks = try store.loadBookmarks()
			let closedHistoryTabs = try store.loadClosedTabs()
			let restoredTabs = savedTabs.compactMap { saved -> BrowserTab? in
				let internalPage = saved.internalPage.flatMap(BrowserInternalPage.init(persistenceID:))
				guard saved.internalPage == nil || internalPage != nil else { return nil }
				return BrowserTab(
					id: saved.id,
					internalPage: internalPage,
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
			}
			let tabs = restoredTabs.isEmpty ? [BrowserTab()] : restoredTabs
			loadedTabs = tabs
			loadedSelectedTabID = tabs.first(where: { $0.id == snapshot?.selectedTabID })?.id ?? tabs[0].id
			loadedWorkspace = savedWorkspace ?? BrowserWorkspace.migrated(
				tabs: savedTabs,
				selectedTabID: loadedSelectedTabID,
				theme: Defaults[.browserTheme]
			)
			loadedBookmarks = bookmarks
			loadedClosedHistoryTabs = closedHistoryTabs
			loadedClosedTabIDs = snapshot?.closedTabIDs ?? []
			loadedDeletedBookmarkIDs = snapshot?.deletedBookmarkIDs ?? []
			loadedPersistence = store
			loadedErrorDescription = nil
		} catch {
			let tab = BrowserTab()
			loadedTabs = [tab]
			loadedSelectedTabID = tab.id
			loadedWorkspace = BrowserWorkspace.migrated(
				tabs: [tab.openTab],
				selectedTabID: tab.id,
				theme: Defaults[.browserTheme]
			)
			loadedBookmarks = []
			loadedClosedHistoryTabs = []
			loadedClosedTabIDs = []
			loadedDeletedBookmarkIDs = []
			loadedPersistence = nil
			loadedErrorDescription = error.localizedDescription
		}

		tabs = loadedTabs
		selectedTabID = loadedSelectedTabID
		workspace = loadedWorkspace
		recentlyUsedTabIDs = [loadedSelectedTabID]
		bookmarks = loadedBookmarks
		closedHistoryTabs = loadedClosedHistoryTabs
		closedTabIDs = loadedClosedTabIDs
		deletedBookmarkIDs = loadedDeletedBookmarkIDs
		persistence = loadedPersistence
		persistenceErrorDescription = loadedErrorDescription
		persistenceTask = nil
		reconcileWorkspace()

		for tab in loadedTabs {
			configure(tab)
		}
		if let selectedTab = loadedTabs.first(where: { $0.id == loadedSelectedTabID }),
		   selectedTab.isHibernated
		{
			selectedTab.wake()
			configure(selectedTab)
		}
		BrowserWindowRegistry.shared.register(self)
		if loadedPersistence != nil {
			persist()
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
		if let existing = visibleTabs.first(where: { $0.internalPage == page }) {
			selectTab(existing.id)
			return
		}
		let tab = BrowserTab(internalPage: page)
		tabs.append(tab)
		selectTab(tab.id)
	}

	var openHistoryTabs: [OpenTab] {
		webTabs.map(\.openTab).filter { $0.url != nil }
	}

	func openHistoryTab(_ saved: OpenTab, inBackground: Bool) {
		if !inBackground, tabs.contains(where: { $0.id == saved.id }) {
			selectTab(saved.id)
			return
		}
		let tab = BrowserTab(
			pageTitle: saved.pageTitle,
			customTitle: saved.customTitle,
			initialURL: saved.url,
			history: saved.history,
			historyIndex: saved.historyIndex,
			openPeeks: saved.peeks,
			pageZoom: saved.pageZoom,
			scrollPosition: saved.scrollPosition,
			isHibernated: inBackground
		)
		configure(tab)
		tabs.append(tab)
		if inBackground {
			schedulePersistence()
		} else {
			selectTab(tab.id)
		}
	}

	func openHistoryURL(_ url: URL, inBackground: Bool) {
		let tab = BrowserTab(initialURL: url)
		configure(tab)
		tabs.append(tab)
		if inBackground {
			schedulePersistence()
		} else {
			selectTab(tab.id)
		}
	}

	#if DEBUG
		func openFailedWebsiteState(_ kind: BrowserNavigationFailure.Kind) {
			let tab = BrowserTab(internalPage: .failedWebsiteState(kind))
			tabs.append(tab)
			selectTab(tab.id)
		}
	#endif

	func selectTab(_ id: UUID) {
		guard let tab = tabs.first(where: { $0.id == id }) else { return }
		if !workspace.favouriteTabIDs.contains(id),
		   let ownerIndex = workspace.spaces.firstIndex(where: { $0.tabIDs.contains(id) })
		{
			if let currentIndex = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) {
				spaceSwitchDirection = ownerIndex >= currentIndex ? 1 : -1
			}
			workspace.selectedSpaceID = workspace.spaces[ownerIndex].id
		}
		if tab.isHibernated {
			tab.wake()
			configure(tab)
		}
		selectedTabID = id
		if let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) {
			workspace.spaces[index].selectedTabID = id
		}
		recentlyUsedTabIDs.removeAll { $0 == id }
		recentlyUsedTabIDs.insert(id, at: 0)
		tab.controller?.loadFaviconIfMissing()
		schedulePersistence()
	}

	func switchCandidates(forward: Bool) -> [UUID] {
		let ids = visibleTabs.map(\.id)
		guard ids.count > 1, let selectedIndex = ids.firstIndex(of: selectedTabID) else { return [] }
		return (1 ... ids.count).map { offset in
			let direction = forward ? offset : ids.count - offset
			return ids[(selectedIndex + direction) % ids.count]
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
		let nextVisibleID = visibleTabs.first(where: { $0.id != id })?.id
		if workspace.favouriteTabIDs.contains(id) || workspace.spaces.contains(where: { $0.pinnedTabIDs.contains(id) }) {
			hibernateTab(id)
			if selectedTabID == id {
				if let next = visibleTabs.first(where: { $0.id != id }) {
					selectTab(next.id)
				} else {
					addTab()
				}
			}
			return
		}
		let wasSelected = selectedTabID == id
		let wasInternal = tabs[index].internalPage != nil
		if !wasInternal {
			archiveHistory(of: [tabs[index]])
		}
		releaseAfterTabUpdate([tabs[index]])
		tabs.remove(at: index)
		if !wasInternal {
			closedTabIDs.insert(id)
		}
		recentlyUsedTabIDs.removeAll { $0 == id }

		if tabs.isEmpty {
			addTab()
			return
		}
		if wasSelected, nextVisibleID == nil {
			addTab()
			return
		}

		if wasSelected {
			selectedTabID = wasInternal
				? recentlyUsedTabIDs.first(where: { recentID in tabs.contains { $0.id == recentID } }) ?? tabs[0].id
				: nextVisibleID ?? tabs[min(index, tabs.count - 1)].id
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
			pageTitle: peek.controller.webViewIfLoaded?.title ?? "New Tab",
			existingController: peek.controller
		)
		source.dismissPeek(id)
		configure(tab)
		tabs.append(tab)
		selectTab(tab.id)
	}

	func closeTabsAbove(_ id: UUID) {
		let normalIDs = normalTabs.map(\.id)
		guard let index = normalIDs.firstIndex(of: id), index > 0 else { return }
		removeTabs(Set(normalIDs[..<index]), selecting: id)
	}

	func closeTabsBelow(_ id: UUID) {
		let normalIDs = normalTabs.map(\.id)
		guard let index = normalIDs.firstIndex(of: id), index < normalIDs.count - 1 else { return }
		removeTabs(Set(normalIDs[(index + 1)...]), selecting: id)
	}

	func closeOtherTabs(_ id: UUID) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		removeTabs(Set(normalTabs.map(\.id).filter { $0 != id }), selecting: id)
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
				parentZoom: controller.pageZoom
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
				parentZoom: peek.controller.pageZoom
			)
		}
	}

	private func openNewTab(_ url: URL) {
		let tab = addTab()
		tab.controller?.load(url)
	}

	private func removeTabs(_ ids: Set<UUID>, selecting selectedID: UUID) {
		let protectedIDs = Set(workspace.favouriteTabIDs + workspace.spaces.flatMap(\.pinnedTabIDs))
		let ids = ids.subtracting(protectedIDs)
		guard !ids.isEmpty else { return }
		let removedTabs = tabs.filter { ids.contains($0.id) }
		archiveHistory(of: removedTabs)
		let closedWebIDs = Set(removedTabs.filter { $0.internalPage == nil }.map(\.id))
		releaseAfterTabUpdate(removedTabs)
		tabs.removeAll { ids.contains($0.id) }
		closedTabIDs.formUnion(closedWebIDs)
		recentlyUsedTabIDs.removeAll { ids.contains($0) }
		selectedTabID = selectedID
		recentlyUsedTabIDs.removeAll { $0 == selectedID }
		recentlyUsedTabIDs.insert(selectedID, at: 0)
		schedulePersistence()
	}

	private func releaseAfterTabUpdate(_ removedTabs: [BrowserTab]) {
		// ponytail: Give the tab UI time to update before WebKit teardown; use explicit lifecycle control if teardown still stalls.
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(100))
			withExtendedLifetime(removedTabs) {}
		}
	}

	private func archiveHistory(of removedTabs: [BrowserTab]) {
		let snapshots = removedTabs.filter { $0.internalPage == nil }
			.map { tab in
				var snapshot = tab.openTab
				snapshot.modifiedAt = .now
				return snapshot
			}
			.filter { $0.url != nil }
		closedHistoryTabs.insert(contentsOf: snapshots, at: 0)
	}

	func syncDocument(settings: [String: SyncedSetting]) -> BrowserSyncDocument {
		reconcileWorkspace()
		var syncedWorkspace = workspace
		let webTabIDs = Set(webTabs.map(\.id))
		syncedWorkspace.favouriteTabIDs.removeAll { !webTabIDs.contains($0) }
		for index in syncedWorkspace.spaces.indices {
			syncedWorkspace.spaces[index].tabIDs.removeAll { !webTabIDs.contains($0) }
			syncedWorkspace.spaces[index].pinnedTabIDs.removeAll { !webTabIDs.contains($0) }
			if let selectedID = syncedWorkspace.spaces[index].selectedTabID,
			   !webTabIDs.contains(selectedID)
			{
				syncedWorkspace.spaces[index].selectedTabID = syncedWorkspace.spaces[index].tabIDs.first
			}
		}
		return BrowserSyncDocument(
			tabs: webTabs.map(\.openTab),
			workspace: syncedWorkspace,
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
		let changedTabs = document.tabs.compactMap { saved -> BrowserTab? in
			let internalPage = saved.internalPage.flatMap(BrowserInternalPage.init(persistenceID:))
			guard saved.internalPage == nil || internalPage != nil else { return nil }
			if let current = currentTabs[saved.id], current.openTab == saved {
				return current
			}
			let tab = BrowserTab(
				id: saved.id,
				internalPage: internalPage,
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
		workspace = document.workspace ?? BrowserWorkspace.migrated(
			tabs: document.tabs,
			selectedTabID: document.browser.selectedTabID,
			theme: Defaults[.browserTheme]
		)
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
		reconcileWorkspace()
		schedulePersistence()
	}

	func receiveSharedState(from source: Browser) {
		persistenceTask?.cancel()
		persistenceTask = nil
		let currentTabs = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
		let sharedTabs = source.tabs.map(\.openTab)
		tabs = sharedTabs.map { saved in
			if let current = currentTabs[saved.id],
			   current.openTab == saved || (saved.id == selectedTabID && current.controller != nil)
			{
				return current
			}
			let tab = BrowserTab(openTab: saved)
			configure(tab)
			return tab
		}
		let selectedSpaceID = workspace.selectedSpaceID
		let selectedTabsBySpace = Dictionary(uniqueKeysWithValues: workspace.spaces.map { ($0.id, $0.selectedTabID) })
		workspace = source.workspace
		if workspace.spaces.contains(where: { $0.id == selectedSpaceID }) {
			workspace.selectedSpaceID = selectedSpaceID
		}
		for index in workspace.spaces.indices {
			if let selectedID = selectedTabsBySpace[workspace.spaces[index].id] ?? nil,
			   tabs.contains(where: { $0.id == selectedID })
			{
				workspace.spaces[index].selectedTabID = selectedID
			}
		}
		bookmarks = source.bookmarks
		closedHistoryTabs = source.closedHistoryTabs
		closedTabIDs = source.closedTabIDs
		deletedBookmarkIDs = source.deletedBookmarkIDs
		if !tabs.contains(where: { $0.id == selectedTabID }) {
			selectedTabID = tabs.first?.id ?? UUID()
		}
		reconcileWorkspace()
		if !workspace.favouriteTabIDs.contains(selectedTabID),
		   !selectedSpace.tabIDs.contains(selectedTabID)
		{
			let savedID = selectedSpace.selectedTabID.flatMap { id in
				selectedSpace.tabIDs.contains(id) || workspace.favouriteTabIDs.contains(id) ? id : nil
			}
			if let replacementID = savedID ?? selectedSpace.tabIDs.first ?? workspace.favouriteTabIDs.first {
				selectedTabID = replacementID
				if let tab = tabs.first(where: { $0.id == replacementID }), tab.isHibernated {
					tab.wake()
					configure(tab)
				}
			} else {
				addTab()
			}
		}
	}

	private func reconcileWorkspace() {
		if workspace.spaces.isEmpty {
			workspace = BrowserWorkspace.migrated(
				tabs: tabs.map(\.openTab),
				selectedTabID: selectedTabID,
				theme: Defaults[.browserTheme]
			)
		}
		if !workspace.spaces.contains(where: { $0.id == workspace.selectedSpaceID }) {
			workspace.selectedSpaceID = workspace.spaces[0].id
		}
		let existingIDs = Set(tabs.map(\.id))
		workspace.favouriteTabIDs.removeAll { !existingIDs.contains($0) }
		for index in workspace.spaces.indices {
			workspace.spaces[index].tabIDs.removeAll { !existingIDs.contains($0) }
			let tabIDs = Set(workspace.spaces[index].tabIDs)
			workspace.spaces[index].pinnedTabIDs.removeAll {
				!tabIDs.contains($0)
			}
		}
		let assignedIDs = Set(workspace.favouriteTabIDs + workspace.spaces.flatMap(\.tabIDs))
		let unassignedIDs = tabs.map(\.id).filter { !assignedIDs.contains($0) }
		if let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) {
			workspace.spaces[index].tabIDs.append(contentsOf: unassignedIDs)
			if workspace.spaces[index].tabIDs.contains(selectedTabID)
				|| workspace.favouriteTabIDs.contains(selectedTabID)
			{
				workspace.spaces[index].selectedTabID = selectedTabID
			}
		}
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
			reconcileWorkspace()
			try persistence.saveBookmarks(bookmarks)
			try persistence.saveOpenTabs(tabs.map(\.openTab))
			try persistence.saveClosedTabs(closedHistoryTabs)
			try persistence.saveWorkspace(workspace)
			try persistence.saveBrowserSnapshot(
				BrowserSnapshot(
					selectedTabID: selectedTabID,
					closedTabIDs: closedTabIDs,
					deletedBookmarkIDs: deletedBookmarkIDs
				)
			)
			persistenceErrorDescription = nil
			BrowserWindowRegistry.shared.publish(from: self)
			BrowserSync.shared.scheduleSync()
		} catch {
			persistenceErrorDescription = error.localizedDescription
		}
	}
}
