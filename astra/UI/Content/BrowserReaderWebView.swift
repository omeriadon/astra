import SwiftUI
import WebKit

struct BrowserReaderWebView {
	let controller: BrowserController
	let html: String
	let appearance: BrowserReaderAppearance

	@MainActor
	func makeWebView(coordinator: Coordinator) -> WKWebView {
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		configuration.defaultWebpagePreferences.allowsContentJavaScript = false
		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = coordinator
		webView.loadHTMLString(html, baseURL: nil)
		webView.pageZoom = controller.pageZoom
		return webView
	}

	@MainActor
	func makeCoordinator() -> Coordinator {
		Coordinator(controller: controller, appearance: appearance)
	}

	@MainActor
	final class Coordinator: NSObject, WKNavigationDelegate {
		private weak var controller: BrowserController?
		private var appearance: BrowserReaderAppearance

		init(controller: BrowserController, appearance: BrowserReaderAppearance) {
			self.controller = controller
			self.appearance = appearance
		}

		func updateAppearance(_ appearance: BrowserReaderAppearance, in webView: WKWebView) {
			guard self.appearance != appearance else { return }
			self.appearance = appearance
			applyAppearance(in: webView)
		}

		private func applyAppearance(in webView: WKWebView) {
			webView.callAsyncJavaScript(
				"document.getElementById('reader-appearance').textContent = css;",
				arguments: ["css": appearance.styleSheet],
				in: nil,
				in: .defaultClient,
				completionHandler: nil
			)
		}

		func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
			applyAppearance(in: webView)
		}

		func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
			if action.navigationType == .other, action.request.url?.absoluteString == "about:blank" {
				decisionHandler(.allow)
				return
			}
			decisionHandler(.cancel)
			guard action.navigationType == .linkActivated,
			      let url = action.request.url,
			      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
			      url.user == nil, url.password == nil,
			      let controller, controller.readerHTML != nil else { return }
			controller.toggleReader()
			controller.load(url)
		}
	}
}

#if os(macOS)
	extension BrowserReaderWebView: NSViewRepresentable {
		func makeNSView(context: Context) -> WKWebView {
			makeWebView(coordinator: context.coordinator)
		}

		func updateNSView(_ webView: WKWebView, context: Context) {
			webView.pageZoom = controller.pageZoom
			context.coordinator.updateAppearance(appearance, in: webView)
		}
	}
#elseif os(iOS)
	extension BrowserReaderWebView: UIViewRepresentable {
		func makeUIView(context: Context) -> WKWebView {
			makeWebView(coordinator: context.coordinator)
		}

		func updateUIView(_ webView: WKWebView, context: Context) {
			webView.pageZoom = controller.pageZoom
			context.coordinator.updateAppearance(appearance, in: webView)
		}
	}
#endif
