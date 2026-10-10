import SwiftUI

struct ThemeSurface: View {
	let theme: BrowserTheme
	var colors: [Color]?
	var noiseColorAmount: Double?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack {
			Group {
				if let colors {
					MeshGradientSurface(colors: colors)
				} else {
					MeshGradientSurface(points: theme.meshColorPoints)
				}
			}
			.opacity(theme.meshOpacity)

			// Disabled noise previously still instantiated the texture-backed
			// Noise view at zero opacity for every background and theme layer.
			// Don't allocate or update GPU noise resources until actually needed.
			if theme.shaderNoiseEnabled, theme.shaderNoiseAmount > 0 {
				StableRandomNoise(
					isMonochrome: theme.shaderNoiseMonochrome,
					opacity: theme.shaderNoiseAmount,
					colorAmount: noiseColorAmount
				)
				.transition(.opacity)
				.animation(
					reduceMotion ? nil : .smooth(duration: 0.2),
					value: theme.shaderNoiseAmount
				)
			}
		}
		.animation(
			reduceMotion ? nil : .smooth(duration: 0.2),
			value: theme.shaderNoiseEnabled && theme.shaderNoiseAmount > 0
		)
	}
}
