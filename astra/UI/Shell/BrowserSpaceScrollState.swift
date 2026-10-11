import Foundation
import Observation

@MainActor
@Observable
final class BrowserSpaceScrollState {
	/// The iOS ScrollView still uses SwiftUI observation for its geometry.
	/// On macOS the native pager updates presentation progress each refresh;
	/// that data must not invalidate the SwiftUI view graph.
	var position: Double?

	#if os(macOS)
		@ObservationIgnored private(set) var presentationPosition: Double?
		@ObservationIgnored private var presentationObservers: [UUID: (Double) -> Void] = [:]

		func publishPresentationPosition(_ position: Double) {
			guard presentationPosition != position else { return }
			presentationPosition = position
			for observer in presentationObservers.values {
				observer(position)
			}
		}

		func addPresentationObserver(_ observer: @escaping (Double) -> Void) -> UUID {
			let id = UUID()
			presentationObservers[id] = observer
			if let presentationPosition {
				observer(presentationPosition)
			}
			return id
		}

		func removePresentationObserver(_ id: UUID) {
			presentationObservers.removeValue(forKey: id)
		}
	#endif
}
