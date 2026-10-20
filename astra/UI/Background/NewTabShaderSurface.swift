import SwiftUI

/// Native Metal presets for the new-tab picker. Presets use the current
/// Space's positioned mesh.
enum NewTabShaderPreset: String {
	case ripple
	case datamosh
	case topographic

	var textureIndex: Float {
		switch self {
			case .topographic: 0
			case .ripple: 1
			case .datamosh: 2
		}
	}
}

/// Uses only the built-in procedural Space artwork. Only the selected new-tab effect mounts a timeline. The clock
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
		let primary = theme.firstColor
		return Color(.sRGB,
		             red: isDark ? primary.red * 0.25 : 0.72 + primary.red * 0.28,
		             green: isDark ? primary.green * 0.25 : 0.72 + primary.green * 0.28,
		             blue: isDark ? primary.blue * 0.25 : 0.72 + primary.blue * 0.28,
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
			// Keep the static artwork and palette outside the animation updates.
			let palette = positionedPalette
			let artwork = Rectangle().fill(textureShader(size: geometry.size, palette: palette))
			TimelineView(.animation(minimumInterval: 1.0 / (preset == .topographic ? 60.0 : 30.0), paused: !running)) { context in
				// Sample the timeline date so shader uniforms change on every scheduled frame.
				let time = Float(clock.value(at: context.date.timeIntervalSinceReferenceDate))
				ZStack {
					baseColor
					artwork
						.layerEffect(effectShader(size: geometry.size, time: time),
						             maxSampleOffset: sampleOffset(size: geometry.size))
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

	private func sampleOffset(size: CGSize) -> CGSize {
		switch preset {
			case .topographic: return .zero
			case .datamosh: return CGSize(width: 96, height: 96)
			case .ripple:
				// The ripple corrects X displacement by aspect ratio; bound tall windows too.
				let aspect = max(size.width / max(size.height, 1), 0.001)
				return CGSize(width: min(size.width, 33 / aspect), height: min(size.height, 33))
		}
	}

	private func textureShader(size: CGSize, palette: ([Float], [Color])) -> Shader {
		let (locations, colors) = palette
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
			case .ripple:
				ShaderLibrary.astraLiveRipple(
					.float2(size), .float(time),
					.float(33), .float(50), .float(2.3), .float(2.4), .float(3)
				)
			case .topographic:
				ShaderLibrary.astraTopographic(
					.float2(size), .float(time), .float(17), .float(0.06), .float(0), .float(0.13)
				)
			case .datamosh:
				ShaderLibrary.astraDatamosh(
					.float2(size), .float(time), .float(0.015), .float(60), .float(0.95), .float(0.7)
				)
		}
	}
}
