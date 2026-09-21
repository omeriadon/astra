import Foundation
import Observation

@MainActor
@Observable
final class BrowserTab: Identifiable {
	let id: UUID
	var title: String {
		didSet { didChange?() }
	}

	let controller: BrowserController

	@ObservationIgnored
	var didChange: (@MainActor () -> Void)?

	var openTab: OpenTab {
		OpenTab(
			id: id,
			title: title,
			url: controller.url,
			history: controller.history,
			historyIndex: controller.historyIndex
		)
	}

	init(
		id: UUID = UUID(),
		title: String = "New Tab",
		initialURL: URL? = nil,
		history: [URL] = [],
		historyIndex: Int = 0
	) {
		self.id = id
		self.title = title
		controller = BrowserController(
			initialURL: initialURL,
			history: history,
			historyIndex: historyIndex
		)
		controller.navigationDidChange = { [weak self] in
			self?.didChange?()
		}
	}
}
