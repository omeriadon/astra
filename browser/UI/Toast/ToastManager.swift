import Foundation
import Observation

struct BrowserToast: Equatable {
	let symbol: String
	let message: String
}

@MainActor
@Observable
final class ToastManager {
	static let shared = ToastManager()

	private(set) var toast: BrowserToast?
	private var dismissalTask: Task<Void, Never>?

	func show(symbol: String, message: String) {
		dismissalTask?.cancel()
		toast = BrowserToast(symbol: symbol, message: message)
		dismissalTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(1))
			guard !Task.isCancelled else { return }
			self?.toast = nil
		}
	}
}
