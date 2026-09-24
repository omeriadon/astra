import Foundation
import Observation

// stop removing import webkit, it is used by `pageZoom`
import WebKit

enum BrowserInternalPage: Equatable {
	case themeEditor
	case settings

	var title: String {
		switch self {
			case .themeEditor:
				"Theme"
			case .settings:
				"Settings"
		}
	}

	var symbol: String {
		switch self {
			case .themeEditor:
				"paintpalette"
			case .settings:
				"gearshape"
		}
	}
}

@MainActor
@Observable
final class BrowserTab: Identifiable {
	let id: UUID
	let internalPage: BrowserInternalPage?
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
	private var storedURL: URL?
	private var storedHistory: [URL]
	private var storedHistoryIndex: Int
	private var storedPageZoom: Double
	private var storedScrollPosition: BrowserScrollPosition
	private var storedPeeks: [OpenPeek]
	private(set) var modifiedAt: Date

	@ObservationIgnored
	var didChange: (@MainActor () -> Void)?

	var openTab: OpenTab {
		OpenTab(
			id: id,
			pageTitle: pageTitle,
			customTitle: customTitle,
			url: controller?.url ?? storedURL,
			history: controller?.history ?? storedHistory,
			historyIndex: controller?.historyIndex ?? storedHistoryIndex,
			pageZoom: controller?.pageZoom ?? storedPageZoom,
			scrollPosition: controller?.scrollPosition ?? storedScrollPosition,
			isHibernated: isHibernated,
			modifiedAt: modifiedAt,
			peeks: isHibernated ? storedPeeks : peeks.map(\.openPeek)
		)
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
		existingController: BrowserController? = nil
	) {
		self.id = id
		self.internalPage = internalPage
		self.pageTitle = pageTitle
		self.customTitle = customTitle
		storedURL = initialURL
		storedHistory = history
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
				history: history,
				historyIndex: historyIndex,
				scrollPosition: scrollPosition
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

	func hibernate() {
		guard internalPage == nil else { return }
		guard let controller else { return }
		storedURL = controller.url
		storedHistory = controller.history
		storedHistoryIndex = controller.historyIndex
		storedPageZoom = controller.pageZoom
		storedScrollPosition = controller.scrollPosition
		storedPeeks = peeks.map(\.openPeek)
		controller.stopLoading()
		self.controller = nil
		peeks.removeAll()
		markModified()
	}

	func wake() {
		guard internalPage == nil else { return }
		guard controller == nil else { return }
		let controller = BrowserController(
			initialURL: storedURL,
			history: storedHistory,
			historyIndex: storedHistoryIndex,
			scrollPosition: storedScrollPosition
		)
		controller.pageZoom = storedPageZoom
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
		peeks.removeSubrange(index...)
		markModified()
	}

	func requestPeekDismissal() {
		peeks.last?.isDismissing = true
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
	}

	private func observeController() {
		controller?.navigationDidChange = { [weak self] in
			self?.markModified()
		}
		controller?.titleDidChange = { [weak self] title in
			self?.updatePageTitle(title)
		}
	}

	private func markModified() {
		modifiedAt = .now
		didChange?()
	}
}
