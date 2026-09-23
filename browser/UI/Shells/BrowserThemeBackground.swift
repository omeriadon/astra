import Noise
import SwiftUI
#if os(macOS)
	import MaterialView
#endif

struct BrowserThemeBackground: View {
	let theme: BrowserTheme
	#if os(macOS)
		private static let blurStyle = NSMaterialView.Effect.MaterialStyle(
			backgroundColor: .clear,
			saturationFactor: 1,
			brightnessFactor: 0,
			blurRadius: 10
		)

		private static let windowEffect = NSMaterialView.Effect(
			active: blurStyle,
			inactive: blurStyle,
			emphasized: blurStyle
		)

		private struct WindowMaterial: NSViewRepresentable {
			func makeNSView(context _: Context) -> NSMaterialView {
				let view = NSMaterialView()
				// Window configuration runs when the view attaches, before later SwiftUI updates.
				view.isContentView = true
				view.state = .active
				view.scale = 1
				view.reduceTransparencyOverride = false
				view.increaseContrastOverride = false
				view.effect = BrowserThemeBackground.windowEffect
				return view
			}

			func updateNSView(_: NSMaterialView, context _: Context) {}
		}
	#endif

	var body: some View {
		ZStack {
			#if os(macOS)
				WindowMaterial()
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			#else
				Color.gray
			#endif

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
