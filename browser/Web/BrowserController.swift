import CoreGraphics
import Observation
import SwiftUI
import WebKit
#if os(macOS)
	import AppKit
#endif

@MainActor
@Observable
final class BrowserController: NSObject {
	@ObservationIgnored
	let webView: WKWebView = {
		let configuration = WKWebViewConfiguration()
		FaviconStore.shared.configureFaviconObservation(
			in: configuration.userContentController
		)
		return WKWebView(frame: .zero, configuration: configuration)
	}()

	private(set) var history: [URL]
	private(set) var historyIndex: Int
	private(set) var canGoBack = false
	private(set) var canGoForward = false
	private(set) var backHistoryItems: [WKBackForwardListItem] = []
	private(set) var forwardHistoryItems: [WKBackForwardListItem] = []

	var url: URL?
	private(set) var isLoading = false
	private(set) var estimatedProgress = 0.0
	private(set) var themeColor: Color?
	private(set) var themeColorIsLight: Bool?
	#if os(macOS)
		private(set) var previewSnapshot: NSImage?
	#endif

	@ObservationIgnored
	var navigationDidChange: (@MainActor () -> Void)?
	@ObservationIgnored
	var titleDidChange: (@MainActor (String?) -> Void)?
	@ObservationIgnored
	var newWindowRequested: (@MainActor (URL, UnitPoint) -> Void)?

	@ObservationIgnored
	private var observations: [NSKeyValueObservation] = []
	@ObservationIgnored
	private var navigationGeneration = 0
	@ObservationIgnored
	private var hasDeclaredThemeColor = false
	#if os(macOS)
		@ObservationIgnored
		private var previewSnapshotRefreshTask: Task<Void, Never>?
		@ObservationIgnored
		private var isRefreshingPreviewSnapshot = false
	#endif

	init(initialURL: URL? = nil, history: [URL] = [], historyIndex: Int = 0) {
		let restoredHistory = history.isEmpty ? initialURL.map { [$0] } ?? [] : history
		let restoredHistoryIndex = restoredHistory.isEmpty ? 0 : min(max(historyIndex, 0), restoredHistory.count - 1)
		self.history = restoredHistory
		self.historyIndex = restoredHistoryIndex
		url = restoredHistory.isEmpty ? nil : restoredHistory[restoredHistoryIndex]
		super.init()
		webView.navigationDelegate = self
		webView.uiDelegate = self
		updateThemeColor(url == nil ? .black : webView.underPageBackgroundColor ?? .white)

		observations = [
			webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.canGoBack = webView.canGoBack
				}
			},
			webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.canGoForward = webView.canGoForward
				}
			},
			webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.isLoading = webView.isLoading
				}
			},
			webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.estimatedProgress = webView.estimatedProgress
				}
			},
			webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					guard let self else { return }
					guard let url = change.newValue ?? webView.url else { return }
					self.url = url
					self.updateHistory()
				}
			},
			webView.observe(\.themeColor, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					guard let self else { return }
					guard let color = change.newValue ?? webView.themeColor else {
						self.hasDeclaredThemeColor = false
						return
					}
					self.hasDeclaredThemeColor = true
					self.updateThemeColor(color)
				}
			},
			webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					self?.titleDidChange?(change.newValue ?? webView.title)
				}
			},
		]
		#if os(macOS)
			startPreviewSnapshotRefresh()
		#endif

		if let url {
			load(url)
		}
	}

	deinit {
		#if os(macOS)
			previewSnapshotRefreshTask?.cancel()
		#endif
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

	func go(to item: WKBackForwardListItem) {
		webView.go(to: item)
	}

	func reload() {
		webView.reload()
	}

	func reloadFromOrigin() {
		webView.reloadFromOrigin()
	}

	func zoomIn() {
		webView.pageZoom = min(webView.pageZoom + 0.1, 5)
		ToastManager.shared.show(
			symbol: "plus.magnifyingglass",
			message: "Zoom \(Int(webView.pageZoom * 100))%"
		)
	}

	func zoomOut() {
		webView.pageZoom = max(webView.pageZoom - 0.1, 0.25)
		ToastManager.shared.show(
			symbol: "minus.magnifyingglass",
			message: "Zoom \(Int(webView.pageZoom * 100))%"
		)
	}

	func loadFaviconIfMissing() {
		guard let url else { return }
		Task { @MainActor in
			await FaviconStore.shared.loadFavicon(
				for: url,
				from: webView,
				onlyIfMissing: true
			)
		}
	}

	#if os(macOS)
		func refreshPreviewSnapshot() async {
			guard let image = await takeSnapshot() else { return }
			previewSnapshot = image
		}
	#endif

	private func updateHistory() {
		let backForwardList = webView.backForwardList
		backHistoryItems = Array(backForwardList.backList.reversed())
		forwardHistoryItems = backForwardList.forwardList
		history = backForwardList.backList.map(\.url)
		historyIndex = history.count
		if let currentItem = backForwardList.currentItem {
			history.append(currentItem.url)
		}
		history.append(contentsOf: backForwardList.forwardList.map(\.url))
		navigationDidChange?()
	}

	private func updateThemeColor(_ color: PlatformColor) {
		#if os(macOS)
			guard let color = color.usingColorSpace(.deviceRGB) else {
				return
			}
		#endif

		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		#if os(iOS)
			guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
				return
			}
		#elseif os(macOS)
			color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		#endif

		themeColor = Color(color)
		themeColorIsLight = red + green + blue > 1.5
	}

	private func takeSnapshot() async -> SnapshotImage? {
		guard url != nil, !webView.bounds.isEmpty else { return nil }
		#if os(macOS)
			guard !isRefreshingPreviewSnapshot else { return nil }
			isRefreshingPreviewSnapshot = true
			defer { isRefreshingPreviewSnapshot = false }
		#endif

		let configuration = WKSnapshotConfiguration()
		configuration.rect = webView.bounds
		configuration.snapshotWidth = 180
		return try? await webView.takeSnapshot(configuration: configuration)
	}

	private func capturePageSnapshot(generation: Int) async {
		guard let image = await takeSnapshot(),
		      generation == navigationGeneration
		else { return }

		#if os(macOS)
			previewSnapshot = image
		#endif

		guard !hasDeclaredThemeColor,
		      let cgImage = Self.cgImage(from: image),
		      let color = Self.dominantPageColor(in: cgImage)
		else { return }

		updateThemeColor(color)
	}

	#if os(macOS)
		private func startPreviewSnapshotRefresh() {
			previewSnapshotRefreshTask = Task { @MainActor [weak self] in
				while !Task.isCancelled {
					do {
						try await Task.sleep(for: .seconds(Double.random(in: 50 ... 58)))
					} catch {
						return
					}

					guard let self else { return }
					await refreshPreviewSnapshot()
				}
			}
		}
	#endif

	private static func cgImage(from image: SnapshotImage) -> CGImage? {
		#if os(iOS)
			image.cgImage
		#elseif os(macOS)
			image.cgImage(forProposedRect: nil, context: nil, hints: nil)
		#endif
	}

	private static func dominantPageColor(in image: CGImage) -> PlatformColor? {
		let width = 40
		let height = 40
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(
				data: buffer.baseAddress,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: width * 4,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
			) else { return false }
			context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
			return true
		}
		guard didDraw else { return nil }

		var chromatic: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
		var black = 0
		var white = 0
		for index in stride(from: 0, to: pixels.count, by: 4) {
			let red = Int(pixels[index])
			let green = Int(pixels[index + 1])
			let blue = Int(pixels[index + 2])
			let maximum = max(red, green, blue)
			let minimum = min(red, green, blue)
			let saturation = maximum == 0 ? 0 : Double(maximum - minimum) / Double(maximum)
			if saturation < 0.18 {
				if 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue) < 128 {
					black += 1
				} else {
					white += 1
				}
				continue
			}

			let delta = maximum - minimum
			var hue: Double = if maximum == red {
				Double(green - blue) / Double(delta)
			} else if maximum == green {
				2 + Double(blue - red) / Double(delta)
			} else {
				4 + Double(red - green) / Double(delta)
			}
			hue = (hue * 60).truncatingRemainder(dividingBy: 360)
			if hue < 0 {
				hue += 360
			}
			let hueBucket = Int(hue / 15)
			let saturationBucket = min(2, Int(saturation * 3))
			let key = hueBucket * 3 + saturationBucket
			let bucket = chromatic[key, default: (0, 0, 0, 0)]
			chromatic[key] = (bucket.count + 1, bucket.red + red, bucket.green + green, bucket.blue + blue)
		}

		let dominant = chromatic.values.max { $0.count < $1.count }
		let neutralCount = max(black, white)
		if let dominant, dominant.count >= 320, dominant.count >= neutralCount / 3 {
			let red = CGFloat(dominant.red) / CGFloat(dominant.count) / 255
			let green = CGFloat(dominant.green) / CGFloat(dominant.count) / 255
			let blue = CGFloat(dominant.blue) / CGFloat(dominant.count) / 255
			return PlatformColor(red: red, green: green, blue: blue, alpha: 1)
		}
		return black >= white ? PlatformColor.black : PlatformColor.white
	}
}

extension BrowserController: WKNavigationDelegate {
	func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
		navigationGeneration += 1
		hasDeclaredThemeColor = false
	}

	func webView(_: WKWebView, didFinish _: WKNavigation!) {
		updateHistory()
		let generation = navigationGeneration
		if let url {
			Task { @MainActor in
				await FaviconStore.shared.loadFavicon(for: url, from: webView)
			}
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			try? await Task.sleep(for: .milliseconds(200))
			await capturePageSnapshot(generation: generation)
		}
	}
}

extension BrowserController: WKUIDelegate {
	func webView(
		_ webView: WKWebView,
		createWebViewWith _: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures _: WKWindowFeatures
	) -> WKWebView? {
		guard navigationAction.targetFrame == nil,
		      let url = navigationAction.request.url
		else { return nil }

		newWindowRequested?(url, newWindowSource(in: webView))
		return nil
	}

	private func newWindowSource(in webView: WKWebView) -> UnitPoint {
		guard webView.bounds.width > 0, webView.bounds.height > 0 else { return .center }

		#if os(macOS)
			guard let window = webView.window else { return .center }
			let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
			let point = webView.convert(windowPoint, from: nil)
			return UnitPoint(
				x: min(max(point.x / webView.bounds.width, 0), 1),
				y: min(max(1 - point.y / webView.bounds.height, 0), 1)
			)
		#else
			return .center
		#endif
	}
}

#if os(iOS)
	private typealias PlatformColor = UIColor
#elseif os(macOS)
	private typealias PlatformColor = NSColor
	private typealias SnapshotImage = NSImage
#endif
#if os(iOS)
	private typealias SnapshotImage = UIImage
#endif
