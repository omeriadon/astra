import Defaults
import Foundation
import Observation

#if os(macOS)
	import AppKit
#endif

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
		didSet {
			if !isApplyingSynchronizedMetadata {
				markModified()
			}
		}
	}

	private(set) var customTitle: String? {
		didSet {
			if !isApplyingSynchronizedMetadata {
				markModified()
			}
		}
	}

	var title: String {
		internalPage?.title ?? customTitle ?? pageTitle
	}

	var hasCustomTitle: Bool {
		customTitle != nil
	}

	private(set) var controller: BrowserController?
	private(set) var monitorMatch: BrowserMonitorMatch?

	func setMonitorMatch(_ match: BrowserMonitorMatch?) {
		monitorMatch = match
		markModified()
	}

	private(set) var pictureInPictureReturnControllerID: UUID?
	var activeController: BrowserController? {
		if let pictureInPictureReturnControllerID {
			if controller?.id == pictureInPictureReturnControllerID {
				return controller
			}
			if let peekController = peeks.first(where: { $0.controller.id == pictureInPictureReturnControllerID })?.controller {
				return peekController
			}
		}
		return peeks.last?.controller ?? controller
	}

	var isDeveloperMode: Bool {
		guard internalPage == nil else { return false }
		if Defaults[.developerModeEnabled] {
			return true
		}
		guard let host = (activeController?.url ?? currentURL)?.host else { return false }
		return host == "localhost"
			|| host.hasSuffix(".localhost")
			|| host == "127.0.0.1"
			|| host == "::1"
	}

	var isHibernated: Bool {
		internalPage == nil && controller == nil
	}

	var currentURL: URL? {
		controller?.url ?? storedURL
	}

	var copyableURL: URL? {
		internalPage == nil ? activeController?.url ?? currentURL : nil
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
	/// Transient activity used by automatic hibernation; restored tabs get a fresh window.
	private(set) var lastInteractionAt: Date
	@ObservationIgnored
	private var restorationBaseline: OpenTab?
	@ObservationIgnored
	private var isApplyingSynchronizedMetadata = false

	@ObservationIgnored
	var didChange: (@MainActor () -> Void)?
	@ObservationIgnored
	var didRecordHistoryVisit: (@MainActor (BrowserController, URL, String, Int) -> Void)?
	@ObservationIgnored
	var didUpdateHistoryVisitTitle: (@MainActor (BrowserController, URL, String, Int) -> Void)?

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
			monitorMatch: monitorMatch,
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
		monitorMatch: BrowserMonitorMatch? = nil,
		initialURL: URL? = nil,
		history: [URL] = [],
		historyIndex: Int = 0,
		openPeeks: [OpenPeek] = [],
		pageZoom: Double? = nil,
		scrollPosition: BrowserScrollPosition = .zero,
		isHibernated: Bool = false,
		modifiedAt: Date = .now,
		existingController: BrowserController? = nil,
		session: BrowserWebSession? = nil,
		recordsNavigationHistory: Bool = true,
		restorationState: Data? = nil,
		fileAccessBookmark: Data? = nil,
		suppressInitialHistoryVisit: Bool = false,
		initialRestorationBaseline: OpenTab? = nil
	) {
		let session = existingController?.session ?? session ?? .shared
		self.id = id
		self.internalPage = internalPage
		self.session = existingController?.session ?? session
		self.pageTitle = pageTitle
		self.customTitle = customTitle
		self.monitorMatch = monitorMatch
		storedURL = initialURL
		storedRestorationState = restorationState
		storedFileAccessBookmark = fileAccessBookmark
		storedHistory = history
		self.recordsNavigationHistory = recordsNavigationHistory
		storedHistoryIndex = historyIndex
		let initialPageZoom = BrowserZoomPolicy.clamp(pageZoom ?? Defaults[.defaultPageZoom])
		storedPageZoom = initialPageZoom
		storedScrollPosition = scrollPosition
		storedPeeks = openPeeks
		self.modifiedAt = modifiedAt
		lastInteractionAt = .now
		peeks = isHibernated ? [] : openPeeks.map { BrowserPeek(openPeek: $0, session: session) }
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
				fileAccessBookmark: fileAccessBookmark,
				suppressInitialHistoryVisit: suppressInitialHistoryVisit
			)
		}
		if existingController == nil {
			controller?.pageZoom = initialPageZoom
		}
		observeController()
		for peek in peeks {
			observe(peek)
		}
		// Restored tabs already have a fully decoded OpenTab. Reusing it avoids
		// serializing WebKit interaction state again for every startup tab.
		restorationBaseline = initialRestorationBaseline ?? openTab
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
			fileAccessBookmark: saved.fileAccessBookmark,
			suppressInitialHistoryVisit: true,
			initialRestorationBaseline: saved
		)
	}

	var canHibernate: Bool {
		controller?.canHibernate != false && peeks.allSatisfy(\.controller.canHibernate)
	}

	func markInteraction() {
		lastInteractionAt = .now
	}

	func hibernate() {
		guard internalPage == nil else { return }
		guard let controller, canHibernate else { return }
		storedRestorationState = controller.encryptedInteractionState
		let interactionState = controller.webViewIfLoaded?.interactionState
		if storedRestorationState == nil {
			if let data = interactionState as? Data, data.count <= 4 * 1024 * 1024 {
				storedInteractionState = data
			} else if interactionState is Data {
				storedInteractionState = nil
			} else {
				storedInteractionState = interactionState
			}
		} else {
			storedInteractionState = nil
		}
		storedFileAccessBookmark = controller.fileAccessBookmark
		storedHistoryPrefix = controller.liveHistoryPrefix
		storedURL = controller.url
		storedHistory = controller.history
		storedHistoryIndex = controller.historyIndex
		storedPageZoom = controller.pageZoom
		storedScrollPosition = controller.scrollPosition
		storedPeeks = peeks.map(\.openPeek)
		restorationBaseline = openTab
		for peek in peeks {
			peek.controller.stopForClose()
		}
		controller.stopForClose()
		self.controller = nil
		peeks.removeAll()
		markModified()
	}

	func stopForClose(force: Bool = false) {
		guard force || !BrowserWindowRegistry.shared.isReferenced(self) else { return }
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
			fileAccessBookmark: storedFileAccessBookmark,
			suppressInitialHistoryVisit: true
		)
		controller.pageZoom = storedPageZoom
		if let storedInteractionState {
			controller.restoreInteractionState(storedInteractionState, historyPrefix: storedHistoryPrefix)
		}
		storedInteractionState = nil
		self.controller = controller
		peeks = storedPeeks.map { BrowserPeek(openPeek: $0, session: session) }
		observeController()
		for peek in peeks {
			observe(peek)
		}
		didChange?()
	}

	func addPeek(_ peek: BrowserPeek) {
		pictureInPictureReturnControllerID = nil
		observe(peek)
		peeks.append(peek)
		markModified()
	}

	func dismissPeek(_ id: UUID, confirmed: Bool = false) {
		guard let index = peeks.firstIndex(where: { $0.id == id }) else { return }
		let containsProtectedMedia = peeks[index...].contains(where: \.controller.requiresMediaTeardownConfirmation)
		#if os(macOS)
			if containsProtectedMedia, !confirmed {
				Task { @MainActor [weak self] in
					let alert = BrowserWebsiteUI.alert(
						title: "Close Picture in Picture?",
						message: "Closing this peek will stop its media playback.",
						confirm: "Close Peek"
					)
					let window = self?.activeController?.webViewIfLoaded?.window
					if await BrowserWebsiteUI.present(alert, in: window) == .alertFirstButtonReturn {
						self?.dismissPeek(id, confirmed: true)
					}
				}
				return
			}
		#else
			if containsProtectedMedia, !confirmed,
			   let webView = peeks[index...].first(where: { $0.controller.requiresMediaTeardownConfirmation })?.controller.webViewIfLoaded
			{
				Task { @MainActor [weak self] in
					let result = await BrowserWebsiteUI.javascriptDialog(
						title: "Close Peek?",
						message: "Closing this peek will stop media playback.",
						confirmTitle: "Close Peek",
						cancelTitle: "Cancel",
						in: webView
					) { [weak self] in
						self?.peeks.contains(where: { $0.id == id }) == true
					}
					if result.confirmed {
						self?.dismissPeek(id, confirmed: true)
					}
				}
				return
			}
			if containsProtectedMedia, !confirmed {
				return
			}
		#endif
		for peek in peeks[index...] {
			peek.controller.stopForClose()
		}
		peeks.removeSubrange(index...)
		pictureInPictureReturnControllerID = nil
		markModified()
	}

	func takePeekForPromotion(_ id: UUID) -> BrowserPeek? {
		guard peeks.last?.id == id else { return nil }
		let peek = peeks.removeLast()
		pictureInPictureReturnControllerID = nil
		markModified()
		return peek
	}

	func showPictureInPictureController(_ controller: BrowserController) {
		guard self.controller === controller || peeks.contains(where: { $0.controller === controller }) else { return }
		pictureInPictureReturnControllerID = controller.id
	}

	func clearPictureInPictureReturnController() {
		pictureInPictureReturnControllerID = nil
	}

	func requestPeekDismissal() {
		if let controller, controller.id == pictureInPictureReturnControllerID {
			clearPictureInPictureReturnController()
			return
		}
		guard let peek = peeks.first(where: { $0.controller === activeController }) else { return }
		if peek.controller.requiresMediaTeardownConfirmation {
			dismissPeek(peek.id)
			return
		}
		peek.isDismissing = true
	}

	func applySynchronizedMetadata(from remote: OpenTab) {
		let updated = openTab.applyingSynchronizedMetadata(from: remote)
		isApplyingSynchronizedMetadata = true
		pageTitle = updated.pageTitle
		customTitle = updated.customTitle
		monitorMatch = updated.monitorMatch
		recordsNavigationHistory = updated.recordsNavigationHistory
		storedPageZoom = updated.pageZoom
		if !updated.recordsNavigationHistory {
			storedHistory = currentURL.map { [$0] } ?? []
			storedHistoryIndex = 0
			storedRestorationState = nil
			storedPeeks = []
		}
		controller?.pageZoom = updated.pageZoom
		isApplyingSynchronizedMetadata = false
		modifiedAt = updated.modifiedAt
		openTabCache = nil
		restorationBaseline = openTab
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
		peek.controller.historyVisitDidCommit = { [weak self, weak controller = peek.controller] url, title, navigationID in
			guard let self, let controller else { return }
			didRecordHistoryVisit?(controller, url, title, navigationID)
		}
		peek.controller.historyVisitTitleDidChange = { [weak self, weak controller = peek.controller] url, title, navigationID in
			guard let self, let controller else { return }
			didUpdateHistoryVisitTitle?(controller, url, title, navigationID)
		}
		peek.controller.navigationDidChange = { [weak self] in
			self?.markNavigationModified()
		}
		peek.controller.zoomDidChange = { [weak self] in
			guard let self, !self.isApplyingSynchronizedMetadata else { return }
			markNavigationModified()
		}
		peek.controller.scrollPositionDidChange = { [weak self] in
			self?.markModifiedForScroll()
		}
	}

	private func observeController() {
		guard let controller else { return }
		controller.historyVisitDidCommit = { [weak self, weak controller] url, title, navigationID in
			guard let self, let controller else { return }
			didRecordHistoryVisit?(controller, url, title, navigationID)
		}
		controller.historyVisitTitleDidChange = { [weak self, weak controller] url, title, navigationID in
			guard let self, let controller else { return }
			didUpdateHistoryVisitTitle?(controller, url, title, navigationID)
		}
		controller.navigationDidChange = { [weak self] in
			self?.markNavigationModified()
		}
		controller.zoomDidChange = { [weak self] in
			guard let self, !self.isApplyingSynchronizedMetadata else { return }
			markNavigationModified()
		}
		controller.scrollPositionDidChange = { [weak self] in
			self?.markModifiedForScroll()
		}
		controller.titleDidChange = { [weak self] title in
			self?.updatePageTitle(title)
		}
	}

	private func markModified() {
		modifiedAt = .now
		openTabCache = nil
		didChange?()
	}

	private func hasSameNavigationState(as baseline: OpenTab) -> Bool {
		// openTab also captures/encrypts WebKit interactionState. The change
		// detector only compares URL/history/zoom/scroll, so constructing a full
		// OpenTab here did expensive restoration-state work for no reason.
		let url = (controller?.url ?? storedURL).map(BrowserAddress.withoutCredentials)
		let history = recordsNavigationHistory
			? (controller?.history ?? storedHistory).map(BrowserAddress.withoutCredentials)
			: url.map { [$0] } ?? []
		let historyIndex = recordsNavigationHistory
			? (controller?.historyIndex ?? storedHistoryIndex)
			: 0
		return url == baseline.url
			&& history == baseline.history
			&& historyIndex == baseline.historyIndex
			&& (controller?.pageZoom ?? storedPageZoom) == baseline.pageZoom
			&& (controller?.scrollPosition ?? storedScrollPosition) == baseline.scrollPosition
	}

	private func markNavigationModified() {
		openTabCache = nil
		if let restorationBaseline, hasSameNavigationState(as: restorationBaseline) {
			return
		}
		restorationBaseline = nil
		markModified()
	}

	private func markModifiedForScroll() {
		openTabCache = nil
		if let restorationBaseline, hasSameNavigationState(as: restorationBaseline) {
			return
		}
		restorationBaseline = nil
		modifiedAt = .now
		openTabCache = nil
		didScrollChange?()
	}
}
