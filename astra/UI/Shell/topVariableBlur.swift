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

/// Fade geometry depends only on the viewport and the four edge dimensions.
/// Keep it equatable so unrelated tab-selection and download updates don't
/// re-evaluate the mask's six gradient stops.
private struct SidebarScrollAlphaGradient: View, Equatable {
	let top: CGFloat
	let topOpacityHeight: CGFloat?
	let bottom: CGFloat
	let bottomOpacityHeight: CGFloat

	var body: some View {
		GeometryReader { geometry in
			let height = max(geometry.size.height, 1)
			let topEnd = min(max(top / height, 0), 1)
			let bottomStart = max(topEnd, 1 - min(max(bottom / height, 0), 1))
			let topOpacityPoint = min(max((topOpacityHeight ?? 20) / height, 0), topEnd)
			let bottomOpacityPoint = max(
				bottomStart,
				1 - min(max(bottomOpacityHeight / height, 0), 1)
			)
			LinearGradient(
				stops: [
					.init(color: topOpacityHeight == nil ? .clear : .white.opacity(0.3), location: 0),
					.init(color: .white.opacity(0.3), location: topOpacityPoint),
					.init(color: .white, location: topEnd),
					.init(color: .white, location: bottomStart),
					.init(color: .white.opacity(0.3), location: bottomOpacityPoint),
					.init(color: .white.opacity(0.3), location: 1),
				],
				startPoint: .top,
				endPoint: .bottom
			)
			.frame(width: geometry.size.width, height: geometry.size.height)
		}
	}
}

private extension View {
	func sidebarScrollAlphaMask(
		top: CGFloat,
		topOpacityHeight: CGFloat?,
		bottom: CGFloat,
		bottomOpacityHeight: CGFloat = 34
	) -> some View {
		mask {
			SidebarScrollAlphaGradient(
				top: top,
				topOpacityHeight: topOpacityHeight,
				bottom: bottom,
				bottomOpacityHeight: bottomOpacityHeight
			).equatable()
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
		topOpacityHeight: CGFloat? = nil,
		bottom: CGFloat = 45,
		bottomOpacityHeight: CGFloat = 34
	) -> some View {
		modifier(SidebarScrollOpacityFadeModifier(
			top: top,
			topOpacityHeight: topOpacityHeight,
			bottom: bottom,
			bottomOpacityHeight: bottomOpacityHeight
		))
	}
}

private struct SidebarScrollOpacityFadeModifier: ViewModifier {
	let top: CGFloat
	let topOpacityHeight: CGFloat?
	let bottom: CGFloat
	let bottomOpacityHeight: CGFloat
	@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
	@State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

	func body(content: Content) -> some View {
		let faded = content
			.scrollEdgeEffectHidden(true, for: .vertical)
			.sidebarScrollAlphaMask(
				top: top,
				topOpacityHeight: topOpacityHeight,
				bottom: bottom,
				bottomOpacityHeight: bottomOpacityHeight
			)

		Group {
			#if os(macOS)
				if reduceTransparency {
					faded.clipShape(Rectangle())
				} else if lowPowerMode {
					// Keep edge Haze at the same radius without compositing
					// the entire scrolling sidebar.
					faded
						.modifier(SidebarScrollVariableBlurModifier(top: top, bottom: bottom))
						.clipShape(Rectangle())
				} else {
					faded
						.modifier(SidebarScrollVariableBlurModifier(top: top, bottom: bottom))
						.compositingGroup()
						.clipShape(Rectangle())
				}
			#else
				faded.clipShape(Rectangle())
			#endif
		}
		.environment(\.sidebarScrollIndicatorBottomInset, bottom)
		.onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
			lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
		}
	}
}

/// Mark variable blur only where it is visible. Each GeometryReader here used to
/// recompute layout on sidebar scroll; native overlay frames already fill width.
private struct SidebarScrollVariableBlurModifier: ViewModifier {
	let top: CGFloat
	let bottom: CGFloat

	func body(content: Content) -> some View {
		content
			.overlay(alignment: .bottom) {
				#if os(macOS)
					HazeEffect(
						maskProvider: LinearGradientMaskProvider(
							startPoint: .bottom, endPoint: .top,
							startOpacity: 1, endOpacity: 0, isSmooth: true
						),
						maxBlurRadius: 3, isolatesBackdrop: true
					)
					.frame(height: bottom)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
				#endif
			}
			.overlay(alignment: .top) {
				#if os(macOS)
					HazeEffect(
						maskProvider: LinearGradientMaskProvider(
							startPoint: .top, endPoint: .bottom,
							startOpacity: 1, endOpacity: 0, isSmooth: true
						),
						maxBlurRadius: 2, isolatesBackdrop: true
					)
					.frame(height: top)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
				#endif
			}
	}
}
