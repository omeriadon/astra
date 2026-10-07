//
//  topVariableBlur.swift
//  astra
//
//  Created by Adon Omeri on 6/10/2026.
//

import SwiftUI

extension View {
	/// Fades the rendered view itself at the vertical scroll edges.
	///
	/// This is an alpha mask, not a dark overlay: content becomes transparent
	/// toward the top and bottom edges while the sidebar backdrop remains intact.
	func sidebarScrollOpacityFade(
		top: CGFloat = 38,
		bottom: CGFloat = 38
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
