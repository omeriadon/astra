import Defaults
import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class Browser {
	private static var didApplyStartupBehavior = false
	private static var launchMetadataTask: Task<Bool?, Never>?
	let windowID = UUID()
	let isMini: Bool
	let session: BrowserWebSession

	var isPrivate: Bool {
		session.isPrivate
	}

	private(set) var tabs: [BrowserTab]
	private(set) var selectedTabID: UUID
	private(set) var workspace: BrowserWorkspace
	private(set) var spaceSwitchDirection = 1
	private(set) var recentlyUsedTabIDs: [UUID]
	private(set) var bookmarks: [Bookmark]
	private(set) var historyVisits: [BrowserVisit]
	@ObservationIgnored
	private var lastVisitedURL: [UUID: URL] = [:]
	@ObservationIgnored
	private var lastVisitID: [UUID: UUID] = [:]
	@ObservationIgnored
	private var lastVisitedDocument: [UUID: Int] = [:]
	private(set) var closedHistoryTabs: [OpenTab]
	private(set) var closedTabIDs: Set<UUID>
	private(set) var deletedBookmarkIDs: Set<UUID>
	private(set) var closedTabsAt: [UUID: Date]
	private(set) var deletedBookmarksAt: [UUID: Date]
	private(set) var deletedSpacesAt: [UUID: Date]
	private(set) var deletedVisitsAt: [UUID: Date]
	private(set) var historyClearedAt: Date
	private(set) var selectedTabModifiedAt: Date
	private(set) var persistenceErrorDescription: String?
	private(set) var previousShutdownWasClean: Bool?

	@ObservationIgnored
	var navigationIntercept: ((URL) -> Bool)? {
		didSet {
			for tab in tabs {
				configure(tab)
			}
		}
	}

	var isAboutToQuit: Bool = false
	var addressFocusRequest = 0
	var settingsPage: BrowserSettingsView.Page = .ui
	var settingsScrollTarget: String?
	var newTabSearchText = "" {
		didSet {
			guard oldValue != newTabSearchText else { return }
			newTabSearchSelection = nil
			newTabGoogleSuggestions = []
		}
	}

	var newTabSearchSelection: String?
	var newTabGoogleSuggestions: [String] = []
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

	@ObservationIgnored
	private var pendingFullPersistence = false

	@ObservationIgnored
	private var scrollPersistenceTask: Task<Void, Never>?

	@ObservationIgnored
	private var pendingScrollPersistence = false

	/// False until disk hydration completes; persistence calls before then only
	/// stash flags so a placeholder window never saves or broadcasts itself.
	@ObservationIgnored
	private var didFinishHydration = true
	var isReadyForSync: Bool { didFinishHydration && !hydrationFailed && persistence != nil }

	@ObservationIgnored
	private var hydrationFailed = false

	/// O(1) tab lookup for sidebar/history rows (avoids O(n²) scans).
	var tabsByID: [UUID: BrowserTab] {
		Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
	}

	var recentHistoryVisits: [BrowserVisit] {
		historyVisits.sorted {
			$0.visitedAt == $1.visitedAt
				? $0.id.uuidString < $1.id.uuidString
				: $0.visitedAt > $1.visitedAt
		}
	}

	var frequentHistory: [BrowserVisitSummary] {
		BrowserVisit.summaries(historyVisits).sorted {
			if $0.visitCount != $1.visitCount {
				return $0.visitCount > $1.visitCount
			}
			if $0.lastVisitedAt != $1.lastVisitedAt {
				return $0.lastVisitedAt > $1.lastVisitedAt
			}
			return $0.url.absoluteString < $1.url.absoluteString
		}
	}

	func tab(withID id: UUID) -> BrowserTab? {
		tabs.first { $0.id == id }
	}

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
		guard !isPrivate else { return [] }
		let lookup = tabsByID
		return workspace.favouriteTabIDs.compactMap { lookup[$0] }
	}

	var pinnedTabs: [BrowserTab] {
		guard !isPrivate else { return [] }
		let lookup = tabsByID
		return selectedSpace.pinnedTabIDs.compactMap { lookup[$0] }
	}

	var normalTabs: [BrowserTab] {
		if isPrivate {
			return tabs
		}
		let lookup = tabsByID
		let pinnedIDs = Set(selectedSpace.pinnedTabIDs)
		return selectedSpace.tabIDs.filter { !pinnedIDs.contains($0) }.compactMap { lookup[$0] }
	}

	var visibleTabs: [BrowserTab] {
		favouriteTabs + pinnedTabs + normalTabs
	}

	func createSpace() {
		guard !isPrivate else { return }
		let space = BrowserSpace()
		let mutationDate = nextWorkspaceMutationDate()
		spaceSwitchDirection = 1
		workspace.spaces.append(space)
		workspace.selectedSpaceID = space.id
		workspace.modifiedAt = mutationDate
		workspace.selectionModifiedAt = mutationDate
		openInternalPage(.themeEditor)
		schedulePersistence()
	}

	func deleteSpace(_ id: UUID) {
		guard workspace.spaces.count > 1,
		      let removed = workspace.spaces.first(where: { $0.id == id }),
		      let destinationIndex = workspace.spaces.firstIndex(where: { $0.id != id })
		else { return }
		let destinationID = workspace.spaces[destinationIndex].id
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces[destinationIndex].tabIDs.append(contentsOf: removed.tabIDs)
		workspace.spaces[destinationIndex].pinnedTabIDs.append(contentsOf: removed.pinnedTabIDs)
		for removedFolder in removed.pinnedFolders {
			if let folderIndex = workspace.spaces[destinationIndex].pinnedFolders.firstIndex(where: { $0.id == removedFolder.id }) {
				var folder = workspace.spaces[destinationIndex].pinnedFolders[folderIndex]
				folder.tabIDs.append(contentsOf: removedFolder.tabIDs.filter { !folder.tabIDs.contains($0) })
				folder.modifiedAt = mutationDate
				workspace.spaces[destinationIndex].pinnedFolders[folderIndex] = folder
			} else {
				workspace.spaces[destinationIndex].pinnedFolders.append(removedFolder)
			}
		}
		if removed.tabIDs.contains(selectedTabID) {
			workspace.spaces[destinationIndex].selectedTabID = selectedTabID
		}
		workspace.spaces[destinationIndex].modifiedAt = mutationDate
		workspace.modifiedAt = mutationDate
		workspace.spaces.removeAll { $0.id == id }
		workspace.deletedSpaceIDs.insert(id)
		workspace.deletedSpacesAt[id] = mutationDate
		deletedSpacesAt[id] = workspace.deletedSpacesAt[id]
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
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces[index].name = name
		workspace.spaces[index].modifiedAt = mutationDate
		workspace.modifiedAt = mutationDate
		schedulePersistence()
	}

	func setSelectedSpaceSymbol(_ symbol: String) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) else { return }
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces[index].symbol = symbol
		workspace.spaces[index].modifiedAt = mutationDate
		workspace.modifiedAt = mutationDate
		schedulePersistence()
	}

	func setSelectedSpaceTheme(_ theme: BrowserTheme) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) else { return }
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces[index].theme = theme
		workspace.spaces[index].modifiedAt = mutationDate
		workspace.modifiedAt = mutationDate
		schedulePersistence()
	}

	enum TabArea {
		case favourite
		case pinned
		case normal
	}

	func createPinnedFolder(named name: String = "New Folder") {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) else { return }
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces[index].pinnedFolders.append(PinnedTabFolder(name: name, modifiedAt: mutationDate))
		workspace.spaces[index].modifiedAt = mutationDate
		workspace.modifiedAt = mutationDate
		schedulePersistence()
	}

	func renamePinnedFolder(_ id: UUID, to name: String) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }),
		      let folderIndex = workspace.spaces[index].pinnedFolders.firstIndex(where: { $0.id == id }),
		      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces[index].pinnedFolders[folderIndex].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
		workspace.spaces[index].pinnedFolders[folderIndex].modifiedAt = mutationDate
		workspace.spaces[index].modifiedAt = mutationDate
		workspace.modifiedAt = mutationDate
		schedulePersistence()
	}

	func deletePinnedFolder(_ id: UUID) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }),
		      let folder = workspace.spaces[index].pinnedFolders.first(where: { $0.id == id })
		else { return }
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces[index].pinnedFolders.removeAll { $0.id == id }
		if folder.tabIDs.isEmpty || folder.tabIDs.contains(where: isSyncableTabID) {
			workspace.spaces[index].deletedPinnedFoldersAt[id] = mutationDate
		}
		workspace.spaces[index].modifiedAt = mutationDate
		workspace.modifiedAt = mutationDate
		schedulePersistence()
	}

	func movePinnedTab(_ tabID: UUID, toFolder folderID: UUID?, in spaceID: UUID? = nil, before targetID: UUID? = nil) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == (spaceID ?? workspace.selectedSpaceID) }),
		      workspace.spaces[index].pinnedTabIDs.contains(tabID),
		      targetID != tabID
		else { return }
		let destinationFolderIndex = folderID.flatMap { id in
			workspace.spaces[index].pinnedFolders.firstIndex(where: { $0.id == id })
		}
		guard folderID == nil || destinationFolderIndex != nil else { return }
		let mutationDate = nextWorkspaceMutationDate()
		let destinationDate = mutationDate.addingTimeInterval(0.001)
		for folderIndex in workspace.spaces[index].pinnedFolders.indices {
			let oldCount = workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.count
			workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.removeAll { $0 == tabID }
			if oldCount != workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.count {
				workspace.spaces[index].pinnedFolders[folderIndex].modifiedAt = mutationDate
			}
		}
		if let folderIndex = destinationFolderIndex {
			let insertion = targetID.flatMap { workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.firstIndex(of: $0) }
				?? workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.endIndex
			workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.insert(tabID, at: insertion)
			workspace.spaces[index].pinnedFolders[folderIndex].modifiedAt = destinationDate
		}
		workspace.spaces[index].modifiedAt = destinationDate
		workspace.modifiedAt = destinationDate
		schedulePersistence()
	}

	func moveTab(_ id: UUID, to area: TabArea, in spaceID: UUID? = nil, before targetID: UUID? = nil) {
		guard !isPrivate, tabs.contains(where: { $0.id == id }), targetID != id else { return }
		let destinationIndex = area == .favourite
			? nil
			: workspace.spaces.firstIndex(where: { $0.id == (spaceID ?? workspace.selectedSpaceID) })
		guard area == .favourite || destinationIndex != nil else { return }
		let wasFavourite = workspace.favouriteTabIDs.contains(id)
		let mutationDate = nextWorkspaceMutationDate()
		let destinationDate = mutationDate.addingTimeInterval(0.001)
		workspace.favouriteTabIDs.removeAll { $0 == id }
		for index in workspace.spaces.indices {
			let removedMembership = workspace.spaces[index].tabIDs.contains(id)
				|| workspace.spaces[index].pinnedTabIDs.contains(id)
				|| workspace.spaces[index].pinnedFolders.contains(where: { $0.tabIDs.contains(id) })
			if removedMembership {
				workspace.spaces[index].modifiedAt = mutationDate
			}
			workspace.spaces[index].tabIDs.removeAll { $0 == id }
			workspace.spaces[index].pinnedTabIDs.removeAll { $0 == id }
			for folderIndex in workspace.spaces[index].pinnedFolders.indices {
				let oldCount = workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.count
				workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.removeAll { $0 == id }
				if oldCount != workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.count {
					workspace.spaces[index].pinnedFolders[folderIndex].modifiedAt = mutationDate
				}
			}
		}
		if area == .favourite {
			let index = targetID.flatMap { workspace.favouriteTabIDs.firstIndex(of: $0) } ?? workspace.favouriteTabIDs.endIndex
			workspace.favouriteTabIDs.insert(id, at: index)
			workspace.favouritesModifiedAt = destinationDate
		} else if let index = destinationIndex {
			let insertion = targetID.flatMap { workspace.spaces[index].tabIDs.firstIndex(of: $0) } ?? workspace.spaces[index].tabIDs.endIndex
			workspace.spaces[index].tabIDs.insert(id, at: insertion)
			if area == .pinned {
				let pinnedInsertion = targetID.flatMap { workspace.spaces[index].pinnedTabIDs.firstIndex(of: $0) }
					?? workspace.spaces[index].pinnedTabIDs.endIndex
				workspace.spaces[index].pinnedTabIDs.insert(id, at: pinnedInsertion)
			}
			workspace.spaces[index].modifiedAt = destinationDate
			if wasFavourite {
				workspace.favouritesModifiedAt = mutationDate
			}
		} else {
			preconditionFailure("Validated tab destination became unavailable")
		}
		workspace.modifiedAt = destinationDate
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

	private func isSyncableTabID(_ id: UUID) -> Bool {
		guard let tab = tabs.first(where: { $0.id == id }) else { return false }
		return isSyncableTab(tab.openTab)
	}

	private func isSyncableTab(_ tab: OpenTab) -> Bool {
		guard tab.internalPage == nil, tab.fileAccessBookmark == nil else { return false }
		guard let url = tab.url else { return true }
		return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
	}

	private var webTabs: [BrowserTab] {
		tabs.filter { $0.internalPage == nil }
	}

	private var persistedSelectedTabID: UUID {
		selectedTab?.internalPage == nil ? selectedTabID : webTabs.first?.id ?? selectedTabID
	}

	init(isMini: Bool = false, isPrivate: Bool = false) {
		self.isMini = isMini
		let session = isPrivate ? BrowserWebSession(isPrivate: true) : .shared
		self.session = session
		if !isMini, !isPrivate {
			BrowserWindowRegistry.shared.activeBrowser?.flushPersistence()
		}
		// Synchronous placeholder only: disk decode happens off-main in
		// hydrateFromDisk() so the first frame never waits on JSON.
		let placeholder = BrowserTab(modifiedAt: .distantPast, session: session)
		let placeholderID = placeholder.id
		let placeholderModifiedAt = placeholder.modifiedAt
		var persistenceStore: BrowserPersistence?
		var persistenceError: String?
		do {
			if !isMini, !isPrivate {
				persistenceStore = try BrowserPersistence()
			}
		} catch {
			persistenceError = error.localizedDescription
		}
		tabs = [placeholder]
		selectedTabID = placeholderID
		workspace = BrowserWorkspace.migrated(
			tabs: [placeholder.openTab],
			selectedTabID: placeholderID,
			theme: Defaults[.browserTheme]
		)
		recentlyUsedTabIDs = [placeholderID]
		bookmarks = []
		historyVisits = []
		closedHistoryTabs = []
		closedTabIDs = []
		deletedBookmarkIDs = []
		closedTabsAt = [:]
		deletedBookmarksAt = [:]
		deletedSpacesAt = [:]
		deletedVisitsAt = [:]
		historyClearedAt = .distantPast
		selectedTabModifiedAt = .distantPast
		persistence = persistenceStore
		persistenceErrorDescription = persistenceError
		persistenceTask = nil
		didFinishHydration = persistenceStore == nil
		reconcileWorkspace()
		configure(placeholder)
		if !isMini {
			BrowserWindowRegistry.shared.register(self)
		}
		BrowserController.prewarmSharedProcess()
		if persistenceStore != nil {
			hydrateFromDisk(placeholderID: placeholderID, placeholderModifiedAt: placeholderModifiedAt)
		}
	}

	/// Saved-state snapshot decoded off-main.
	private struct HydratedState: @unchecked Sendable {
		var tabs: [OpenTab]
		var snapshot: BrowserSnapshot?
		var workspace: BrowserWorkspace?
		var bookmarks: [Bookmark]
		var closedTabs: [OpenTab]
		var historyVisits: [BrowserVisit]?
		var previousShutdownWasClean: Bool?
	}

	private func hydrateFromDisk(placeholderID: UUID, placeholderModifiedAt: Date) {
		guard let persistence else { return }
		if Self.launchMetadataTask == nil {
			Self.launchMetadataTask = Task.detached(priority: .utility) {
				let previous = try? persistence.loadShutdownMetadata()?.clean
				try? persistence.saveShutdownMetadata(clean: false)
				return previous
			}
		}
		let launchMetadataTask = Self.launchMetadataTask
		Task.detached(priority: .userInitiated) { [persistence] in
			do {
				let previousShutdownWasClean = await launchMetadataTask?.value
				await BrowserRestorationStore.prepare()
				let loaded: HydratedState
				if let state = try persistence.loadPersistedState() {
					loaded = HydratedState(
						tabs: state.openTabs,
						snapshot: state.snapshot,
						workspace: state.workspace,
						bookmarks: state.bookmarks,
						closedTabs: state.closedTabs,
						historyVisits: state.historyVisits,
						previousShutdownWasClean: previousShutdownWasClean
					)
				} else {
					let tabs = try persistence.loadOpenTabs()
					let snapshot = try persistence.loadBrowserSnapshot()
					let workspace = try persistence.loadWorkspace()
					let bookmarks = try persistence.loadBookmarks()
					let closedTabs = try persistence.loadClosedTabs()
					loaded = HydratedState(
						tabs: tabs,
						snapshot: snapshot,
						workspace: workspace,
						bookmarks: bookmarks,
						closedTabs: closedTabs,
						previousShutdownWasClean: previousShutdownWasClean
					)
				}
				await MainActor.run { [weak self] in
					for tab in self?.tabs ?? [] {
						tab.invalidateStoredSnapshot()
					}
					self?.applyHydratedState(loaded, placeholderID: placeholderID, placeholderModifiedAt: placeholderModifiedAt)
				}
			} catch {
				let message = error.localizedDescription
				await MainActor.run { [weak self] in
					self?.hydrationFailed = true
					self?.didFinishHydration = true
					self?.persistenceErrorDescription = message
				}
			}
		}
	}

	private func applyHydratedState(_ loaded: HydratedState, placeholderID: UUID, placeholderModifiedAt: Date) {
		defer {
			didFinishHydration = true
			previousShutdownWasClean = loaded.previousShutdownWasClean
			applyHistoryRetention()
			persist()
			BrowserSync.shared.hydrationDidFinish(self)
		}
		let placeholderIsUntouched = tabs.count == 1
			&& tabs.first?.id == placeholderID
			&& tabs.first?.modifiedAt == placeholderModifiedAt
			&& tabs.first?.currentURL == nil
		guard placeholderIsUntouched else {
			Self.didApplyStartupBehavior = true
			let cachedTabs = loaded.tabs
			let cachedWorkspace = loaded.workspace ?? BrowserWorkspace.migrated(
				tabs: cachedTabs,
				selectedTabID: loaded.snapshot?.selectedTabID ?? cachedTabs.first?.id ?? UUID(),
				theme: Defaults[.browserTheme]
			)
			let cached = BrowserSyncDocument(
				tabs: cachedTabs,
				workspace: cachedWorkspace,
				bookmarks: loaded.bookmarks,
				history: loaded.historyVisits ?? Self.migratedHistory(loaded.tabs + loaded.closedTabs),
				browser: loaded.snapshot ?? BrowserSnapshot(),
				settings: [:]
			)
			let current = BrowserSyncDocument(
				tabs: tabs.map(\.openTab),
				workspace: workspace,
				bookmarks: bookmarks,
				history: historyVisits,
				browser: BrowserSnapshot(
					selectedTabID: selectedTabID,
					selectedTabModifiedAt: selectedTabModifiedAt,
					closedTabIDs: closedTabIDs,
					deletedBookmarkIDs: deletedBookmarkIDs,
					deletedBookmarksAt: deletedBookmarksAt,
					closedTabsAt: closedTabsAt,
					deletedSpacesAt: deletedSpacesAt,
					deletedVisitsAt: deletedVisitsAt,
					historyClearedAt: historyClearedAt
				),
				settings: [:]
			)
			let merged = current.merging(cached)
			applySyncDocument(merged)
			closedHistoryTabs = loaded.closedTabs
			return
		}
		let startupBehavior: BrowserStartupBehavior
		if !Self.didApplyStartupBehavior {
			Self.didApplyStartupBehavior = true
			startupBehavior = Defaults[.startupBehavior]
		} else {
			startupBehavior = .restore
		}
		let restoredTabs = loaded.tabs.compactMap { saved -> BrowserTab? in
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
				modifiedAt: saved.modifiedAt,
				recordsNavigationHistory: saved.recordsNavigationHistory,
				restorationState: saved.restorationState,
				fileAccessBookmark: saved.fileAccessBookmark,
				suppressInitialHistoryVisit: true
			)
		}
		var newTabs: [BrowserTab]
		if startupBehavior == .restore {
			newTabs = restoredTabs.isEmpty ? [BrowserTab()] : restoredTabs
		} else {
			let homepage = startupBehavior == .homepage ? BrowserHomepage.validURL(Defaults[.homepageURL]) : nil
			newTabs = restoredTabs
			newTabs.append(BrowserTab(initialURL: homepage, session: session))
		}
		let newSelectedTabID = startupBehavior == .restore
			? (newTabs.first(where: { $0.id == loaded.snapshot?.selectedTabID })?.id ?? newTabs[0].id)
			: newTabs[newTabs.count - 1].id
		tabs = newTabs
		selectedTabID = newSelectedTabID
		workspace = loaded.workspace ?? BrowserWorkspace.migrated(
			tabs: loaded.tabs,
			selectedTabID: newSelectedTabID,
			theme: Defaults[.browserTheme]
		)
		recentlyUsedTabIDs = [newSelectedTabID]
		bookmarks = loaded.bookmarks.map { item in
			var item = item
			item.url = BrowserAddress.withoutCredentials(item.url)
			return item
		}
		historyVisits = visibleHistoryVisits(loaded.historyVisits ?? Self.migratedHistory(loaded.tabs + loaded.closedTabs))
		closedHistoryTabs = loaded.closedTabs
		closedTabIDs = loaded.snapshot?.closedTabIDs ?? []
		selectedTabModifiedAt = loaded.snapshot?.selectedTabModifiedAt ?? .distantPast
		deletedBookmarkIDs = loaded.snapshot?.deletedBookmarkIDs ?? []
		closedTabsAt = loaded.snapshot?.closedTabsAt ?? [:]
		deletedBookmarksAt = loaded.snapshot?.deletedBookmarksAt ?? [:]
		deletedSpacesAt = loaded.snapshot?.deletedSpacesAt ?? [:]
		deletedVisitsAt = loaded.snapshot?.deletedVisitsAt ?? [:]
		historyClearedAt = loaded.snapshot?.historyClearedAt ?? .distantPast
		historyVisits = visibleHistoryVisits(historyVisits)
		persistenceErrorDescription = nil
		reconcileWorkspace()
		for tab in newTabs {
			configure(tab)
		}
		if let selectedTab = newTabs.first(where: { $0.id == newSelectedTabID }),
		   selectedTab.isHibernated
		{
			selectedTab.wake()
			configure(selectedTab)
		}
		BrowserExtensionManager.shared.sync(self)
	}

	@discardableResult
	func addTab(inBackground: Bool = false) -> BrowserTab {
		let tab = BrowserTab(session: session)
		configure(tab)
		tabs.append(tab)
		if !inBackground {
			recentlyUsedTabIDs.insert(tab.id, at: min(1, recentlyUsedTabIDs.count))
		}
		// Assign to the selected space synchronously so the sidebar row
		// appears in the same transaction as the content switch (previously
		// this only happened in debounced persist() → ~500ms row delay).
		reconcileWorkspace()
		markWorkspaceStructureChanged()
		if !inBackground {
			selectTab(tab.id)
		}
		// New tab changes open-tabs.json; selection-only save is not enough.
		schedulePersistence(fullState: true)
		return tab
	}

	func adoptMiniTab(_ tab: BrowserTab) {
		guard session === tab.session, !tabs.contains(where: { $0.id == tab.id }) else { return }
		configure(tab)
		tabs.append(tab)
		reconcileWorkspace()
		markWorkspaceStructureChanged()
		selectTab(tab.id)
		schedulePersistence(fullState: true)
		#if DEBUG
			assert(selectedTab === tab)
			assert(selectedSpace.tabIDs.contains(tab.id))
			assert(tabs.filter { $0.id == tab.id }.count == 1)
		#endif
	}

	func openInternalPage(_ page: BrowserInternalPage, inNewTab: Bool = false) {
		guard !isPrivate || page == .settings else { return }
		if isPrivate {
			settingsPage = .privacyAndSecurity
		}
		if !inNewTab, let existing = visibleTabs.first(where: { $0.internalPage == page }) {
			selectTab(existing.id)
			return
		}
		let tab = BrowserTab(internalPage: page, session: session)
		tabs.append(tab)
		reconcileWorkspace()
		markWorkspaceStructureChanged()
		selectTab(tab.id)
		schedulePersistence(fullState: true)
	}

	var openHistoryTabs: [OpenTab] {
		webTabs.map(\.openTab).filter { $0.url != nil }
	}

	@discardableResult
	func openHistoryTab(_ saved: OpenTab, inBackground: Bool) -> BrowserTab {
		if !inBackground, let existing = tabs.first(where: { $0.id == saved.id }) {
			selectTab(existing.id)
			return existing
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
			isHibernated: inBackground,
			session: session
		)
		configure(tab)
		if !inBackground {
			// Start WebView + load on this runloop instead of waiting for
			// ContentView's Color.clear + Task.yield hop.
			tab.controller?.prepareWebView()
		}
		tabs.append(tab)
		reconcileWorkspace()
		markWorkspaceStructureChanged()
		if inBackground {
			schedulePersistence()
		} else {
			selectTab(tab.id)
			schedulePersistence(fullState: true)
		}
		return tab
	}

	func reopenLastClosedTab() {
		guard !closedHistoryTabs.isEmpty else { return }
		let saved = closedHistoryTabs.removeFirst()
		let tab = openHistoryTab(saved, inBackground: false)
		if let spaceID = saved.closedSpaceID,
		   let normalIndex = saved.closedNormalIndex,
		   let space = workspace.spaces.first(where: { $0.id == spaceID })
		{
			let normalIDs = space.tabIDs.filter {
				!space.pinnedTabIDs.contains($0) && $0 != tab.id
			}
			let targetID = normalIDs.dropFirst(max(0, normalIndex)).first
			moveTab(tab.id, to: .normal, in: spaceID, before: targetID)
		}
		schedulePersistence()
	}

	@discardableResult
	func openHistoryURL(_ url: URL, inBackground: Bool) -> BrowserTab {
		let tab = BrowserTab(initialURL: url, session: session)
		configure(tab)
		if !inBackground {
			tab.controller?.prepareWebView()
		}
		tabs.append(tab)
		reconcileWorkspace()
		markWorkspaceStructureChanged()
		if inBackground {
			schedulePersistence()
		} else {
			selectTab(tab.id)
			schedulePersistence(fullState: true)
		}
		return tab
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
		tab.clearPictureInPictureReturnController()
		if !workspace.favouriteTabIDs.contains(id),
		   let ownerIndex = workspace.spaces.firstIndex(where: { $0.tabIDs.contains(id) })
		{
			if let currentIndex = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) {
				spaceSwitchDirection = ownerIndex >= currentIndex ? 1 : -1
			}
			workspace.selectedSpaceID = workspace.spaces[ownerIndex].id
		}
		let didWake = tab.isHibernated
		if didWake {
			tab.wake()
			configure(tab)
		}
		if selectedTabID != id {
			newTabSearchText = ""
			newTabSearchSelection = nil
			newTabGoogleSuggestions = []
		}
		selectedTabID = id
		let selectionDate = nextWorkspaceMutationDate()
		selectedTabModifiedAt = selectionDate
		if let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) {
			workspace.spaces[index].selectedTabID = id
			workspace.spaces[index].modifiedAt = selectionDate
		}
		workspace.modifiedAt = selectionDate
		workspace.selectionModifiedAt = selectionDate
		recentlyUsedTabIDs.removeAll { $0 == id }
		recentlyUsedTabIDs.insert(id, at: 0)
		tab.controller?.loadFaviconIfMissing()
		#if os(macOS)
			for tab in tabs {
				tab.controller?.previewSnapshotRefreshSuspended = tab.id != id
			}
		#endif
		// Waking rebuilds the controller (open-tabs changed); pure selection
		// only needs workspace+snapshot.
		schedulePersistence(fullState: didWake)
	}

	func switchCandidates(forward: Bool) -> [UUID] {
		BrowserWorkspace.tabSwitchCandidates(
			visibleTabIDs: visibleTabs.map(\.id),
			recentlyUsedTabIDs: recentlyUsedTabIDs,
			selectedTabID: selectedTabID,
			forward: forward
		)
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
		bookmarks.append(Bookmark(name: tab.title, url: BrowserAddress.withoutCredentials(url)))
		schedulePersistence()
	}

	func openBookmark(_ bookmark: Bookmark) {
		guard let tab = selectedTab else { return }
		if tab.internalPage != nil {
			openHistoryURL(bookmark.url, inBackground: false)
			return
		}
		if tab.isHibernated {
			tab.wake()
			configure(tab)
		}
		tab.controller?.load(bookmark.url)
	}

	func removeBookmark(_ id: UUID) {
		let removed = bookmarks.first { $0.id == id }
		bookmarks.removeAll { $0.id == id }
		if let removed, ["http", "https"].contains(removed.url.scheme?.lowercased() ?? "") {
			deletedBookmarkIDs.insert(id)
			deletedBookmarksAt[id] = .now
		}
		schedulePersistence()
	}

	@discardableResult
	func duplicateTab(_ id: UUID) -> BrowserTab? {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
		let source = tabs[index]
		guard source.internalPage == nil else { return nil }
		let sourceSnapshot = source.openTab
		let tab = BrowserTab(
			pageTitle: source.pageTitle,
			customTitle: source.customTitle,
			initialURL: sourceSnapshot.url,
			history: sourceSnapshot.history,
			historyIndex: sourceSnapshot.historyIndex,
			openPeeks: sourceSnapshot.peeks,
			pageZoom: sourceSnapshot.pageZoom,
			scrollPosition: sourceSnapshot.scrollPosition,
			session: session,
			recordsNavigationHistory: sourceSnapshot.recordsNavigationHistory,
			fileAccessBookmark: sourceSnapshot.fileAccessBookmark
		)
		configure(tab)
		tabs.insert(tab, at: index + 1)
		reconcileWorkspace()
		markWorkspaceStructureChanged()
		if workspace.favouriteTabIDs.contains(id) {
			let nextID = workspace.favouriteTabIDs.drop(while: { $0 != id }).dropFirst().first
			moveTab(tab.id, to: .favourite, before: nextID)
		} else if let space = workspace.spaces.first(where: { $0.tabIDs.contains(id) }) {
			let nextTabID = space.tabIDs.drop(while: { $0 != id }).dropFirst().first
			let isPinned = space.pinnedTabIDs.contains(id)
			moveTab(tab.id, to: isPinned ? .pinned : .normal, in: space.id, before: nextTabID)
			if isPinned,
			   let folder = space.pinnedFolders.first(where: { $0.tabIDs.contains(id) })
			{
				let nextFolderTabID = folder.tabIDs.drop(while: { $0 != id }).dropFirst().first
				movePinnedTab(tab.id, toFolder: folder.id, in: space.id, before: nextFolderTabID)
			}
		}
		selectTab(tab.id)
		schedulePersistence(fullState: true)
		return tab
	}

	func closeTab(_ id: UUID, confirmed: Bool = false) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		#if os(iOS)
			let tab = tabs[index]
			let protectedController = ([tab.controller].compactMap { $0 } + tab.peeks.map(\.controller))
				.first(where: \.requiresMediaTeardownConfirmation)
			if !confirmed, let protectedController {
				guard let webView = protectedController.webViewIfLoaded else { return }
				Task { @MainActor [weak self] in
					let result = await BrowserWebsiteUI.javascriptDialog(
						title: "Close tab?",
						message: "Closing this tab will stop its media playback.",
						confirmTitle: "Close Tab",
						cancelTitle: "Cancel",
						in: webView
					) { [weak self] in
						self?.tabs.contains(where: { $0.id == id }) == true
					}
					if result.confirmed {
						self?.closeTab(id, confirmed: true)
					}
				}
				return
			}
		#endif
		#if os(macOS)
			let tab = tabs[index]
			let hasUnsavedChanges = tab.controller?.hasUnsavedChanges == true || tab.peeks.contains(where: \.controller.hasUnsavedChanges)
			let hasProtectedMedia = tab.controller?.requiresMediaTeardownConfirmation == true
				|| tab.peeks.contains(where: \.controller.requiresMediaTeardownConfirmation)
			if !confirmed, hasUnsavedChanges || hasProtectedMedia {
				Task { @MainActor [weak self] in
					let message = hasUnsavedChanges && hasProtectedMedia
						? "Changes may not be saved, and closing will stop media playback."
						: hasUnsavedChanges ? "Changes you made may not be saved." : "Closing will stop media playback."
					let alert = BrowserWebsiteUI.alert(title: "Close this tab?", message: message, confirm: "Close Tab")
					let window = tab.activeController?.webViewIfLoaded?.window
					if await BrowserWebsiteUI.present(alert, in: window) == .alertFirstButtonReturn {
						self?.closeTab(id, confirmed: true)
					}
				}
				return
			}
		#endif
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
		let normalIDs = normalTabs.map(\.id)
		let fallbackTabID = BrowserWorkspace.tabSelectionAfterClosing(
			tabID: id,
			normalTabIDs: normalIDs,
			visibleTabIDs: visibleTabs.map(\.id)
		)
		let wasSelected = selectedTabID == id
		let wasInternal = tabs[index].internalPage != nil
		if !wasInternal {
			archiveHistory(of: [tabs[index]])
		}
		let shouldCreateSyncTombstone = !wasInternal && isSyncableTab(tabs[index].openTab)
		releaseAfterTabUpdate([tabs[index]])
		tabs.remove(at: index)
		if shouldCreateSyncTombstone {
			closedTabIDs.insert(id)
			closedTabsAt[id] = .now
		}
		for index in workspace.spaces.indices where workspace.spaces[index].tabIDs.contains(id) {
			workspace.spaces[index].modifiedAt = .now
		}
		workspace.modifiedAt = .now
		recentlyUsedTabIDs.removeAll { $0 == id }

		if tabs.isEmpty {
			addTab()
			return
		}
		if wasSelected {
			guard let nextID = fallbackTabID else {
				addTab()
				return
			}
			selectTab(nextID)
		}
		reconcileWorkspace()
		schedulePersistence()
	}

	func hibernateTab(_ id: UUID, onlyIfBackground: Bool = false) {
		guard let tab = tabs.first(where: { $0.id == id }), !tab.isHibernated, tab.canHibernate else { return }
		Task { @MainActor [weak self, weak tab] in
			guard let self, let tab else { return }
			await tab.controller?.refreshActivity()
			for peek in tab.peeks {
				await peek.controller.refreshActivity()
			}
			guard tabs.contains(where: { $0 === tab }), tab.canHibernate,
			      !onlyIfBackground || selectedTabID != id else { return }
			tab.hibernate()
			BrowserExtensionManager.shared.webViewDidChange(for: id, in: self)
			schedulePersistence()
		}
	}

	func promotePeek(in source: BrowserTab, id: UUID) {
		guard let peek = source.takePeekForPromotion(id) else { return }
		let webView = peek.controller.webViewIfLoaded
		let navigationIdentifier = peek.controller.navigationIdentifier
		let tab = BrowserTab(
			pageTitle: peek.controller.webViewIfLoaded?.title ?? "New Tab",
			existingController: peek.controller
		)
		configure(tab)
		tabs.append(tab)
		reconcileWorkspace()
		selectTab(tab.id)
		assert(tab.controller === peek.controller)
		assert(tab.controller?.navigationIdentifier == navigationIdentifier)
		if let webView {
			assert(tab.controller?.webViewIfLoaded === webView)
		}
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
		scrollPersistenceTask?.cancel()
		scrollPersistenceTask = nil
		pendingFullPersistence = true
		persist()
	}

	func flushAndWaitForPersistence() async {
		flushPersistence()
		await session.persistenceWriteTask?.value
	}

	func markCleanShutdown() async {
		guard !isPrivate, let persistence else { return }
		await session.persistenceWriteTask?.value
		do {
			try await Task.detached(priority: .utility) {
				try persistence.saveShutdownMetadata(clean: true)
			}.value
		} catch {
			persistenceErrorDescription = error.localizedDescription
		}
	}

	private static func migratedHistory(_ tabs: [OpenTab]) -> [BrowserVisit] {
		var seen = Set<URL>()
		return tabs.sorted { $0.modifiedAt > $1.modifiedAt }.flatMap { tab in
			(tab.history + (tab.url.map { [$0] } ?? [])).reversed().compactMap { url in
				guard let safeURL = BrowserVisit.normalizedURL(url),
				      seen.insert(safeURL).inserted else { return nil }
				return BrowserVisit(
					url: safeURL,
					title: url == tab.url ? tab.pageTitle : safeURL.host ?? safeURL.absoluteString,
					visitedAt: tab.modifiedAt,
					modifiedAt: .distantPast
				)
			}
		}
	}

	private func recordHistoryVisit(from controller: BrowserController, url: URL, title: String, navigationID: Int) {
		guard !isPrivate, !isMini, ownsHistoryController(controller), controller.canRecordVisit,
		      let safeURL = BrowserVisit.normalizedURL(url) else { return }
		if BrowserVisit.matchesRecordedVisit(
			url: safeURL,
			navigationID: navigationID,
			lastURL: lastVisitedURL[controller.id],
			lastNavigationID: lastVisitedDocument[controller.id],
			visitID: lastVisitID[controller.id]
		) {
			updateHistoryVisitTitle(from: controller, url: safeURL, title: title, navigationID: navigationID)
			return
		}
		let now = Date.now
		let modifiedAt = nextHistoryMutationDate(after: now)
		let visit = BrowserVisit(url: safeURL, title: title, visitedAt: now, modifiedAt: modifiedAt)
		lastVisitedURL[controller.id] = safeURL
		lastVisitedDocument[controller.id] = navigationID
		lastVisitID[controller.id] = visit.id
		historyVisits.insert(visit, at: 0)
		applyHistoryRetention()
		schedulePersistence()
	}

	private func updateHistoryVisitTitle(from controller: BrowserController, url: URL, title: String, navigationID: Int) {
		guard ownsHistoryController(controller),
		      lastVisitedURL[controller.id] == url,
		      lastVisitedDocument[controller.id] == navigationID,
		      let id = lastVisitID[controller.id],
		      let index = historyVisits.firstIndex(where: { $0.id == id }) else { return }
		var visit = historyVisits[index]
		visit.updateTitle(title, at: nextHistoryMutationDate(after: .now))
		historyVisits[index] = visit
		schedulePersistence()
	}

	private func ownsHistoryController(_ controller: BrowserController) -> Bool {
		guard controller.session === session else { return false }
		return tabs.contains { tab in
			tab.controller === controller || tab.peeks.contains { $0.controller === controller }
		}
	}

	private func nextHistoryMutationDate(after date: Date) -> Date {
		let latest = ([historyClearedAt] + Array(deletedVisitsAt.values) + historyVisits.map(\.modifiedAt)).max() ?? .distantPast
		return date > latest ? date : latest.addingTimeInterval(0.001)
	}

	private func visibleHistoryVisits(_ visits: [BrowserVisit]) -> [BrowserVisit] {
		var seenIDs = Set<UUID>()
		return visits.compactMap { source in
			guard let url = BrowserVisit.normalizedURL(source.url),
			      (historyClearedAt == .distantPast || source.modifiedAt > historyClearedAt),
			      deletedVisitsAt[source.id].map({ source.modifiedAt > $0 }) ?? true,
			      seenIDs.insert(source.id).inserted else { return nil }
			var visit = source
			visit.url = url
			return visit
		}
	}

	func applyHistoryRetention() {
		guard !isPrivate else { return }
		let retained = BrowserVisit.retained(historyVisits, days: Defaults[.historyRetentionDays])
		guard retained != historyVisits else { return }
		let retainedIDs = Set(retained.map(\.id))
		removeHistory(Set(historyVisits.map(\.id)).subtracting(retainedIDs))
	}

	func clearHistory() {
		guard !isPrivate, !isMini else { return }
		let peers = BrowserWindowRegistry.shared.openBrowsers.filter {
			$0 !== self && $0.session === session && !$0.isPrivate && !$0.isMini
		}
		let latestPeerDate = peers.flatMap { browser in
			[browser.historyClearedAt] + Array(browser.deletedVisitsAt.values) + browser.historyVisits.map(\.modifiedAt)
		}.max() ?? .distantPast
		let clearDate = max(nextHistoryMutationDate(after: .now), latestPeerDate.addingTimeInterval(0.001))
		for browser in [self] + peers {
			browser.clearLocalHistory(at: clearDate)
		}
		schedulePersistence()
	}

	private func clearLocalHistory(at date: Date) {
		historyVisits.removeAll()
		historyClearedAt = date
		deletedVisitsAt.removeAll()
		lastVisitID.removeAll()
		lastVisitedURL.removeAll()
		lastVisitedDocument.removeAll()
		closedHistoryTabs.removeAll()
		for tab in tabs {
			tab.clearRecordedHistory()
		}
		historyVisits.removeAll()
	}

	func removeHistory(_ ids: Set<UUID>) {
		guard !isPrivate, !isMini else { return }
		let peers = BrowserWindowRegistry.shared.openBrowsers.filter {
			$0 !== self && $0.session === session && !$0.isPrivate && !$0.isMini
		}
		let browsers = [self] + peers
		let removedIDs = Set(browsers.flatMap { $0.historyVisits.map(\.id) }).intersection(ids)
		guard !removedIDs.isEmpty else { return }
		let latestPeerDate = peers.flatMap { browser in
			[browser.historyClearedAt] + Array(browser.deletedVisitsAt.values)
				+ browser.historyVisits.filter { removedIDs.contains($0.id) }.map(\.modifiedAt)
		}.max() ?? .distantPast
		let deletionDate = max(nextHistoryMutationDate(after: .now), latestPeerDate.addingTimeInterval(0.001))
		for browser in browsers {
			browser.removeHistoryLocally(removedIDs, at: deletionDate)
		}
		schedulePersistence()
	}

	func removeHistory(from start: Date?, until end: Date?) {
		guard !isPrivate, !isMini else { return }
		let peers = BrowserWindowRegistry.shared.openBrowsers.filter {
			$0 !== self && $0.session === session && !$0.isPrivate && !$0.isMini
		}
		let ids = Set(([self] + peers).flatMap {
			BrowserVisit.inRange($0.historyVisits, from: start, until: end).map(\.id)
		})
		removeHistory(ids)
	}

	func removeHistory(for url: URL) {
		guard let safeURL = BrowserVisit.normalizedURL(url) else { return }
		let peers = BrowserWindowRegistry.shared.openBrowsers.filter {
			$0 !== self && $0.session === session && !$0.isPrivate && !$0.isMini
		}
		let ids = Set(([self] + peers).flatMap { browser in
			browser.historyVisits.filter { $0.url == safeURL }.map(\.id)
		})
		removeHistory(ids)
	}

	private func removeHistoryLocally(_ ids: Set<UUID>, at date: Date) {
		historyVisits.removeAll { ids.contains($0.id) }
		for id in ids { deletedVisitsAt[id] = date }
		removeHistoryVisitReferences(ids)
		schedulePersistence()
	}

	private func removeHistoryVisitReferences(_ ids: Set<UUID>) {
		for (controllerID, visitID) in Array(lastVisitID) where ids.contains(visitID) {
			lastVisitID.removeValue(forKey: controllerID)
			lastVisitedURL.removeValue(forKey: controllerID)
			lastVisitedDocument.removeValue(forKey: controllerID)
		}
	}

	func importBookmarks(_ incoming: [Bookmark]) {
		guard !isPrivate else { return }
		var existing = Set(bookmarks.map(\.url))
		for bookmark in incoming where ["http", "https", "file"].contains(bookmark.url.scheme?.lowercased() ?? "") {
			guard existing.insert(bookmark.url).inserted else { continue }
			bookmarks.append(Bookmark(name: bookmark.name, url: BrowserAddress.withoutCredentials(bookmark.url), modifiedAt: bookmark.modifiedAt))
		}
		schedulePersistence()
	}

	func importHistory(_ incoming: [BrowserVisit]) {
		guard !isPrivate else { return }
		var existing = Set(historyVisits.map(\.url))
		var existingIDs = Set(historyVisits.map(\.id))
		for source in incoming {
			guard var visit = visibleHistoryVisits([source]).first else { continue }
			guard existing.insert(visit.url).inserted, existingIDs.insert(visit.id).inserted else { continue }
			visit.modifiedAt = nextHistoryMutationDate(after: .now)
			historyVisits.append(visit)
		}
		historyVisits.sort { $0.visitedAt > $1.visitedAt }
		schedulePersistence()
	}

	private func attachPersistence(to tab: BrowserTab) {
		tab.didChange = { [weak self] in
			self?.schedulePersistence()
		}
		tab.didRecordHistoryVisit = { [weak self] controller, url, title, navigationID in
			self?.recordHistoryVisit(from: controller, url: url, title: title, navigationID: navigationID)
		}
		tab.didUpdateHistoryVisitTitle = { [weak self] controller, url, title, navigationID in
			self?.updateHistoryVisitTitle(from: controller, url: url, title: title, navigationID: navigationID)
		}
		tab.didScrollChange = { [weak self] in
			self?.scheduleScrollPersistence()
		}
	}

	private func configure(_ tab: BrowserTab) {
		attachPersistence(to: tab)
		guard let controller = tab.controller else { return }
		controller.pictureInPictureRestoreRequested = { [weak self, weak tab, weak controller] in
			guard let self, let tab, let controller else { return }
			selectTab(tab.id)
			tab.showPictureInPictureController(controller)
			#if os(macOS)
				controller.webViewIfLoaded?.window?.makeKeyAndOrderFront(nil)
				NSApp.activate(ignoringOtherApps: true)
			#endif
		}
		controller.promptOwnership = { [weak self, weak tab, weak controller] webView in
			guard let self, let tab, let controller,
			      tabs.contains(where: { $0 === tab }),
			      selectedTabID == tab.id,
			      tab.activeController === controller else { return false }
			return webView.window != nil
		}
		controller.navigationIntercept = navigationIntercept
		controller.extensionStateDidChange = { [weak self] in
			guard let self else { return }
			BrowserExtensionManager.shared.sync(self)
		}
		controller.extensionWebViewDidChange = { [weak self, id = tab.id] in
			guard let self else { return }
			BrowserExtensionManager.shared.webViewDidChange(for: id, in: self)
		}
		controller.popupRequested = { [weak self, weak tab, weak controller] configuration, source, inBackground in
			guard let self, let tab, let controller else { return nil }
			return createPopup(configuration: configuration, source: source, in: tab, depth: 1, parentZoom: controller.pageZoom, inBackground: inBackground)
		}
		controller.newTabRequested = { [weak self, weak controller] request, inBackground in
			guard let self else { return }
			if isMini {
				controller?.navigate(request)
			} else {
				openNewTab(request, inBackground: inBackground)
			}
		}
		controller.closeRequested = { [weak self, weak tab] in
			guard let tab else { return }
			self?.closeTab(tab.id)
		}
		controller.escapeRequested = { [weak tab] in
			tab?.requestPeekDismissal()
		}
		controller.newWindowRequested = { [weak self, weak controller, weak tab] url, source in
			guard let self, let controller, let tab else { return }
			if isMini {
				controller.load(url)
				return
			}
			if isPrivate || Defaults[.peekLevel] == .none {
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
			zoomsOut: Defaults[.zoomOutInPeeks],
			session: session
		)
		configure(peek, in: tab)
		tab.addPeek(peek)
	}

	private func configure(_ peek: BrowserPeek, in tab: BrowserTab) {
		peek.controller.pictureInPictureRestoreRequested = { [weak self, weak tab, weak controller = peek.controller] in
			guard let self, let tab, let controller else { return }
			selectTab(tab.id)
			tab.showPictureInPictureController(controller)
			#if os(macOS)
				controller.webViewIfLoaded?.window?.makeKeyAndOrderFront(nil)
				NSApp.activate(ignoringOtherApps: true)
			#endif
		}
		peek.controller.promptOwnership = { [weak self, weak tab, weak controller = peek.controller] webView in
			guard let self, let tab, let controller,
			      tabs.contains(where: { $0 === tab }),
			      selectedTabID == tab.id,
			      tab.activeController === controller else { return false }
			return webView.window != nil
		}
		peek.controller.navigationIntercept = navigationIntercept
		peek.controller.popupRequested = { [weak self, weak tab, weak peek] configuration, source, inBackground in
			guard let self, let tab, let peek else { return nil }
			return createPopup(configuration: configuration, source: source, in: tab, depth: peek.depth + 1, parentZoom: peek.controller.pageZoom, inBackground: inBackground)
		}
		peek.controller.newTabRequested = { [weak self] request, inBackground in
			self?.openNewTab(request, inBackground: inBackground)
		}
		peek.controller.closeRequested = { [weak tab, id = peek.id] in
			tab?.dismissPeek(id)
		}
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

	private func createPopup(
		configuration: WKWebViewConfiguration,
		source: UnitPoint,
		in tab: BrowserTab,
		depth: Int,
		parentZoom: Double,
		inBackground: Bool?
	) -> WKWebView {
		let popup = BrowserController(session: session, configuration: configuration)
		#if os(macOS)
			popup.previewSnapshotRefreshSuspended = inBackground == true
		#endif
		if inBackground == nil, !isPrivate, !isMini,
		   depth <= Defaults[.peekLevel].maximumDepth,
		   depth == tab.peeks.count + 1
		{
			let peek = BrowserPeek(
				depth: depth,
				source: source,
				parentZoom: parentZoom,
				zoomsOut: Defaults[.zoomOutInPeeks],
				session: session,
				existingController: popup
			)
			configure(peek, in: tab)
			tab.addPeek(peek)
		} else {
			let popupTab = BrowserTab(existingController: popup, session: session)
			configure(popupTab)
			tabs.append(popupTab)
			reconcileWorkspace()
			markWorkspaceStructureChanged()
			if inBackground == true {
				schedulePersistence(fullState: true)
			} else {
				selectTab(popupTab.id)
			}
		}
		return popup.webView
	}

	private func openNewTab(_ url: URL) {
		openNewTab(URLRequest(url: url), inBackground: false)
	}

	private func openNewTab(_ request: URLRequest, inBackground: Bool) {
		let tab = addTab(inBackground: inBackground)
		#if os(macOS)
			tab.controller?.previewSnapshotRefreshSuspended = inBackground
		#endif
		tab.controller?.navigate(request)
		tab.controller?.prepareWebView()
	}

	private func removeTabs(_ ids: Set<UUID>, selecting selectedID: UUID, confirmed: Bool = false) {
		let protectedIDs = Set(workspace.favouriteTabIDs + workspace.spaces.flatMap(\.pinnedTabIDs))
		let ids = ids.subtracting(protectedIDs)
		guard !ids.isEmpty else { return }
		let removedTabs = tabs.filter { ids.contains($0.id) }
		guard !removedTabs.isEmpty else { return }
		let previousSelectionID = selectedTabID
		let fallbackSelectionID = BrowserWorkspace.tabSelectionAfterClosing(
			tabID: previousSelectionID,
			normalTabIDs: normalTabs.map(\.id),
			visibleTabIDs: visibleTabs.map(\.id)
		)
		#if os(iOS)
			let controllers = removedTabs.flatMap { tab in
				[tab.controller].compactMap { $0 } + tab.peeks.map(\.controller)
			}
			let protectedController = controllers.first(where: \.requiresMediaTeardownConfirmation)
			if !confirmed, let protectedController, let webView = protectedController.webViewIfLoaded {
				Task { @MainActor [weak self] in
					let result = await BrowserWebsiteUI.javascriptDialog(
						title: "Close tabs?",
						message: "Closing these tabs will stop media playback.",
						confirmTitle: "Close Tabs",
						cancelTitle: "Cancel",
						in: webView
					) { [weak self] in
						self?.tabs.contains(where: { ids.contains($0.id) }) == true
					}
					if result.confirmed {
						self?.removeTabs(ids, selecting: selectedID, confirmed: true)
					}
				}
				return
			}
			if !confirmed && removedTabs.contains(where: { tab in
				tab.controller?.requiresMediaTeardownConfirmation == true
					|| tab.peeks.contains { $0.controller.requiresMediaTeardownConfirmation }
			}) { return }
		#endif
		#if os(macOS)
			let hasUnsavedChanges = removedTabs.contains { tab in
				tab.controller?.hasUnsavedChanges == true || tab.peeks.contains { $0.controller.hasUnsavedChanges }
			}
			let hasProtectedMedia = removedTabs.contains { tab in
				tab.controller?.requiresMediaTeardownConfirmation == true
					|| tab.peeks.contains { $0.controller.requiresMediaTeardownConfirmation }
			}
			if !confirmed, hasUnsavedChanges || hasProtectedMedia {
				Task { @MainActor [weak self] in
					let message = hasUnsavedChanges && hasProtectedMedia
						? "Some tabs contain unsaved changes or media playback that will stop."
						: hasUnsavedChanges ? "Some tabs contain changes that may not be saved." : "Closing these tabs will stop media playback."
					let alert = BrowserWebsiteUI.alert(title: "Close these tabs?", message: message, confirm: "Close Tabs")
					if await BrowserWebsiteUI.present(alert, in: NSApp.keyWindow) == .alertFirstButtonReturn {
						self?.removeTabs(ids, selecting: selectedID, confirmed: true)
					}
				}
				return
			}
		#endif
		archiveHistory(of: removedTabs)
		let closedWebIDs = Set(removedTabs.filter { isSyncableTab($0.openTab) }.map(\.id))
		releaseAfterTabUpdate(removedTabs)
		tabs.removeAll { ids.contains($0.id) }
		closedTabIDs.formUnion(closedWebIDs)
		for id in closedWebIDs {
			closedTabsAt[id] = .now
		}
		for index in workspace.spaces.indices where workspace.spaces[index].tabIDs.contains(where: ids.contains) {
			workspace.spaces[index].modifiedAt = .now
		}
		workspace.modifiedAt = .now
		recentlyUsedTabIDs.removeAll { ids.contains($0) }
		guard !tabs.isEmpty else {
			addTab()
			return
		}
		selectedTabID = if tabs.contains(where: { $0.id == selectedID }) {
			selectedID
		} else if tabs.contains(where: { $0.id == previousSelectionID }) {
			previousSelectionID
		} else if let fallbackSelectionID, tabs.contains(where: { $0.id == fallbackSelectionID }) {
			fallbackSelectionID
		} else {
			tabs[0].id
		}
		selectTab(selectedTabID)
		reconcileWorkspace()
		schedulePersistence()
	}

	private func releaseAfterTabUpdate(_ removedTabs: [BrowserTab]) {
		// ponytail: Give the tab UI time to update before WebKit teardown; use explicit lifecycle control if teardown still stalls.
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(100))
			for tab in removedTabs {
				tab.stopForClose()
			}
		}
	}

	private func archiveHistory(of removedTabs: [BrowserTab]) {
		let snapshots = removedTabs.filter { $0.internalPage == nil }
			.map { tab in
				var snapshot = tab.openTab
				snapshot.modifiedAt = .now
				if let space = workspace.spaces.first(where: { $0.tabIDs.contains(tab.id) }) {
					snapshot.closedSpaceID = space.id
					snapshot.closedNormalIndex = space.tabIDs
						.filter { !space.pinnedTabIDs.contains($0) }
						.firstIndex(of: tab.id)
				}
				return snapshot
			}
		closedHistoryTabs.insert(contentsOf: snapshots, at: 0)
	}

	func syncDocument(settings: [String: SyncedSetting]) -> BrowserSyncDocument {
		reconcileWorkspace()
		return completeLocalSyncDocument(settings: settings).portableProjection()
	}

	private func completeLocalSyncDocument(settings: [String: SyncedSetting]) -> BrowserSyncDocument {
		BrowserSyncDocument(
			tabs: tabs.map(\.openTab),
			workspace: workspace,
			bookmarks: bookmarks,
			history: historyVisits,
			browser: BrowserSnapshot(
				selectedTabID: persistedSelectedTabID,
				selectedTabModifiedAt: selectedTabModifiedAt,
				closedTabIDs: closedTabIDs,
				deletedBookmarkIDs: deletedBookmarkIDs,
				deletedBookmarksAt: deletedBookmarksAt,
				closedTabsAt: closedTabsAt,
				deletedSpacesAt: deletedSpacesAt,
				deletedVisitsAt: deletedVisitsAt,
				historyClearedAt: historyClearedAt
			),
			settings: settings
		)
	}

	func applySyncDocument(_ incoming: BrowserSyncDocument) {
		guard !isPrivate else { return }
		let localState = completeLocalSyncDocument(settings: [:])
		let localPortableTabs = Dictionary(
			localState.portableProjection().tabs.map { ($0.id, $0) },
			uniquingKeysWith: { _, latest in latest }
		)
		let document = incoming.preservingLocalOnlyData(from: localState)
		let currentTabs = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
		let changedTabs = document.tabs.compactMap { saved -> BrowserTab? in
			let internalPage = saved.internalPage.flatMap(BrowserInternalPage.init(persistenceID:))
			guard saved.internalPage == nil || internalPage != nil else { return nil }
			if let current = currentTabs[saved.id] {
				if localPortableTabs[saved.id] == saved
					|| current.modifiedAt > saved.modifiedAt
					|| !current.canHibernate
				{
					return current
				}
				if current.currentURL.map(BrowserAddress.withoutCredentials) == saved.url {
					current.applySynchronizedMetadata(from: saved)
					return current
				}
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
				modifiedAt: saved.modifiedAt,
				recordsNavigationHistory: saved.recordsNavigationHistory,
				restorationState: saved.restorationState,
				fileAccessBookmark: saved.fileAccessBookmark,
				suppressInitialHistoryVisit: true
			)
			configure(tab)
			return tab
		}
		let changedTabIDs = Set(changedTabs.map(\.id))
		let retainedInternalTabs = tabs.filter {
			$0.internalPage != nil && !changedTabIDs.contains($0.id)
		}
		if changedTabs.isEmpty, retainedInternalTabs.isEmpty {
			let tab = BrowserTab(session: session)
			configure(tab)
			tabs = [tab]
		} else {
			tabs = changedTabs + retainedInternalTabs
		}
		assert(Set(tabs.map(\.id)).count == tabs.count)
		closedTabIDs = document.browser.closedTabIDs
		if document.browser.selectedTabModifiedAt > selectedTabModifiedAt {
			selectedTabID = document.browser.selectedTabID
			selectedTabModifiedAt = document.browser.selectedTabModifiedAt
		}
		deletedBookmarkIDs = document.browser.deletedBookmarkIDs
		closedTabsAt = document.browser.closedTabsAt
		deletedBookmarksAt = document.browser.deletedBookmarksAt
		deletedSpacesAt = document.browser.deletedSpacesAt
		deletedVisitsAt = document.browser.deletedVisitsAt
		historyClearedAt = document.browser.historyClearedAt
		bookmarks = document.bookmarks
		historyVisits = visibleHistoryVisits(document.history)
		workspace = document.workspace ?? BrowserWorkspace.migrated(
			tabs: document.tabs,
			selectedTabID: document.browser.selectedTabID,
			theme: Defaults[.browserTheme]
		)
		workspace.deletedSpaceIDs.formUnion(document.browser.deletedSpacesAt.keys)
		workspace.deletedSpacesAt.merge(document.browser.deletedSpacesAt) { max($0, $1) }
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
		guard !isPrivate, !source.isPrivate else { return }
		persistenceTask?.cancel()
		persistenceTask = nil

		let selectedTabBeforeMerge = selectedTabID
		let selectedTabDateBeforeMerge = selectedTabModifiedAt
		let selectedSpaceBeforeMerge = workspace.selectedSpaceID
		let selectionDateBeforeMerge = workspace.selectionModifiedAt
		let selectedTabsBySpace = Dictionary(uniqueKeysWithValues: workspace.spaces.map { ($0.id, $0.selectedTabID) })
		let recentlyUsedBeforeMerge = recentlyUsedTabIDs
		let closedHistoryBeforeMerge = closedHistoryTabs
		var localState = completeLocalSyncDocument(settings: [:])
		var incomingState = source.completeLocalSyncDocument(settings: [:])
		localState.browser.selectedTabID = selectedTabBeforeMerge
		localState.browser.selectedTabModifiedAt = selectedTabDateBeforeMerge
		incomingState.browser.selectedTabID = selectedTabBeforeMerge
		incomingState.browser.selectedTabModifiedAt = selectedTabDateBeforeMerge
		if var localWorkspace = localState.workspace {
			localWorkspace.selectedSpaceID = selectedSpaceBeforeMerge
			localWorkspace.selectionModifiedAt = selectionDateBeforeMerge
			for index in localWorkspace.spaces.indices {
				if let selectedID = selectedTabsBySpace[localWorkspace.spaces[index].id] ?? nil {
					localWorkspace.spaces[index].selectedTabID = selectedID
				}
			}
			localState.workspace = localWorkspace
		}
		if var sourceWorkspace = incomingState.workspace {
			sourceWorkspace.selectedSpaceID = selectedSpaceBeforeMerge
			sourceWorkspace.selectionModifiedAt = selectionDateBeforeMerge
			for index in sourceWorkspace.spaces.indices {
				if let selectedID = selectedTabsBySpace[sourceWorkspace.spaces[index].id] ?? nil {
					sourceWorkspace.spaces[index].selectedTabID = selectedID
				}
			}
			incomingState.workspace = sourceWorkspace
		}
		var merged = localState.merging(incomingState)
		merged = merged.preservingLocalOnlyData(from: localState)
		applySyncDocument(merged)
		closedHistoryTabs = Dictionary(
			(closedHistoryBeforeMerge + source.closedHistoryTabs).map { ($0.id, $0) },
			uniquingKeysWith: { current, incoming in
				if current.modifiedAt != incoming.modifiedAt {
					return current.modifiedAt > incoming.modifiedAt ? current : incoming
				}
				let encoder = JSONEncoder()
				encoder.outputFormatting = [.sortedKeys]
				let currentData = (try? encoder.encode(current)) ?? Data()
				let incomingData = (try? encoder.encode(incoming)) ?? Data()
				return currentData.lexicographicallyPrecedes(incomingData) ? incoming : current
			}
		).values
			.filter { saved in
				!tabs.contains(where: { $0.id == saved.id })
					&& (historyClearedAt == .distantPast || saved.modifiedAt > historyClearedAt)
			}
			.sorted {
				$0.modifiedAt == $1.modifiedAt
					? $0.id.uuidString < $1.id.uuidString
					: $0.modifiedAt > $1.modifiedAt
			}

		if tabs.contains(where: { $0.id == selectedTabBeforeMerge }) {
			selectedTabID = selectedTabBeforeMerge
			selectedTabModifiedAt = selectedTabDateBeforeMerge
		}
		if workspace.spaces.contains(where: { $0.id == selectedSpaceBeforeMerge }) {
			workspace.selectedSpaceID = selectedSpaceBeforeMerge
			workspace.selectionModifiedAt = selectionDateBeforeMerge
		}
		for index in workspace.spaces.indices {
			if let selectedID = selectedTabsBySpace[workspace.spaces[index].id] ?? nil,
				workspace.spaces[index].tabIDs.contains(selectedID) || workspace.favouriteTabIDs.contains(selectedID)
			{
				workspace.spaces[index].selectedTabID = selectedID
			}
		}
		recentlyUsedTabIDs = recentlyUsedBeforeMerge.filter { id in tabs.contains { $0.id == id } }
		if !recentlyUsedTabIDs.contains(selectedTabID) {
			recentlyUsedTabIDs.insert(selectedTabID, at: 0)
		}
		reconcileWorkspace()
		schedulePersistence()
	}

	private func markWorkspaceStructureChanged() {
		let mutationDate = nextWorkspaceMutationDate()
		workspace.modifiedAt = mutationDate
		if let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }) {
			workspace.spaces[index].modifiedAt = mutationDate
		}
	}

	private func nextWorkspaceMutationDate() -> Date {
		let spaceDates = workspace.spaces.flatMap { space in
			[space.modifiedAt] + space.pinnedFolders.map(\.modifiedAt)
		}
		let latest = ([workspace.modifiedAt, workspace.favouritesModifiedAt, workspace.selectionModifiedAt, selectedTabModifiedAt] + spaceDates).max()
			?? .distantPast
		let now = Date.now
		return now > latest ? now : latest.addingTimeInterval(0.001)
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
		let assignedIDs = Set(workspace.favouriteTabIDs + workspace.spaces.flatMap(\.tabIDs))
		let unassignedIDs = tabs.map(\.id).filter { !assignedIDs.contains($0) }
		workspace.reconcileMembership(existingTabIDs: existingIDs, unassignedTabIDs: unassignedIDs)
		if let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }),
		   workspace.spaces[index].tabIDs.contains(selectedTabID)
			|| workspace.favouriteTabIDs.contains(selectedTabID)
		{
			workspace.spaces[index].selectedTabID = selectedTabID
		}
	}

	private func schedulePersistence(fullState: Bool = true) {
		guard !isPrivate else { return }
		BrowserExtensionManager.shared.sync(self)
		guard persistence != nil else { return }
		if fullState {
			pendingFullPersistence = true
		}
		guard didFinishHydration else { return }
		let isFull = pendingFullPersistence
		persistenceTask?.cancel()
		persistenceTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(isFull ? 300 : 150))
			guard !Task.isCancelled, let self else { return }
			persist()
		}
	}

	private func schedulePersistence() {
		schedulePersistence(fullState: true)
	}

	private func scheduleSelectionPersistence() {
		schedulePersistence(fullState: false)
	}

	private func scheduleScrollPersistence() {
		guard persistence != nil else { return }
		pendingScrollPersistence = true
		guard didFinishHydration else { return }
		scrollPersistenceTask?.cancel()
		scrollPersistenceTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(1500))
			guard !Task.isCancelled, let self else { return }
			persist()
		}
	}

	private func persist() {
		guard !hydrationFailed else { return }
		guard let persistence else { return }
		guard didFinishHydration else {
			pendingFullPersistence = true
			return
		}
		reconcileWorkspace()
		let isStructural = pendingFullPersistence
		pendingFullPersistence = false
		pendingScrollPersistence = false
		let state = BrowserPersistedState(
			bookmarks: bookmarks,
			openTabs: tabs.map(\.openTab),
			closedTabs: closedHistoryTabs,
			workspace: workspace,
				snapshot: BrowserSnapshot(
				selectedTabID: selectedTabID,
				selectedTabModifiedAt: selectedTabModifiedAt,
				closedTabIDs: closedTabIDs,
				deletedBookmarkIDs: deletedBookmarkIDs,
				deletedBookmarksAt: deletedBookmarksAt,
				closedTabsAt: closedTabsAt,
				deletedSpacesAt: deletedSpacesAt,
				deletedVisitsAt: deletedVisitsAt,
				historyClearedAt: historyClearedAt
			),
			historyVisits: historyVisits,
			windowRecords: [BrowserWindowRecord(
				windowID: windowID,
				tabIDs: tabs.map(\.id),
				selectedTabID: selectedTabID
			)]
		)
		// Encode + file IO off-main so Cmd+T / history-open stay instant.
		// Scroll-only saves skip cross-window fan-out and sync: no structural change.
		let previousWrite = session.persistenceWriteTask
		session.persistenceWriteTask = Task.detached(priority: .utility) { [persistence, state] in
			await previousWrite?.value
			do {
				try persistence.savePersistedState(state)
				await MainActor.run { [weak self] in
					guard let self else { return }
					persistenceErrorDescription = nil
					guard isStructural else { return }
					BrowserWindowRegistry.shared.publishSoon(from: self)
					BrowserSync.shared.scheduleSync()
				}
			} catch {
				let message = error.localizedDescription
				await MainActor.run { [weak self] in
					self?.persistenceErrorDescription = message
				}
			}
		}
	}
}
