import Noise
import SwiftUI

struct BrowserThemeBackground: View {
	let theme: BrowserTheme

	var body: some View {
		ZStack {
			Group {
				if theme.usesGradient {
					LinearGradient(
						colors: [theme.firstColor.color, theme.secondColor.color],
						startPoint: theme.gradientDirection.startPoint,
						endPoint: theme.gradientDirection.endPoint
					)
				} else {
					theme.firstColor.color
				}
			}
			.modifier(
				RandomNoiseEffect(
					isEnabled: theme.shaderNoiseEnabled,
					intensity: theme.shaderNoiseAmount,
					style: theme.shaderNoiseStyle
				)
			)

			if theme.noiseEnabled {
				Noise(style: .noisy)
					.monochrome()
					.blendMode(.overlay)
					.opacity(theme.noiseAmount)
					.accessibilityHidden(true)
			}
		}
	}
}
