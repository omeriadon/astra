import SwiftUI

/// Native Metal presets for the new-tab picker. Presets use the current
/// Space's positioned mesh, except for the monochrome prismatic search field.
enum NewTabShaderPreset: String {
	case smoke
	case holographic
	case ripple
	case datamosh
	case topographic

	var textureIndex: Float {
		switch self {
			case .smoke, .topographic: 0
			case .ripple: 1
			case .datamosh: 2
			case .holographic: 3
		}
	}
}

/// Uses procedural Space artwork, or an imported image for Topographic. Only the selected new-tab effect mounts a timeline. The clock
/// pauses (rather than jumping) on tab switching, occlusion and Reduce Motion.
struct NewTabShaderSurface: View {
	let theme: BrowserTheme
	let preset: NewTabShaderPreset
	let canAnimate: Bool
	var settings = NewTabEffectSettings()
	var imageID = ""
	@State private var sourceImage: CGImage?

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
					source(size: geometry.size)
						.layerEffect(effectShader(size: geometry.size, time: time),
						             maxSampleOffset: sampleOffset)
				}
			}
		}
		.allowsHitTesting(false)
		.accessibilityHidden(true)
		.task(id: preset == .topographic ? imageID : "") {
			let id = preset == .topographic ? imageID : ""
			sourceImage = nil
			guard !id.isEmpty else { return }
			let loaded = await Task.detached { NewTabImageStore.load(id) }.value
			guard !Task.isCancelled else { return }
			sourceImage = loaded
		}
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

	@ViewBuilder
	private func source(size: CGSize) -> some View {
		if preset == .topographic, let sourceImage {
			Image(decorative: sourceImage, scale: 1)
				.resizable().scaledToFill()
				.frame(width: size.width, height: size.height).clipped()
		} else {
			Rectangle().fill(textureShader(size: size))
		}
	}

	private var sampleOffset: CGSize {
		switch preset {
		case .holographic, .topographic: .zero
		case .datamosh: CGSize(width: 96, height: 96)
		default: CGSize(width: 64, height: 64)
		}
	}

	private func value(_ key: String) -> Float { Float(settings.value(preset.rawValue, key)) }

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
					.float2(size), .float(time * value("speed")),
					.float(value("amount")), .float(value("scale")), .float(value("turbulence")), .color(smokeColor)
				)
			case .holographic:
				ShaderLibrary.astraHolographicPrismatic(
					.float2(size), .float(time),
					.float(value("intensity")), .float(value("scale")), .float(value("speed")), .float(value("angle"))
				)
			case .ripple:
				ShaderLibrary.astraLiveRipple(
					.float2(size), .float(time),
					.float(value("amplitude")), .float(value("frequency")), .float(value("speed")), .float(value("damping")), .float(value("rings"))
				)
			case .topographic:
				ShaderLibrary.astraTopographic(
					.float2(size), .float(time), .float(value("lineCount")),
					.float(value("lineWidth")), .float(value("colorize")), .float(value("animate"))
				)
			case .datamosh:
				ShaderLibrary.astraDatamosh(
					.float2(size), .float(time),
					.float(value("corruption")), .float(value("smear")), .float(value("bleed")), .float(value("rate"))
				)
		}
	}
}
