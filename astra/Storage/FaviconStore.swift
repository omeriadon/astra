import Foundation
import Observation
import SwiftUI
import WebKit

#if os(macOS)
	import AppKit

	private typealias PlatformImage = NSImage
#elseif os(iOS)
	import UIKit

	private typealias PlatformImage = UIImage
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
	@ObservationIgnored
	private var faviconSaveTask: Task<Void, Never>?
	/// Decoded-once cache: row bodies call image() on every render, and
	/// PlatformImage(data:) decode per row is what made selection lag with N tabs.
	@ObservationIgnored
	private var decodedImages: [String: PlatformImage] = [:]
	@ObservationIgnored
	private var liveImages: [ObjectIdentifier: (cacheKey: String, image: PlatformImage)] = [:]
	@ObservationIgnored
	private var inFlightFaviconKeys = Set<String>()

	var isEmpty: Bool {
		favicons.isEmpty
	}

	override private init() {
		let persistence: BrowserPersistence?
		do {
			persistence = try BrowserPersistence()
		} catch {
			persistence = nil
		}
		self.persistence = persistence
		favicons = [:]
		super.init()

		// Decode the base64 icon dict off-main; rows show placeholders until set.
		if let persistence {
			Task.detached(priority: .utility) { [persistence] in
				guard let loaded = try? persistence.loadFavicons(), !loaded.isEmpty else { return }
				await MainActor.run { [weak self] in
					guard let self else { return }
					for (key, data) in loaded where favicons[key] == nil {
						favicons[key] = data
					}
				}
			}
		}

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
		if let webView {
			let webViewID = ObjectIdentifier(webView)
			if let live = liveFavicons[webViewID], live.cacheKey == key {
				if let cached = liveImages[webViewID], cached.cacheKey == key {
					return Self.swiftUIImage(cached.image)
				}
				if let decoded = Self.makePlatformImage(live.data) {
					liveImages[webViewID] = (key, decoded)
					return Self.swiftUIImage(decoded)
				}
				return nil
			}
		}
		if let cached = decodedImages[key] {
			return Self.swiftUIImage(cached)
		}
		guard let data = favicons[key], let decoded = Self.makePlatformImage(data) else { return nil }
		decodedImages[key] = decoded
		return Self.swiftUIImage(decoded)
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

		// Simultaneous navigations to one host share a single fetch; losers
		// read the cached result via favicons[key] on their next lookup.
		guard !inFlightFaviconKeys.contains(key) else { return }
		inFlightFaviconKeys.insert(key)
		defer { inFlightFaviconKeys.remove(key) }

		var request = URLRequest(url: iconURL)
		request.cachePolicy = .reloadRevalidatingCacheData
		request.timeoutInterval = 15
		guard let (data, response) = try? await URLSession.shared.data(for: request),
		      let response = response as? HTTPURLResponse,
		      200 ..< 300 ~= response.statusCode,
		      !data.isEmpty,
		      data.count <= 1_000_000,
		      generation == cacheGeneration,
		      requestGenerations[webViewID] == requestGeneration,
		      let platformImage = Self.makePlatformImage(data)
		else { return }

		liveFavicons[webViewID] = (key, data)
		liveImages[webViewID] = (key, platformImage)
		guard favicons[key] != data else { return }

		favicons[key] = data
		decodedImages[key] = platformImage
		scheduleFaviconSave()
	}

	func clear() {
		cacheGeneration += 1
		requestGenerations.removeAll()
		liveFavicons.removeAll()
		liveImages.removeAll()
		decodedImages.removeAll()
		favicons.removeAll()
		scheduleFaviconSave()
	}

	private func scheduleFaviconSave() {
		guard persistence != nil else { return }
		faviconSaveTask?.cancel()
		let snapshot = favicons
		faviconSaveTask = Task.detached(priority: .utility) { [persistence] in
			try? await Task.sleep(for: .milliseconds(800))
			guard !Task.isCancelled else { return }
			try? persistence?.saveFavicons(snapshot)
		}
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

	private static func makePlatformImage(_ data: Data) -> PlatformImage? {
		#if os(macOS)
			NSImage(data: data)
		#elseif os(iOS)
			UIImage(data: data)
		#endif
	}

	private static func swiftUIImage(_ image: PlatformImage) -> Image {
		#if os(macOS)
			Image(nsImage: image)
		#elseif os(iOS)
			Image(uiImage: image)
		#endif
	}
}
