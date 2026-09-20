import Observation
import WebKit

@MainActor
@Observable
final class BrowserController: NSObject {
	@ObservationIgnored
	let webView = WKWebView()

	var canGoBack = false
	var canGoForward = false

	@ObservationIgnored
	private var observations: [NSKeyValueObservation] = []

	override init() {
		super.init()

		observations = [
			webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
				Task { @MainActor in
					self?.canGoBack = webView.canGoBack
				}
			},

			webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
				Task { @MainActor in
					self?.canGoForward = webView.canGoForward
				}
			},
		]
	}

	func load(_ url: URL) {
		webView.load(URLRequest(url: url))
	}

	func goBack() {
		webView.goBack()
	}

	func goForward() {
		webView.goForward()
	}

	func reload() {
		webView.reload()
	}
}
