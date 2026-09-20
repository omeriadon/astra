import Foundation
import Observation

@MainActor
@Observable
final class BrowserTab: Identifiable {
	let id: UUID
	let controller: BrowserController

	init(id: UUID = UUID()) {
		self.id = id
		controller = BrowserController()
	}
}
