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
		OpenTab(id: id, title: title, url: controller.url)
	}

	init(id: UUID = UUID(), title: String = "New Tab", initialURL: URL? = nil) {
		self.id = id
		self.title = title
		controller = BrowserController(initialURL: initialURL)
		controller.navigationDidChange = { [weak self] in
			self?.didChange?()
		}
	}
}
