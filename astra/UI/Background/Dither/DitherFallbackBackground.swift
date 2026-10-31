#if !os(macOS)
	import Foundation

	/// Locked new-tab preset. Dimensions use points, so the grid is independent of Retina scale.
	nonisolated struct DitherFallbackConfiguration: Equatable, Sendable {
		/// Width and height of each square, excluding the gap. Reasonable range: 1...24 pt.
		let gridSize = 7.0
		/// Empty space between squares. Reasonable range: 0...12 pt.
		let gridSpacing = 0.77
		/// Square corner radius; capped at half the square size. Reasonable range: 0...12 pt.
		let cornerRadius = 1.8
		/// Noise translation per second. Reasonable range: 0...0.2; negative values reverse motion.
		let waveSpeed = 0.03
		/// Frequency multiplier between noise octaves. Reasonable range: 1...6.
		let waveFrequency = 2.7
		/// Contribution retained by each successive noise octave. Reasonable range: 0...0.8.
		let waveAmplitude = 0.37
		/// Number of noise layers. Reasonable range: 1...5; additional layers cost GPU time.
		let noiseOctaves = 5
		/// Overall wave size; larger values make broader clouds. Reasonable range: 0.25...4.
		let waveScale = 0.3
		/// Number of brightness levels; fractional values are supported. Reasonable range: 2...16.
		let colorLevels = 3.7
		/// Ordered threshold strength; zero produces plain quantized bands. Reasonable range: 0...1.
		let ditherStrength = 0.21
		/// Wave light/dark contrast around the midpoint. Reasonable range: 0.25...3.
		let contrast = 1.88
		/// Offset applied before quantization. Reasonable range: -0.5...0.5.
		let brightness = -0.5
		/// Minimum theme colour visible in dark wave regions. Reasonable range: 0...0.5.
		let minimumIntensity = 0.0
		/// Amount of the current mesh colour mixed into the waves. Reasonable range: 0...1.
		let themeColorAmount = 1.0
		/// Overall effect opacity, including squares and gaps. Reasonable range: 0...1.
		let opacity = 1.0
		/// Whether the clock and cursor simulation run. false freezes a static, cursor-free frame.
		let animationEnabled = true
		/// Whether cursor input affects the noise field. true or false.
		let cursorInteractionEnabled = true
		/// Cursor influence radius as a fraction of view height. Reasonable range: 0.05...1.5.
		let cursorRadius = 0.5
		/// Cursor field strength; positive erases, negative reveals. Reasonable range: -2...2.
		let cursorStrength = 1.0
		/// Time for the critically damped cursor to settle; larger values feel heavier. Range: 0.05...1 s.
		let cursorResponse = 0.28
		/// Length in seconds of the delayed cursor wake. Reasonable range: 0...1 s.
		let cursorTrailDuration = 0.7
		/// Time constant for cursor presence to fade after leaving. Reasonable range: 0.1...2 s.
		let cursorFadeDuration = 0.8
		/// Radial displacement of the wave field around the cursor. Reasonable range: 0...0.3.
		let cursorWarp = 0.15
		/// Maximum animation refresh rate. Reasonable range: 15...120 fps; default 30 saves GPU work.
		let framesPerSecond = 30.0

		/// Theme-derived values are sanitized at the rendering boundary, including nonfinite values.
		func safe(_ value: Double, _ range: ClosedRange<Double>, fallback: Double = 0) -> Double {
			min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
		}
	}

	import SwiftUI

	/// Native Metal fill, with no WebView, per-square SwiftUI views, texture readback, or event timer.
	struct DitherFallbackBackground: View {
		/// Current Space theme; positions and colours update with the Space.
		let theme: BrowserTheme
		/// Immutable visual and motion preset.
		private let configuration = DitherFallbackConfiguration()
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
				visible && canAnimate && !reduceMotion && configuration.animationEnabled
			#else
				visible && canAnimate && scenePhase == .active && !reduceMotion && configuration.animationEnabled
			#endif
		}

		var body: some View {
			let settings = configuration
			let palette = positionedPalette
			GeometryReader { geometry in
				TimelineView(.animation(
					minimumInterval: 1 / settings.safe(settings.framesPerSecond, 15 ... 120, fallback: 30),
					paused: !running
				)) { context in
					let now = context.date.timeIntervalSinceReferenceDate
					Rectangle()
						.fill(shader(size: geometry.size, time: clock.value(at: now), now: now, palette: palette))
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

		private var positionedPalette: ([Float], [Color]) {
			// The theme uses at most four points. Keep positions and colours paired and bounded.
			let points = Array(theme.meshColorPoints.prefix(4))
			let positions = points.flatMap { point in
				[Float(configuration.safe(point.x, 0 ... 1)), Float(configuration.safe(point.y, 0 ... 1))]
			}
			let colors = points.map { point in
				Color(.sRGB, red: configuration.safe(point.color.red, 0 ... 1), green: configuration.safe(point.color.green, 0 ... 1),
				      blue: configuration.safe(point.color.blue, 0 ... 1))
			}
			return (positions, colors)
		}

		private func shader(size: CGSize, time: Double, now: Double, palette: ([Float], [Color])) -> Shader {
			let c = configuration
			let (positions, colors) = palette
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
				        1, Double(min(max(c.noiseOctaves, 1), 5))),
				.float4(c.safe(c.cursorRadius, 0.05 ... 1.5, fallback: 0.6), c.safe(c.cursorStrength, -2 ... 2),
				        c.safe(c.cursorWarp, 0 ... 0.3), 0),
				.color(dark ? .black : .white),
				.floatArray(positions), .colorArray(colors), .floatArray(trail)
			)
		}
	}

#endif
