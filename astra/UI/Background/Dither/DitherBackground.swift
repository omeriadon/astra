import SwiftUI

/// Native Metal fill, with no WebView, per-square SwiftUI views, texture readback.
struct DitherBackground: View {
	/// Current Space theme; positions and colours update with the Space.
	let theme: BrowserTheme
	/// Persisted visual and motion settings.
	let configuration: DitherConfiguration
	/// Optional input shared with an ancestor to track hover over foreground controls.
	var pointer: DitherPointerInput?
	/// Owning new-tab window visibility; defaults to true for standalone previews.
	var canAnimate = true

	init(theme: BrowserTheme, configuration: DitherConfiguration = DitherConfiguration(), pointer: DitherPointerInput? = nil, canAnimate: Bool = true) {
		self.theme = theme
		self.configuration = configuration.bounded()
		self.pointer = pointer
		self.canAnimate = canAnimate
	}

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.colorScheme) private var colorScheme
	@State private var localPointer = DitherPointerInput()

	private var running: Bool {
		#if os(macOS)
			canAnimate
		#else
			canAnimate && scenePhase == .active
		#endif
	}

	var body: some View {
		#if os(macOS)
			DitherNativeSurface(
				configuration: effectiveConfiguration,
				inputs: nativeInputs,
				pointer: pointer ?? localPointer,
				isActive: running
			)
			.onContinuousHover { phase in
				guard pointer == nil else { return }
				switch phase {
					case let .active(location): localPointer.location = location
					case .ended: localPointer.location = nil
				}
			}
			.accessibilityHidden(true)
		#else
			DitherFallbackBackground(theme: theme, pointer: pointer, canAnimate: canAnimate)
		#endif
	}

	private var effectiveConfiguration: DitherConfiguration {
		var value = configuration
		if value.useThemeColors, value.backgroundStyle == "custom" {
			let dark = theme.appearanceMode == .dark || (theme.appearanceMode == .auto && colorScheme == .dark)
			value.backgroundColor = SIMD3<Float>(repeating: dark ? 0 : 1)
		}
		if reduceMotion {
			value.disableAnimation = true
			value.intro = false
			value.cursorInteractionEnabled = false
		}
		return value
	}

	#if os(macOS)
		private var nativeInputs: DitherRenderInputs {
			let points = theme.meshColorPoints.prefix(DitherConfiguration.supportedPaletteCount)
			return DitherRenderInputs(
				themePositions: points.map { SIMD2<Float>(Float(configuration.safe($0.x, 0 ... 1)), Float(configuration.safe($0.y, 0 ... 1))) },
				themeColors: points.map { SIMD3<Float>(Float(configuration.safe($0.color.red, 0 ... 1)), Float(configuration.safe($0.color.green, 0 ... 1)), Float(configuration.safe($0.color.blue, 0 ... 1))) },
				cursorTrail: [],
				cursorTouch: .zero,
				cursorPresence: 0
			)
		}
	#endif
}
