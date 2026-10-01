import Foundation
import ImageIO
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
	private static let maximumImageBytes = 1_000_000
	private static let maximumImageDimension = 512
	private static let maximumCacheEntries = 256
	private static let maximumCacheBytes = 16_000_000
	private static let maximumConcurrentRequests = 4
	private static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
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
	private var fetchedAt: [String: Date] = [:]
	private var activeRequests: [ObjectIdentifier: UUID] = [:]

	@ObservationIgnored
	private let persistence: BrowserPersistence?

	@ObservationIgnored
	private let networkSession: URLSession

	@ObservationIgnored
	private var cacheGeneration = 0
	@ObservationIgnored
	private var faviconSaveTask: Task<Void, Never>?
	@ObservationIgnored
	private var decodedImages: [String: PlatformImage] = [:]
	@ObservationIgnored
	private var liveImages: [ObjectIdentifier: (cacheKey: String, image: PlatformImage)] = [:]

	var isEmpty: Bool {
		favicons.isEmpty
	}

	override private convenience init() {
		self.init(isPrivate: false)
	}

	init(isPrivate: Bool) {
		let persistence: BrowserPersistence?
		do {
			persistence = isPrivate ? nil : try BrowserPersistence()
		} catch {
			persistence = nil
		}
		self.persistence = persistence
		networkSession = isPrivate ? URLSession(configuration: .ephemeral) : .shared
		favicons = [:]
		super.init()

		if let persistence {
			Task.detached(priority: .utility) { [persistence] in
				guard let loaded = try? persistence.loadFavicons(), !loaded.isEmpty else { return }
				await MainActor.run { [weak self] in
					guard let self else { return }
					var migrationRequired = false
					for (storedKey, data) in loaded {
						guard Self.isValidImage(data) else {
							migrationRequired = true
							continue
						}
						let key = FaviconKey.origin(for: URL(string: storedKey))
							?? FaviconKey.origin(for: URL(string: "https://\(storedKey)"))
						guard let key else {
							migrationRequired = true
							continue
						}
						migrationRequired = migrationRequired || key != storedKey || favicons[key] != nil
						favicons[key] = data
					}
					if trimCache() || migrationRequired {
						scheduleFaviconSave()
					}
				}
			}
		}
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
		guard let key = FaviconKey.origin(for: pageURL) else { return nil }
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
		guard let key = FaviconKey.origin(for: pageURL),
		      FaviconKey.origin(for: webView.url) == key
		else { return }

		let webViewID = ObjectIdentifier(webView)
		guard activeRequests[webViewID] != nil || activeRequests.count < Self.maximumConcurrentRequests else { return }
		let requestID = UUID()
		activeRequests[webViewID] = requestID
		let generation = cacheGeneration
		defer {
			if activeRequests[webViewID] == requestID {
				activeRequests[webViewID] = nil
			}
		}

		let hasLiveFavicon = liveFavicons[webViewID]?.cacheKey == key
		let isFresh = fetchedAt[key].map { Date().timeIntervalSince($0) < Self.refreshInterval } ?? false
		if onlyIfMissing, (hasLiveFavicon || favicons[key] != nil), isFresh {
			return
		}
		guard !Task.isCancelled else { return }

		let script = """
		(() => {
			const icons = [...document.querySelectorAll('link[rel~="icon"]')];
			icons.sort((a, b) => (Number(b.sizes?.[0]?.split('x')[0]) || 0)
				- (Number(a.sizes?.[0]?.split('x')[0]) || 0));
			return icons[0]?.href ?? new URL('/favicon.ico', document.baseURI).href;
		})()
		"""
		guard let address = try? await webView.evaluateJavaScript(script) as? String,
		      !Task.isCancelled,
		      activeRequests[webViewID] == requestID,
		      FaviconKey.origin(for: webView.url) == key,
		      let iconURL = URL(string: address),
		      FaviconKey.origin(for: iconURL) != nil
		else { return }

		var request = URLRequest(url: iconURL)
		request.cachePolicy = .reloadRevalidatingCacheData
		request.timeoutInterval = 15
		guard let (bytes, response) = try? await networkSession.bytes(for: request),
		      let response = response as? HTTPURLResponse,
		      200 ..< 300 ~= response.statusCode,
		      response.expectedContentLength <= Int64(Self.maximumImageBytes) || response.expectedContentLength < 0
		else { return }

		var data = Data()
		for try await byte in bytes {
			guard !Task.isCancelled,
			      activeRequests[webViewID] == requestID,
			      generation == cacheGeneration,
			      FaviconKey.origin(for: webView.url) == key,
			      data.count < Self.maximumImageBytes
			else { return }
			data.append(byte)
		}

		guard !data.isEmpty,
		      Self.isValidImage(data),
		      !Task.isCancelled,
		      activeRequests[webViewID] == requestID,
		      generation == cacheGeneration,
		      FaviconKey.origin(for: webView.url) == key,
		      let platformImage = Self.makePlatformImage(data)
		else { return }

		liveFavicons[webViewID] = (key, data)
		liveImages[webViewID] = (key, platformImage)
		fetchedAt[key] = .now
		favicons[key] = data
		decodedImages[key] = platformImage
		trimCache()
		scheduleFaviconSave()
	}

	func clear() {
		cacheGeneration += 1
		activeRequests.removeAll()
		liveFavicons.removeAll()
		liveImages.removeAll()
		decodedImages.removeAll()
		fetchedAt.removeAll()
		favicons.removeAll()
		scheduleFaviconSave()
	}

	@discardableResult
	private func trimCache() -> Bool {
		var totalBytes = favicons.values.reduce(0) { $0 + $1.count }
		guard favicons.count > Self.maximumCacheEntries || totalBytes > Self.maximumCacheBytes else { return false }
		var removedEntry = false
		let oldestFirst = favicons.keys.sorted {
			(fetchedAt[$0] ?? .distantPast) < (fetchedAt[$1] ?? .distantPast)
		}
		for key in oldestFirst {
			guard favicons.count > Self.maximumCacheEntries || totalBytes > Self.maximumCacheBytes else { break }
			totalBytes -= favicons.removeValue(forKey: key)?.count ?? 0
			fetchedAt[key] = nil
			decodedImages[key] = nil
			removedEntry = true
		}
		return removedEntry
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

	private static func isValidImage(_ data: Data) -> Bool {
		guard !data.isEmpty,
		      data.count <= maximumImageBytes,
		      let source = CGImageSourceCreateWithData(data as CFData, nil),
		      CGImageSourceGetCount(source) > 0,
		      CGImageSourceGetCount(source) <= 32
		else { return false }
		for index in 0 ..< CGImageSourceGetCount(source) {
			guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
			      let width = properties[kCGImagePropertyPixelWidth] as? Int,
			      let height = properties[kCGImagePropertyPixelHeight] as? Int,
			      width > 0,
			      height > 0,
			      width <= maximumImageDimension,
			      height <= maximumImageDimension
			else { return false }
		}
		return true
	}

	private static func makePlatformImage(_ data: Data) -> PlatformImage? {
		guard isValidImage(data) else { return nil }
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
