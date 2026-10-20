import Foundation

/// Locked new-tab preset. Dimensions use points, so the grid is independent of Retina scale.
nonisolated struct DitherConfiguration: Equatable, Sendable {
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
