import Foundation
import Observation

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

	@ObservationIgnored
	var didChange: (@MainActor () -> Void)?

	var openTab: OpenTab {
		OpenTab(
			id: id,
			pageTitle: pageTitle,
			customTitle: customTitle,
			url: controller.url,
			history: controller.history,
			historyIndex: controller.historyIndex
		)
	}

	init(
		id: UUID = UUID(),
		pageTitle: String = "New Tab",
		customTitle: String? = nil,
		initialURL: URL? = nil,
		history: [URL] = [],
		historyIndex: Int = 0
	) {
		self.id = id
		self.pageTitle = pageTitle
		self.customTitle = customTitle
		controller = BrowserController(
			initialURL: initialURL,
			history: history,
			historyIndex: historyIndex
		)
		controller.navigationDidChange = { [weak self] in
			self?.didChange?()
		}
		controller.titleDidChange = { [weak self] title in
			self?.updatePageTitle(title)
		}
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
}
