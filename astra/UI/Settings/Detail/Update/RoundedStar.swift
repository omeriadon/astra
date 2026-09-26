import SwiftUI

struct RoundedStar: Shape {
	var cornerRadius: CGFloat
	var innerRadius: CGFloat = 0.22

	func path(in rect: CGRect) -> Path {
		let center = CGPoint(x: rect.midX, y: rect.midY)
		let rx = rect.width / 2
		let ry = rect.height / 2

		// 4 tips + 4 inner corners
		let points: [CGPoint] = (0 ..< 8).map { index in
			let angle = Angle.degrees(-90 + Double(index) * 45).radians
			let radius = index.isMultiple(of: 2) ? 1.0 : innerRadius

			return CGPoint(
				x: center.x + cos(angle) * rx * radius,
				y: center.y + sin(angle) * ry * radius
			)
		}

		var path = Path()

		for i in points.indices {
			let previous = points[(i - 1 + points.count) % points.count]
			let current = points[i]
			let next = points[(i + 1) % points.count]

			let before = point(
				from: current,
				toward: previous,
				distance: cornerRadius
			)

			let after = point(
				from: current,
				toward: next,
				distance: cornerRadius
			)

			if i == 0 {
				path.move(to: before)
			} else {
				path.addLine(to: before)
			}

			path.addQuadCurve(
				to: after,
				control: current
			)
		}

		path.closeSubpath()

		return path
	}

	private func point(
		from start: CGPoint,
		toward end: CGPoint,
		distance: CGFloat
	) -> CGPoint {
		let dx = end.x - start.x
		let dy = end.y - start.y
		let length = sqrt(dx * dx + dy * dy)

		guard length > 0 else {
			return start
		}

		let d = min(distance, length / 2)

		return CGPoint(
			x: start.x + dx / length * d,
			y: start.y + dy / length * d
		)
	}
}
