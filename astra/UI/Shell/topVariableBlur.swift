//
//  topVariableBlur.swift
//  astra
//
//  Created by Adon Omeri on 6/10/2026.
//

import SwiftUI

private extension View {
	func sidebarScrollAlphaMask(
		top: CGFloat,
		bottom: CGFloat
	) -> some View {
		mask {
			GeometryReader { geometry in
				let height = max(geometry.size.height, 1)
				let topEnd = min(max(top / height, 0), 1)
				let bottomStart = max(topEnd, 1 - min(max(bottom / height, 0), 1))

				LinearGradient(
					stops: [
						.init(color: .clear, location: 0),
						.init(color: .white, location: topEnd),
						.init(color: .white, location: bottomStart),
						.init(color: .clear, location: 1),
					],
					startPoint: .top,
					endPoint: .bottom
				)
				.frame(width: geometry.size.width, height: geometry.size.height)
				.ignoresSafeArea()
			}
		}
	}
}

#if os(macOS)
	import Haze

	extension View {
		/// Fades the rendered scroll content itself and applies a subtle variable
		/// backdrop blur over the exact same top and bottom edge regions.
		func sidebarScrollOpacityFade(
			top: CGFloat = 38,
			bottom: CGFloat = 38,
			blurRadius: CGFloat = 4
		) -> some View {
			scrollEdgeEffectHidden(true, for: .vertical)
				.sidebarScrollAlphaMask(top: top, bottom: bottom)
				.overlay(alignment: .top) {
					HazeEffect(
						maskProvider: LinearGradientMaskProvider(
							startPoint: .top,
							endPoint: .bottom,
							startOpacity: 1,
							endOpacity: 0,
							isSmooth: true
						),
						maxBlurRadius: blurRadius,
						isolatesBackdrop: true
					)
					.frame(height: top)
					.ignoresSafeArea()
					.allowsHitTesting(false)
					.accessibilityHidden(true)
				}
				.overlay(alignment: .bottom) {
					HazeEffect(
						maskProvider: LinearGradientMaskProvider(
							startPoint: .bottom,
							endPoint: .top,
							startOpacity: 1,
							endOpacity: 0,
							isSmooth: true
						),
						maxBlurRadius: blurRadius,
						isolatesBackdrop: true
					)
					.frame(height: bottom)
					.ignoresSafeArea()
					.allowsHitTesting(false)
					.accessibilityHidden(true)
				}
		}
	}
#else
	extension View {
		func sidebarScrollOpacityFade(
			top: CGFloat = 38,
			bottom: CGFloat = 38,
			blurRadius _: CGFloat = 4
		) -> some View {
			sidebarScrollAlphaMask(top: top, bottom: bottom)
		}
	}
#endif
