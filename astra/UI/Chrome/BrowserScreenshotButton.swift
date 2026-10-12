#if os(macOS)
	import SwiftUI

	struct BrowserScreenshotButton: View {
		let browser: Browser
		let controller: BrowserController
		@Environment(\.colorScheme) private var colorScheme
		@State private var screenshot: BrowserScreenshot?
		@State private var isCapturing = false
		@State private var showsEditor = false

		var body: some View {
			Button {
				Task { await capture(framed: true) }
			} label: {
				AstraTopBarIcon(title: "Screenshot Page", systemImage: "camera")
			}
			.astraTopBarButton()
			.disabled(isCapturing || !controller.hasRenderedWebView)
			.help("Capture the visible page")
			.accessibilityLabel("Screenshot Page")
			.accessibilityIdentifier("browser-screenshot-page")
			.contextMenu {
				Button("Copy Plain Screenshot", systemImage: "doc.on.clipboard") {
					Task { await capture(framed: false) }
				}
				.accessibilityIdentifier("browser-screenshot-copy-plain-direct")
			}
			.popover(isPresented: $showsEditor) {
				if let screenshot {
					BrowserScreenshotEditor(
						screenshot: screenshot,
						dark: colorScheme == .dark,
						maximumNoise: BrowserTheme().shaderNoiseMaximumOpacity,
						onCopy: { image in
							if BrowserScreenshot.copy(image) {
								showsEditor = false
								browser.session.toastManager.show(symbol: "doc.on.clipboard", message: "Screenshot copied")
							} else {
								browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: "Could not copy screenshot")
							}
						}
					)
					.environment(\.colorScheme, colorScheme)
				}
			}
		}

		private func capture(framed: Bool) async {
			guard !isCapturing, browser.selectedTab?.activeController === controller else { return }
			isCapturing = true
			defer { isCapturing = false }
			do {
				let capture = try await controller.captureScreenshot()
				guard browser.selectedTab?.activeController === controller else { return }
				if framed {
					screenshot = capture
					showsEditor = true
				} else if BrowserScreenshot.copy(capture.image) {
					browser.session.toastManager.show(symbol: "doc.on.clipboard", message: "Screenshot copied")
				} else {
					browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: "Could not copy screenshot")
				}
			} catch {
				browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: "Could not capture page")
			}
		}
	}

	private struct BrowserScreenshotEditor: View {
		let screenshot: BrowserScreenshot
		let dark: Bool
		let maximumNoise: Double
		let onCopy: (NSImage) -> Void
		private let previewScreenshot: BrowserScreenshot
		@State private var hue = 0.65
		@State private var grayscale = 0.0
		@State private var activeTrack: ScreenshotTrack = .color
		@State private var exportFailed = false

		init(
			screenshot: BrowserScreenshot,
			dark: Bool,
			maximumNoise: Double,
			onCopy: @escaping (NSImage) -> Void
		) {
			self.screenshot = screenshot
			self.dark = dark
			self.maximumNoise = maximumNoise
			self.onCopy = onCopy
			let previewWidth = Self.previewSize(for: screenshot.image.size).width
			let framedWidth = BrowserScreenshot.framedSize(for: screenshot.image.size).width
			let previewScale = min(screenshot.scale, previewWidth / framedWidth * 2)
			previewScreenshot = BrowserScreenshot(image: screenshot.image, scale: previewScale)
		}

		var body: some View {
			let previewSize = Self.previewSize(for: screenshot.image.size)
			let framedImage = previewScreenshot.framed(
				hue: hue,
				grayscale: grayscale,
				grayscaleEnabled: activeTrack == .grayscale,
				dark: dark,
				noiseAmount: maximumNoise * 0.8
			)
			VStack(spacing: 14) {
				if let framedImage {
					Image(nsImage: framedImage)
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(width: previewSize.width, height: previewSize.height)
						.clipShape(.rect(cornerRadius: 22))
						.accessibilityLabel("Framed screenshot preview")
						.accessibilityIdentifier("browser-screenshot-preview")
				} else {
					Text("Preview unavailable")
						.foregroundStyle(.secondary)
						.accessibilityLabel("Screenshot preview unavailable")
				}
				ScreenshotTrackSlider(hue: $hue, grayscale: $grayscale, activeTrack: $activeTrack)
					.padding(12)
					.background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
				Button(role: .confirm) {
					if let framedImage = screenshot.framed(
						hue: hue,
						grayscale: grayscale,
						grayscaleEnabled: activeTrack == .grayscale,
						dark: dark,
						noiseAmount: maximumNoise * 0.8
					) {
						onCopy(framedImage)
					} else {
						exportFailed = true
					}
				} label: {
					Label("Copy Framed", systemImage: "photo.on.rectangle")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.glassProminent)
				.controlSize(.large)
				.frame(maxWidth: .infinity)
				.accessibilityIdentifier("browser-screenshot-copy-framed")
				.padding(12)
				.background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
				if exportFailed {
					Text("Could not render framed screenshot")
						.font(.caption)
						.foregroundStyle(.red)
						.accessibilityIdentifier("browser-screenshot-render-error")
				}
			}
			.padding(18)
			.background(
				LinearGradient(
					colors: [
						Color(hue: hue, saturation: 0.65, brightness: 0.75),
						Color(hue: hue, saturation: 0.75, brightness: 0.45),
					],
					startPoint: .top,
					endPoint: .bottom
				),
				in: .rect(cornerRadius: 40)
			)
			.frame(width: previewSize.width + 36)
			.presentationSizing(.fitted)
		}

		private static func aspectRatio(for imageSize: CGSize) -> CGFloat {
			let framedSize = BrowserScreenshot.framedSize(for: imageSize)
			return framedSize.width / framedSize.height
		}

		private static func previewSize(for imageSize: CGSize) -> CGSize {
			let aspectRatio = aspectRatio(for: imageSize)
			let width = min(520, max(300, 340 * aspectRatio))
			return CGSize(width: width, height: width / aspectRatio)
		}
	}

	private enum ScreenshotTrack {
		case color
		case grayscale
	}

	private struct ScreenshotTrackSlider: View {
		@Binding var hue: Double
		@Binding var grayscale: Double
		@Binding var activeTrack: ScreenshotTrack
		@Environment(\.accessibilityReduceMotion) private var reduceMotion
		@Environment(\.displayScale) private var displayScale

		private let thumbSize: CGFloat = 46
		private let gap: CGFloat = 12

		var body: some View {
			GeometryReader { geometry in
				let layout = trackLayout(width: geometry.size.width)
				ZStack(alignment: .leading) {
					Capsule()
						.fill(LinearGradient(
							colors: (0 ... 12).map { Color(hue: Double($0) / 12, saturation: 0.8, brightness: 1) },
							startPoint: .leading,
							endPoint: .trailing
						))
						.blur(radius: 1 / displayScale)
						.frame(width: layout.colorWidth, height: 20)
						.clipShape(Capsule())
						.offset(x: thumbSize / 2)
						.contentShape(Rectangle())
					Capsule()
						.fill(LinearGradient(colors: [.white, .black], startPoint: .leading, endPoint: .trailing))
						.frame(width: layout.grayscaleWidth, height: 20)
						.offset(x: thumbSize / 2 + layout.colorWidth + gap)
						.contentShape(Rectangle())
					Image(systemName: activeTrack == .color ? "paintpalette" : "circle.lefthalf.filled")
						.font(.system(size: 17, weight: .medium))
						.frame(width: thumbSize, height: thumbSize)
						.glassEffect(.regular.tint(.white.opacity(0.18)).interactive(), in: Circle())
						.position(x: thumbPosition(layout: layout), y: thumbSize / 2)
						.zIndex(1)
				}
				.frame(height: thumbSize)
				.contentShape(Rectangle())
				.gesture(DragGesture(minimumDistance: 1).onChanged { gesture in
					update(at: gesture.location.x, layout: layout)
				})
				.simultaneousGesture(SpatialTapGesture().onEnded { event in
					update(at: event.location.x, layout: layout)
				})
				.animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3), value: activeTrack)
			}
			.frame(height: thumbSize)
			.accessibilityElement()
			.accessibilityLabel(activeTrack == .color ? "Frame color" : "Frame grayscale")
			.accessibilityValue(Text(activeTrack == .color ? hue : grayscale, format: .percent))
			.accessibilityHint("Drag left or right to adjust the selected track")
			.accessibilityAdjustableAction { direction in
				switch direction {
					case .increment: updateActive(by: 0.05)
					case .decrement: updateActive(by: -0.05)
					@unknown default: break
				}
			}
			.accessibilityIdentifier("browser-screenshot-track-slider")
			.accessibilityAction(named: "Use color track") {
				selectTrack(.color)
			}
			.accessibilityAction(named: "Use grayscale track") {
				selectTrack(.grayscale)
			}
		}

		private func trackLayout(width: CGFloat) -> (colorWidth: CGFloat, grayscaleWidth: CGFloat) {
			let usable = max(width - thumbSize - gap, 120)
			return (usable * 0.7, usable * 0.3)
		}

		private func thumbPosition(layout: (colorWidth: CGFloat, grayscaleWidth: CGFloat)) -> CGFloat {
			if activeTrack == .color {
				return thumbSize / 2 + CGFloat(hue) * layout.colorWidth
			}
			return thumbSize / 2 + layout.colorWidth + gap + CGFloat(grayscale) * layout.grayscaleWidth
		}

		private func update(at location: CGFloat, layout: (colorWidth: CGFloat, grayscaleWidth: CGFloat)) {
			let colorStart = thumbSize / 2
			let grayscaleStart = colorStart + layout.colorWidth + gap
			if location < grayscaleStart {
				if activeTrack != .color {
					activeTrack = .color
					performThemeAlignmentHaptic()
				}
				hue = min(max((location - colorStart) / layout.colorWidth, 0), 1)
			} else {
				if activeTrack != .grayscale {
					activeTrack = .grayscale
					performThemeAlignmentHaptic()
				}
				grayscale = min(max((location - grayscaleStart) / layout.grayscaleWidth, 0), 1)
			}
		}

		private func updateActive(by amount: Double) {
			if activeTrack == .color {
				hue = min(max(hue + amount, 0), 1)
			} else {
				grayscale = min(max(grayscale + amount, 0), 1)
			}
		}

		private func selectTrack(_ track: ScreenshotTrack) {
			guard activeTrack != track else { return }
			activeTrack = track
			performThemeAlignmentHaptic()
		}
	}

	private func performThemeAlignmentHaptic() {
		NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
	}

	#Preview("Landscape") {
		BrowserScreenshotEditor(
			screenshot: BrowserScreenshot(image: NSImage(size: CGSize(width: 1200, height: 700)), scale: 2),
			dark: true,
			maximumNoise: 0.2,
			onCopy: { _ in }
		)
	}

	#Preview("Portrait") {
		BrowserScreenshotEditor(
			screenshot: BrowserScreenshot(image: NSImage(size: CGSize(width: 700, height: 1200)), scale: 2),
			dark: true,
			maximumNoise: 0.2,
			onCopy: { _ in }
		)
	}
#endif
