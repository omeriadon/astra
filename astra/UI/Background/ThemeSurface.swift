import SwiftUI

struct ThemeSurface: View {
	let theme: BrowserTheme
	var colors: [Color]?
	var noiseColorAmount: Double?

	var body: some View {
		ZStack {
			MeshGradientSurface(colors: colors ?? MeshGradientSurface.colors(for: theme.meshColorPoints))
				.opacity(theme.meshOpacity)

			StableRandomNoise(
				isMonochrome: theme.shaderNoiseMonochrome,
				opacity: theme.shaderNoiseEnabled ? theme.shaderNoiseAmount : 0,
				colorAmount: noiseColorAmount
			)
		}
	}
}
