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

			if theme.shaderNoiseEnabled {
				Group {
					if theme.shaderNoiseMonochrome {
						Noise(style: .random)
							.monochrome()
					} else {
						Noise(style: .random)
					}
				}
				.blur(radius: theme.shaderNoiseBlur)
				.opacity(min(theme.shaderNoiseAmount, theme.shaderNoiseMonochrome ? 0.25 : 0.5))
				.accessibilityHidden(true)
			}
		}
	}
}
