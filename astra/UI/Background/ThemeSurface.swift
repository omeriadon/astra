import SwiftUI

struct ThemeSurface: View {
	let theme: BrowserTheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack {
			MeshGradientSurface(points: theme.meshColorPoints)
				.opacity(theme.meshOpacity)
				.animation(reduceMotion ? nil : .smooth(duration: 0.2), value: theme.meshOpacity)

			// Disabled noise previously still instantiated the texture-backed
			// Noise view at zero opacity for every background and theme layer.
			// Don't allocate or update GPU noise resources until actually needed.
			if theme.shaderNoiseEnabled, theme.shaderNoiseAmount > 0 {
				StableRandomNoise(
					isMonochrome: theme.shaderNoiseMonochrome,
					opacity: theme.shaderNoiseAmount
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
