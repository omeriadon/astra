//
//  PurpleHeaderShape.swift
//  astra
//
//  Created by Adon Omeri on 26/9/2026.
//

import SwiftUI

struct PurpleHeaderShape: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width
		let h = rect.height

		var path = Path()

		path.move(to: .zero)
		path.addLine(to: CGPoint(x: w, y: 0))

		// Right end of the purple region.
		path.addLine(
			to: CGPoint(
				x: w,
				y: h * 0.48
			)
		)

		// Long sweeping lower edge, matching the icon.
		path.addCurve(
			to: CGPoint(
				x: 0,
				y: h * 0.14
			),
			control1: CGPoint(
				x: w * 0.70,
				y: h * 0.43
			),
			control2: CGPoint(
				x: w * 0.28,
				y: h * 0.27
			)
		)

		path.closeSubpath()

		return path
	}
}
