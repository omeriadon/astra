import AuthenticationServices
import Observation

@MainActor
@Observable
final class WatchBrowser {
	var errorDescription: String?
	@ObservationIgnored private var session: ASWebAuthenticationSession?

	func open(_ link: WatchLink) {
		guard link.canOpen else {
			errorDescription = "This link cannot be opened on Apple Watch."
			return
		}
		session?.cancel()
		let next = ASWebAuthenticationSession(url: link.url, callbackURLScheme: nil) { _, error in
			guard let error,
			      (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue else { return }
			let message = error.localizedDescription
			Task { @MainActor in self.errorDescription = message }
		}
		session = next
		if !next.start() {
			errorDescription = "The system browser could not open this website."
		}
	}
}
