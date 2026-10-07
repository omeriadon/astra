//
//  topVariableBlur.swift
//  astra
//
//  Created by Adon Omeri on 6/10/2026.
//

import SwiftUI
#if os(macOS)
	import Haze

	extension View {
		func sidebarBackdropEdgeBlur(height: CGFloat = 28, radius: CGFloat = 8) -> some View {
			scrollEdgeEffectHidden(true, for: .vertical)
				.overlay(alignment: .top) {
					HazeEffect(
						maskProvider: LinearGradientMaskProvider(
							startPoint: .top,
							endPoint: .bottom,
							startOpacity: 1,
							endOpacity: 0
						),
						maxBlurRadius: radius
					)
					.frame(height: height)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
				}
				.overlay(alignment: .bottom) {
					HazeEffect(
						maskProvider: LinearGradientMaskProvider(
							startPoint: .bottom,
							endPoint: .top,
							startOpacity: 1,
							endOpacity: 0
						),
						maxBlurRadius: radius
					)
					.frame(height: height)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
				}
		}
	}
#endif
