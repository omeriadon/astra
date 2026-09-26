//
//  UpdateTopShape.swift
//  astra
//
//  Created by Adon Omeri on 26/9/2026.
//

import SwiftUI

struct UpdateTopShape: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width
		let h = rect.height

		var path = Path()

		path.move(to: CGPoint(x: 0, y: 0))
		path.addLine(to: CGPoint(x: w, y: 0))
		path.addLine(to: CGPoint(x: w, y: h * 0.72))

		path.addCurve(
			to: CGPoint(x: 0, y: h * 0.56),
			control1: CGPoint(x: w * 0.73, y: h * 0.98),
			control2: CGPoint(x: w * 0.28, y: h * 0.88)
		)

		path.closeSubpath()
		return path
	}
}
