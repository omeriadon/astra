//
//  topVariableBlur.swift
//  astra
//
//  Created by Adon Omeri on 6/10/2026.
//

import SwiftUI
#if os(macOS)
	import Haze
#endif

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
				let bottomEnd = max(bottomStart, 1 - min(max((bottom - 38) / height, 0), 1))
				let topOpacityPoint = min(20 / height, topEnd)
				let bottomOpacityPoint = min(bottomStart + 20 / height, bottomEnd)

				LinearGradient(
					stops: [
						.init(color: .clear, location: 0),
						.init(color: .white.opacity(0.3), location: topOpacityPoint),
						.init(color: .white, location: topEnd),
						.init(color: .clear, location: bottomStart),
						.init(color: .white.opacity(0.3), location: bottomOpacityPoint),
						.init(color: .white, location: bottomEnd),
						.init(color: .white, location: 1),
					],
					startPoint: .top,
					endPoint: .bottom
				)
				.frame(width: geometry.size.width, height: geometry.size.height)
			}
		}
	}
}

private struct SidebarScrollContentMarginsModifier: ViewModifier {
	let top: CGFloat

	func body(content: Content) -> some View {
		content
			.ignoresSafeArea(.container, edges: .vertical)
			.contentMargins(.top, top, for: .scrollContent)
	}
}

extension View {
	func sidebarScrollContentMargins(
		top: CGFloat = 33
	) -> some View {
		modifier(SidebarScrollContentMarginsModifier(top: top))
	}

	func sidebarScrollOpacityFade(
		top: CGFloat = 38,
		bottom: CGFloat = 38
	) -> some View {
		scrollEdgeEffectHidden(true, for: .vertical)
			.sidebarScrollAlphaMask(top: top, bottom: bottom)
			.overlay(alignment: .bottom) {
				#if os(macOS)
					GeometryReader { geometry in
						HazeEffect(
							maskProvider: LinearGradientMaskProvider(
								startPoint: .bottom,
								endPoint: .top,
								startOpacity: 1,
								endOpacity: 0,
								isSmooth: true
							),
							maxBlurRadius: 2,
							isolatesBackdrop: true
						)
						.frame(width: geometry.size.width, height: bottom)
						.frame(maxHeight: .infinity, alignment: .bottom)
					}
					.allowsHitTesting(false)
					.accessibilityHidden(true)
				#endif
			}
			.compositingGroup()
			.clipShape(Rectangle())
	}
}
