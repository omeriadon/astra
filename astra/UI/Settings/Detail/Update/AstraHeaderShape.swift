//
//  AstraHeaderShape.swift
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

		// Start top-left
		path.move(to: CGPoint(x: 0, y: 0))

		// Top
		path.addLine(to: CGPoint(x: w, y: 0))

		// Right side
		path.addLine(to: CGPoint(x: w, y: h * 0.72))

		// Curved bottom, right -> left
		path.addCurve(
			to: CGPoint(x: 0, y: h * 0.55),
			control1: CGPoint(
				x: w * 0.65,
				y: h * 0.92
			),
			control2: CGPoint(
				x: w * 0.30,
				y: h * 0.82
			)
		)

		path.closeSubpath()

		return path
	}
}
