import SwiftUI

struct ThemeSurface: View {
	let theme: BrowserTheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack {
			MeshGradientSurface(points: theme.meshColorPoints)
				.opacity(theme.meshOpacity)
				.animation(reduceMotion ? nil : .smooth(duration: 0.2), value: theme.meshOpacity)

			StableRandomNoise(
				isMonochrome: theme.shaderNoiseMonochrome,
				opacity: theme.shaderNoiseEnabled ? theme.shaderNoiseAmount : 0
			)
			.animation(
				reduceMotion ? nil : .smooth(duration: 0.2),
				value: theme.shaderNoiseEnabled ? theme.shaderNoiseAmount : 0
			)
		}
	}
}
