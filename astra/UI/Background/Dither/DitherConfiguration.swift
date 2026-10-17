import Foundation

/// SwiftUI-facing controls. Dimensions use points, so the grid is independent of Retina scale.
nonisolated struct DitherConfiguration: Codable, Equatable, Sendable {
	/// Width and height of each square, excluding the gap. Reasonable range: 1...24 pt.
	var gridSize = 4.0
	/// Empty space between squares. Reasonable range: 0...12 pt.
	var gridSpacing = 1.0
	/// Square corner radius; capped at half the square size. Reasonable range: 0...12 pt.
	var cornerRadius = 0.0
	/// Noise translation per second. Reasonable range: 0...0.2; negative values reverse motion.
	var waveSpeed = 0.055
	/// Frequency multiplier between noise octaves. Reasonable range: 1...6.
	var waveFrequency = 4.1
	/// Contribution retained by each successive noise octave. Reasonable range: 0...0.8.
	var waveAmplitude = 0.37
	/// Number of noise layers. Reasonable range: 1...5; additional layers cost GPU time.
	var noiseOctaves = 4
	/// Overall wave size; larger values make broader clouds. Reasonable range: 0.25...4.
	var waveScale = 1.0
	/// Number of brightness levels; fractional values are supported. Reasonable range: 2...16.
	var colorLevels = 5.4
	/// Ordered threshold strength; zero produces plain quantized bands. Reasonable range: 0...1.
	var ditherStrength = 1.0
	/// Wave light/dark contrast around the midpoint. Reasonable range: 0.25...3.
	var contrast = 1.45
	/// Offset applied before quantization. Reasonable range: -0.5...0.5.
	var brightness = 0.06
	/// Minimum theme colour visible in dark wave regions. Reasonable range: 0...0.5.
	var minimumIntensity = 0.14
	/// Amount of the current mesh colour mixed into the waves. Reasonable range: 0...1.
	var themeColorAmount = 1.0
	/// Overall effect opacity, including squares and gaps. Reasonable range: 0...1.
	var opacity = 1.0
	/// Whether the clock and cursor simulation run. false freezes a static, cursor-free frame.
	var animationEnabled = true
	/// Whether cursor input affects the noise field. true or false.
	var cursorInteractionEnabled = true
	/// Cursor influence radius as a fraction of view height. Reasonable range: 0.05...1.5.
	var cursorRadius = 0.6
	/// Cursor field strength; positive erases, negative reveals. Reasonable range: -2...2.
	var cursorStrength = 1.0
	/// Time for the critically damped cursor to settle; larger values feel heavier. Range: 0.05...1 s.
	var cursorResponse = 0.28
	/// Length in seconds of the delayed cursor wake. Reasonable range: 0...1 s.
	var cursorTrailDuration = 0.45
	/// Time constant for cursor presence to fade after leaving. Reasonable range: 0.1...2 s.
	var cursorFadeDuration = 0.5
	/// Radial displacement of the wave field around the cursor. Reasonable range: 0...0.3.
	var cursorWarp = 0.07
	/// Maximum animation refresh rate. Reasonable range: 15...120 fps; default 30 saves GPU work.
	var framesPerSecond = 45.0

	/// Public mutable controls are sanitized at the rendering boundary, including nonfinite values.
	func safe(_ value: Double, _ range: ClosedRange<Double>, fallback: Double = 0) -> Double {
		min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
	}

	static func decode(_ data: Data) -> Self {
		(try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
	}

	var encoded: Data {
		(try? JSONEncoder().encode(self)) ?? Data()
	}
}
