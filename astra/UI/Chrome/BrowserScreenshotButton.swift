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
			Button("Screenshot Page", systemImage: "camera") {
				Task { await capture(framed: true) }
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.glass)
			.disabled(isCapturing || !controller.hasCurrentPageDocument || controller.navigationFailure != nil)
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
		@State private var hue = 0.65
		@State private var noise = 0.0
		@State private var neutral = false

		var body: some View {
			let framedImage = screenshot.framed(hue: hue, neutral: neutral, dark: dark, noiseAmount: noise * maximumNoise)
			VStack(spacing: 16) {
				Text("Frame Screenshot")
					.font(.headline)
				if let framedImage {
					Image(nsImage: framedImage)
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(maxWidth: .infinity, maxHeight: 280)
						.clipShape(.rect(cornerRadius: 16))
						.accessibilityLabel("Framed screenshot preview")
						.accessibilityIdentifier("browser-screenshot-preview")
				}
				HStack(alignment: .top, spacing: 12) {
					VStack(spacing: 16) {
						ThemeControlSlider(
							value: $hue,
							label: "Frame color",
							symbol: "paintpalette",
							identifier: "browser-screenshot-hue",
							tickCount: 7,
							trackColors: (0 ... 12).map { Color(hue: Double($0) / 12, saturation: 0.8, brightness: 1) }
						)
						.onChange(of: hue) { _, _ in neutral = false }
						ThemeControlSlider(
							value: $noise,
							label: "Monochrome noise amount",
							symbol: "app.background.dotted",
							identifier: "browser-screenshot-noise",
							tickCount: 6
						)
					}
					Button("Neutral Gradient", systemImage: "circle.lefthalf.filled") {
						neutral.toggle()
					}
					.labelStyle(.iconOnly)
					.buttonStyle(.glass)
					.buttonBorderShape(.circle)
					.tint(neutral ? .accentColor : .clear)
					.accessibilityLabel("Neutral Gradient")
					.accessibilityValue(neutral ? "On" : "Off")
					.accessibilityIdentifier("browser-screenshot-neutral")
				}
				HStack {
					Button("Copy Plain", systemImage: "doc.on.clipboard") {
						onCopy(screenshot.image)
					}
					.buttonStyle(.glass)
					.accessibilityIdentifier("browser-screenshot-copy-plain")
					Spacer()
					Button("Copy Framed", systemImage: "photo.on.rectangle", role: .confirm) {
						if let framedImage {
							onCopy(framedImage)
						}
					}
					.buttonStyle(.glassProminent)
					.disabled(framedImage == nil)
					.accessibilityIdentifier("browser-screenshot-copy-framed")
				}
			}
			.padding(20)
			.frame(width: 440)
			.presentationSizing(.fitted)
		}
	}
#endif
