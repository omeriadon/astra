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

/// Serializes favicon commits. Old snapshots cannot complete after a newer
/// snapshot has been written, even if one disk operation takes longer.
private actor FaviconPersistenceWriter {
	private let persistence: BrowserPersistence

	init(_ persistence: BrowserPersistence) {
		self.persistence = persistence
	}

	func save(_ snapshot: [String: Data]) {
		try? persistence.saveFavicons(snapshot)
	}
}

@MainActor
@Observable
final class FaviconStore: NSObject, WKScriptMessageHandler {
	@MainActor
	private final class ActiveRequest {
		weak var webView: WKWebView?
		let id: UUID

		init(webView: WKWebView, id: UUID) {
			self.webView = webView
			self.id = id
		}
	}

	static let shared = FaviconStore()
	private static let messageHandlerName = "faviconChanged"
	private nonisolated static let maximumImageBytes = 1_000_000
	private nonisolated static let maximumImageDimension = 512
	private static let maximumCacheEntries = 256
	private static let maximumCacheBytes = 16_000_000
	private static let maximumConcurrentRequests = 4
	private static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
	private static let observationScript = """
	(() => {
		// This runs once per document in the isolated WebKit content world.
		if (document.__astraFaviconObserverInstalled) return;
		document.__astraFaviconObserverInstalled = true;
		const iconSelector = 'link[rel~="icon"]';
		let pendingWhileHidden = false;
		let scheduled = false;

		const scheduleNotification = () => {
			if (document.hidden) {
				pendingWhileHidden = true;
				return;
			}
			if (scheduled) return;
			scheduled = true;
			setTimeout(() => {
				scheduled = false;
				if (document.hidden) {
					pendingWhileHidden = true;
					return;
				}
				pendingWhileHidden = false;
				window.webkit.messageHandlers.faviconChanged.postMessage(true);
			}, 250);
		};

		document.addEventListener('visibilitychange', () => {
			if (!document.hidden && pendingWhileHidden) scheduleNotification();
		});

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
			if (faviconChanged) scheduleNotification();
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
	@ObservationIgnored
	private var fetchedAt: [String: Date] = [:]
	/// Bounded URL-to-origin cache: sidebar rows can be reevaluated frequently
	/// without reparsing every unchanged URL into URLComponents.
	@ObservationIgnored private var visibleOriginCache: [URL: String] = [:]
	@ObservationIgnored
	private var activeRequests: [ObjectIdentifier: ActiveRequest] = [:]
	@ObservationIgnored
	private var currentNetworkRequests = 0

	@ObservationIgnored
	private let persistence: BrowserPersistence?
	@ObservationIgnored
	private let persistenceWriter: FaviconPersistenceWriter?

	@ObservationIgnored
	private let networkSession: URLSession

	@ObservationIgnored
	private var cacheGeneration = 0
	@ObservationIgnored
	private var faviconSaveTask: Task<Void, Never>?
	@ObservationIgnored
	private let decodedImages: NSCache<NSString, PlatformImage> = {
		let cache = NSCache<NSString, PlatformImage>()
		// Validated favicons can be 512x512 each. Bounding compressed data
		// alone does not bound the decoded pixel backing stores.
		cache.totalCostLimit = 32 * 1024 * 1024
		cache.countLimit = 64
		return cache
	}()

	var isEmpty: Bool {
		favicons.isEmpty
	}

	override private convenience init() {
		self.init(isPrivate: false)
	}

	init(isPrivate: Bool) {
		BrowserLog.debug(.favicons, "favicon-store.init", metadata: ["private": String(isPrivate)])
		let persistence: BrowserPersistence?
		do {
			persistence = isPrivate ? nil : try BrowserPersistence.makeShared()
		} catch {
			persistence = nil
		}
		self.persistence = persistence
		persistenceWriter = persistence.map(FaviconPersistenceWriter.init)
		networkSession = isPrivate ? URLSession(configuration: .ephemeral) : .shared
		let cachedFavicons = isPrivate ? [:] : BrowserLaunchCache.load()?.favicons ?? [:]
		favicons = cachedFavicons
		super.init()

		if let persistence {
			let hydrationGeneration = cacheGeneration
			let cachedFaviconKeys = Set(cachedFavicons.keys)
			Task.detached(priority: .utility) { [persistence] in
				guard let loaded = try? persistence.loadFavicons(), !loaded.isEmpty else { return }
				// ImageIO header validation can touch every frame in an .ico/gif.
				// Do all of that off-main; startup used to validate up to 256 icons
				// serially inside MainActor.run before the cache became usable.
				let prepared = loaded.compactMap { storedKey, data -> (String, String, Data)? in
					guard Self.isValidImage(data) else { return nil }
					let key = FaviconKey.origin(for: URL(string: storedKey))
						?? FaviconKey.origin(for: URL(string: "https://\(storedKey)"))
					guard let key else { return nil }
					return (storedKey, key, data)
				}
				let rejectedOrRewritten = prepared.count != loaded.count
				await MainActor.run { [weak self] in
					guard let self, cacheGeneration == hydrationGeneration else { return }
					var migrationRequired = rejectedOrRewritten
					for (storedKey, key, data) in prepared {
						if cachedFaviconKeys.contains(key) {
							favicons[key] = data
							migrationRequired = true
							continue
						}
						guard favicons[key] == nil else {
							migrationRequired = true
							continue
						}
						migrationRequired = migrationRequired || key != storedKey
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

	private func visibleOrigin(for url: URL?) -> String? {
		guard let url else { return nil }
		if let cached = visibleOriginCache[url] { return cached }
		guard let origin = FaviconKey.origin(for: url) else { return nil }
		if visibleOriginCache.count >= 512 {
			visibleOriginCache.removeAll(keepingCapacity: true)
		}
		visibleOriginCache[url] = origin
		return origin
	}

	/// Used by tab selection: a cached icon needs no WebKit JavaScript probe or
	/// network refresh just because the user returned to an existing tab.
	func hasCachedFavicon(for pageURL: URL?) -> Bool {
		guard let key = visibleOrigin(for: pageURL) else { return false }
		return favicons[key] != nil
	}

	func image(for pageURL: URL?, in _: WKWebView? = nil) -> Image? {
		guard let key = visibleOrigin(for: pageURL) else { return nil }
		if let cached = decodedImages.object(forKey: key as NSString) {
			return Self.swiftUIImage(cached)
		}
		guard let data = favicons[key], let decoded = Self.makePlatformImage(data) else { return nil }
		decodedImages.setObject(decoded, forKey: key as NSString, cost: Self.decodedImageCost(decoded))
		return Self.swiftUIImage(decoded)
	}

	func loadFavicon(for pageURL: URL, from webView: WKWebView, onlyIfMissing: Bool = false) async {
		BrowserLog.trace(.favicons, "favicon.load", metadata: ["url": BrowserLog.url(pageURL), "only_if_missing": String(onlyIfMissing)])
		guard let key = FaviconKey.origin(for: pageURL),
		      FaviconKey.origin(for: webView.url) == key
		else { return }

		let webViewID = ObjectIdentifier(webView)
		activeRequests = activeRequests.filter { $0.value.webView != nil }
		let existingRequest = activeRequests[webViewID]
		guard existingRequest?.webView === webView || activeRequests.count < Self.maximumConcurrentRequests * 4 else { return }
		let requestID = UUID()
		let activeRequest = ActiveRequest(webView: webView, id: requestID)
		activeRequests[webViewID] = activeRequest
		let generation = cacheGeneration
		defer {
			if activeRequests[webViewID] === activeRequest {
				activeRequests[webViewID] = nil
			}
		}

		let isFresh = fetchedAt[key].map { Date().timeIntervalSince($0) < Self.refreshInterval } ?? false
		if onlyIfMissing, favicons[key] != nil, isFresh {
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
		      activeRequests[webViewID] === activeRequest,
		      FaviconKey.origin(for: webView.url) == key,
		      let iconURL = URL(string: address),
		      FaviconKey.origin(for: iconURL) != nil
		else { return }

		var request = URLRequest(url: iconURL)
		request.cachePolicy = .reloadRevalidatingCacheData
		request.timeoutInterval = 15
		guard currentNetworkRequests < Self.maximumConcurrentRequests else { return }
		currentNetworkRequests += 1
		defer { currentNetworkRequests -= 1 }
		guard let data = await Self.fetchValidatedFaviconData(
			session: networkSession,
			request: request
		) else { return }

		guard !Task.isCancelled,
		      activeRequests[webViewID] === activeRequest,
		      generation == cacheGeneration,
		      FaviconKey.origin(for: webView.url) == key,
		      let platformImage = Self.makePlatformImage(data)
		else { return }

		fetchedAt[key] = .now
		favicons[key] = data
		decodedImages.setObject(platformImage, forKey: key as NSString, cost: Self.decodedImageCost(platformImage))
		trimCache()
		scheduleFaviconSave()
	}

	func clear() {
		BrowserLog.notice(.favicons, "favicon.clear")
		cacheGeneration += 1
		activeRequests.removeAll()
		decodedImages.removeAllObjects()
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
			decodedImages.removeObject(forKey: key as NSString)
			removedEntry = true
		}
		return removedEntry
	}

	private func scheduleFaviconSave() {
		guard let writer = persistenceWriter else { return }
		faviconSaveTask?.cancel()
		faviconSaveTask = Task { @MainActor [weak self] in
			do {
				try await Task.sleep(for: .milliseconds(800))
			} catch {
				return
			}
			guard !Task.isCancelled, let self else { return }
			// Do not capture a COW dictionary before the debounce completes:
			// that forces a full copy on every subsequent favicon mutation.
			let snapshot = favicons
			BrowserLaunchCache.updateFavicons(snapshot)
			await writer.save(snapshot)
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

	/// Stream and validate favicon bytes away from MainActor. The old byte-by-byte
	/// loop ran inside FaviconStore's global actor, so a 100–500 KB icon could
	/// schedule hundreds of thousands of tiny main-thread append operations.
	private nonisolated static func fetchValidatedFaviconData(
		session: URLSession,
		request: URLRequest
	) async -> Data? {
		do {
			let (bytes, response) = try await session.bytes(for: request)
			guard let response = response as? HTTPURLResponse,
			      200 ..< 300 ~= response.statusCode,
			      response.expectedContentLength <= Int64(maximumImageBytes)
			      || response.expectedContentLength < 0
			else { return nil }

			var data = Data()
			if response.expectedContentLength > 0 {
				data.reserveCapacity(min(Int(response.expectedContentLength), maximumImageBytes))
			}
			for try await byte in bytes {
				guard !Task.isCancelled, data.count < maximumImageBytes else { return nil }
				data.append(byte)
			}
			guard !data.isEmpty, isValidImage(data) else { return nil }
			return data
		} catch {
			return nil
		}
	}

	private nonisolated static func isValidImage(_ data: Data) -> Bool {
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

	/// Approximate decoded pixel cost for eviction (not WebKit or GPU memory).
	/// NSCache may also evict entries sooner under memory pressure.
	private static func decodedImageCost(_ image: PlatformImage) -> Int {
		#if os(macOS)
			let dimensions = image.representations.map { (max($0.pixelsWide, 1), max($0.pixelsHigh, 1)) }
			let pixels = dimensions.max { $0.0 * $0.1 < $1.0 * $1.1 } ?? (512, 512)
			return pixels.0 * pixels.1 * 4
		#elseif os(iOS)
			let width = max(Int(image.size.width * image.scale), 1)
			let height = max(Int(image.size.height * image.scale), 1)
			return width * height * 4
		#endif
	}

	private static func makePlatformImage(_ data: Data) -> PlatformImage? {
		#if os(macOS)
			return NSImage(data: data)
		#elseif os(iOS)
			return UIImage(data: data)
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
