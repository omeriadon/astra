import CoreGraphics
import Observation
import SwiftUI
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
	private(set) var themeColor: Color?
	private(set) var themeColorIsLight: Bool?

	@ObservationIgnored
	var navigationDidChange: (@MainActor () -> Void)?

	@ObservationIgnored
	private var observations: [NSKeyValueObservation] = []
	@ObservationIgnored
	private var navigationGeneration = 0

	init(initialURL: URL? = nil, history: [URL] = [], historyIndex: Int = 0) {
		let restoredHistory = history.isEmpty ? [initialURL ?? Self.startURL] : history
		let restoredHistoryIndex = min(max(historyIndex, 0), restoredHistory.count - 1)
		self.history = restoredHistory
		self.historyIndex = restoredHistoryIndex
		url = restoredHistory[restoredHistoryIndex]
		super.init()
		webView.navigationDelegate = self
		updateThemeColor(webView.underPageBackgroundColor ?? .white)

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
			webView.observe(\.themeColor, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					guard let color = change.newValue ?? webView.themeColor else { return }
					self?.updateThemeColor(color)
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

	private func samplePageColor(generation: Int) async {
		guard webView.themeColor == nil else { return }
		let configuration = WKSnapshotConfiguration()
		configuration.rect = webView.bounds

		guard let image = try? await webView.takeSnapshot(configuration: configuration),
		      let cgImage = Self.cgImage(from: image),
		      let color = Self.dominantPageColor(in: cgImage),
		      generation == navigationGeneration,
		      webView.themeColor == nil
		else { return }

		updateThemeColor(color)
	}

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
	}

	func webView(_: WKWebView, didFinish _: WKNavigation!) {
		let generation = navigationGeneration
		Task { @MainActor [weak self] in
			guard let self else { return }
			await samplePageColor(generation: generation)
		}
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
