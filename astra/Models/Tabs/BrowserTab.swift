import Foundation
import Observation

// stop removing import webkit, it is used by `pageZoom`
import WebKit

enum BrowserInternalPage: Equatable, CaseIterable {
	case themeEditor
	case settings
	case history
	case bookmarks
	#if DEBUG
		case failedWebsiteState(BrowserNavigationFailure.Kind)
	#endif

	static var allCases: [Self] {
		var pages: [Self] = [.themeEditor, .settings, .history, .bookmarks]
		#if DEBUG
			pages += BrowserNavigationFailure.Kind.allCases.map { .failedWebsiteState($0) }
		#endif
		return pages
	}

	var persistenceID: String {
		switch self {
			case .themeEditor: "themeEditor"
			case .settings: "settings"
			case .history: "history"
			case .bookmarks: "bookmarks"
			#if DEBUG
				case let .failedWebsiteState(kind): "failedWebsiteState:\(kind.rawValue)"
			#endif
		}
	}

	init?(persistenceID: String) {
		switch persistenceID {
			case "themeEditor": self = .themeEditor
			case "settings": self = .settings
			case "history": self = .history
			case "bookmarks": self = .bookmarks
			default:
				#if DEBUG
					if persistenceID.hasPrefix("failedWebsiteState:"),
					   let kind = BrowserNavigationFailure.Kind(
					   	rawValue: String(persistenceID.dropFirst("failedWebsiteState:".count))
					   )
					{
						self = .failedWebsiteState(kind)
						return
					}
				#endif
				return nil
		}
	}

	var title: String {
		switch self {
			case .themeEditor:
				"Edit Space"
			case .settings:
				"Settings"
			case .history:
				"History"
			case .bookmarks:
				"Bookmarks"
			#if DEBUG
				case let .failedWebsiteState(kind):
					String(localized: kind.title)
			#endif
		}
	}

	var symbol: String {
		switch self {
			case .themeEditor:
				"paintpalette"
			case .settings:
				"gearshape"
			case .history:
				"clock.arrow.circlepath"
			case .bookmarks:
				"bookmark"
			#if DEBUG
				case let .failedWebsiteState(kind):
					kind.systemImage
			#endif
		}
	}
}

@MainActor
@Observable
final class BrowserTab: Identifiable {
	let id: UUID
	let internalPage: BrowserInternalPage?
	let session: BrowserWebSession
	private(set) var pageTitle: String {
		didSet { markModified() }
	}

	private(set) var customTitle: String? {
		didSet { markModified() }
	}

	var title: String {
		internalPage?.title ?? customTitle ?? pageTitle
	}

	var hasCustomTitle: Bool {
		customTitle != nil
	}

	private(set) var controller: BrowserController?
	var activeController: BrowserController? {
		peeks.last?.controller ?? controller
	}

	var isHibernated: Bool {
		internalPage == nil && controller == nil
	}

	var currentURL: URL? {
		controller?.url ?? storedURL
	}

	private(set) var peeks: [BrowserPeek]
	@ObservationIgnored
	private var storedInteractionState: Any?
	private var storedRestorationState: Data?
	private var storedFileAccessBookmark: Data?
	private var storedHistoryPrefix: [URL] = []
	private var storedURL: URL?
	private var recordsNavigationHistory: Bool
	private var storedHistory: [URL]
	private var storedHistoryIndex: Int
	private var storedPageZoom: Double
	private var storedScrollPosition: BrowserScrollPosition
	private var storedPeeks: [OpenPeek]
	private(set) var modifiedAt: Date

	@ObservationIgnored
	var didChange: (@MainActor () -> Void)?

	/// Scroll-only updates (persisted on a slow debounce, no cross-window fan-out).
	@ObservationIgnored
	var didScrollChange: (@MainActor () -> Void)?

	@ObservationIgnored
	private var openTabCache: OpenTab?

	var openTab: OpenTab {
		if let openTabCache {
			return openTabCache
		}
		let next = OpenTab(
			id: id,
			internalPage: internalPage?.persistenceID,
			pageTitle: pageTitle,
			customTitle: customTitle,
			url: (controller?.url ?? storedURL).map(BrowserAddress.withoutCredentials),
			history: recordsNavigationHistory ? (controller?.history ?? storedHistory).map(BrowserAddress.withoutCredentials) : currentURL.map { [BrowserAddress.withoutCredentials($0)] } ?? [],
			historyIndex: recordsNavigationHistory ? (controller?.historyIndex ?? storedHistoryIndex) : 0,
			pageZoom: controller?.pageZoom ?? storedPageZoom,
			scrollPosition: controller?.scrollPosition ?? storedScrollPosition,
			isHibernated: isHibernated,
			modifiedAt: modifiedAt,
			peeks: recordsNavigationHistory ? (isHibernated ? storedPeeks : peeks.map(\.openPeek)) : [],
			recordsNavigationHistory: recordsNavigationHistory,
			restorationState: recordsNavigationHistory && !session.isPrivate ? controller?.encryptedInteractionState ?? storedRestorationState : nil,
			fileAccessBookmark: controller?.fileAccessBookmark ?? storedFileAccessBookmark
		)
		openTabCache = next
		return next
	}

	init(
		id: UUID = UUID(),
		internalPage: BrowserInternalPage? = nil,
		pageTitle: String = "New Tab",
		customTitle: String? = nil,
		initialURL: URL? = nil,
		history: [URL] = [],
		historyIndex: Int = 0,
		openPeeks: [OpenPeek] = [],
		pageZoom: Double = 1,
		scrollPosition: BrowserScrollPosition = .zero,
		isHibernated: Bool = false,
		modifiedAt: Date = .now,
		existingController: BrowserController? = nil,
		session: BrowserWebSession? = nil,
		recordsNavigationHistory: Bool = true,
		restorationState: Data? = nil,
		fileAccessBookmark: Data? = nil
	) {
		let session = existingController?.session ?? session ?? .shared
		self.id = id
		self.internalPage = internalPage
		self.session = existingController?.session ?? session
		self.pageTitle = pageTitle
		self.customTitle = customTitle
		storedURL = initialURL
		storedRestorationState = restorationState
		storedFileAccessBookmark = fileAccessBookmark
		storedHistory = history
		self.recordsNavigationHistory = recordsNavigationHistory
		storedHistoryIndex = historyIndex
		storedPageZoom = pageZoom
		storedScrollPosition = scrollPosition
		storedPeeks = openPeeks
		self.modifiedAt = modifiedAt
		peeks = isHibernated ? [] : openPeeks.map(BrowserPeek.init(openPeek:))
		controller = if isHibernated || internalPage != nil {
			nil
		} else {
			existingController ?? BrowserController(
				initialURL: initialURL,
				session: session,
				history: history,
				historyIndex: historyIndex,
				scrollPosition: scrollPosition,
				restorationState: restorationState,
				fileAccessBookmark: fileAccessBookmark
			)
		}
		if existingController == nil {
			controller?.pageZoom = pageZoom
		}
		observeController()
		for peek in peeks {
			observe(peek)
		}
	}

	convenience init(openTab saved: OpenTab) {
		self.init(
			id: saved.id,
			internalPage: saved.internalPage.flatMap(BrowserInternalPage.init(persistenceID:)),
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
			fileAccessBookmark: saved.fileAccessBookmark
		)
	}

	var canHibernate: Bool {
		controller?.canHibernate != false && peeks.allSatisfy(\.controller.canHibernate)
	}

	func hibernate() {
		guard internalPage == nil else { return }
		guard let controller, canHibernate else { return }
		storedInteractionState = controller.webViewIfLoaded?.interactionState
		storedRestorationState = controller.encryptedInteractionState
		storedFileAccessBookmark = controller.fileAccessBookmark
		storedHistoryPrefix = controller.liveHistoryPrefix
		storedURL = controller.url
		storedHistory = controller.history
		storedHistoryIndex = controller.historyIndex
		storedPageZoom = controller.pageZoom
		storedScrollPosition = controller.scrollPosition
		storedPeeks = peeks.map(\.openPeek)
		for peek in peeks {
			peek.controller.stopForClose()
		}
		controller.stopForClose()
		self.controller = nil
		peeks.removeAll()
		markModified()
	}

	func stopForClose() {
		controller?.stopForClose()
		for peek in peeks {
			peek.controller.stopForClose()
		}
	}

	func wake() {
		guard internalPage == nil else { return }
		guard controller == nil else { return }
		let controller = BrowserController(
			initialURL: storedURL,
			session: session,
			history: storedHistory,
			historyIndex: storedHistoryIndex,
			scrollPosition: storedScrollPosition,
			restorationState: storedRestorationState,
			fileAccessBookmark: storedFileAccessBookmark
		)
		controller.pageZoom = storedPageZoom
		if let storedInteractionState {
			controller.restoreInteractionState(storedInteractionState, historyPrefix: storedHistoryPrefix)
		}
		storedInteractionState = nil
		self.controller = controller
		peeks = storedPeeks.map(BrowserPeek.init(openPeek:))
		observeController()
		for peek in peeks {
			observe(peek)
		}
		didChange?()
	}

	func addPeek(_ peek: BrowserPeek) {
		observe(peek)
		peeks.append(peek)
		markModified()
	}

	func dismissPeek(_ id: UUID) {
		guard let index = peeks.firstIndex(where: { $0.id == id }) else { return }
		for peek in peeks[index...] {
			peek.controller.stopForClose()
		}
		peeks.removeSubrange(index...)
		markModified()
	}

	func requestPeekDismissal() {
		peeks.last?.isDismissing = true
	}

	func invalidateStoredSnapshot() {
		openTabCache = nil
	}

	func clearRecordedHistory() {
		recordsNavigationHistory = false
		storedRestorationState = nil
		storedHistory = currentURL.map { [$0] } ?? []
		storedHistoryIndex = 0
		storedPeeks = []
		markModified()
	}

	func rename(to title: String) {
		guard internalPage == nil else { return }
		customTitle = title
	}

	func revertTitle() {
		guard internalPage == nil else { return }
		customTitle = nil
	}

	private func updatePageTitle(_ title: String?) {
		let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
		let nextTitle: String = if let title, !title.isEmpty {
			title
		} else {
			"New Tab"
		}
		guard pageTitle != nextTitle else { return }
		pageTitle = nextTitle
	}

	private func observe(_ peek: BrowserPeek) {
		peek.controller.navigationDidChange = { [weak self] in
			self?.markModified()
		}
		peek.controller.scrollPositionDidChange = { [weak self] in
			self?.markModifiedForScroll()
		}
	}

	private func observeController() {
		controller?.navigationDidChange = { [weak self] in
			self?.markModified()
		}
		controller?.scrollPositionDidChange = { [weak self] in
			self?.markModifiedForScroll()
		}
		controller?.titleDidChange = { [weak self] title in
			self?.updatePageTitle(title)
		}
	}

	private func markModified() {
		modifiedAt = .now
		openTabCache = nil
		didChange?()
	}

	private func markModifiedForScroll() {
		modifiedAt = .now
		openTabCache = nil
		didScrollChange?()
	}
}
