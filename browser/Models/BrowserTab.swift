import Foundation
import Observation

// stop removing import webkit, it is used by `pageZoom`
import WebKit

@MainActor
@Observable
final class BrowserTab: Identifiable {
	let id: UUID
	private(set) var pageTitle: String {
		didSet { didChange?() }
	}

	private(set) var customTitle: String? {
		didSet { didChange?() }
	}

	var title: String {
		customTitle ?? pageTitle
	}

	var hasCustomTitle: Bool {
		customTitle != nil
	}

	let controller: BrowserController
	var activeController: BrowserController {
		peeks.last?.controller ?? controller
	}

	private(set) var peeks: [BrowserPeek]

	@ObservationIgnored
	var didChange: (@MainActor () -> Void)?

	var openTab: OpenTab {
		OpenTab(
			id: id,
			pageTitle: pageTitle,
			customTitle: customTitle,
			url: controller.url,
			history: controller.history,
			historyIndex: controller.historyIndex,
			pageZoom: controller.webView.pageZoom,
			peeks: peeks.map(\.openPeek)
		)
	}

	init(
		id: UUID = UUID(),
		pageTitle: String = "New Tab",
		customTitle: String? = nil,
		initialURL: URL? = nil,
		history: [URL] = [],
		historyIndex: Int = 0,
		openPeeks: [OpenPeek] = [],
		pageZoom: Double = 1,
		existingController: BrowserController? = nil
	) {
		self.id = id
		self.pageTitle = pageTitle
		self.customTitle = customTitle
		controller = existingController ?? BrowserController(
			initialURL: initialURL,
			history: history,
			historyIndex: historyIndex
		)
		if existingController == nil {
			controller.webView.pageZoom = pageZoom
		}
		peeks = openPeeks.map(BrowserPeek.init(openPeek:))
		controller.navigationDidChange = { [weak self] in
			self?.didChange?()
		}
		controller.titleDidChange = { [weak self] title in
			self?.updatePageTitle(title)
		}
		for peek in peeks {
			observe(peek)
		}
	}

	func addPeek(_ peek: BrowserPeek) {
		observe(peek)
		peeks.append(peek)
		didChange?()
	}

	func dismissPeek(_ id: UUID) {
		guard let index = peeks.firstIndex(where: { $0.id == id }) else { return }
		peeks.removeSubrange(index...)
		didChange?()
	}

	func rename(to title: String) {
		customTitle = title
	}

	func revertTitle() {
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
			self?.didChange?()
		}
	}
}
