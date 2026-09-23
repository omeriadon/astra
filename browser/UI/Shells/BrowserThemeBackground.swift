import Noise
import SwiftUI

struct BrowserThemeBackground: View {
	let theme: BrowserTheme

	var body: some View {
		ZStack {
			MeshGradientSurface(points: theme.meshColorPoints)
				.opacity(theme.meshOpacity)

			if theme.shaderNoiseEnabled {
				StableRandomNoise(
					isMonochrome: theme.shaderNoiseMonochrome,
					opacity: theme.shaderNoiseAmount
				)
			}
		}
	}
}

private struct StableRandomNoise: View {
	let isMonochrome: Bool
	let opacity: Double

	@State private var textureSize = CGSize.zero

	var body: some View {
		GeometryReader { geometry in
			Group {
				if isMonochrome {
					Noise(style: .random)
						.monochrome()
				} else {
					Noise(style: .random)
				}
			}
			.frame(
				width: max(textureSize.width, geometry.size.width),
				height: max(textureSize.height, geometry.size.height),
				alignment: .topLeading
			)
			.blur(radius: 10)
			.opacity(opacity)
			.accessibilityHidden(true)
			.onAppear {
				ensureTextureCovers(geometry.size)
			}
			.onChange(of: geometry.size) { _, size in
				ensureTextureCovers(size)
			}
		}
		.clipped()
	}

	private func ensureTextureCovers(_ size: CGSize) {
		guard size.width > textureSize.width || size.height > textureSize.height else { return }

		textureSize = CGSize(
			width: max(textureSize.width, size.width * 2.5),
			height: max(textureSize.height, size.height * 2.5)
		)
	}
}
