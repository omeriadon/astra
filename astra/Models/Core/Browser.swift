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
	private static var launchHydrationTask: Task<HydratedState, Error>?
	let windowID: UUID
	let isMini: Bool
	let session: BrowserWebSession
	private let restorationRecord: BrowserWindowRecord?
	private(set) var savedWindowFrame: BrowserWindowFrame?

	var isPrivate: Bool {
		session.isPrivate
	}

	private(set) var tabs: [BrowserTab] {
		didSet {
			tabLookup = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
			visibleTabMembershipRevision &+= 1
			tabCollectionRevision &+= 1
			tabSearchRevision &+= 1
		}
	}

	@ObservationIgnored
	private var tabLookup: [UUID: BrowserTab] = [:]
	/// Changes only when the tab-object collection is replaced, not on selection.
	private(set) var tabCollectionRevision = 0
	private(set) var selectedTabID: UUID
	private(set) var splitLeftTabID: UUID?
	private(set) var splitRightTabID: UUID?
	/// A compact dependency for consumers that only need to know whether
	/// visible tab membership *might* have changed. Comparing the entire
	/// array of BrowserTab references in each SwiftUI update is unnecessary.
	private(set) var visibleTabMembershipRevision = 0
	@ObservationIgnored private var publishingTabSelection = false
	/// Monotonic token for structural workspace changes, excluding same-space tab selection.
	private(set) var sidebarStructureRevision = 0
	private(set) var workspace: BrowserWorkspace {
		didSet {
			// The frequent, same-space tab-selection path only changes selection
			// metadata. Skip O(total tabs) membership comparisons entirely.
			if publishingTabSelection && oldValue.selectedSpaceID == workspace.selectedSpaceID {
				return
			}
			sidebarStructureRevision &+= 1
			// Selection timestamps and the active tab are not membership changes.
			// Keep the Control-Tab observer dormant for normal tab selections.
			let membershipChanged = oldValue.selectedSpaceID != workspace.selectedSpaceID
				|| oldValue.favouriteTabIDs != workspace.favouriteTabIDs
				|| oldValue.spaces.count != workspace.spaces.count
				|| !zip(oldValue.spaces, workspace.spaces).allSatisfy { old, new in
					old.id == new.id && old.tabIDs == new.tabIDs
						&& old.pinnedTabIDs == new.pinnedTabIDs
				}
			if membershipChanged {
				visibleTabMembershipRevision &+= 1
			}
		}
	}

	private(set) var recentlyUsedTabIDs: [UUID]
	/// A scalar Observation token for library projections. Comparing complete
	/// bookmark and reading-list arrays at every SwiftUI invalidation is O(N).
	private(set) var libraryChangeRevision = 0
	private(set) var bookmarks: [Bookmark] {
		didSet { libraryChangeRevision &+= 1 }
	}

	private(set) var readingList: [ReadingListItem] {
		didSet { libraryChangeRevision &+= 1 }
	}

	/// Lightweight change token so SwiftUI doesn't compare an entire history
	/// array for equality on every new navigation or title update.
	private(set) var historyChangeRevision = 0
	private(set) var historyVisits: [BrowserVisit] {
		didSet {
			recentHistoryCache = nil
			frequentHistoryCache = nil
			historyChangeRevision &+= 1
			historySearch.invalidate(before: historyChangeRevision)
		}
	}

	/// Reuse prepared history on a worker; UI reads only revision/query-matched results.
	let historySearch = BrowserHistorySearchModel()
	let librarySearch = BrowserLibrarySearchModel()
	private(set) var tabSearchRevision = 0
	@ObservationIgnored private var recentHistoryCache: (revision: Int, value: [BrowserVisit])?
	@ObservationIgnored private var frequentHistoryCache: (revision: Int, value: [BrowserVisitSummary])?
	/// Lamport-style local watermark for history tombstones, imports and visits.
	/// Computing the maximum across thousands of rows on *every navigation*
	/// made history recording increasingly expensive during long sessions.
	@ObservationIgnored
	private var latestHistoryMutationDate: Date?
	@ObservationIgnored
	private var lastVisitedURL: [UUID: URL] = [:]
	@ObservationIgnored
	private var lastVisitID: [UUID: UUID] = [:]
	@ObservationIgnored
	private var lastVisitedDocument: [UUID: Int] = [:]
	private(set) var closedHistoryTabs: [OpenTab]
	@ObservationIgnored private var pendingClosedRestoration: [UUID: (Data, URL)] = [:]
	private(set) var closedTabIDs: Set<UUID>
	private(set) var deletedBookmarkIDs: Set<UUID>
	private(set) var closedTabsAt: [UUID: Date]
	private(set) var deletedBookmarksAt: [UUID: Date]
	private(set) var deletedReadingListAt: [UUID: Date]
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

	var showsAISidebar = false
	#if !ASTRA_WEBSITE_APP_RUNTIME
		let aiChat = BrowserAIChat()
	#endif
	var isAboutToQuit: Bool = false
	var addressFocusRequest = 0
	var settingsPage: BrowserSettingsView.Page = .ui
	var settingsScrollTarget: String?
	var newTabSearchText = "" {
		didSet {
			guard oldValue != newTabSearchText else { return }
			newTabSearchGeneration &+= 1
			newTabSearchSelection = nil
			newTabGoogleSuggestions = []
			pendingSearchEngineDiscovery = nil
		}
	}

	var showsQuickSearch = false
	var quickSearchFocusRequest = 0
	var newTabSearchSelection: String?
	var newTabClipboardURL: URL?
	var newTabSearchGeneration = 0
	var addressSearchText = "" {
		didSet {
			if oldValue != addressSearchText {
				addressSearchGeneration &+= 1
				addressSuggestionsRequest = nil
				pendingSearchEngineDiscovery = nil
			}
		}
	}

	var addressSearchGeneration = 0
	var addressFieldIsFocused = false
	var newTabGoogleSuggestions: [String] = []
	var addressSuggestionsRequest: BrowserSearchSuggestionsRequest?
	var pendingSearchEngineDiscovery: BrowserSearchEngineDiscovery?
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

	@ObservationIgnored private(set) var syncRevision: UInt64 = 0
	@ObservationIgnored private var sharedMergeTask: Task<Void, Never>?
	private static var persistenceRevision: UInt64 = 0

	@ObservationIgnored
	private let persistence: BrowserPersistence?

	@ObservationIgnored
	private var persistenceTask: Task<Void, Never>?

	@ObservationIgnored
	private var pendingFullPersistence = false

	@ObservationIgnored
	private var scrollPersistenceTask: Task<Void, Never>?

	@ObservationIgnored
	private var automaticHibernationManager: BrowserHibernationManager?
	/// The controller retention policy is isolated from the SwiftUI stack.
	/// It is lazily initialized only when a window displays WebKit content.
	@ObservationIgnored
	lazy var tabResources = BrowserTabResourceManager(browser: self)

	@ObservationIgnored
	private var pendingScrollPersistence = false
	@ObservationIgnored
	private var pendingScrollTabIDs = Set<UUID>()

	/// False until disk hydration completes; persistence calls before then only
	/// stash flags so a placeholder window never saves or broadcasts itself.
	@ObservationIgnored
	private var didFinishHydration = true
	var isReadyForSync: Bool {
		didFinishHydration && !hydrationFailed && persistence != nil
	}

	var isHydrationFinished: Bool {
		didFinishHydration
	}

	@ObservationIgnored
	private var hydrationFailed = false
	@ObservationIgnored
	private var launchCacheSelectedTabID: UUID?
	@ObservationIgnored
	private var launchCacheSeeded = false
	@ObservationIgnored
	private var launchCacheWasModified = false

	/// O(1) tab lookup for sidebar/history/rendering hot paths.
	/// The dictionary is rebuilt only when the tab array itself changes.
	var tabsByID: [UUID: BrowserTab] {
		if tabLookup.count != tabs.count {
			tabLookup = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
		}
		return tabLookup
	}

	var recentHistoryVisits: [BrowserVisit] {
		// Reading the revision preserves SwiftUI Observation dependencies
		// without sorting a large history collection on every body evaluation.
		let revision = historyChangeRevision
		if let cache = recentHistoryCache, cache.revision == revision {
			return cache.value
		}
		let result = historyVisits.sorted {
			$0.visitedAt == $1.visitedAt
				? $0.id.uuidString < $1.id.uuidString
				: $0.visitedAt > $1.visitedAt
		}
		recentHistoryCache = (revision, result)
		return result
	}

	var frequentHistory: [BrowserVisitSummary] {
		let revision = historyChangeRevision
		if let cache = frequentHistoryCache, cache.revision == revision {
			return cache.value
		}
		let result = BrowserVisit.summaries(historyVisits, sortByRecency: false).sorted {
			if $0.visitCount != $1.visitCount {
				return $0.visitCount > $1.visitCount
			}
			if $0.lastVisitedAt != $1.lastVisitedAt {
				return $0.lastVisitedAt > $1.lastVisitedAt
			}
			return $0.url.absoluteString < $1.url.absoluteString
		}
		frequentHistoryCache = (revision, result)
		return result
	}

	func tab(withID id: UUID) -> BrowserTab? {
		tabsByID[id]
	}

	var selectedTab: BrowserTab? {
		tabsByID[selectedTabID]
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
		BrowserLog.info(.spaces, "space.create", metadata: ["window": BrowserLog.id(windowID), "existing": String(workspace.spaces.count)])
		guard !isPrivate else { return }
		let space = makeRandomSpace()
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces.append(space)
		workspace.selectedSpaceID = space.id
		workspace.modifiedAt = mutationDate
		workspace.selectionModifiedAt = mutationDate
		openInternalPage(.themeEditor)
		schedulePersistence()
	}

	/// New spaces receive their own editable appearance rather than inheriting the
	/// default blue/grey theme. Existing spaces are never re-randomised.
	private func makeRandomSpace() -> BrowserSpace {
		let palettes: [(primary: BrowserColor, accent: BrowserColor)] = [
			(.init(red: 0.98, green: 0.68, blue: 0.66), .init(red: 0.91, green: 0.28, blue: 0.47)),
			(.init(red: 0.78, green: 0.27, blue: 0.20), .init(red: 1.00, green: 0.62, blue: 0.33)),
			(.init(red: 1.00, green: 0.58, blue: 0.25), .init(red: 0.94, green: 0.83, blue: 0.48)),
			(.init(red: 0.96, green: 0.83, blue: 0.44), .init(red: 0.87, green: 0.54, blue: 0.29)),
			(.init(red: 0.75, green: 0.89, blue: 0.44), .init(red: 0.35, green: 0.64, blue: 0.32)),
			(.init(red: 0.18, green: 0.49, blue: 0.39), .init(red: 0.54, green: 0.80, blue: 0.61)),
			(.init(red: 0.54, green: 0.88, blue: 0.76), .init(red: 0.17, green: 0.62, blue: 0.67)),
			(.init(red: 0.18, green: 0.61, blue: 0.66), .init(red: 0.14, green: 0.35, blue: 0.57)),
			(.init(red: 0.38, green: 0.55, blue: 0.88), .init(red: 0.65, green: 0.78, blue: 0.97)),
			(.init(red: 0.66, green: 0.63, blue: 0.97), .init(red: 0.39, green: 0.34, blue: 0.76)),
			(.init(red: 0.53, green: 0.28, blue: 0.73), .init(red: 0.83, green: 0.57, blue: 0.91)),
			(.init(red: 0.88, green: 0.46, blue: 0.78), .init(red: 0.60, green: 0.29, blue: 0.64)),
			(.init(red: 0.83, green: 0.24, blue: 0.45), .init(red: 1.00, green: 0.64, blue: 0.65)),
			(.init(red: 0.31, green: 0.43, blue: 0.57), .init(red: 0.66, green: 0.73, blue: 0.81)),
			(.init(red: 0.22, green: 0.33, blue: 0.69), .init(red: 0.41, green: 0.69, blue: 0.92)),
			(.init(red: 0.43, green: 0.30, blue: 0.30), .init(red: 0.84, green: 0.63, blue: 0.48)),
		]
		// Prefer a visibly different palette from every existing space.
		let distinctPalettes = palettes.filter { palette in
			!workspace.spaces.contains { existing in
				let color = existing.theme.meshColorPoints.first?.color ?? existing.theme.firstColor
				let red = palette.primary.red - color.red
				let green = palette.primary.green - color.green
				let blue = palette.primary.blue - color.blue
				return red * red + green * green + blue * blue < 0.09
			}
		}
		let palette = (distinctPalettes.isEmpty ? palettes : distinctPalettes).randomElement() ?? palettes[0]
		let unusedSymbols = BrowserSpace.symbols.filter { symbol in
			!workspace.spaces.contains { $0.symbol == symbol }
		}
		let symbol = (unusedSymbols.isEmpty ? BrowserSpace.symbols : unusedSymbols).randomElement()
			?? "circle.grid.2x2.fill"

		var theme = BrowserTheme()
		let isGradient = Int.random(in: 0 ... 3) != 0
		theme.usesGradient = isGradient
		theme.firstColor = palette.primary
		theme.secondColor = palette.accent
		theme.gradientDirection = ThemeGradientDirection.allCases.randomElement() ?? .topLeading
		theme.meshOpacity = Double.random(in: 0.58 ... 0.92)
		theme.appearanceMode = Bool.random()
			? .auto
			: (palette.primary.luminance > 0.55 ? .light : .dark)
		theme.meshColorPoints = [
			ThemeColorPoint(
				color: palette.primary,
				x: isGradient ? 0.25 : 0.5,
				y: isGradient ? 0.3 : 0.5
			),
		]
		if isGradient {
			theme.meshColorPoints.append(
				ThemeColorPoint(color: palette.accent, x: 0.75, y: 0.7)
			)
			if Bool.random() {
				let highlight = BrowserColor(
					red: min(1, (palette.primary.red + palette.accent.red) / 2 + 0.1),
					green: min(1, (palette.primary.green + palette.accent.green) / 2 + 0.1),
					blue: min(1, (palette.primary.blue + palette.accent.blue) / 2 + 0.1)
				)
				theme.meshColorPoints.append(
					ThemeColorPoint(color: highlight, x: 0.25, y: 0.8)
				)
			}
		}
		return BrowserSpace(symbol: symbol, theme: theme)
	}

	func reorderSpaces(_ ids: [UUID], before destinationID: UUID?) {
		guard !isPrivate,
		      !ids.isEmpty,
		      Set(ids).count == ids.count,
		      Set(ids).isSubset(of: workspace.spaces.map(\.id))
		else { return }
		if let destinationID {
			guard workspace.spaces.contains(where: { $0.id == destinationID }),
			      !ids.contains(destinationID) else { return }
		}

		let movingIDs = Set(ids)
		let moving = workspace.spaces.filter { movingIDs.contains($0.id) }
		let remaining = workspace.spaces.filter { !movingIDs.contains($0.id) }
		let insertionIndex = destinationID.flatMap { destination in
			remaining.firstIndex { $0.id == destination }
		} ?? remaining.endIndex
		var reordered = remaining
		reordered.insert(contentsOf: moving, at: insertionIndex)
		guard reordered.map(\.id) != workspace.spaces.map(\.id) else { return }

		workspace.spaces = reordered
		workspace.modifiedAt = nextWorkspaceMutationDate()
		schedulePersistence()
	}

	/// Deleting internal browser pages alone does not require confirmation.
	/// Any ordinary web tab, pinned tab, or pinned-folder tab does.
	func requiresSpaceDeletionConfirmation(_ id: UUID) -> Bool {
		guard let space = workspace.spaces.first(where: { $0.id == id }) else { return false }
		if !space.pinnedTabIDs.isEmpty || space.pinnedFolders.contains(where: { !$0.tabIDs.isEmpty }) {
			return true
		}
		let lookup = tabsByID
		// Treat unresolved tab IDs conservatively: do not discard their
		// workspace membership without asking.
		return space.tabIDs.contains { lookup[$0]?.internalPage == nil }
	}

	func deleteSpace(_ id: UUID) {
		BrowserLog.info(.spaces, "space.delete", metadata: ["window": BrowserLog.id(windowID), "space": BrowserLog.id(id), "count": String(workspace.spaces.count)])
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
		BrowserLog.debug(.spaces, "space.select", metadata: ["window": BrowserLog.id(windowID), "from": BrowserLog.id(workspace.selectedSpaceID), "to": BrowserLog.id(id)])
		guard id != workspace.selectedSpaceID,
		      let nextIndex = workspace.spaces.firstIndex(where: { $0.id == id }) else { return }
		closeEaselSplit()
		let space = workspace.spaces[nextIndex]
		let targetID: UUID? = {
			if let preferred = space.selectedTabID,
			   space.tabIDs.contains(preferred) || workspace.favouriteTabIDs.contains(preferred)
			{
				return preferred
			}
			return space.tabIDs.first ?? workspace.favouriteTabIDs.first
		}()
		if let targetID {
			// Switch space and tab in one observable workspace mutation.
			// Selection alone does not require a structural extension sync.
			selectTab(targetID, inSpace: id)
		} else {
			// Creating the first tab in an empty space already persists.
			workspace.selectedSpaceID = id
			addTab()
		}
		scheduleSelectionPersistence()
	}

	@discardableResult
	func applyTodayTabGroups(_ groups: [BrowserTabGroupingFeature.Group], in spaceID: UUID, expectedIDs: [UUID]) -> Bool {
		guard !isPrivate, let index = workspace.spaces.firstIndex(where: { $0.id == spaceID }) else { return false }
		let space = workspace.spaces[index]
		let normalIDs = space.tabIDs.filter { !space.pinnedTabIDs.contains($0) }
		guard normalIDs == expectedIDs else { return false }
		// Streaming group suggestions may update repeatedly while the AI
		// response is still arriving. Publish workspace once, then coalesce
		// persistence rather than capturing every tab's WebKit interaction
		// state and rebuilding a full session snapshot for each partial.
		var nextWorkspace = workspace
		nextWorkspace.spaces[index].todayTabGroups = groups
		let mutationDate = nextWorkspaceMutationDate()
		nextWorkspace.spaces[index].modifiedAt = mutationDate
		nextWorkspace.modifiedAt = mutationDate
		workspace = nextWorkspace
		// The grouping changes no extension tab identities or membership.
		schedulePersistence(fullState: true, syncExtensions: false)
		return true
	}

	nonisolated static func filteredTodayTabGroups(_ groups: [BrowserTabGroupingFeature.Group], normalIDs: [UUID]) -> [BrowserTabGroupingFeature.Group] {
		let normalIDSet = Set(normalIDs)
		return groups.compactMap { group in
			let ids = group.tabIDs.filter { normalIDSet.contains($0) }
			return ids.isEmpty ? nil : BrowserTabGroupingFeature.Group(name: group.name, tabIDs: ids)
		}
	}

	@discardableResult
	func pinTodayTabGroupAsFolder(_ groupID: String, in spaceID: UUID) -> Bool {
		guard !isPrivate,
		      let index = workspace.spaces.firstIndex(where: { $0.id == spaceID }),
		      let groupIndex = workspace.spaces[index].todayTabGroups.firstIndex(where: { $0.id == groupID })
		else { return false }
		let space = workspace.spaces[index]
		let pinnedIDs = Set(space.pinnedTabIDs)
		let tabIDs = space.todayTabGroups[groupIndex].tabIDs.filter { space.tabIDs.contains($0) && !pinnedIDs.contains($0) }
		guard !tabIDs.isEmpty else { return false }

		let mutationDate = nextWorkspaceMutationDate()
		let group = space.todayTabGroups[groupIndex]
		workspace.spaces[index].pinnedTabIDs.append(contentsOf: tabIDs)
		workspace.spaces[index].pinnedFolders.append(
			PinnedTabFolder(name: group.name, tabIDs: tabIDs, modifiedAt: mutationDate.addingTimeInterval(0.001))
		)
		workspace.spaces[index].todayTabGroups = space.todayTabGroups.enumerated().compactMap { currentIndex, currentGroup in
			let remainingIDs = currentGroup.tabIDs.filter { !tabIDs.contains($0) }
			guard currentIndex != groupIndex || !remainingIDs.isEmpty else { return nil }
			return BrowserTabGroupingFeature.Group(name: currentGroup.name, tabIDs: remainingIDs)
		}
		workspace.spaces[index].modifiedAt = mutationDate.addingTimeInterval(0.001)
		workspace.modifiedAt = mutationDate.addingTimeInterval(0.001)
		schedulePersistence()
		return true
	}

	func renameSelectedSpace(_ name: String) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }),
		      workspace.spaces[index].name != name else { return }
		var next = workspace
		let mutationDate = nextWorkspaceMutationDate()
		next.spaces[index].name = name
		next.spaces[index].modifiedAt = mutationDate
		next.modifiedAt = mutationDate
		workspace = next
		// Typing changes metadata, not the extension-tab model.
		schedulePersistence(fullState: true, syncExtensions: false)
	}

	func setSelectedSpaceSymbol(_ symbol: String) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }),
		      workspace.spaces[index].symbol != symbol else { return }
		var next = workspace
		let mutationDate = nextWorkspaceMutationDate()
		next.spaces[index].symbol = symbol
		next.spaces[index].modifiedAt = mutationDate
		next.modifiedAt = mutationDate
		workspace = next
		schedulePersistence(fullState: true, syncExtensions: false)
	}

	func setSelectedSpaceTheme(_ theme: BrowserTheme) {
		guard let index = workspace.spaces.firstIndex(where: { $0.id == workspace.selectedSpaceID }),
		      workspace.spaces[index].theme != theme else { return }
		// Mesh editing changes continuously during a drag. Commit the complete
		// value once, without invalidating every SwiftUI observer for separate
		// nested theme/timestamp updates or syncing unchanged extension tabs.
		var next = workspace
		let mutationDate = nextWorkspaceMutationDate()
		next.spaces[index].theme = theme
		next.spaces[index].modifiedAt = mutationDate
		next.modifiedAt = mutationDate
		workspace = next
		schedulePersistence(fullState: true, syncExtensions: false)
	}

	enum TabArea {
		case favourite
		case pinned
		case normal
	}

	func createPinnedFolder(named name: String = "New Folder", with tabIDs: [UUID] = [], in spaceID: UUID? = nil) {
		guard !isPrivate else { return }
		let destinationID = spaceID ?? workspace.selectedSpaceID
		guard workspace.spaces.contains(where: { $0.id == destinationID }) else { return }
		var folderSeen = Set<UUID>()
		let validIDs = tabIDs.filter { folderSeen.insert($0).inserted && tab(withID: $0) != nil }
		if !validIDs.isEmpty {
			moveTabs(validIDs, to: .pinned, in: destinationID)
		}
		guard let index = workspace.spaces.firstIndex(where: { $0.id == destinationID }) else { return }
		let mutationDate = nextWorkspaceMutationDate()
		workspace.spaces[index].pinnedFolders.append(PinnedTabFolder(name: name, tabIDs: validIDs, modifiedAt: mutationDate))
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

	/// Apply a native SwiftUI reorder difference atomically across favourite, pinned,
	/// normal, and pinned-folder collections. The input order is the visual drag order.
	func moveTabs(_ ids: [UUID], to area: TabArea, in spaceID: UUID? = nil, before targetID: UUID? = nil, folderID: UUID? = nil, todayGroupID: String? = nil) {
		guard !isPrivate else { return }
		let existing = Set(tabs.map(\.id))
		var seen = Set<UUID>()
		let moving = ids.filter { existing.contains($0) && seen.insert($0).inserted }
		guard !moving.isEmpty else { return }
		guard area != .normal || moving.allSatisfy({ tab(withID: $0)?.internalPage != .easel }) else { return }
		let movingSet = Set(moving)
		guard targetID.map({ !movingSet.contains($0) }) ?? true else { return }
		let destinationID = spaceID ?? workspace.selectedSpaceID
		guard area == .favourite || workspace.spaces.contains(where: { $0.id == destinationID }) else { return }
		if let folderID {
			guard area == .pinned, workspace.spaces.contains(where: { $0.id == destinationID && $0.pinnedFolders.contains(where: { $0.id == folderID }) }) else { return }
		}
		if let todayGroupID {
			guard area == .normal, workspace.spaces.contains(where: { $0.id == destinationID && $0.todayTabGroups.contains(where: { $0.id == todayGroupID }) }) else { return }
		}
		var next = workspace
		let timestamp = nextWorkspaceMutationDate()
		let destinationDate = timestamp.addingTimeInterval(0.001)
		if next.favouriteTabIDs.contains(where: { movingSet.contains($0) }) {
			next.favouritesModifiedAt = timestamp
		}
		next.favouriteTabIDs.removeAll { movingSet.contains($0) }
		for index in next.spaces.indices {
			let space = next.spaces[index]
			if space.tabIDs.contains(where: { movingSet.contains($0) }) {
				next.spaces[index].modifiedAt = timestamp
			}
			next.spaces[index].tabIDs.removeAll { movingSet.contains($0) }
			next.spaces[index].pinnedTabIDs.removeAll { movingSet.contains($0) }
			for folderIndex in next.spaces[index].pinnedFolders.indices {
				let previous = next.spaces[index].pinnedFolders[folderIndex].tabIDs
				next.spaces[index].pinnedFolders[folderIndex].tabIDs.removeAll { movingSet.contains($0) }
				if previous != next.spaces[index].pinnedFolders[folderIndex].tabIDs {
					next.spaces[index].pinnedFolders[folderIndex].modifiedAt = timestamp
				}
			}
			next.spaces[index].todayTabGroups = next.spaces[index].todayTabGroups.compactMap { group in
				let ids = group.tabIDs.filter { !movingSet.contains($0) }
				return ids.isEmpty && group.id != todayGroupID ? nil : BrowserTabGroupingFeature.Group(name: group.name, tabIDs: ids)
			}
		}
		if area == .favourite {
			let insertAt = targetID.flatMap { next.favouriteTabIDs.firstIndex(of: $0) } ?? next.favouriteTabIDs.endIndex
			next.favouriteTabIDs.insert(contentsOf: moving, at: insertAt)
			next.favouritesModifiedAt = destinationDate
		} else if let index = next.spaces.firstIndex(where: { $0.id == destinationID }) {
			let insertAt = targetID.flatMap { next.spaces[index].tabIDs.firstIndex(of: $0) } ?? next.spaces[index].tabIDs.endIndex
			next.spaces[index].tabIDs.insert(contentsOf: moving, at: insertAt)
			if area == .pinned {
				let pinnedIndex = targetID.flatMap { next.spaces[index].pinnedTabIDs.firstIndex(of: $0) } ?? next.spaces[index].pinnedTabIDs.endIndex
				next.spaces[index].pinnedTabIDs.insert(contentsOf: moving, at: pinnedIndex)
				if let folderID, let folderIndex = next.spaces[index].pinnedFolders.firstIndex(where: { $0.id == folderID }) {
					let folderInsert = targetID.flatMap { next.spaces[index].pinnedFolders[folderIndex].tabIDs.firstIndex(of: $0) } ?? next.spaces[index].pinnedFolders[folderIndex].tabIDs.endIndex
					next.spaces[index].pinnedFolders[folderIndex].tabIDs.insert(contentsOf: moving, at: folderInsert)
					next.spaces[index].pinnedFolders[folderIndex].modifiedAt = destinationDate
				}
			}
			next.spaces[index].modifiedAt = destinationDate
			if area == .normal, let todayGroupID,
			   let groupIndex = next.spaces[index].todayTabGroups.firstIndex(where: { $0.id == todayGroupID })
			{
				let group = next.spaces[index].todayTabGroups[groupIndex]
				let groupInsert = targetID.flatMap { group.tabIDs.firstIndex(of: $0) } ?? group.tabIDs.endIndex
				var tabIDs = group.tabIDs
				tabIDs.insert(contentsOf: moving, at: groupInsert)
				next.spaces[index].todayTabGroups[groupIndex] = BrowserTabGroupingFeature.Group(
					name: group.name,
					tabIDs: tabIDs
				)
			}
		}
		for index in next.spaces.indices {
			let normalIDs = next.spaces[index].tabIDs.filter { !next.spaces[index].pinnedTabIDs.contains($0) }
			next.spaces[index].todayTabGroups = Self.filteredTodayTabGroups(next.spaces[index].todayTabGroups, normalIDs: normalIDs)
		}
		next.modifiedAt = destinationDate
		guard next != workspace else { return }
		workspace = next
		schedulePersistence()
	}

	func moveTab(_ id: UUID, to area: TabArea, in spaceID: UUID? = nil, before targetID: UUID? = nil) {
		guard !isPrivate, tabs.contains(where: { $0.id == id }), targetID != id else { return }
		guard area != .normal || tab(withID: id)?.internalPage != .easel else { return }
		let destinationIndex = area == .favourite
			? nil
			: workspace.spaces.firstIndex(where: { $0.id == (spaceID ?? workspace.selectedSpaceID) })
		guard area == .favourite || destinationIndex != nil else { return }
		var nextWorkspace = workspace
		let wasFavourite = nextWorkspace.favouriteTabIDs.contains(id)
		let mutationDate = nextWorkspaceMutationDate()
		let destinationDate = mutationDate.addingTimeInterval(0.001)
		nextWorkspace.favouriteTabIDs.removeAll { $0 == id }
		for index in nextWorkspace.spaces.indices {
			let removedMembership = nextWorkspace.spaces[index].tabIDs.contains(id)
				|| nextWorkspace.spaces[index].pinnedTabIDs.contains(id)
				|| nextWorkspace.spaces[index].pinnedFolders.contains(where: { $0.tabIDs.contains(id) })
			if removedMembership {
				nextWorkspace.spaces[index].modifiedAt = mutationDate
			}
			nextWorkspace.spaces[index].tabIDs.removeAll { $0 == id }
			nextWorkspace.spaces[index].pinnedTabIDs.removeAll { $0 == id }
			for folderIndex in nextWorkspace.spaces[index].pinnedFolders.indices {
				let oldCount = nextWorkspace.spaces[index].pinnedFolders[folderIndex].tabIDs.count
				nextWorkspace.spaces[index].pinnedFolders[folderIndex].tabIDs.removeAll { $0 == id }
				if oldCount != nextWorkspace.spaces[index].pinnedFolders[folderIndex].tabIDs.count {
					nextWorkspace.spaces[index].pinnedFolders[folderIndex].modifiedAt = mutationDate
				}
			}
		}
		if area == .favourite {
			let index = targetID.flatMap { nextWorkspace.favouriteTabIDs.firstIndex(of: $0) } ?? nextWorkspace.favouriteTabIDs.endIndex
			nextWorkspace.favouriteTabIDs.insert(id, at: index)
			nextWorkspace.favouritesModifiedAt = destinationDate
		} else if let index = destinationIndex {
			let insertion = targetID.flatMap { nextWorkspace.spaces[index].tabIDs.firstIndex(of: $0) } ?? nextWorkspace.spaces[index].tabIDs.endIndex
			nextWorkspace.spaces[index].tabIDs.insert(id, at: insertion)
			if area == .pinned {
				let pinnedInsertion = targetID.flatMap { nextWorkspace.spaces[index].pinnedTabIDs.firstIndex(of: $0) }
					?? nextWorkspace.spaces[index].pinnedTabIDs.endIndex
				nextWorkspace.spaces[index].pinnedTabIDs.insert(id, at: pinnedInsertion)
			}
			nextWorkspace.spaces[index].modifiedAt = destinationDate
			if wasFavourite {
				nextWorkspace.favouritesModifiedAt = mutationDate
			}
		} else {
			preconditionFailure("Validated tab destination became unavailable")
		}
		nextWorkspace.modifiedAt = destinationDate
		let changesSelectedSpace = selectedTabID == id
			&& area != .favourite
			&& spaceID != nil
			&& nextWorkspace.selectedSpaceID != spaceID
		if changesSelectedSpace, let spaceID {
			nextWorkspace.selectedSpaceID = spaceID
		}
		// One observed update for all folder, pinned, membership and order
		// changes; SwiftUI never sees an intermediate half-moved tab.
		workspace = nextWorkspace
		if changesSelectedSpace {
			selectTab(id)
		}
		schedulePersistence()
	}

	private func isSyncableTabID(_ id: UUID) -> Bool {
		guard let tab = tabs.first(where: { $0.id == id }) else { return false }
		return isSyncableTab(tab.openTab)
	}

	private func isSyncableTab(_ tab: OpenTab) -> Bool {
		guard !tab.isDiscardableNewTab, tab.internalPage == nil || tab.internalPage == "easel", tab.fileAccessBookmark == nil else { return false }
		guard let url = tab.url else { return true }
		return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
	}

	private var webTabs: [BrowserTab] {
		tabs.filter { $0.internalPage == nil }
	}

	private var persistedSelectedTabID: UUID {
		(selectedTab?.internalPage == nil || selectedTab?.internalPage == .easel) ? selectedTabID : webTabs.first?.id ?? selectedTabID
	}

	init(isMini: Bool = false, isPrivate: Bool = false, windowRecord: BrowserWindowRecord? = nil) {
		BrowserSettingsSchema.migrateLegacyNewTabPreference()
		windowID = windowRecord?.windowID ?? UUID()
		self.isMini = isMini
		restorationRecord = windowRecord
		savedWindowFrame = windowRecord?.frame
		let session = isPrivate ? BrowserWebSession(isPrivate: true) : .shared
		self.session = session
		let launchCache = !isMini && !isPrivate && Defaults[.startupBehavior] == .restore
			? BrowserLaunchCache.load()
			: nil
		// Another normal window reuses the hydrated in-memory browser state.
		// Do not force a full session snapshot on the main actor just because
		// the user opened a window; the normal debounced writer still persists
		// updates and the quit/sleep paths retain their explicit flushes.
		// Synchronous placeholder only: disk decode happens off-main in
		// hydrateFromDisk() so the first frame never waits on JSON.
		let placeholder = BrowserTab(modifiedAt: .distantPast, session: session)
		// Read this preference once for all cached tab shells rather than
		// once per BrowserTab initializer (up to 256 on a typical restore).
		let cachedDefaultPageZoom = launchCache == nil ? nil : Defaults[.defaultPageZoom]
		let placeholderID = placeholder.id
		let placeholderModifiedAt = placeholder.modifiedAt
		let cachedTabs = launchCache?.tabs.sorted { $0.order < $1.order }.map { cached in
			BrowserTab(
				id: cached.id,
				internalPage: cached.internalPage.flatMap(BrowserInternalPage.init(persistenceID:)),
				pageTitle: cached.title,
				customTitle: cached.internalPage == "easel" ? cached.title : nil,
				initialURL: cached.url,
				pageZoom: cachedDefaultPageZoom,
				isHibernated: true,
				modifiedAt: .distantPast,
				session: session
			)
		} ?? []
		let initialTabs = cachedTabs.isEmpty ? [placeholder] : cachedTabs
		let initialSelectedTabID = launchCache?.selectedTabID.flatMap { id in initialTabs.contains(where: { $0.id == id }) ? id : nil }
			?? initialTabs[0].id
		let cachedSpaceIDs = Set(initialTabs.map(\.id))
		let initialWorkspace: BrowserWorkspace
		if let launchCache, !launchCache.spaces.isEmpty {
			let spaces = launchCache.spaces.map { cached in
				BrowserSpace(
					id: cached.id,
					name: cached.name,
					symbol: cached.symbol,
					theme: cached.theme,
					tabIDs: cached.tabIDs.filter(cachedSpaceIDs.contains),
					selectedTabID: cached.selectedTabID,
					modifiedAt: .distantPast
				)
			}
			initialWorkspace = BrowserWorkspace(
				spaces: spaces,
				favouriteTabIDs: launchCache.favouriteTabIDs.filter(cachedSpaceIDs.contains),
				selectedSpaceID: launchCache.selectedSpaceID.flatMap { id in spaces.contains(where: { $0.id == id }) ? id : nil }
					?? spaces[0].id,
				modifiedAt: .distantPast,
				selectionModifiedAt: .distantPast
			)
		} else {
			initialWorkspace = BrowserWorkspace.migrated(
				tabs: initialTabs.map(\.openTab),
				selectedTabID: initialSelectedTabID,
				theme: Defaults[.browserTheme]
			)
		}
		var persistenceStore: BrowserPersistence?
		var persistenceError: String?
		do {
			if !isMini, !isPrivate {
				persistenceStore = try BrowserPersistence.makeShared()
			}
		} catch {
			BrowserLog.error(.persistence, "browser.persistence.initialize-failed", metadata: [
				"window": BrowserLog.id(windowID),
				"error": BrowserLog.errorDescription(error),
			])
			persistenceError = error.localizedDescription
		}
		tabs = initialTabs
		selectedTabID = initialSelectedTabID
		launchCacheSelectedTabID = launchCache?.selectedTabID
		launchCacheSeeded = launchCache != nil
		workspace = initialWorkspace
		recentlyUsedTabIDs = [initialSelectedTabID]
		bookmarks = []
		readingList = []
		historyVisits = []
		closedHistoryTabs = []
		closedTabIDs = []
		deletedBookmarkIDs = []
		closedTabsAt = [:]
		deletedBookmarksAt = [:]
		deletedReadingListAt = [:]
		deletedSpacesAt = [:]
		deletedVisitsAt = [:]
		historyClearedAt = .distantPast
		selectedTabModifiedAt = .distantPast
		persistence = persistenceStore
		persistenceErrorDescription = persistenceError
		persistenceTask = nil
		didFinishHydration = persistenceStore == nil
		reconcileWorkspace()
		for tab in initialTabs {
			configure(tab)
		}
		if !isMini {
			BrowserWindowRegistry.shared.register(self)
		}
		if !isMini {
			automaticHibernationManager = BrowserHibernationManager(browser: self)
		}
		if !isPrivate, !isMini,
		   let source = BrowserWindowRegistry.shared.openBrowsers.first(where: {
		   	$0 !== self && !$0.isPrivate && !$0.isMini && $0.isHydrationFinished
		   })
		{
			tabs = source.tabs
			workspace = source.workspace
			selectedTabID = source.selectedTabID
			recentlyUsedTabIDs = source.recentlyUsedTabIDs
			bookmarks = source.bookmarks
			readingList = source.readingList
			historyVisits = source.historyVisits
			latestHistoryMutationDate = nil
			closedHistoryTabs = source.closedHistoryTabs
			closedTabIDs = source.closedTabIDs
			deletedBookmarkIDs = source.deletedBookmarkIDs
			closedTabsAt = source.closedTabsAt
			deletedBookmarksAt = source.deletedBookmarksAt
			deletedReadingListAt = source.deletedReadingListAt
			deletedSpacesAt = source.deletedSpacesAt
			deletedVisitsAt = source.deletedVisitsAt
			historyClearedAt = source.historyClearedAt
			selectedTabModifiedAt = source.selectedTabModifiedAt
			didFinishHydration = true
			if let record = restorationRecord,
			   let selectedID = record.restoredSelection(availableTabIDs: Set(tabs.map(\.id)))
			{
				selectTab(selectedID)
			}
			// register(_:) deliberately skipped the pre-hydration placeholder.
			BrowserExtensionManager.shared.sync(self)
		} else if persistenceStore != nil {
			hydrateFromDisk(placeholderID: placeholderID, placeholderModifiedAt: placeholderModifiedAt)
		} else if !isMini, initialTabs.allSatisfy(\.openTab.isDiscardableNewTab) {
			requestNewTab()
		}
	}

	/// Saved-state snapshot decoded off-main.
	private struct HydratedState: @unchecked Sendable {
		var tabs: [OpenTab]
		var snapshot: BrowserSnapshot?
		var workspace: BrowserWorkspace?
		var bookmarks: [Bookmark]
		var readingList: [ReadingListItem]
		var closedTabs: [OpenTab]
		var historyVisits: [BrowserVisit]?
		var previousShutdownWasClean: Bool?
		var windowRecords: [BrowserWindowRecord]
	}

	private func hydrateFromDisk(placeholderID: UUID, placeholderModifiedAt: Date) {
		BrowserLog.info(.persistence, "browser.hydration.begin", metadata: ["window": BrowserLog.id(windowID), "placeholder": BrowserLog.id(placeholderID)])
		guard let persistence else { return }
		if Self.launchMetadataTask == nil {
			Self.launchMetadataTask = Task.detached(priority: .utility) {
				let previous = try? persistence.loadShutdownMetadata()?.clean
				try? persistence.saveShutdownMetadata(clean: false)
				return previous
			}
		}

		// AppDelegate constructs every restored window back-to-back. Without a
		// shared task each window independently read and decoded the same complete
		// browser-state.json, then independently prepared the restoration key.
		// Share that immutable launch snapshot until startup restoration finishes.
		if Self.launchHydrationTask == nil {
			let launchMetadataTask = Self.launchMetadataTask
			Self.launchHydrationTask = Task.detached(priority: .userInitiated) { [persistence] in
				// Keychain restoration-key preparation and the saved JSON read are
				// independent. Overlap them instead of paying their startup latency
				// serially. Both must complete before constructing restored controllers.
				let restorationPreparation = Task { @MainActor in
					await BrowserRestorationStore.prepare()
				}
				let diskStarted = BrowserLog.clock()
				let persisted = try persistence.loadPersistedState()
				BrowserLog.duration(.persistence, "startup.persisted-state-read",
				                    since: diskStarted, warnAboveMilliseconds: 250)
				if let state = persisted {
					let previousShutdownWasClean = await launchMetadataTask?.value
					await restorationPreparation.value
					return HydratedState(
						tabs: state.openTabs,
						snapshot: state.snapshot,
						workspace: state.workspace,
						bookmarks: Bookmark.preservingLegacyOrder(state.bookmarks),
						readingList: state.readingList,
						closedTabs: state.closedTabs,
						historyVisits: state.historyVisits,
						previousShutdownWasClean: previousShutdownWasClean,
						windowRecords: state.windowRecords ?? []
					)
				}

				let tabs = try persistence.loadOpenTabs()
				let snapshot = try persistence.loadBrowserSnapshot()
				let workspace = try persistence.loadWorkspace()
				let bookmarks = try persistence.loadBookmarks()
				let closedTabs = try persistence.loadClosedTabs()
				let previousShutdownWasClean = await launchMetadataTask?.value
				await restorationPreparation.value
				return HydratedState(
					tabs: tabs,
					snapshot: snapshot,
					workspace: workspace,
					bookmarks: Bookmark.preservingLegacyOrder(bookmarks),
					readingList: [],
					closedTabs: closedTabs,
					historyVisits: nil,
					previousShutdownWasClean: previousShutdownWasClean,
					windowRecords: []
				)
			}
		}
		guard let hydrationTask = Self.launchHydrationTask else { return }

		Task { @MainActor [weak self] in
			do {
				let loaded = try await hydrationTask.value
				guard let self else { return }
				for tab in tabs {
					tab.invalidateStoredSnapshot()
				}
				// Replace disposable cached UI state with authoritative disk state
				// without animating every sidebar row on first restoration.
				withTransaction(Transaction(animation: nil)) {
					self.applyHydratedState(loaded, placeholderID: placeholderID, placeholderModifiedAt: placeholderModifiedAt)
				}
			} catch {
				guard let self else { return }
				BrowserLog.error(.persistence, "browser.hydration.failed", metadata: [
					"window": BrowserLog.id(windowID),
					"error": BrowserLog.errorDescription(error),
				])
				hydrationFailed = true
				didFinishHydration = true
				persistenceErrorDescription = error.localizedDescription
			}
		}
	}

	static func finishLaunchHydrationSharing() {
		launchHydrationTask = nil
	}

	private func applyHydratedState(_ loaded: HydratedState, placeholderID: UUID, placeholderModifiedAt: Date) {
		let applyStartedAt = BrowserLog.clock()
		BrowserLog.info(.persistence, "browser.hydration.apply", metadata: ["window": BrowserLog.id(windowID), "placeholder": BrowserLog.id(placeholderID)])
		defer {
			BrowserLog.duration(
				.persistence,
				"browser.hydration.apply.end",
				since: applyStartedAt,
				warnAboveMilliseconds: 100,
				metadata: ["window": BrowserLog.id(windowID), "tabs": String(tabs.count), "history": String(historyVisits.count)]
			)
			didFinishHydration = true
			previousShutdownWasClean = loaded.previousShutdownWasClean
			applyHistoryRetention()
			persist()
			BrowserSync.shared.hydrationDidFinish(self)
		}
		// Empty New Tabs are real session entries, not disposable restoration anchors.
		let savedTabs = loaded.tabs
		let placeholderIsUntouched = tabs.count == 1
			&& tabs.first?.id == placeholderID
			&& tabs.first?.modifiedAt == placeholderModifiedAt
			&& tabs.first?.currentURL == nil
		let launchCacheIsUntouched = launchCacheSeeded && !launchCacheWasModified
		guard placeholderIsUntouched || launchCacheIsUntouched else {
			let selectionBeforeHydration = selectedTabID
			let cacheSelectionIsUntouched = launchCacheSelectedTabID == selectionBeforeHydration
				&& selectedTabModifiedAt == .distantPast
			Self.didApplyStartupBehavior = true
			let cachedTabs = savedTabs
			let cachedWorkspace = loaded.workspace ?? BrowserWorkspace.migrated(
				tabs: cachedTabs,
				selectedTabID: loaded.snapshot?.selectedTabID ?? cachedTabs.first?.id ?? UUID(),
				theme: Defaults[.browserTheme]
			)
			let cached = BrowserSyncDocument(
				tabs: cachedTabs,
				workspace: cachedWorkspace,
				bookmarks: loaded.bookmarks,
				readingList: loaded.readingList,
				history: loaded.historyVisits ?? Self.migratedHistory(savedTabs + loaded.closedTabs),
				browser: loaded.snapshot ?? BrowserSnapshot(),
				settings: [:]
			)
			let current = BrowserSyncDocument(
				tabs: tabs.map(\.openTab),
				workspace: workspace,
				bookmarks: bookmarks,
				readingList: readingList,
				history: historyVisits,
				browser: BrowserSnapshot(
					selectedTabID: selectedTabID,
					selectedTabModifiedAt: selectedTabModifiedAt,
					closedTabIDs: closedTabIDs,
					deletedBookmarkIDs: deletedBookmarkIDs,
					deletedBookmarksAt: deletedBookmarksAt,
					deletedReadingListAt: deletedReadingListAt,
					closedTabsAt: closedTabsAt,
					deletedSpacesAt: deletedSpacesAt,
					deletedVisitsAt: deletedVisitsAt,
					historyClearedAt: historyClearedAt
				),
				settings: [:]
			)
			let merged = current.merging(cached)
				.preservingLocalOnlyData(from: cached)
				.preservingLocalOnlyData(from: current)
			applySyncDocument(merged)
			if selectionBeforeHydration == placeholderID || cacheSelectionIsUntouched,
			   let record = loaded.windowRecords.first(where: { $0.windowID == windowID }) ?? restorationRecord,
			   let selection = record.restoredSelection(availableTabIDs: Set(tabs.map(\.id)))
			{
				selectTab(selection)
			}
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
		// Reopening a session previously constructed a BrowserController for
		// every non-hibernated saved tab. Its initializer can start WebKit
		// navigation before the tab is ever selected. Preserve the foreground
		// tab's eager restoration; leave background tabs dormant until selected.
		// Their saved URL, history, scroll and encrypted WebKit state remain
		// available to BrowserTab.wake() without doing any work at launch.
		let savedWindow = loaded.windowRecords.first { $0.windowID == windowID } ?? restorationRecord
		let availableSavedIDs = Set(savedTabs.map(\.id))
		let foregroundSavedID = savedWindow?.restoredSelection(availableTabIDs: availableSavedIDs)
			?? loaded.snapshot.flatMap { availableSavedIDs.contains($0.selectedTabID) ? $0.selectedTabID : nil }
			?? savedTabs.first?.id
		let restoredTabs = savedTabs.compactMap { saved -> BrowserTab? in
			let internalPage = saved.internalPage.flatMap(BrowserInternalPage.init(persistenceID:))
			guard saved.internalPage == nil || internalPage != nil else { return nil }
			if let shared = BrowserWindowRegistry.shared.sharedTab(withID: saved.id, for: self),
			   shared.internalPage == internalPage
			{
				return shared
			}
			return BrowserTab(
				id: saved.id,
				internalPage: internalPage,
				pageTitle: saved.pageTitle,
				customTitle: saved.customTitle,
				monitorMatch: saved.monitorMatch,
				initialURL: saved.url,
				history: saved.history,
				historyIndex: saved.historyIndex,
				openPeeks: saved.peeks,
				pageZoom: saved.pageZoom,
				scrollPosition: saved.scrollPosition,
				isHibernated: saved.isHibernated || startupBehavior != .restore || saved.id != foregroundSavedID,
				modifiedAt: saved.modifiedAt,
				recordsNavigationHistory: saved.recordsNavigationHistory,
				restorationState: saved.restorationState,
				fileAccessBookmark: saved.fileAccessBookmark,
				easel: saved.easel,
				suppressInitialHistoryVisit: true,
				initialRestorationBaseline: saved
			)
		}
		// Preserve restored New Tabs; an explicit blank-start preference opens
		// one additional new tab without replacing the saved session.
		var newTabs = restoredTabs
		if startupBehavior == .homepage, let homepage = BrowserHomepage.validURL(Defaults[.homepageURL]) {
			newTabs.append(BrowserTab(initialURL: homepage, session: session))
		}
		if newTabs.isEmpty {
			newTabs = [BrowserTab(session: session)] // First session tab when there is no saved content.
		}
		let restoredWindowSelection = savedWindow?.restoredSelection(availableTabIDs: Set(newTabs.map(\.id)))
		let newSelectedTabID = startupBehavior != .homepage
			? (restoredWindowSelection ?? newTabs.first(where: { $0.id == loaded.snapshot?.selectedTabID })?.id ?? newTabs[0].id)
			: newTabs[newTabs.count - 1].id
		if savedWindowFrame == nil {
			savedWindowFrame = savedWindow?.frame
		}
		tabs = newTabs
		selectedTabID = newSelectedTabID
		workspace = loaded.workspace ?? BrowserWorkspace.migrated(
			tabs: savedTabs,
			selectedTabID: newSelectedTabID,
			theme: Defaults[.browserTheme]
		)
		recentlyUsedTabIDs = [newSelectedTabID]
		bookmarks = loaded.bookmarks.map { item in
			var item = item
			item.url = BrowserAddress.withoutCredentials(item.url)
			return item
		}
		readingList = loaded.readingList
		historyVisits = visibleHistoryVisits(loaded.historyVisits ?? Self.migratedHistory(savedTabs + loaded.closedTabs))
		closedHistoryTabs = loaded.closedTabs
		closedTabIDs = loaded.snapshot?.closedTabIDs ?? []
		selectedTabModifiedAt = loaded.snapshot?.selectedTabModifiedAt ?? .distantPast
		deletedBookmarkIDs = loaded.snapshot?.deletedBookmarkIDs ?? []
		closedTabsAt = loaded.snapshot?.closedTabsAt ?? [:]
		deletedBookmarksAt = loaded.snapshot?.deletedBookmarksAt ?? [:]
		deletedReadingListAt = loaded.snapshot?.deletedReadingListAt ?? [:]
		deletedSpacesAt = loaded.snapshot?.deletedSpacesAt ?? [:]
		deletedVisitsAt = loaded.snapshot?.deletedVisitsAt ?? [:]
		historyClearedAt = loaded.snapshot?.historyClearedAt ?? .distantPast
		historyVisits = visibleHistoryVisits(historyVisits)
		latestHistoryMutationDate = nil
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
		if startupBehavior == .blank {
			requestNewTab()
		}
	}

	func requestNewTab() {
		closeEaselSplit()
		let clipboardURL = NSPasteboard.general.string(forType: .string).flatMap(BrowserSearchMatching.pastedHTTPURL)
		newTabClipboardURL = clipboardURL
		newTabSearchText = ""
		newTabSearchSelection = nil
		showsQuickSearch = false
		_ = addTab()
		quickSearchFocusRequest += 1
	}

	func openHistoryEntry(from controller: BrowserController, offset: Int) {
		guard offset == -1 || offset == 1,
		      let source = selectedTab,
		      source.activeController === controller,
		      let webView = controller.webViewIfLoaded,
		      let url = webView.backForwardList.item(at: offset)?.url
		else { return }

		let tab = addTab(inBackground: true)
		tab.controller?.navigate(URLRequest(url: url))
		tab.controller?.prepareWebView()

		if isPrivate {
			if let tabIndex = tabs.firstIndex(where: { $0.id == tab.id }),
			   let sourceIndex = tabs.firstIndex(where: { $0.id == source.id })
			{
				tabs.remove(at: tabIndex)
				tabs.insert(tab, at: sourceIndex + 1)
			}
			reconcileWorkspace()
			return
		}

		let space = workspace.spaces.first { $0.tabIDs.contains(source.id) } ?? selectedSpace
		let targetID: UUID? = if workspace.favouriteTabIDs.contains(source.id) || space.pinnedTabIDs.contains(source.id) {
			space.tabIDs.first { !space.pinnedTabIDs.contains($0) && $0 != tab.id }
		} else {
			space.tabIDs.drop(while: { $0 != source.id }).dropFirst().first
		}
		moveTab(tab.id, to: .normal, in: space.id, before: targetID)

		if let spaceIndex = workspace.spaces.firstIndex(where: { $0.id == space.id }),
		   let groupIndex = workspace.spaces[spaceIndex].todayTabGroups.firstIndex(where: { $0.tabIDs.contains(source.id) }),
		   let groupTabIndex = workspace.spaces[spaceIndex].todayTabGroups[groupIndex].tabIDs.firstIndex(of: source.id)
		{
			let group = workspace.spaces[spaceIndex].todayTabGroups[groupIndex]
			var tabIDs = group.tabIDs
			tabIDs.insert(tab.id, at: groupTabIndex + 1)
			workspace.spaces[spaceIndex].todayTabGroups[groupIndex] = BrowserTabGroupingFeature.Group(
				name: group.name,
				tabIDs: tabIDs
			)
		}
		markWorkspaceStructureChanged()
		schedulePersistence()
	}

	func dismissQuickSearch() {
		showsQuickSearch = false
		newTabSearchText = ""
		newTabSearchSelection = nil
		newTabClipboardURL = nil
	}

	@discardableResult
	func addTab(inBackground: Bool = false) -> BrowserTab {
		let workflowStart = BrowserLog.clock()
		let countBefore = tabs.count
		defer {
			BrowserLog.duration(.performance, "workflow.tab.create-to-model-commit",
			                    since: workflowStart, warnAboveMilliseconds: 16,
			                    metadata: [
			                    	"background": String(inBackground),
			                    	"tabs_before": String(countBefore),
			                    	"tabs_after": String(tabs.count),
			                    ])
		}
		BrowserLog.info(.tabs, "tab.create", metadata: ["window": BrowserLog.id(windowID), "background": String(inBackground), "count_before": String(tabs.count)])
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
		BrowserLog.info(.navigation, "internal.open", metadata: ["page": String(describing: page), "new_tab": String(inNewTab)])
		guard !isPrivate || page == .settings else { return }
		guard page != .easel || !isMini else { return }
		if isPrivate {
			settingsPage = .privacyAndSecurity
		}
		#if os(macOS)
			if page == .settings {
				BrowserSettingsWindowController.shared.show(for: self)
				return
			}
		#endif
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

	@discardableResult
	func createEasel() -> BrowserTab? {
		guard !isPrivate, !isMini else { return nil }
		let leftID = selectedTab?.canAppearInEaselSplit == true ? selectedTabID : splitLeftTabID
		let before = Set(tabs.map(\.id))
		openInternalPage(.easel, inNewTab: true)
		guard let tab = tabs.first(where: { !before.contains($0.id) }) else { return nil }
		moveTab(tab.id, to: .pinned, in: workspace.selectedSpaceID)
		if let leftID {
			splitLeftTabID = leftID
			splitRightTabID = tab.id
			selectTab(leftID)
		}
		return tab
	}

	/// Split panes are window-local, and must both belong to the visible space.
	var isShowingTabSplit: Bool {
		guard let leftID = splitLeftTabID, let rightID = splitRightTabID, leftID != rightID else { return false }
		return visibleTabs.contains(where: { $0.id == leftID && $0.canAppearInEaselSplit })
			&& visibleTabs.contains(where: { $0.id == rightID && $0.canAppearInEaselSplit })
	}

	var isShowingEaselSplit: Bool {
		isShowingTabSplit && splitRightTabID.flatMap { tab(withID: $0)?.internalPage } == .easel
	}

	enum SplitSide: Sendable, Equatable {
		case left, right
	}

	func splitSide(for id: UUID) -> SplitSide? {
		guard isShowingTabSplit else { return nil }
		if splitLeftTabID == id {
			return .left
		}
		if splitRightTabID == id {
			return .right
		}
		return nil
	}

	/// Open any two eligible website/easel tabs side by side.
	func openSplit(_ id: UUID, beside anchorID: UUID, onLeft: Bool) {
		guard !isPrivate, !isMini, id != anchorID,
		      let tab = tab(withID: id), let anchor = self.tab(withID: anchorID),
		      tab.canAppearInEaselSplit, anchor.canAppearInEaselSplit,
		      visibleTabs.contains(where: { $0.id == id }),
		      visibleTabs.contains(where: { $0.id == anchorID })
		else { return }
		closeEaselSplit()
		selectTab(anchorID)
		splitLeftTabID = onLeft ? id : anchorID
		splitRightTabID = onLeft ? anchorID : id
	}

	func deleteEasel(_ id: UUID, confirmed: Bool = false) {
		guard !isPrivate, let tab = tab(withID: id), tab.internalPage == .easel else { return }
		// Empty easels have no content to lose, so deleting them is immediate.
		if !confirmed, tab.easelDocument.items.isEmpty {
			deleteEasel(id, confirmed: true)
			return
		}
		#if os(macOS)
			if !confirmed {
				Task { @MainActor [weak self] in
					let alert = BrowserWebsiteUI.alert(title: "Delete this easel?", message: "Its contents will be permanently deleted from your devices, and any open peeks will close.", confirm: "Delete Easel")
					if await BrowserWebsiteUI.present(alert, in: NSApp.keyWindow) == .alertFirstButtonReturn {
						self?.deleteEasel(id, confirmed: true)
					}
				}
				return
			}
		#else
			guard confirmed else { return }
		#endif
		let fallback = visibleTabs.first(where: { $0.id != id })?.id
		let date = BrowserUserDataMutation.nextDate(after: max(tab.modifiedAt, nextWorkspaceMutationDate()), deletion: closedTabsAt[id] ?? .distantPast)
		if workspace.favouriteTabIDs.contains(id) {
			workspace.favouriteTabIDs.removeAll { $0 == id }
			workspace.favouritesModifiedAt = date
		}
		for index in workspace.spaces.indices where workspace.spaces[index].tabIDs.contains(id) {
			workspace.spaces[index].tabIDs.removeAll { $0 == id }
			workspace.spaces[index].pinnedTabIDs.removeAll { $0 == id }
			for folderIndex in workspace.spaces[index].pinnedFolders.indices {
				workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.removeAll { $0 == id }
			}
			workspace.spaces[index].modifiedAt = date
		}
		if splitRightTabID == id {
			closeEaselSplit()
		}
		releaseAfterTabUpdate([tab])
		tabs.removeAll { $0.id == id }
		closedTabIDs.insert(id)
		closedTabsAt[id] = date
		reconcileWorkspace()
		markWorkspaceStructureChanged()
		if selectedTabID == id {
			if let fallback {
				selectTab(fallback)
			} else {
				addTab()
			}
		}
		schedulePersistence(fullState: true)
	}

	func openEaselInSplit(_ id: UUID) {
		guard let easel = tab(withID: id), easel.internalPage == .easel,
		      let anchor = splitLeftTabID.flatMap({ tab(withID: $0) }) ?? selectedTab,
		      anchor.id != easel.id else { return }
		openSplit(id, beside: anchor.id, onLeft: false)
	}

	/// Context-menu destinations are limited to Easels in the source tab's Space.
	func easelQuoteDestinations(for source: BrowserTab) -> [BrowserEaselQuoteDestination] {
		guard !isPrivate, !isMini, source.internalPage == nil,
		      selectedSpace.tabIDs.contains(source.id) else { return [] }
		return selectedSpace.tabIDs.compactMap { id in
			guard let tab = tab(withID: id), tab.internalPage == .easel else { return nil }
			return BrowserEaselQuoteDestination(id: id, title: tab.title)
		}
	}

	func addEaselQuote(_ quote: BrowserEaselQuote, to easelID: UUID, from sourceID: UUID) {
		guard quote.isValid, !isPrivate, !isMini,
		      let source = tab(withID: sourceID), source.internalPage == nil,
		      let sourceURL = source.currentURL.map(BrowserAddress.withoutCredentials),
		      sourceURL == quote.url,
		      selectedSpace.tabIDs.contains(sourceID),
		      selectedSpace.tabIDs.contains(easelID),
		      let easel = tab(withID: easelID), easel.internalPage == .easel
		else { return }
		var item = BrowserEaselDocument.Item(kind: .quote)
		item.quote = quote
		item.width = 360
		item.height = 210
		var document = easel.easelDocument
		document.items.append(item)
		guard easel.updateEasel(document) else { return }
		// The editor positions the new quote at the currently visible viewport
		// center, including when its tab was already mounted.
		easel.pendingQuotePlacementID = item.id
		closeEaselSplit()
		selectTab(easelID)
	}

	func openEaselQuote(_ quote: BrowserEaselQuote, in tab: BrowserTab) {
		guard tab.internalPage == .easel, quote.isValid else { return }
		selectTab(tab.id)
		let peek = BrowserPeek(url: quote.url, depth: tab.peeks.count + 1,
		                       source: .trailing, parentZoom: 1,
		                       zoomsOut: Defaults[.zoomOutInPeeks], session: session, easelQuote: quote)
		configure(peek, in: tab)
		tab.addPeek(peek)
	}

	func openEaselLink(_ url: URL, in tab: BrowserTab) {
		guard tab.internalPage == .easel, BrowserEaselDocument.isSafeLink(url) else { return }
		selectTab(tab.id)
		let peek = BrowserPeek(url: url, depth: tab.peeks.count + 1, source: .trailing, parentZoom: 1, zoomsOut: Defaults[.zoomOutInPeeks], session: session)
		configure(peek, in: tab)
		tab.addPeek(peek)
	}

	func closeEaselSplit() {
		splitLeftTabID = nil
		splitRightTabID = nil
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
			monitorMatch: saved.monitorMatch,
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
		guard let saved = closedHistoryTabs.first else { return }
		Task { await reopenClosedTab(saved.id, inBackground: false) }
	}

	@discardableResult
	func reopenClosedTab(_ id: UUID, inBackground: Bool) async -> BrowserTab? {
		guard let summary = closedHistoryTabs.first(where: { $0.id == id }) else { return nil }
		let saved: OpenTab
		do {
			if let persistence, summary.closedArchiveID != nil {
				saved = try await Task.detached(priority: .userInitiated) { try persistence.loadClosedTab(summary) }.value
			} else { saved = summary }
		} catch { persistenceErrorDescription = error.localizedDescription; return nil }
		guard !Task.isCancelled, let index = closedHistoryTabs.firstIndex(where: { $0.id == id && $0.modifiedAt == summary.modifiedAt }) else { return nil }
		closedHistoryTabs.remove(at: index)
		let tab = openHistoryTab(saved, inBackground: inBackground)
		if let spaceID = saved.closedSpaceID,
		   let normalIndex = saved.closedNormalIndex,
		   let space = workspace.spaces.first(where: { $0.id == spaceID })
		{
			let normalIDs = space.tabIDs.filter {
				!space.pinnedTabIDs.contains($0) && $0 != tab.id
			}
			let targetID = normalIDs.dropFirst(max(0, normalIndex)).first
			if !isPrivate {
				moveTab(tab.id, to: .normal, in: spaceID, before: targetID)
			}
		}
		schedulePersistence()
		return tab
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
		selectTab(id, inSpace: nil)
	}

	private func selectTab(_ id: UUID, inSpace requestedSpaceID: UUID?) {
		if let selectedTab { tabResources.refreshProtection(of: selectedTab) }
		let selectionStartedAt = BrowserLog.clock()
		BrowserLog.debug(.tabs, "tab.select", metadata: ["window": BrowserLog.id(windowID), "from": BrowserLog.id(selectedTabID), "to": BrowserLog.id(id)])
		guard let tab = tab(withID: id) else { return }
		if isShowingTabSplit, id != splitLeftTabID, id != splitRightTabID {
			closeEaselSplit()
		}
		defer {
			BrowserLog.duration(
				.performance,
				"tab.select.end",
				since: selectionStartedAt,
				warnAboveMilliseconds: 40,
				metadata: ["window": BrowserLog.id(windowID), "tab": BrowserLog.id(id), "hibernated": String(tab.isHibernated)]
			)
		}
		let previousTab = selectedTab
		if tab.monitorMatch != nil {
			tab.setMonitorMatch(nil)
		}
		showsQuickSearch = false
		previousTab?.activeController?.clearHoveredLink()
		tab.activeController?.clearHoveredLink()
		tab.clearPictureInPictureReturnController()

		// Mouse-down selection is deliberately followed by the Button's normal
		// mouse-up action. Make that second selection effectively free, and also
		// avoid rewriting workspace timestamps/persistence for any repeated click
		// on an already-active warm tab.
		if selectedTabID == id, !tab.isHibernated,
		   requestedSpaceID == nil || requestedSpaceID == workspace.selectedSpaceID
		{
			if !BrowserWindowRegistry.shared.ownsTab(id, in: self) {
				BrowserWindowRegistry.shared.claimSelectedTab(in: self)
			}
			return
		}

		// BrowserWorkspace is a value type observed throughout the shell. Build
		// the complete selection mutation locally and publish it once instead of
		// invalidating observers for every nested field write.
		var nextWorkspace = workspace
		if let requestedSpaceID {
			nextWorkspace.selectedSpaceID = requestedSpaceID
		} else if !nextWorkspace.favouriteTabIDs.contains(id),
		          let ownerIndex = nextWorkspace.spaces.firstIndex(where: { $0.tabIDs.contains(id) })
		{
			nextWorkspace.selectedSpaceID = nextWorkspace.spaces[ownerIndex].id
		}

		let didWake = tab.isHibernated
		newTabSearchText = ""
		newTabSearchSelection = nil
		newTabGoogleSuggestions = []
		newTabClipboardURL = nil
		previousTab?.markInteraction()
		selectedTabID = id
		tab.markInteraction()

		let selectionDate = nextWorkspaceMutationDate()
		selectedTabModifiedAt = selectionDate
		if let index = nextWorkspace.spaces.firstIndex(where: { $0.id == nextWorkspace.selectedSpaceID }) {
			nextWorkspace.spaces[index].selectedTabID = id
			nextWorkspace.spaces[index].modifiedAt = selectionDate
		}
		nextWorkspace.modifiedAt = selectionDate
		nextWorkspace.selectionModifiedAt = selectionDate
		publishingTabSelection = true
		workspace = nextWorkspace
		publishingTabSelection = false

		BrowserWindowRegistry.shared.claimSelectedTab(in: self)
		if didWake {
			Task { @MainActor [weak self, weak tab] in
				await Task.yield()
				guard let self, let tab, selectedTabID == id else { return }
				tab.wake()
				configure(tab)
			}
		}

		recentlyUsedTabIDs.removeAll { $0 == id }
		recentlyUsedTabIDs.insert(id, at: 0)
		tab.controller?.loadFaviconIfMissing()
		#if os(macOS)
			if previousTab !== tab {
				previousTab?.controller?.previewSnapshotRefreshSuspended = true
			}
			tab.controller?.previewSnapshotRefreshSuspended = false
		#endif
		// Waking rebuilds the controller (open-tabs changed); pure selection
		// only needs workspace+snapshot.
		schedulePersistence(fullState: didWake)
	}

	func switchCandidates(forward: Bool) -> [UUID] {
		BrowserWorkspace.tabSwitchCandidates(
			visibleTabIDs: visibleTabs.map(\.id),
			selectedTabID: selectedTabID,
			forward: forward
		)
	}

	func commitTabSwitch(to id: UUID) {
		selectTab(id)
	}

	func copyURL(for tab: BrowserTab) {
		guard let url = tab.copyableURL else { return }
		let address = BrowserAddress.withoutCredentials(url)
		#if os(macOS)
			NSPasteboard.general.clearContents()
			guard NSPasteboard.general.setString(address.absoluteString, forType: .string) else { return }
		#elseif os(iOS)
			UIPasteboard.general.url = address
		#endif
		session.toastManager.show(symbol: "doc.on.doc", message: "URL copied")
	}

	var canBookmarkSelectedPage: Bool {
		guard let url = selectedPageBookmarkURL else { return false }
		return !bookmarks.contains { $0.url == url }
	}

	/// Prefer the selected webpage, but keep AI available when an Easel or
	/// other ineligible tab is selected beside an eligible webpage.
	var aiSidebarPageTab: BrowserTab? {
		guard !isPrivate else { return nil }
		if let selectedTab, selectedTab.internalPage == nil, selectedTab.currentURL != nil {
			return selectedTab
		}
		guard isShowingTabSplit else { return nil }
		if let leftID = splitLeftTabID, let leftTab = tab(withID: leftID),
		   leftTab.internalPage == nil, leftTab.currentURL != nil
		{
			return leftTab
		}
		if let rightID = splitRightTabID, let rightTab = tab(withID: rightID),
		   rightTab.internalPage == nil, rightTab.currentURL != nil
		{
			return rightTab
		}
		return nil
	}

	var canShowAISidebar: Bool {
		#if ASTRA_WEBSITE_APP_RUNTIME
			false
		#else
			aiSidebarPageTab != nil
		#endif
	}

	func createBookmarkFolder(_ name: String) {
		guard !isPrivate, !name.isEmpty, name.utf8.count <= 500 else { return }
		if !Defaults[.bookmarkFolderNames].contains(name) {
			Defaults[.bookmarkFolderNames].append(name)
		}
		scheduleUserDataPersistence()
	}

	func bookmarkTabs(_ ids: [UUID]) {
		guard !isPrivate, !isMini else { return }
		var known = Set(bookmarks.map(\.url))
		var didAdd = false
		for id in ids {
			guard let tab = tab(withID: id), tab.internalPage == nil,
			      let url = (tab.activeController?.committedURL ?? tab.currentURL).map(BrowserAddress.withoutCredentials),
			      url.absoluteString.utf8.count <= 16384, known.insert(url).inserted
			else { continue }
			let title = tab.activeController?.webViewIfLoaded?.title ?? tab.title
			guard title.utf8.count <= 16384 else { continue }
			bookmarks.append(Bookmark(name: title, url: url))
			didAdd = true
		}
		if didAdd {
			scheduleUserDataPersistence()
		}
	}

	func bookmarkSelectedPage() {
		guard let tab = selectedTab,
		      let url = selectedPageBookmarkURL,
		      !bookmarks.contains(where: { $0.url == url })
		else { return }
		let title = tab.activeController?.webViewIfLoaded?.title ?? tab.title
		guard title.utf8.count <= 16384 else { return }
		bookmarks.append(Bookmark(name: title, url: url))
		scheduleUserDataPersistence()
	}

	private var selectedPageBookmarkURL: URL? {
		guard let source = selectedTab?.activeController?.committedURL ?? selectedTab?.currentURL else { return nil }
		let url = BrowserAddress.withoutCredentials(source)
		return url.absoluteString.utf8.count <= 16384 ? url : nil
	}

	func updateBookmark(_ id: UUID, name: String, folder: String, isFavorite: Bool, order: Int) {
		guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
		let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let folder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
		guard name.utf8.count <= 16384, folder.utf8.count <= 4096 else { return }
		guard bookmarks[index].name != name || bookmarks[index].folder != folder
			|| bookmarks[index].isFavorite != isFavorite || bookmarks[index].order != order else { return }
		bookmarks[index].name = name
		bookmarks[index].folder = folder
		bookmarks[index].isFavorite = isFavorite
		bookmarks[index].order = order
		bookmarks[index].modifiedAt = BrowserUserDataMutation.nextDate(after: bookmarks[index].modifiedAt, deletion: deletedBookmarksAt[id] ?? .distantPast)
		scheduleUserDataPersistence()
	}

	func reorderBookmarks(_ ids: [UUID]) {
		var updated = bookmarks
		let indexes = Dictionary(updated.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
		var changed = false
		for (order, id) in ids.enumerated() {
			guard let index = indexes[id], updated[index].order != order else { continue }
			updated[index].order = order
			updated[index].modifiedAt = BrowserUserDataMutation.nextDate(after: updated[index].modifiedAt, deletion: deletedBookmarksAt[id] ?? .distantPast)
			changed = true
		}
		guard changed else { return }
		bookmarks = updated
		scheduleUserDataPersistence()
	}

	func addToReadingList(_ url: URL, title: String) {
		guard title.utf8.count <= 16384,
		      canAddToReadingList(url),
		      let safe = BrowserHomepage.validURL(url.absoluteString) else { return }
		readingList.append(ReadingListItem(url: safe, title: title))
		scheduleUserDataPersistence()
	}

	func canAddToReadingList(_ url: URL) -> Bool {
		guard !isPrivate, url.absoluteString.utf8.count <= 16384,
		      let safe = BrowserHomepage.validURL(url.absoluteString) else { return false }
		return !readingList.contains(where: { $0.url == safe })
	}

	func addToReadingList(tabID: UUID) {
		guard canAddToReadingList(tabID: tabID),
		      let tab = tabs.first(where: { $0.id == tabID }),
		      let controller = tab.activeController,
		      controller.session === session, let url = controller.committedURL,
		      controller.url == url else { return }
		addToReadingList(url, title: controller.webViewIfLoaded?.title ?? tab.title)
	}

	func canAddToReadingList(tabID: UUID) -> Bool {
		guard !isPrivate, !isMini,
		      let tab = tabs.first(where: { $0.id == tabID }), tab.internalPage == nil,
		      tab.session === session, let controller = tab.activeController,
		      controller.session === session, let url = controller.committedURL,
		      controller.url == url, controller.canRecordVisit else { return false }
		return canAddToReadingList(url)
	}

	func canSaveReadingListSnapshot(tabID: UUID) -> Bool {
		guard !isPrivate, !isMini,
		      let tab = tabs.first(where: { $0.id == tabID }),
		      let controller = tab.activeController,
		      let item = readingList.first(where: { $0.url == controller.committedURL }) else { return false }
		return ownsReadingListCapture(tab, controller: controller, item: item)
	}

	func setReadingListRead(_ id: UUID, isRead: Bool) {
		guard let index = readingList.firstIndex(where: { $0.id == id }), readingList[index].isRead != isRead else { return }
		readingList[index].isRead = isRead
		readingList[index].modifiedAt = BrowserUserDataMutation.nextDate(after: readingList[index].modifiedAt, deletion: deletedReadingListAt[id] ?? .distantPast)
		scheduleUserDataPersistence()
	}

	func removeReadingListItem(_ id: UUID) {
		guard let item = readingList.first(where: { $0.id == id }) else { return }
		readingList.removeAll { $0.id == id }
		deletedReadingListAt[id] = BrowserUserDataMutation.nextDate(after: item.modifiedAt, deletion: deletedReadingListAt[id] ?? .distantPast)
		if let persistence {
			let previousWrite = session.persistenceWriteTask
			session.persistenceWriteTask = Task.detached(priority: .utility) {
				await previousWrite?.value
				try? persistence.removeReadingArchive(id: id)
			}
		}
		scheduleUserDataPersistence()
	}

	func saveReadingListSnapshot(tabID: UUID) {
		guard let tab = tabs.first(where: { $0.id == tabID }),
		      let controller = tab.activeController,
		      let url = controller.committedURL,
		      let item = readingList.first(where: { $0.url == url }),
		      let webView = controller.webViewIfLoaded,
		      canSaveReadingListSnapshot(tabID: tabID),
		      let persistence else { return }
		let documentID = controller.navigationIdentifier
		webView.createWebArchiveData { [weak self, weak tab, weak controller] result in
			guard let self, let tab, let controller,
			      ownsReadingListCapture(tab, controller: controller, item: item),
			      controller.navigationIdentifier == documentID else { return }
			guard case let .success(data) = result else {
				session.toastManager.show(symbol: "exclamationmark.triangle", message: "Could not capture this page for offline reading")
				return
			}
			let previousWrite = session.persistenceWriteTask
			let browser = self
			let capturedTab = tab
			let capturedController = controller
			session.persistenceWriteTask = Task.detached(priority: .utility) { [browser, capturedTab, capturedController] in
				await previousWrite?.value
				let generation: UUID
				do {
					generation = try persistence.saveReadingArchive(data, id: item.id, url: item.url)
				} catch {
					BrowserLog.error(.persistence, "reading-list.archive-save.failed", metadata: [
						"item": BrowserLog.id(item.id),
						"bytes": String(data.count),
						"error": BrowserLog.errorDescription(error),
					])
					await MainActor.run {
						guard browser.ownsReadingListCapture(capturedTab, controller: capturedController, item: item),
						      capturedController.navigationIdentifier == documentID else { return }
						browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: "Offline copy could not be saved because storage is full or unavailable")
					}
					return
				}
				let stillCurrent = await MainActor.run {
					guard browser.ownsReadingListCapture(capturedTab, controller: capturedController, item: item),
					      capturedController.navigationIdentifier == documentID else { return false }
					browser.session.toastManager.show(symbol: "checkmark.circle", message: "Saved offline copy")
					return true
				}
				if !stillCurrent {
					try? persistence.removeReadingArchive(id: item.id, ifGeneration: generation)
				}
			}
		}
	}

	func openReadingListItem(_ item: ReadingListItem, offline: Bool) {
		guard !isPrivate, !isMini else { return }
		guard offline else {
			openHistoryURL(item.url, inBackground: false)
			return
		}
		guard isRegisteredNormalWindow, let persistence else { return }
		let windowID = windowID
		let sourceTabID = selectedTabID
		let browser = self
		Task.detached(priority: .userInitiated) { [browser] in
			let archive: Result<Data?, Error>
			do {
				archive = try .success(persistence.loadReadingArchive(id: item.id, url: item.url))
			} catch {
				archive = .failure(error)
			}
			await MainActor.run {
				guard browser.windowID == windowID, browser.isRegisteredNormalWindow,
				      browser.selectedTabID == sourceTabID, !browser.isPrivate,
				      let currentItem = browser.readingList.first(where: { $0.id == item.id }),
				      ReadingListItem.admitsOfflineOpen(currentItem, id: item.id, url: item.url, isPrivate: browser.isPrivate) else { return }
				let data: Data
				switch archive {
					case let .success(value):
						guard let value else {
							browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: "No offline copy is available")
							return
						}
						data = value
					case .failure:
						browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: "Could not read the offline copy")
						return
				}
				let tab = browser.addTab()
				guard let controller = tab.activeController, tab.session === browser.session,
				      controller.session === browser.session else { return }
				controller.prepareWebView()
				controller.loadWebArchive(data, baseURL: item.url)
			}
		}
	}

	private var isRegisteredNormalWindow: Bool {
		!isPrivate && !isMini && BrowserWindowRegistry.shared.openBrowsers.contains { $0 === self }
	}

	private func ownsReadingListCapture(_ tab: BrowserTab, controller: BrowserController, item: ReadingListItem) -> Bool {
		guard isRegisteredNormalWindow,
		      tabs.contains(where: { $0 === tab }), tab.internalPage == nil,
		      tab.session === session, tab.activeController === controller,
		      controller.session === session, controller.committedURL == item.url,
		      controller.url == item.url, controller.canRecordVisit,
		      !controller.isLoading, controller.navigationFailure == nil,
		      let webView = controller.webViewIfLoaded,
		      controller.isWebViewReady, webView.url == item.url, !webView.isLoading else { return false }
		return readingList.contains(where: { $0.id == item.id && $0.url == item.url })
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
		tab.activeController?.load(bookmark.url)
	}

	func removeBookmark(_ id: UUID) {
		let removed = bookmarks.first { $0.id == id }
		bookmarks.removeAll { $0.id == id }
		if let removed, ["http", "https"].contains(removed.url.scheme?.lowercased() ?? "") {
			deletedBookmarkIDs.insert(id)
			deletedBookmarksAt[id] = BrowserUserDataMutation.nextDate(after: removed.modifiedAt, deletion: deletedBookmarksAt[id] ?? .distantPast)
		}
		scheduleUserDataPersistence()
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
		BrowserLog.info(.tabs, "tab.close", metadata: ["window": BrowserLog.id(windowID), "tab": BrowserLog.id(id), "confirmed": String(confirmed), "count_before": String(tabs.count)])
		if showsQuickSearch, id == selectedTabID, !confirmed {
			dismissQuickSearch()
			return
		}
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		#if os(iOS)
			let tab = tabs[index]
			let protectedController = ([tab.controller].compactMap(\.self) + tab.peeks.map(\.controller))
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
					let window = unsafe tab.activeController?.webViewIfLoaded?.window
					if await BrowserWebsiteUI.present(alert, in: window) == .alertFirstButtonReturn {
						self?.closeTab(id, confirmed: true)
					}
				}
				return
			}
		#endif
		if id == splitLeftTabID || id == splitRightTabID {
			closeEaselSplit()
		}
		if workspace.favouriteTabIDs.contains(id) || workspace.spaces.contains(where: { $0.pinnedTabIDs.contains(id) }) {
			if tabs[index].internalPage == .easel, let peek = tabs[index].peeks.first {
				tabs[index].dismissPeek(peek.id, confirmed: true)
			} else {
				hibernateTab(id)
			}
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
		let shouldCreateSyncTombstone = isSyncableTab(tabs[index].openTab)
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
		BrowserLog.info(.tabs, "tab.hibernate", metadata: ["tab": BrowserLog.id(id), "background_only": String(onlyIfBackground)])
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

	@discardableResult
	func finishAutomaticHibernation(_ tab: BrowserTab, interactionState: Data) -> Bool {
		guard tabs.contains(where: { $0 === tab }), tab.canHibernate else { return false }
		tab.hibernate(interactionState: interactionState)
		guard tab.isHibernated else { return false }
		BrowserExtensionManager.shared.webViewDidChange(for: tab.id, in: self)
		schedulePersistence()
		return true
	}

	func handleMemoryPressure(_ level: BrowserHibernationManager.PressureLevel) {
		// Reduce idle mounted WebViews immediately; hibernation then reclaims
		// full background WebKit resources after safety and activity checks.
		tabResources.updateMemoryPressure(level)
		automaticHibernationManager?.handleMemoryPressure(level)
	}

	func promotePeek(in source: BrowserTab, id: UUID) {
		guard let sourceIndex = tabs.firstIndex(where: { $0 === source }),
		      let peek = source.takePeekForPromotion(id) else { return }
		let webView = peek.controller.webViewIfLoaded
		let navigationIdentifier = peek.controller.navigationIdentifier
		let tab = BrowserTab(
			pageTitle: peek.controller.webViewIfLoaded?.title ?? "New Tab",
			existingController: peek.controller
		)
		configure(tab)
		tabs.insert(tab, at: sourceIndex + 1)
		reconcileWorkspace()
		if let spaceIndex = workspace.spaces.firstIndex(where: { $0.tabIDs.contains(source.id) }) {
			let space = workspace.spaces[spaceIndex]
			let nextID = space.tabIDs.drop(while: { $0 != source.id }).dropFirst().first
			moveTab(tab.id, to: .normal, in: space.id, before: nextID)
			if let groupIndex = space.todayTabGroups.firstIndex(where: { $0.tabIDs.contains(source.id) }),
			   let groupTabIndex = space.todayTabGroups[groupIndex].tabIDs.firstIndex(of: source.id)
			{
				let group = space.todayTabGroups[groupIndex]
				var tabIDs = group.tabIDs
				tabIDs.insert(tab.id, at: groupTabIndex + 1)
				workspace.spaces[spaceIndex].todayTabGroups[groupIndex] = BrowserTabGroupingFeature.Group(
					name: group.name,
					tabIDs: tabIDs
				)
			}
		}
		markWorkspaceStructureChanged()
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
		BrowserLog.debug(.persistence, "browser.persistence.flush-request", metadata: ["window": BrowserLog.id(windowID)])
		persistenceTask?.cancel()
		persistenceTask = nil
		scrollPersistenceTask?.cancel()
		scrollPersistenceTask = nil
		pendingFullPersistence = true
		persist()
	}

	func updateWindowFrame(_ frame: BrowserWindowFrame) {
		guard !isPrivate, !isMini, savedWindowFrame != frame else { return }
		savedWindowFrame = frame
		guard persistence != nil else { return }
		persistenceTask?.cancel()
		persistenceTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(600))
			guard !Task.isCancelled else { return }
			self?.persist()
		}
	}

	func flushAndWaitForPersistence() async {
		flushPersistence()
		await session.persistenceWriteTask?.value
		if !isPrivate, !isMini {
			await BrowserBoostStore.shared.flushPersistence()
		}
	}

	func markCleanShutdown() async {
		BrowserLog.notice(.persistence, "browser.clean-shutdown", metadata: ["window": BrowserLog.id(windowID)])
		guard !isPrivate, let persistence else { return }
		await session.persistenceWriteTask?.value
		do {
			try await Task.detached(priority: .utility) {
				try persistence.saveShutdownMetadata(clean: true)
			}.value
		} catch {
			BrowserLog.error(.persistence, "browser.shutdown-metadata.failed", metadata: [
				"window": BrowserLog.id(windowID),
				"error": BrowserLog.errorDescription(error),
			])
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
		scheduleUserDataPersistence()
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
		scheduleUserDataPersistence()
	}

	private func ownsHistoryController(_ controller: BrowserController) -> Bool {
		guard controller.session === session else { return false }
		return tabs.contains { tab in
			tab.controller === controller || tab.peeks.contains { $0.controller === controller }
		}
	}

	private func nextHistoryMutationDate(after date: Date) -> Date {
		let latest: Date
		if let cached = latestHistoryMutationDate {
			latest = cached
		} else {
			// Only restoration, cross-window synchronization or bulk deletion
			// can invalidate the cache. The common navigation path is O(1).
			var maximum = historyClearedAt
			for deletedAt in deletedVisitsAt.values where deletedAt > maximum {
				maximum = deletedAt
			}
			for visit in historyVisits where visit.modifiedAt > maximum {
				maximum = visit.modifiedAt
			}
			latest = maximum
		}
		let next = date > latest ? date : latest.addingTimeInterval(0.001)
		latestHistoryMutationDate = next
		return next
	}

	private func visibleHistoryVisits(_ visits: [BrowserVisit]) -> [BrowserVisit] {
		var seenIDs = Set<UUID>()
		return visits.compactMap { source in
			guard let url = BrowserVisit.normalizedURL(source.url),
			      historyClearedAt == .distantPast || source.modifiedAt > historyClearedAt,
			      deletedVisitsAt[source.id].map({ source.modifiedAt > $0 }) ?? true,
			      seenIDs.insert(source.id).inserted else { return nil }
			var visit = source
			visit.url = url
			return visit
		}
	}

	func applyHistoryRetention() {
		guard !isPrivate else { return }
		let days = Defaults[.historyRetentionDays]
		guard days > 0 else { return }
		let retained = BrowserVisit.retained(historyVisits, days: days)
		guard retained.count != historyVisits.count else { return }
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
		scheduleUserDataPersistence()
	}

	private func clearLocalHistory(at date: Date) {
		latestHistoryMutationDate = nil
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
		scheduleUserDataPersistence()
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
		latestHistoryMutationDate = nil
		historyVisits.removeAll { ids.contains($0.id) }
		for id in ids {
			deletedVisitsAt[id] = date
		}
		removeHistoryVisitReferences(ids)
		scheduleUserDataPersistence()
	}

	private func removeHistoryVisitReferences(_ ids: Set<UUID>) {
		for (controllerID, visitID) in Array(lastVisitID) where ids.contains(visitID) {
			lastVisitID.removeValue(forKey: controllerID)
			lastVisitedURL.removeValue(forKey: controllerID)
			lastVisitedDocument.removeValue(forKey: controllerID)
		}
	}

	func importBookmarks(_ incoming: [Bookmark], replacingDuplicates: Bool = false) {
		guard !isPrivate else { return }
		// Import batches must not publish a new @Observable array for every
		// record: a large HTML import otherwise invalidates the whole bookmarks
		// List thousands of times before the user sees the completed result.
		var updated = bookmarks
		var indexes = Dictionary(updated.enumerated().map { ($1.url, $0) }, uniquingKeysWith: { first, _ in first })
		var changed = false
		for bookmark in incoming where BrowserHomepage.validURL(bookmark.url.absoluteString) != nil
			&& bookmark.url.absoluteString.utf8.count <= 16384
			&& bookmark.name.utf8.count <= 16384
			&& bookmark.folder.utf8.count <= 4096
			&& (bookmark.order == Int.min || (0 ... 100_000).contains(bookmark.order))
		{
			if let index = indexes[bookmark.url] {
				guard replacingDuplicates else { continue }
				let current = updated[index]
				guard current.name != bookmark.name || current.folder != bookmark.folder
					|| current.isFavorite != bookmark.isFavorite || current.order != bookmark.order else { continue }
				updated[index] = Bookmark(id: current.id, name: bookmark.name, url: BrowserAddress.withoutCredentials(bookmark.url), modifiedAt: BrowserUserDataMutation.nextDate(after: current.modifiedAt, deletion: deletedBookmarksAt[current.id] ?? .distantPast), folder: bookmark.folder, isFavorite: bookmark.isFavorite, order: bookmark.order == Int.min ? updated.count : bookmark.order)
				changed = true
			} else {
				let imported = Bookmark(name: bookmark.name, url: BrowserAddress.withoutCredentials(bookmark.url), modifiedAt: bookmark.modifiedAt, folder: bookmark.folder, isFavorite: bookmark.isFavorite, order: bookmark.order == Int.min ? updated.count : bookmark.order)
				indexes[bookmark.url] = updated.count
				updated.append(imported)
				changed = true
			}
		}
		guard changed else { return }
		bookmarks = updated
		scheduleUserDataPersistence()
	}

	func importReadingList(_ incoming: [ReadingListItem], replacingDuplicates: Bool = false) {
		guard !isPrivate else { return }
		var updated = readingList
		var indexes = Dictionary(updated.enumerated().map { ($1.url, $0) }, uniquingKeysWith: { first, _ in first })
		var changed = false
		for item in incoming where BrowserHomepage.validURL(item.url.absoluteString) != nil
			&& item.url.absoluteString.utf8.count <= 16384
			&& item.title.utf8.count <= 16384
		{
			if let index = indexes[item.url] {
				guard replacingDuplicates else { continue }
				let current = updated[index]
				guard current.title != item.title || current.isRead != item.isRead else { continue }
				updated[index] = ReadingListItem(id: current.id, url: item.url, title: item.title, addedAt: item.addedAt, modifiedAt: BrowserUserDataMutation.nextDate(after: current.modifiedAt, deletion: deletedReadingListAt[current.id] ?? .distantPast), isRead: item.isRead)
				changed = true
			} else {
				let imported = ReadingListItem(url: item.url, title: item.title, addedAt: item.addedAt, modifiedAt: item.modifiedAt, isRead: item.isRead)
				indexes[item.url] = updated.count
				updated.append(imported)
				changed = true
			}
		}
		guard changed else { return }
		readingList = updated
		scheduleUserDataPersistence()
	}

	func importHistory(_ incoming: [BrowserVisit]) {
		guard !isPrivate else { return }
		var updated = historyVisits
		var existing = Set(updated.map { "\($0.url.absoluteString)\u{1f}\($0.visitedAt.timeIntervalSince1970.bitPattern)" })
		var existingIDs = Set(updated.map(\.id))
		let mutationDate = nextHistoryMutationDate(after: .now)
		var changed = false
		for source in BrowserVisit.retained(incoming, days: Defaults[.historyRetentionDays]) {
			guard var visit = visibleHistoryVisits([source]).first else { continue }
			let key = "\(visit.url.absoluteString)\u{1f}\(visit.visitedAt.timeIntervalSince1970.bitPattern)"
			guard existing.insert(key).inserted, existingIDs.insert(visit.id).inserted else { continue }
			visit.modifiedAt = mutationDate
			updated.append(visit)
			changed = true
		}
		guard changed else { return }
		updated.sort { $0.visitedAt > $1.visitedAt }
		historyVisits = updated
		scheduleUserDataPersistence()
	}

	private func attachPersistence(to tab: BrowserTab) {
		tab.didChange = { [weak self, id = tab.id] in
			guard let self else { return }
			tabSearchRevision &+= 1
			// Navigation/title/peek metadata changes do not change extension
			// tab membership. Update the affected tab only, while still
			// scheduling full cross-window persistence and synchronization.
			BrowserExtensionManager.shared.tabPropertiesDidChange(for: id, in: self)
			schedulePersistence(fullState: true, syncExtensions: false)
		}
		tab.didRecordHistoryVisit = { [weak self] controller, url, title, navigationID in
			self?.recordHistoryVisit(from: controller, url: url, title: title, navigationID: navigationID)
		}
		tab.didUpdateHistoryVisitTitle = { [weak self] controller, url, title, navigationID in
			self?.updateHistoryVisitTitle(from: controller, url: url, title: title, navigationID: navigationID)
		}
		tab.didScrollChange = { [weak self, id = tab.id] isPeek in
			if isPeek {
				// OpenPeek scroll state lives inside the parent tab snapshot;
				// do not silently lose it through the parent-only scroll journal.
				self?.schedulePersistence(fullState: true, syncExtensions: false)
			} else {
				self?.scheduleScrollPersistence(for: id)
			}
		}
	}

	func prepareSelectedTabDisplayOwner() {
		selectedTab?.controller?.displayWindowID = windowID
		for peek in selectedTab?.peeks ?? [] {
			peek.controller.displayWindowID = windowID
		}
	}

	func configureSelectedTab() {
		if let tab = selectedTab {
			configure(tab)
		}
	}

	func configureOwnedTabs() {
		// Unregistering one window previously checked each of this window's
		// tabs against every other window, then repeated the same global scan
		// inside configure(_:). Resolve ownership once for the entire batch.
		let ownedIDs = BrowserWindowRegistry.shared.ownedTabIDs(in: self)
		for tab in tabs where ownedIDs.contains(tab.id) {
			configure(tab, ownershipVerified: true)
		}
	}

	private func configure(_ tab: BrowserTab, ownershipVerified: Bool = false) {
		guard ownershipVerified || BrowserWindowRegistry.shared.ownsTab(tab.id, in: self) else { return }
		if tab.internalPage == .easel {
			attachPersistence(to: tab)
			for peek in tab.peeks {
				configure(peek, in: tab)
			}
			return
		}
		guard let controller = tab.controller else { return }
		controller.displayWindowID = windowID
		controller.navigationIntercept = navigationIntercept
		if controller.browserConfigurationWindowID == windowID {
			// Tab selection used to reinstall every callback closure on every click.
			// Existing controllers only need newly-created peeks checked.
			for peek in tab.peeks {
				configure(peek, in: tab)
			}
			return
		}
		controller.browserConfigurationWindowID = windowID
		attachPersistence(to: tab)
		controller.pictureInPictureRestoreRequested = { [weak self, weak tab, weak controller] in
			guard let self, let tab, let controller else { return }
			selectTab(tab.id)
			tab.showPictureInPictureController(controller)
			#if os(macOS)
				unsafe controller.webViewIfLoaded?.window?.makeKeyAndOrderFront(nil)
				NSApp.activate(ignoringOtherApps: true)
			#endif
		}
		controller.promptOwnership = { [weak self, weak tab, weak controller] webView in
			guard let self, let tab, let controller,
			      tabs.contains(where: { $0 === tab }),
			      selectedTabID == tab.id,
			      tab.activeController === controller else { return false }
			return unsafe webView.window != nil
		}
		controller.extensionStateDidChange = { [weak self, id = tab.id] in
			guard let self else { return }
			BrowserExtensionManager.shared.loadingDidChange(for: id, in: self)
		}
		controller.extensionWebViewDidChange = { [weak self, id = tab.id] in
			guard let self else { return }
			BrowserExtensionManager.shared.webViewDidChange(for: id, in: self)
		}
		controller.popupRequested = { [weak self, weak tab, weak controller] configuration, source, inBackground in
			guard let self, let tab, let controller else { return nil }
			return createPopup(configuration: configuration, source: source, in: tab, depth: 1, parentZoom: controller.pageZoom, inBackground: inBackground)
		}
		controller.easelQuoteDestinations = { [weak self, weak tab] in
			guard let self, let tab else { return [] }
			return easelQuoteDestinations(for: tab)
		}
		controller.addQuoteToEasel = { [weak self, weak tab] destinationID, quote in
			guard let self, let tab else { return }
			addEaselQuote(quote, to: destinationID, from: tab.id)
		}
		controller.newTabRequested = { [weak self, weak controller, weak tab] request, inBackground in
			guard let self else { return }
			if isMini {
				controller?.navigate(request)
			} else {
				openNewTab(request, inBackground: inBackground, after: tab?.id)
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
		peek.controller.displayWindowID = windowID
		peek.controller.navigationIntercept = navigationIntercept
		guard peek.controller.browserConfigurationWindowID != windowID else { return }
		peek.controller.browserConfigurationWindowID = windowID
		peek.controller.pictureInPictureRestoreRequested = { [weak self, weak tab, weak controller = peek.controller] in
			guard let self, let tab, let controller else { return }
			selectTab(tab.id)
			tab.showPictureInPictureController(controller)
			#if os(macOS)
				unsafe controller.webViewIfLoaded?.window?.makeKeyAndOrderFront(nil)
				NSApp.activate(ignoringOtherApps: true)
			#endif
		}
		peek.controller.promptOwnership = { [weak self, weak tab, weak controller = peek.controller] webView in
			guard let self, let tab, let controller,
			      tabs.contains(where: { $0 === tab }),
			      selectedTabID == tab.id,
			      tab.activeController === controller else { return false }
			return unsafe webView.window != nil
		}
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
			if inBackground != nil {
				placeOpenedTab(popupTab.id, after: tab.id)
			}
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

	private func openNewTab(_ request: URLRequest, inBackground: Bool, after sourceID: UUID? = nil) {
		let tab = addTab(inBackground: inBackground)
		if let sourceID {
			placeOpenedTab(tab.id, after: sourceID)
		}
		#if os(macOS)
			tab.controller?.previewSnapshotRefreshSuspended = inBackground
		#endif
		tab.controller?.navigate(request)
		tab.controller?.prepareWebView()
	}

	/// Keep command-clicked links directly below the source rather than at the
	/// bottom of Daily Tabs (or inside pinned/favourites).
	private func placeOpenedTab(_ newID: UUID, after sourceID: UUID) {
		guard newID != sourceID else { return }
		if isPrivate {
			guard let source = tabs.firstIndex(where: { $0.id == sourceID }),
			      let new = tabs.firstIndex(where: { $0.id == newID }) else { return }
			let tab = tabs.remove(at: new)
			tabs.insert(tab, at: min(source + 1, tabs.count))
			return
		}
		guard let space = workspace.spaces.first(where: { $0.tabIDs.contains(sourceID) }) ?? workspace.spaces.first(where: { $0.id == workspace.selectedSpaceID }) else { return }
		let isNormalSource = space.tabIDs.contains(sourceID) && !space.pinnedTabIDs.contains(sourceID)
		let nextID: UUID? = isNormalSource
			? space.tabIDs.drop(while: { $0 != sourceID }).dropFirst().first(where: { !space.pinnedTabIDs.contains($0) && $0 != newID })
			: space.tabIDs.first(where: { !space.pinnedTabIDs.contains($0) && $0 != newID })
		moveTab(newID, to: .normal, in: space.id, before: nextID)
		if isNormalSource,
		   let index = workspace.spaces.firstIndex(where: { $0.id == space.id }),
		   let groupIndex = workspace.spaces[index].todayTabGroups.firstIndex(where: { $0.tabIDs.contains(sourceID) }),
		   let sourcePosition = workspace.spaces[index].todayTabGroups[groupIndex].tabIDs.firstIndex(of: sourceID)
		{
			let group = workspace.spaces[index].todayTabGroups[groupIndex]
			var tabIDs = group.tabIDs
			tabIDs.insert(newID, at: sourcePosition + 1)
			workspace.spaces[index].todayTabGroups[groupIndex] = BrowserTabGroupingFeature.Group(
				name: group.name,
				tabIDs: tabIDs
			)
			markWorkspaceStructureChanged()
			schedulePersistence()
		}
	}

	private func removeTabs(_ ids: Set<UUID>, selecting selectedID: UUID, confirmed: Bool = false) {
		let workflowStart = BrowserLog.clock()
		defer {
			BrowserLog.duration(.performance, "workflow.tabs.close-to-model-commit",
			                    since: workflowStart, warnAboveMilliseconds: 24,
			                    metadata: [
			                    	"requested": String(ids.count),
			                    	"confirmed": String(confirmed),
			                    	"tabs_remaining": String(tabs.count),
			                    ])
		}
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
				[tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)
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
			if !confirmed, removedTabs.contains(where: { tab in
				tab.controller?.requiresMediaTeardownConfirmation == true
					|| tab.peeks.contains { $0.controller.requiresMediaTeardownConfirmation }
			}) {
				return
			}
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
				if let input = tab.restorationInput { pendingClosedRestoration[tab.id] = input }
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

	/// Captures only immutable values; projection, validation and encoding run off-main.
	func captureSyncDocument(settings: [String: SyncedSetting]) -> BrowserSyncDocument {
		reconcileWorkspace()
		return completeLocalSyncDocument(settings: settings)
	}

	private func completeLocalSyncDocument(settings: [String: SyncedSetting]) -> BrowserSyncDocument {
		BrowserSyncDocument(
			tabs: tabs.map(\.openTab),
			workspace: workspace,
			bookmarks: bookmarks,
			readingList: readingList,
			history: historyVisits,
			browser: BrowserSnapshot(
				selectedTabID: persistedSelectedTabID,
				selectedTabModifiedAt: selectedTabModifiedAt,
				closedTabIDs: closedTabIDs,
				deletedBookmarkIDs: deletedBookmarkIDs,
				deletedBookmarksAt: deletedBookmarksAt,
				deletedReadingListAt: deletedReadingListAt,
				closedTabsAt: closedTabsAt,
				deletedSpacesAt: deletedSpacesAt,
				deletedVisitsAt: deletedVisitsAt,
				historyClearedAt: historyClearedAt
			),
			settings: settings,
			boosts: BrowserBoostStore.shared.boosts,
			deletedBoostsAt: BrowserBoostStore.shared.deletedAt
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
		applyPreparedSyncDocument(document, localPortableTabs: localPortableTabs)
	}

	/// The sync engine prepares local-only preservation and portable comparisons
	/// off-main, then verifies the captured revision before calling this method.
	func applyPreparedSyncDocument(_ document: BrowserSyncDocument, localPortableTabs: [UUID: OpenTab], bookmarksChanged: Bool = true, readingListChanged: Bool = true, historyChanged: Bool = true, workspaceChanged: Bool = true) {
		BrowserLog.syncEvent("browser.sync.apply-document", metadata: ["window": BrowserLog.id(windowID)])
		guard !isPrivate else { return }
		BrowserBoostStore.shared.merge(remote: document.boosts, deleted: document.deletedBoostsAt)
		let incomingReadingItems = Dictionary(document.readingList.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
		let removedReadingIDs = Set(readingList.filter { incomingReadingItems[$0.id]?.url != $0.url }.map(\.id))
		let currentTabs = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
		// Portable projection excludes blank tabs, but locally retained blank tabs
		// must survive sync merges and shared-window publications.
		let changedTabs = document.tabs.compactMap { saved -> BrowserTab? in
			let internalPage = saved.internalPage.flatMap(BrowserInternalPage.init(persistenceID:))
			guard saved.internalPage == nil || internalPage != nil else { return nil }
			if let current = currentTabs[saved.id] ?? BrowserWindowRegistry.shared.sharedTab(withID: saved.id, for: self),
			   current.internalPage == internalPage
			{
				if localPortableTabs[saved.id] == saved
					|| current.modifiedAt > saved.modifiedAt
					|| !current.canHibernate
				{
					return current
				}
				if current.currentURL.map(BrowserAddress.withoutCredentials) != saved.url, let url = saved.url {
					current.controller?.load(url)
				}
				current.applySynchronizedMetadata(from: saved)
				return current
			}
			let tab = BrowserTab(
				id: saved.id,
				internalPage: internalPage,
				pageTitle: saved.pageTitle,
				customTitle: saved.customTitle,
				monitorMatch: saved.monitorMatch,
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
				easel: saved.easel,
				suppressInitialHistoryVisit: true
			)
			configure(tab)
			return tab
		}
		let changedTabIDs = Set(changedTabs.map(\.id))
		let retainedInternalTabs = tabs.filter {
			$0.internalPage != nil && $0.internalPage != .easel && !changedTabIDs.contains($0.id)
		}
		if changedTabs.isEmpty, retainedInternalTabs.isEmpty {
			let tab = BrowserTab(session: session)
			configure(tab)
			tabs = [tab]
		} else {
			let nextTabs = changedTabs + retainedInternalTabs
			if tabs.count != nextTabs.count || zip(tabs, nextTabs).contains(where: { $0 !== $1 }) {
				tabs = nextTabs
			}
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
		deletedReadingListAt = document.browser.deletedReadingListAt
		if readingListChanged, readingList != document.readingList {
			readingList = document.readingList
		}
		if let persistence, !removedReadingIDs.isEmpty {
			let previousWrite = session.persistenceWriteTask
			session.persistenceWriteTask = Task.detached(priority: .utility) {
				await previousWrite?.value
				for id in removedReadingIDs {
					try? persistence.removeReadingArchive(id: id)
				}
			}
		}
		deletedSpacesAt = document.browser.deletedSpacesAt
		deletedVisitsAt = document.browser.deletedVisitsAt
		historyClearedAt = document.browser.historyClearedAt
		if bookmarksChanged {
			bookmarks = document.bookmarks
		}
		if historyChanged {
			let nextHistory = visibleHistoryVisits(document.history)
			if historyVisits != nextHistory {
				historyVisits = nextHistory
			}
			latestHistoryMutationDate = nil
		}
		if workspaceChanged {
			workspace = document.workspace ?? BrowserWorkspace.migrated(
				tabs: document.tabs,
				selectedTabID: document.browser.selectedTabID,
				theme: Defaults[.browserTheme]
			)
		}
		let missingDeletedSpaces = Set(document.browser.deletedSpacesAt.keys).subtracting(workspace.deletedSpaceIDs)
		if !missingDeletedSpaces.isEmpty {
			workspace.deletedSpaceIDs.formUnion(missingDeletedSpaces)
		}
		for (id, date) in document.browser.deletedSpacesAt where date > (workspace.deletedSpacesAt[id] ?? .distantPast) {
			workspace.deletedSpacesAt[id] = date
		}
		if !tabs.contains(where: { $0.id == selectedTabID }) {
			selectedTabID = tabs[0].id
		}
		if let selectedTab, selectedTab.isHibernated {
			selectedTab.wake()
			configure(selectedTab)
		}
		let liveTabIDs = Set(tabs.map(\.id))
		recentlyUsedTabIDs = recentlyUsedTabIDs.filter { liveTabIDs.contains($0) }
		if !recentlyUsedTabIDs.contains(selectedTabID) {
			recentlyUsedTabIDs.insert(selectedTabID, at: 0)
		}
		reconcileWorkspace()
		schedulePersistence()
	}

	/// A source snapshot is created once per publication rather than once per
	/// destination window. Keep the payload immutable so all windows receive
	/// the same source revision, even if applying it changes shared tab models.
	/// Keep closed-history conflict resolution deterministic without forcing
	/// the Swift type checker through a deeply nested collection expression.
	private nonisolated static func preferredClosedHistoryRecord(_ current: OpenTab, _ incoming: OpenTab) -> OpenTab {
		if current.modifiedAt != incoming.modifiedAt {
			return current.modifiedAt > incoming.modifiedAt ? current : incoming
		}
		if current == incoming {
			return current
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		let currentData = (try? encoder.encode(current)) ?? Data()
		let incomingData = (try? encoder.encode(incoming)) ?? Data()
		return currentData.lexicographicallyPrecedes(incomingData) ? incoming : current
	}

	func publishSharedState(to recipients: [Browser]) {
		guard !isPrivate, !recipients.isEmpty else { return }
		let started = BrowserLog.clock()
		let snapshot = completeLocalSyncDocument(settings: [:])
		let closed = closedHistoryTabs
		BrowserLog.duration(.sync, "browser.shared-state.snapshot", since: started,
		                    warnAboveMilliseconds: 16,
		                    metadata: ["tabs": String(snapshot.tabs.count), "windows": String(recipients.count)])
		for destination in recipients where destination !== self && !destination.isPrivate {
			destination.receiveSharedState(from: self, sourceSnapshot: snapshot, sourceClosedTabs: closed)
		}
	}

	func receiveSharedState(from source: Browser) {
		guard !isPrivate, !source.isPrivate else { return }
		receiveSharedState(from: source,
		                   sourceSnapshot: source.completeLocalSyncDocument(settings: [:]),
		                   sourceClosedTabs: source.closedHistoryTabs)
	}

	private func receiveSharedState(
		from source: Browser, sourceSnapshot: BrowserSyncDocument, sourceClosedTabs: [OpenTab]
	) {
		sharedMergeTask?.cancel()
		sharedMergeTask = Task { @MainActor [weak self, weak source] in
			guard let self, let source else { return }
			await mergeSharedState(from: source, sourceSnapshot: sourceSnapshot, sourceClosedTabs: sourceClosedTabs)
		}
	}

	private nonisolated struct SharedMergeResult: Sendable {
		let document: BrowserSyncDocument
		let closed: [OpenTab]
		let documentChanged: Bool
		let closedChanged: Bool
		let localPortable: [UUID: OpenTab]
		let bookmarksChanged: Bool
		let readingListChanged: Bool
		let historyChanged: Bool
		let workspaceChanged: Bool
	}

	private func mergeSharedState(from source: Browser, sourceSnapshot: BrowserSyncDocument, sourceClosedTabs: [OpenTab]) async {
		BrowserLog.debug(.sync, "browser.shared-state.receive", metadata: ["window": BrowserLog.id(windowID), "source_window": BrowserLog.id(source.windowID)])
		guard !isPrivate, !source.isPrivate else { return }
		let started = BrowserLog.clock()
		defer {
			BrowserLog.duration(.sync, "browser.shared-state.receive.end", since: started,
			                    warnAboveMilliseconds: 24,
			                    metadata: ["window": BrowserLog.id(windowID)])
		}
		// Never cancel a pending local write just because another window
		// published an unchanged snapshot. The merge below decides whether
		// any receiving state actually needs to be applied.
		let selectedTabBeforeMerge = selectedTabID
		let selectedTabDateBeforeMerge = selectedTabModifiedAt
		let selectedSpaceBeforeMerge = workspace.selectedSpaceID
		let selectionDateBeforeMerge = workspace.selectionModifiedAt
		let selectedTabsBySpace = Dictionary(uniqueKeysWithValues: workspace.spaces.map { ($0.id, $0.selectedTabID) })
		let recentlyUsedBeforeMerge = recentlyUsedTabIDs
		let closedHistoryBeforeMerge = closedHistoryTabs
		let localState = completeLocalSyncDocument(settings: [:])
		let generation = syncRevision
		let capturedLocal = localState
		let historyCutoff = historyClearedAt
		let worker = Task.detached(priority: .utility) {
			var localState = capturedLocal
			var incomingState = sourceSnapshot
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
			// The publishing normal window is authoritative for locally stored
			// blank tabs, including their closure. Preserve other local-only data.
			var localWithoutBlankTabs = localState
			localWithoutBlankTabs.tabs.removeAll { $0.isDiscardableNewTab }
			var merged = localState.merging(incomingState)
			merged = merged.preservingLocalOnlyData(from: localWithoutBlankTabs)
			merged = merged.preservingLocalOnlyData(from: incomingState)
			let openIDs = Set(merged.tabs.map(\.id))
			let candidates = closedHistoryBeforeMerge + sourceClosedTabs
			let records = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: Self.preferredClosedHistoryRecord)
			let closed = records.values.filter { !openIDs.contains($0.id) && (historyCutoff == .distantPast || $0.modifiedAt > historyCutoff) }.sorted {
				$0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt
			}
			let prepared = merged.preservingLocalOnlyData(from: capturedLocal)
			let portable = Dictionary(capturedLocal.portableProjection().tabs.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
			return SharedMergeResult(document: prepared, closed: closed, documentChanged: merged != capturedLocal,
			                         closedChanged: closed != closedHistoryBeforeMerge, localPortable: portable,
			                         bookmarksChanged: prepared.bookmarks != capturedLocal.bookmarks,
			                         readingListChanged: prepared.readingList != capturedLocal.readingList,
			                         historyChanged: prepared.history != capturedLocal.history,
			                         workspaceChanged: prepared.workspace != capturedLocal.workspace)
		}
		let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
		guard !Task.isCancelled else { return }
		guard syncRevision == generation else {
			// Retry against fresh local values; never overwrite an edit made during the worker merge.
			receiveSharedState(from: source, sourceSnapshot: sourceSnapshot, sourceClosedTabs: sourceClosedTabs)
			return
		}

		let documentChanged = result.documentChanged
		let closedHistoryChanged = result.closedChanged
		let mergedClosedHistory = result.closed
		if documentChanged {
			applyPreparedSyncDocument(result.document, localPortableTabs: result.localPortable,
			                          bookmarksChanged: result.bookmarksChanged, readingListChanged: result.readingListChanged,
			                          historyChanged: result.historyChanged, workspaceChanged: result.workspaceChanged)
		}
		// The merge has finalized the tab collection. A hash lookup avoids
		// rescanning all open tabs for each closed-history record and MRU entry.
		let openIDs = Set(tabs.map(\.id))
		if closedHistoryChanged {
			closedHistoryTabs = mergedClosedHistory
		}
		guard documentChanged || closedHistoryChanged else {
			BrowserLog.trace(.sync, "browser.shared-state.no-op",
			                 metadata: ["window": BrowserLog.id(windowID)])
			return
		}
		// Only a changed synchronization document can alter selection and
		// workspace membership. Closed-history-only changes need durability,
		// but must not touch the live workspace or extension bridges.
		if documentChanged {
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
			recentlyUsedTabIDs = recentlyUsedBeforeMerge.filter { openIDs.contains($0) }
			if !recentlyUsedTabIDs.contains(selectedTabID) {
				recentlyUsedTabIDs.insert(selectedTabID, at: 0)
			}
			reconcileWorkspace()
		} else {
			// No live document changes: persist the updated closed history only.
			scheduleUserDataPersistence()
		}
	}

	private func markWorkspaceStructureChanged() {
		let mutationDate = nextWorkspaceMutationDate()
		workspace.modifiedAt = mutationDate
		#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
			if !isPrivate, !isMini {
				AstraSpotlightIndexer.scheduleRefresh()
			}
		#endif
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
		var reconciled = workspace
		if reconciled.spaces.isEmpty {
			reconciled = BrowserWorkspace.migrated(
				tabs: tabs.map(\.openTab),
				selectedTabID: selectedTabID,
				theme: Defaults[.browserTheme]
			)
		}
		if !reconciled.spaces.contains(where: { $0.id == reconciled.selectedSpaceID }) {
			reconciled.selectedSpaceID = reconciled.spaces[0].id
		}
		let existingIDs = Set(tabs.map(\.id))
		let assignedIDs = Set(reconciled.favouriteTabIDs + reconciled.spaces.flatMap(\.tabIDs))
		let unassignedIDs = tabs.map(\.id).filter { !assignedIDs.contains($0) }
		reconciled.reconcileMembership(existingTabIDs: existingIDs, unassignedTabIDs: unassignedIDs)
		let easelIDs = Set(tabs.filter { $0.internalPage == .easel }.map(\.id))
		if !easelIDs.isEmpty {
			for index in reconciled.spaces.indices {
				for id in reconciled.spaces[index].tabIDs where easelIDs.contains(id) && !reconciled.spaces[index].pinnedTabIDs.contains(id) {
					reconciled.spaces[index].pinnedTabIDs.append(id)
				}
			}
		}
		if let index = reconciled.spaces.firstIndex(where: { $0.id == reconciled.selectedSpaceID }),
		   reconciled.spaces[index].tabIDs.contains(selectedTabID)
		   || reconciled.favouriteTabIDs.contains(selectedTabID)
		{
			reconciled.spaces[index].selectedTabID = selectedTabID
		}
		if workspace != reconciled {
			workspace = reconciled
		}
	}

	private func schedulePersistence(fullState: Bool = true, syncExtensions: Bool = true) {
		BrowserLog.trace(.persistence, "browser.persistence.schedule", metadata: ["window": BrowserLog.id(windowID), "full": String(fullState), "hydrated": String(didFinishHydration)])
		guard !isPrivate else { return }
		// Invalidate before any suspension: a sync merge must detect concurrent edits.
		syncRevision &+= 1
		BrowserSync.shared.scheduleSync()
		if launchCacheSeeded, !didFinishHydration {
			launchCacheWasModified = true
		}
		// Selection-only persistence is a hot path and extension activation is
		// already handled by BrowserWindowRegistry. Rebuilding every extension-tab
		// snapshot here made each ordinary tab click walk the entire tab set again.
		if fullState, syncExtensions {
			BrowserExtensionManager.shared.sync(self)
		}
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
			if pendingFullPersistence || pendingScrollPersistence {
				persist()
			} else {
				persistSelectionOnly()
			}
		}
	}

	private func schedulePersistence() {
		schedulePersistence(fullState: true)
	}

	/// Bookmarks, reading-list items and history need full durable/cross-window
	/// saves, but cannot change WebExtension tab membership or pinning. Avoid
	/// invoking sync(_:) over the entire tab collection for these UI actions.
	private func scheduleUserDataPersistence() {
		schedulePersistence(fullState: true, syncExtensions: false)
		#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
			if !isPrivate, !isMini {
				AstraSpotlightIndexer.scheduleRefresh()
			}
		#endif
	}

	private func scheduleSelectionPersistence() {
		schedulePersistence(fullState: false)
	}

	private func scheduleScrollPersistence(for tabID: UUID) {
		guard !isPrivate, persistence != nil else { return }
		syncRevision &+= 1
		BrowserSync.shared.scheduleSync()
		pendingScrollTabIDs.insert(tabID)
		pendingScrollPersistence = true
		guard didFinishHydration else { return }
		scrollPersistenceTask?.cancel()
		scrollPersistenceTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(1500))
			guard !Task.isCancelled else { return }
			self?.persistScrollOnly()
		}
	}

	/// Only snapshot a handful of changed scroll positions on the main actor.
	/// Expensive JSON IO is serialized with all other session writes off-main.
	private func persistScrollOnly() {
		guard !hydrationFailed, didFinishHydration, !isPrivate,
		      let persistence, !pendingFullPersistence else { return }
		let changedIDs = pendingScrollTabIDs
		pendingScrollTabIDs.removeAll()
		pendingScrollPersistence = false
		let updates: [BrowserScrollUpdate] = changedIDs.compactMap { id in
			guard let tab = tab(withID: id), !tab.isHibernated,
			      let controller = tab.controller,
			      tab.internalPage == nil else { return nil }
			return BrowserScrollUpdate(
				tabID: id,
				url: tab.currentURL.map(BrowserAddress.withoutCredentials),
				historyIndex: tab.scrollHistoryIndex,
				position: controller.scrollPosition,
				modifiedAt: tab.modifiedAt
			)
		}
		guard !updates.isEmpty else { return }
		let previousWrite = session.persistenceWriteTask
		session.persistenceWriteTask = Task.detached(priority: .utility) { [persistence, updates] in
			await previousWrite?.value
			do {
				try persistence.saveScrollUpdates(updates)
				await MainActor.run { [weak self] in
					self?.persistenceErrorDescription = nil
				}
			} catch {
				let reason = error.localizedDescription
				BrowserLog.warning(.persistence, "scroll.save.failed",
				                   metadata: ["error": BrowserLog.errorDescription(error)])
				await MainActor.run { [weak self] in
					guard let self else { return }
					persistenceErrorDescription = reason
					// Missing initial checkpoint: create a full one so subsequent
					// scrolls can use the much smaller journal safely.
					schedulePersistence(fullState: true, syncExtensions: false)
				}
			}
		}
	}

	/// Avoid rebuilding every tab, history entry and window record on the
	/// ordinary tab selection path. The checkpoint is merged during hydration.
	private func persistSelectionOnly() {
		guard !hydrationFailed, didFinishHydration, !isPrivate, let persistence else { return }
		BrowserLaunchCache.updateSelection(tabID: selectedTabID, spaceID: workspace.selectedSpaceID)
		if !BrowserLaunchCache.containsSelection(tabID: selectedTabID, spaceID: workspace.selectedSpaceID), let selectedTab {
			let space = selectedSpace
			var tabIDs = Array(space.tabIDs.prefix(BrowserLaunchCache.maximumTabs))
			if !tabIDs.contains(selectedTabID) { tabIDs.append(selectedTabID) }
			BrowserLaunchCache.includeSelection(
				tab: .init(id: selectedTabID, url: selectedTab.currentURL.map(BrowserAddress.withoutCredentials), title: String(selectedTab.title.prefix(240)), order: BrowserLaunchCache.maximumTabs - 1, internalPage: selectedTab.internalPage == .easel ? "easel" : nil),
				space: .init(id: space.id, name: String(space.name.prefix(80)), symbol: space.symbol, theme: space.theme, tabIDs: tabIDs, selectedTabID: selectedTabID))
		}
		let update = BrowserSelectionUpdate(
			windowID: windowID,
			selectedTabID: selectedTabID,
			selectedTabModifiedAt: selectedTabModifiedAt,
			selectedSpaceID: workspace.selectedSpaceID
		)
		let previousWrite = session.persistenceWriteTask
		session.persistenceWriteTask = Task.detached(priority: .utility) { [persistence, update] in
			await previousWrite?.value
			do {
				try persistence.saveSelectionUpdate(update)
				await MainActor.run { [weak self] in
					self?.persistenceErrorDescription = nil
				}
			} catch {
				let message = error.localizedDescription
				BrowserLog.error(.persistence, "selection.save.failed", metadata: [
					"error": BrowserLog.errorDescription(error),
				])
				await MainActor.run { [weak self] in
					self?.persistenceErrorDescription = message
				}
			}
		}
	}

	private func persist() {
		BrowserLog.debug(.persistence, "browser.persistence.snapshot", metadata: ["window": BrowserLog.id(windowID), "tabs": String(tabs.count), "bookmarks": String(bookmarks.count), "history": String(historyVisits.count)])
		guard !hydrationFailed else { return }
		guard let persistence else { return }
		guard didFinishHydration else {
			pendingFullPersistence = true
			return
		}
		let preparationStart = BrowserLog.clock()
		reconcileWorkspace()
		let isStructural = pendingFullPersistence
		pendingFullPersistence = false
		pendingScrollPersistence = false
		pendingScrollTabIDs.removeAll()
		scrollPersistenceTask?.cancel()
		scrollPersistenceTask = nil
		// Persist New Tabs (including URL-less ones) with stable IDs, order,
		// selection and space membership, just like navigated tabs.
		let savedTabs = tabs.map(\.openTab)
		let restorationInputs = Dictionary(uniqueKeysWithValues: tabs.compactMap { tab in tab.restorationInput.map { (tab.id, $0) } })
		let restorationSealer = BrowserRestorationStore.sealer
		let closedRestorationInputs = pendingClosedRestoration
		let savedIDs = Set(savedTabs.map(\.id))
		var savedWorkspace = workspace
		savedWorkspace.reconcileMembership(existingTabIDs: savedIDs, unassignedTabIDs: [])
		let savedSelection = savedIDs.contains(selectedTabID) ? selectedTabID : savedTabs.first?.id ?? selectedTabID
		let state = BrowserPersistedState(
			bookmarks: bookmarks,
			readingList: readingList,
			openTabs: savedTabs,
			closedTabs: closedHistoryTabs,
			workspace: savedWorkspace,
			snapshot: BrowserSnapshot(
				selectedTabID: savedSelection,
				selectedTabModifiedAt: selectedTabModifiedAt,
				closedTabIDs: closedTabIDs,
				deletedBookmarkIDs: deletedBookmarkIDs,
				deletedBookmarksAt: deletedBookmarksAt,
				deletedReadingListAt: deletedReadingListAt,
				closedTabsAt: closedTabsAt,
				deletedSpacesAt: deletedSpacesAt,
				deletedVisitsAt: deletedVisitsAt,
				historyClearedAt: historyClearedAt
			),
			historyVisits: historyVisits,
			windowRecords: BrowserWindowRegistry.shared.recordsForPersistence
		)
		persistLaunchCache()
		BrowserLog.duration(.persistence, "state.snapshot-preparation.end",
		                    since: preparationStart,
		                    warnAboveMilliseconds: 16,
		                    metadata: [
		                    	"tabs": String(tabs.count),
		                    	"history_entries": String(historyVisits.count),
		                    	"windows": String(state.windowRecords?.count ?? 0),
		                    ])
		Self.persistenceRevision &+= 1
		let revision = Self.persistenceRevision
		// Encode + file IO off-main so Cmd+T / history-open stay instant.
		// Scroll-only saves skip cross-window fan-out and sync: no structural change.
		let previousWrite = session.persistenceWriteTask
		session.persistenceWriteTask = Task.detached(priority: .utility) { [persistence, state, windowID] in
			await previousWrite?.value
			do {
				var state = state
				for index in state.openTabs.indices {
					if let input = restorationInputs[state.openTabs[index].id] {
						state.openTabs[index].restorationState = restorationSealer?.seal(input.0, for: input.1)
					}
				}
				for index in state.closedTabs.indices {
					if let input = closedRestorationInputs[state.closedTabs[index].id] {
						state.closedTabs[index].restorationState = restorationSealer?.seal(input.0, for: input.1)
					}
				}
				state.closedTabs = try persistence.compactClosedTabs(state.closedTabs)
				try persistence.savePersistedState(state, revision: revision)
				let compactedClosedTabs = state.closedTabs
				await MainActor.run { [weak self] in
					guard let self else { return }
					persistenceErrorDescription = nil
					for id in closedRestorationInputs.keys { pendingClosedRestoration[id] = nil }
					let compacted = Dictionary(uniqueKeysWithValues: compactedClosedTabs.map { ($0.id, $0) })
					closedHistoryTabs = closedHistoryTabs.map { current in
						guard current.closedArchiveID == nil, let summary = compacted[current.id], summary.modifiedAt == current.modifiedAt else { return current }
						return summary
					}
					guard isStructural else { return }
					BrowserWindowRegistry.shared.publishSoon(from: self)
				}
			} catch {
				let message = error.localizedDescription
				BrowserLog.error(.persistence, "browser.persist.failed", metadata: [
					"window": BrowserLog.id(windowID),
					"error": BrowserLog.errorDescription(error),
				])
				await MainActor.run { [weak self] in
					self?.persistenceErrorDescription = message
				}
			}
		}
	}

	private func persistLaunchCache() {
		guard !isPrivate, !isMini else { return }
		var launchTabs = Array(tabs.prefix(BrowserLaunchCache.maximumTabs))
		if let selectedTab, !launchTabs.contains(where: { $0.id == selectedTab.id }) {
			if !launchTabs.isEmpty { launchTabs.removeLast() }
			launchTabs.append(selectedTab)
		}
		var launchSpaces = Array(workspace.spaces.prefix(BrowserLaunchCache.maximumSpaces))
		if let selected = workspace.spaces.first(where: { $0.id == workspace.selectedSpaceID }),
		   !launchSpaces.contains(where: { $0.id == selected.id }) {
			if !launchSpaces.isEmpty { launchSpaces.removeLast() }
			launchSpaces.append(selected)
		}
		let favicons = session.favicons.favicons
		var cachedFavicons: [String: Data] = [:]
		var cachedFaviconBytes = 0
		let faviconTabOrder = [selectedTab].compactMap(\.self) + launchTabs.filter { $0.id != selectedTabID }
		for tab in faviconTabOrder {
			guard let key = FaviconKey.origin(for: tab.currentURL),
			      let data = favicons[key],
			      cachedFavicons[key] == nil,
			      cachedFavicons.count < BrowserLaunchCache.maximumFavicons,
			      cachedFaviconBytes + data.count <= BrowserLaunchCache.maximumFaviconBytes
			else { continue }
			cachedFavicons[key] = data
			cachedFaviconBytes += data.count
		}
		BrowserLaunchCache.save(BrowserLaunchCache.Snapshot(
			tabs: launchTabs.enumerated().map { index, tab in
				let url = tab.currentURL.map(BrowserAddress.withoutCredentials)
				return BrowserLaunchCache.Tab(
					id: tab.id,
					url: url.flatMap { $0.absoluteString.utf8.count <= 4096 ? $0 : nil },
					title: String(tab.title.prefix(240)),
					order: index,
					internalPage: tab.internalPage == .easel ? "easel" : nil
				)
			},
			spaces: launchSpaces.map { space in
				BrowserLaunchCache.Space(
					id: space.id,
					name: String(space.name.prefix(80)),
					symbol: space.symbol,
					theme: space.theme,
					tabIDs: space.tabIDs,
					selectedTabID: space.selectedTabID
				)
			},
			favouriteTabIDs: workspace.favouriteTabIDs,
			selectedSpaceID: workspace.selectedSpaceID,
			selectedTabID: selectedTabID,
			favicons: cachedFavicons
		))
	}
}
