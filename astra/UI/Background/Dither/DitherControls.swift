import SwiftUI

/// Optional live editor. The rendering view also accepts DitherConfiguration directly from SwiftUI.
struct DitherControls: View {
	@Binding var configuration: DitherConfiguration

	var body: some View {
		Form {
			Section("Grid") {
				control("Square size", \.gridSize, 1 ... 24)
				control("Square spacing", \.gridSpacing, 0 ... 12)
				control("Corner radius", \.cornerRadius, 0 ... 12)
			}
			Section("Waves") {
				Toggle("Animate", isOn: $configuration.animationEnabled)
				control("Speed", \.waveSpeed, -0.2 ... 0.2)
				control("Frequency", \.waveFrequency, 1 ... 6)
				control("Amplitude", \.waveAmplitude, 0 ... 0.8)
				control("Wave scale", \.waveScale, 0.25 ... 4)
				Stepper("Noise layers: \(configuration.noiseOctaves)", value: $configuration.noiseOctaves, in: 1 ... 5)
				control("Frame rate", \.framesPerSecond, 15 ... 120)
			}
			Section("Colour") {
				control("Colour levels", \.colorLevels, 2 ... 16)
				control("Dither strength", \.ditherStrength, 0 ... 1)
				control("Contrast", \.contrast, 0.25 ... 3)
				control("Brightness", \.brightness, -0.5 ... 0.5)
				control("Minimum intensity", \.minimumIntensity, 0 ... 0.5)
				control("Theme colour", \.themeColorAmount, 0 ... 1)
				control("Opacity", \.opacity, 0 ... 1)
			}
			Section("Cursor") {
				Toggle("Cursor interaction", isOn: $configuration.cursorInteractionEnabled)
				control("Radius", \.cursorRadius, 0.05 ... 1.5)
				control("Strength (negative reveals)", \.cursorStrength, -2 ... 2)
				control("Response time", \.cursorResponse, 0.05 ... 1)
				control("Trail duration", \.cursorTrailDuration, 0 ... 1)
				control("Fade time", \.cursorFadeDuration, 0.1 ... 2)
				control("Swirl", \.cursorWarp, 0 ... 0.3)
			}
			Button("Reset Dither") { configuration = DitherConfiguration() }
		}
		.formStyle(.grouped)
	}

	private func control(_ title: String, _ key: WritableKeyPath<DitherConfiguration, Double>, _ range: ClosedRange<Double>) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(title)
				Spacer()
				Text(configuration[keyPath: key], format: .number.precision(.fractionLength(2)))
					.monospacedDigit().foregroundStyle(.secondary)
			}
			Slider(value: $configuration[dynamicMember: key], in: range)
				.accessibilityLabel(title)
		}
	}
}
