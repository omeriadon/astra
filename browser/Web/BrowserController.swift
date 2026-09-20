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
			webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					self?.canGoBack = change.newValue ?? webView.canGoBack
				}
			},

			webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					self?.canGoForward = change.newValue ?? webView.canGoForward
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
