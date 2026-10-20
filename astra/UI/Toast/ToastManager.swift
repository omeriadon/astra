import Foundation
import Observation
import SwiftUI

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
		let boundedMessage = String(message.prefix(500))
		toast = BrowserToast(symbol: symbol, message: boundedMessage)
		AccessibilityNotification.Announcement(boundedMessage).post()
		dismissalTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(symbol == "exclamationmark.triangle" ? 5 : 2))
			guard !Task.isCancelled else { return }
			self?.toast = nil
		}
	}
}
