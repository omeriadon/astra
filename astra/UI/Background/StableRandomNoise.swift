import Noise
import SwiftUI

struct StableRandomNoise: View {
	let isMonochrome: Bool
	let opacity: Double
	var colorAmount: Double?

	@State private var textureSize = CGSize.zero

	var body: some View {
		GeometryReader { geometry in
			Noise(style: .random)
				.saturation(colorAmount ?? (isMonochrome ? 0 : 1))
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
		guard size.width > 0, size.height > 0 else { return }

		// The previous 2.5x overscan in *both* dimensions could shade 6.25
		// times the visible area per theme layer. Keep a modest resize margin,
		// quantized to avoid regenerating noise for each window-resize pixel.
		let quantum: CGFloat = 128
		let target = CGSize(
			width: ceil(size.width * 1.25 / quantum) * quantum,
			height: ceil(size.height * 1.25 / quantum) * quantum
		)
		let needsGrowth = size.width > textureSize.width || size.height > textureSize.height
		// Reclaim oversized backing layers after moving a large window to
		// a smaller screen; ordinary small resizes still reuse the texture.
		let needsShrink = textureSize.width > max(target.width * 2, 1024)
			|| textureSize.height > max(target.height * 2, 1024)
		guard needsGrowth || needsShrink else { return }

		textureSize = needsShrink
			? target
			: CGSize(
				width: max(textureSize.width, target.width),
				height: max(textureSize.height, target.height)
			)
	}
}
