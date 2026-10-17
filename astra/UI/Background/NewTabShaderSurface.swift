import SwiftUI

/// Native Metal presets for the new-tab picker. Presets use the current
/// Space's positioned mesh, except for the monochrome prismatic search field.
enum NewTabShaderPreset: String {
	case smoke
	case holographic
	case ripple
	case datamosh

	var textureIndex: Float {
		switch self {
			case .smoke: 0
			case .ripple: 1
			case .datamosh: 2
			case .holographic: 3
		}
	}
}

/// Creates themed artwork procedurally rather than loading an external
/// bitmap. Only the selected new-tab effect mounts a timeline. The clock
/// pauses (rather than jumping) on tab switching, occlusion and Reduce Motion.
struct NewTabShaderSurface: View {
	let theme: BrowserTheme
	let preset: NewTabShaderPreset
	let canAnimate: Bool

	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.scenePhase) private var scenePhase
	@State private var isVisible = false
	@State private var clock = DitherClock()

	private var isDark: Bool {
		theme.appearanceMode == .dark ||
			(theme.appearanceMode == .auto && colorScheme == .dark)
	}

	private var running: Bool {
		#if os(macOS)
			// canAnimate already tracks NSApp activity and the owning window's occlusion.
			return isVisible && canAnimate && !reduceMotion
		#else
			return isVisible && canAnimate && !reduceMotion && scenePhase == .active
		#endif
	}

	private var baseColor: Color {
		if preset == .holographic {
			return .black
		}
		let primary = theme.firstColor
		return Color(.sRGB,
		             red: isDark ? primary.red * 0.25 : 0.72 + primary.red * 0.28,
		             green: isDark ? primary.green * 0.25 : 0.72 + primary.green * 0.28,
		             blue: isDark ? primary.blue * 0.25 : 0.72 + primary.blue * 0.28,
		             opacity: 1)
	}

	private var smokeColor: Color {
		let primary = theme.firstColor
		return Color(.sRGB,
		             red: isDark ? 0.07 + primary.red * 0.52 : 0.66 + primary.red * 0.26,
		             green: isDark ? 0.07 + primary.green * 0.52 : 0.66 + primary.green * 0.26,
		             blue: isDark ? 0.07 + primary.blue * 0.52 : 0.66 + primary.blue * 0.26,
		             opacity: 1)
	}

	private var positionedPalette: ([Float], [Color]) {
		let points = Array(theme.meshColorPoints.prefix(4))
		if points.isEmpty {
			return ([0.5, 0.5], [theme.firstColor.color])
		}
		return (
			points.flatMap { [Float($0.x), Float($0.y)] },
			points.map(\.color.color)
		)
	}

	var body: some View {
		GeometryReader { geometry in
			TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: !running)) { context in
				// Sample the timeline date so shader uniforms change on every scheduled frame.
				let time = Float(clock.value(at: context.date.timeIntervalSinceReferenceDate))
				ZStack {
					baseColor
					Rectangle()
						.fill(textureShader(size: geometry.size))
						.layerEffect(effectShader(size: geometry.size, time: time),
						             maxSampleOffset: preset == .holographic ? .zero : CGSize(width: 64, height: 64))
				}
			}
		}
		.allowsHitTesting(false)
		.accessibilityHidden(true)
		.onAppear {
			isVisible = true
			clock.setRunning(running, at: Date().timeIntervalSinceReferenceDate)
		}
		.onDisappear {
			isVisible = false
			clock.setRunning(false, at: Date().timeIntervalSinceReferenceDate)
		}
		.onChange(of: running) { _, value in
			clock.setRunning(value, at: Date().timeIntervalSinceReferenceDate)
		}
	}

	private func textureShader(size: CGSize) -> Shader {
		let (locations, colors) = positionedPalette
		return ShaderLibrary.astraNewTabTexture(
			.float2(size),
			.float(preset.textureIndex),
			.floatArray(locations),
			.colorArray(colors),
			.color(theme.firstColor.color)
		)
	}

	private func effectShader(size: CGSize, time: Float) -> Shader {
		switch preset {
			case .smoke:
				ShaderLibrary.astraSmokeReveal(
					.float2(size), .float(time),
					.float(0.8), .color(smokeColor)
				)
			case .holographic:
				ShaderLibrary.astraHolographicPrismatic(
					.float2(size), .float(time),
					.float(0.92), .float(5.2), .float(1.0), .float(0.785)
				)
			case .ripple:
				ShaderLibrary.astraLiveRipple(
					.float2(size), .float(time),
					.float(17), .float(34), .float(4.8), .float(1.6), .float(3)
				)
			case .datamosh:
				ShaderLibrary.astraDatamosh(
					.float2(size), .float(time),
					.float(0.48), .float(42), .float(0.65), .float(12)
				)
		}
	}
}
