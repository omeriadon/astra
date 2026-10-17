import SwiftUI

/// Native Metal fill, with no WebView, per-square SwiftUI views, texture readback, or event timer.
/// Example: DitherBackground(theme: browser.theme, configuration: .init(gridSize: 4, gridSpacing: 1))
struct DitherBackground: View {
	/// Current space theme; positions, colours, and mesh opacity update with the space.
	let theme: BrowserTheme
	/// All visual and motion controls, documented on DitherConfiguration.
	var configuration = DitherConfiguration()
	/// Optional input shared with an ancestor to track hover over foreground controls.
	var pointer: DitherPointerInput?
	/// Owning new-tab window visibility; defaults to true for standalone previews.
	var canAnimate = true

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.colorScheme) private var colorScheme
	@State private var visible = false
	@State private var motion = DitherMotion()
	@State private var clock = DitherClock()

	private var running: Bool {
		#if os(macOS)
			return visible && canAnimate && !reduceMotion && configuration.animationEnabled
		#else
			return visible && canAnimate && scenePhase == .active && !reduceMotion && configuration.animationEnabled
		#endif
	}

	var body: some View {
		let settings = configuration
		GeometryReader { geometry in
			TimelineView(.animation(
				minimumInterval: 1 / settings.safe(settings.framesPerSecond, 15 ... 120, fallback: 30),
				paused: !running
			)) { context in
				let now = context.date.timeIntervalSinceReferenceDate
				Rectangle()
					.fill(shader(size: geometry.size, time: clock.value(at: now), now: now))
					.opacity(settings.safe(settings.opacity, 0 ... 1))
			}
			.onContinuousHover { phase in
				guard pointer == nil else { return }
				switch phase {
					case let .active(location): track(location)
					case .ended: track(nil)
				}
			}
			.onChange(of: running && configuration.cursorInteractionEnabled ? pointer?.location : nil) { _, location in
				track(location)
			}
		}
		.accessibilityHidden(true)
		.onAppear {
			visible = true
			clock.setRunning(running, at: Date().timeIntervalSinceReferenceDate)
		}
		.onDisappear {
			visible = false
			clock.setRunning(false, at: Date().timeIntervalSinceReferenceDate)
			motion = DitherMotion()
		}
		.onChange(of: running) { _, running in
			clock.setRunning(running, at: Date().timeIntervalSinceReferenceDate)
			if !running {
				motion = DitherMotion()
			}
		}
		.onChange(of: configuration.cursorInteractionEnabled) { _, enabled in
			if !enabled {
				motion = DitherMotion()
			}
		}
	}

	private func track(_ location: CGPoint?) {
		guard running, configuration.cursorInteractionEnabled else { return }
		motion.move(to: location, at: Date().timeIntervalSinceReferenceDate,
		            response: configuration.safe(configuration.cursorResponse, 0.05 ... 1, fallback: 0.28),
		            fade: configuration.safe(configuration.cursorFadeDuration, 0.1 ... 2, fallback: 0.5))
	}

	private func shader(size: CGSize, time: Double, now: Double) -> Shader {
		let c = configuration
		// The theme uses at most four points. Keep positions and colours paired and bounded.
		let points = Array(theme.meshColorPoints.prefix(4))
		let positions = points.flatMap { point in
			[Float(c.safe(point.x, 0 ... 1)), Float(c.safe(point.y, 0 ... 1))]
		}
		let colors = points.map { point in
			Color(.sRGB, red: c.safe(point.color.red, 0 ... 1), green: c.safe(point.color.green, 0 ... 1),
			      blue: c.safe(point.color.blue, 0 ... 1))
		}
		let gridSize = c.safe(c.gridSize, 1 ... 24, fallback: 3)
		let trail = running && c.cursorInteractionEnabled
			? motion.trail(at: now,
			               duration: c.safe(c.cursorTrailDuration, 0 ... 1, fallback: 0.45),
			               fade: c.safe(c.cursorFadeDuration, 0.1 ... 2, fallback: 0.5)) : []
		let dark = theme.appearanceMode == .dark || (theme.appearanceMode == .auto && colorScheme == .dark)
		return ShaderLibrary.astraThemeDither(
			.float2(size.width, size.height), .float(time),
			.float4(gridSize, c.safe(c.gridSpacing, 0 ... 12), c.safe(c.cornerRadius, 0 ... (gridSize / 2)), 0),
			.float4(c.safe(c.waveSpeed, -0.2 ... 0.2), c.safe(c.waveFrequency, 1 ... 6),
			        c.safe(c.waveAmplitude, 0 ... 0.8), c.safe(c.waveScale, 0.25 ... 4, fallback: 1)),
			.float4(c.safe(c.colorLevels, 2 ... 16, fallback: 5.4), c.safe(c.ditherStrength, 0 ... 1),
			        c.safe(c.contrast, 0.25 ... 3, fallback: 1), c.safe(c.brightness, -0.5 ... 0.5)),
			.float4(c.safe(c.minimumIntensity, 0 ... 0.5), c.safe(c.themeColorAmount, 0 ... 1),
			        c.safe(theme.meshOpacity, 0 ... 1), Double(min(max(c.noiseOctaves, 1), 5))),
			.float4(c.safe(c.cursorRadius, 0.05 ... 1.5, fallback: 0.6), c.safe(c.cursorStrength, -2 ... 2),
			        c.safe(c.cursorWarp, 0 ... 0.3), 0),
			.color(dark ? .black : .white),
			.floatArray(positions), .colorArray(colors), .floatArray(trail)
		)
	}
}

#Preview("Theme Dither") {
	@Previewable @State var configuration = DitherConfiguration()
	let theme: BrowserTheme = {
		var theme = BrowserTheme()
		theme.meshColorPoints = [
			ThemeColorPoint(color: BrowserColor(red: 0.3, green: 0.2, blue: 0.9), x: 0.2, y: 0.2),
			ThemeColorPoint(color: BrowserColor(red: 0.1, green: 0.8, blue: 0.7), x: 0.8, y: 0.8),
		]
		return theme
	}()
	HStack(spacing: 0) {
		DitherBackground(theme: theme, configuration: configuration)
		DitherControls(configuration: $configuration).frame(width: 320)
	}
	.frame(width: 1000, height: 650)
}
