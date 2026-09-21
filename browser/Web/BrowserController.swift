import Observation
import WebKit

@MainActor
@Observable
final class BrowserController: NSObject {
	private static let startURL = URL(string: "https://www.google.com/search?q=colourful+images")!

	@ObservationIgnored
	let webView = WKWebView()

	private(set) var history: [URL]
	private(set) var historyIndex: Int
	var canGoBack: Bool {
		historyIndex > 0
	}

	var canGoForward: Bool {
		historyIndex < history.count - 1
	}

	var url: URL?

	@ObservationIgnored
	var navigationDidChange: (@MainActor () -> Void)?

	@ObservationIgnored
	private var observations: [NSKeyValueObservation] = []

	init(initialURL: URL? = nil, history: [URL] = [], historyIndex: Int = 0) {
		let restoredHistory = history.isEmpty ? [initialURL ?? Self.startURL] : history
		let restoredHistoryIndex = min(max(historyIndex, 0), restoredHistory.count - 1)
		self.history = restoredHistory
		self.historyIndex = restoredHistoryIndex
		url = restoredHistory[restoredHistoryIndex]
		super.init()

		observations = [
			webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					guard let self else { return }
					guard let url = change.newValue ?? webView.url else { return }
					self.url = url
					self.recordNavigation(to: url)
					self.navigationDidChange?()
				}
			},
		]

		load(restoredHistory[restoredHistoryIndex])
	}

	func load(_ url: URL) {
		webView.load(URLRequest(url: url))
	}

	func goBack() {
		guard canGoBack else { return }
		historyIndex -= 1
		navigationDidChange?()
		load(history[historyIndex])
	}

	func goForward() {
		guard canGoForward else { return }
		historyIndex += 1
		navigationDidChange?()
		load(history[historyIndex])
	}

	func reload() {
		webView.reload()
	}

	private func recordNavigation(to url: URL) {
		guard history[historyIndex] != url else { return }
		history.removeSubrange((historyIndex + 1) ..< history.count)
		if history.last != url {
			history.append(url)
		}
		historyIndex = history.count - 1
	}
}
