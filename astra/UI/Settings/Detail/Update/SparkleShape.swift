//
//  SparkleShape.swift
//  astra
//
//  Created by Adon Omeri on 26/9/2026.
//

import SwiftUI

struct SparkleShape: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width
		let h = rect.height
		let cx = w / 2
		let cy = h / 2

		let innerX = w * 0.32
		let innerY = h * 0.32

		var path = Path()

		path.move(to: CGPoint(x: cx, y: 0))

		path.addQuadCurve(
			to: CGPoint(x: w - innerX, y: innerY),
			control: CGPoint(x: w * 0.56, y: h * 0.12)
		)
		path.addQuadCurve(
			to: CGPoint(x: w, y: cy),
			control: CGPoint(x: w * 0.96, y: h * 0.44)
		)
		path.addQuadCurve(
			to: CGPoint(x: w - innerX, y: h - innerY),
			control: CGPoint(x: w * 0.96, y: h * 0.56)
		)
		path.addQuadCurve(
			to: CGPoint(x: cx, y: h),
			control: CGPoint(x: w * 0.56, y: h * 0.88)
		)
		path.addQuadCurve(
			to: CGPoint(x: innerX, y: h - innerY),
			control: CGPoint(x: w * 0.44, y: h * 0.88)
		)
		path.addQuadCurve(
			to: CGPoint(x: 0, y: cy),
			control: CGPoint(x: w * 0.04, y: h * 0.56)
		)
		path.addQuadCurve(
			to: CGPoint(x: innerX, y: innerY),
			control: CGPoint(x: w * 0.04, y: h * 0.44)
		)
		path.addQuadCurve(
			to: CGPoint(x: cx, y: 0),
			control: CGPoint(x: w * 0.44, y: h * 0.12)
		)

		return path
	}
}
