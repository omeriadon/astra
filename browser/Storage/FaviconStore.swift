import Foundation
import Observation
import SwiftUI
import WebKit

#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif

@MainActor
@Observable
final class FaviconStore: NSObject, WKScriptMessageHandler {
	static let shared = FaviconStore()
	private static let messageHandlerName = "faviconChanged"
	private static let observationScript = """
	(() => {
		const iconSelector = 'link[rel~="icon"]';
		const observer = new MutationObserver(changes => {
			const faviconChanged = changes.some(change => {
				if (change.type === 'attributes') {
					return change.target.matches(iconSelector)
						|| (change.attributeName === 'rel' && change.target.tagName === 'LINK');
				}

				return [...change.addedNodes, ...change.removedNodes].some(node =>
					node.matches?.(iconSelector)
				);
			});

			if (faviconChanged) {
				window.webkit.messageHandlers.faviconChanged.postMessage(true);
			}
		});

		observer.observe(document.head, {
			attributes: true,
			attributeFilter: ['href', 'rel'],
			childList: true,
			subtree: true
		});
	})();
	"""

	private(set) var favicons: [String: Data]
	private var liveFavicons: [ObjectIdentifier: (cacheKey: String, data: Data)] = [:]

	@ObservationIgnored
	private let persistence: BrowserPersistence?

	@ObservationIgnored
	private var cacheGeneration = 0
	@ObservationIgnored
	private var requestGenerations: [ObjectIdentifier: Int] = [:]

	var isEmpty: Bool {
		favicons.isEmpty
	}

	override private init() {
		do {
			let persistence = try BrowserPersistence()
			let favicons = try persistence.loadFavicons()
			self.persistence = persistence
			self.favicons = favicons
		} catch {
			persistence = nil
			favicons = [:]
		}
		super.init()

		#if DEBUG
			assert(Self.cacheKey(for: URL(string: "https://www.example.com/page")!) == "www.example.com")
		#endif
	}

	func configureFaviconObservation(in contentController: WKUserContentController) {
		contentController.add(
			self,
			contentWorld: .defaultClient,
			name: Self.messageHandlerName
		)
		contentController.addUserScript(
			WKUserScript(
				source: Self.observationScript,
				injectionTime: .atDocumentEnd,
				forMainFrameOnly: true,
				in: .defaultClient
			)
		)
	}

	func image(for pageURL: URL?, in webView: WKWebView? = nil) -> Image? {
		guard let key = Self.cacheKey(for: pageURL) else { return nil }
		let liveFavicon = webView.flatMap { liveFavicons[ObjectIdentifier($0)] }
		let data = if liveFavicon?.cacheKey == key {
			liveFavicon?.data
		} else {
			favicons[key]
		}
		guard let data else { return nil }

		#if os(macOS)
			guard let image = NSImage(data: data) else { return nil }
			return Image(nsImage: image)
		#elseif os(iOS)
			guard let image = UIImage(data: data) else { return nil }
			return Image(uiImage: image)
		#endif
	}

	func loadFavicon(for pageURL: URL, from webView: WKWebView, onlyIfMissing: Bool = false) async {
		guard let key = Self.cacheKey(for: pageURL) else { return }
		let webViewID = ObjectIdentifier(webView)
		let hasLiveFavicon = liveFavicons[webViewID]?.cacheKey == key
		if onlyIfMissing, hasLiveFavicon || favicons[key] != nil {
			return
		}
		let generation = cacheGeneration
		let requestGeneration = requestGenerations[webViewID, default: 0] + 1
		requestGenerations[webViewID] = requestGeneration
		let script = """
		document.querySelector('link[rel~="icon"]')?.href
			?? new URL('/favicon.ico', document.baseURI).href
		"""
		guard let address = try? await webView.evaluateJavaScript(script) as? String,
		      let iconURL = URL(string: address),
		      iconURL.scheme == "https" || iconURL.scheme == "http"
		else { return }

		var request = URLRequest(url: iconURL)
		request.cachePolicy = .reloadRevalidatingCacheData
		request.timeoutInterval = 15
		guard let (data, response) = try? await URLSession.shared.data(for: request),
		      let response = response as? HTTPURLResponse,
		      200 ..< 300 ~= response.statusCode,
		      !data.isEmpty,
		      data.count <= 1_000_000,
		      Self.isImage(data),
		      generation == cacheGeneration,
		      requestGenerations[webViewID] == requestGeneration
		else { return }

		liveFavicons[webViewID] = (key, data)
		guard favicons[key] != data else { return }

		favicons[key] = data
		try? persistence?.saveFavicons(favicons)
	}

	func clear() {
		cacheGeneration += 1
		requestGenerations.removeAll()
		liveFavicons.removeAll()
		favicons.removeAll()
		try? persistence?.saveFavicons(favicons)
	}

	func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.name == Self.messageHandlerName,
		      message.frameInfo.isMainFrame,
		      let webView = message.webView,
		      let pageURL = webView.url
		else { return }

		Task { @MainActor in
			await loadFavicon(for: pageURL, from: webView)
		}
	}

	private static func cacheKey(for url: URL?) -> String? {
		guard let url,
		      url.scheme == "https" || url.scheme == "http"
		else { return nil }
		return url.host?.lowercased()
	}

	private static func isImage(_ data: Data) -> Bool {
		#if os(macOS)
			NSImage(data: data) != nil
		#elseif os(iOS)
			UIImage(data: data) != nil
		#endif
	}
}
