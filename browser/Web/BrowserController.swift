import Observation
import WebKit

@MainActor
@Observable
final class BrowserController: NSObject {
	private static let startURL = URL(string: "https://www.google.com/search?q=colourful+images")!

	@ObservationIgnored
	let webView = WKWebView()

	var canGoBack = false
	var canGoForward = false
	var url: URL?

	@ObservationIgnored
	var navigationDidChange: (@MainActor () -> Void)?

	@ObservationIgnored
	private var observations: [NSKeyValueObservation] = []

	init(initialURL: URL? = nil) {
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

			webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.url = change.newValue ?? webView.url
					self.navigationDidChange?()
				}
			},
		]

		load(initialURL ?? Self.startURL)
	}

	func load(_ url: URL) {
		webView.load(URLRequest(url: url))
	}

	func goBack() {
		guard canGoBack else { return }
		webView.goBack()
	}

	func goForward() {
		guard canGoForward else { return }
		webView.goForward()
	}

	func reload() {
		webView.reload()
	}
}
