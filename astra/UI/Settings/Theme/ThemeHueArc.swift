import SwiftUI

struct ThemeHueArc: Shape {
	let start: Double
	let length: Double
	let lineWidth: CGFloat

	func path(in rect: CGRect) -> Path {
		let center = CGPoint(x: rect.midX, y: rect.midY)
		let radius = min(rect.width, rect.height) / 2 - lineWidth / 2
		var path = Path()
		for step in 0 ... 100 {
			let angle = (start + Double(step) / 100 * length) * .pi / 180
			let point = CGPoint(
				x: center.x + cos(angle) * radius,
				y: center.y + sin(angle) * radius
			)
			if step == 0 {
				path.move(to: point)
			} else {
				path.addLine(to: point)
			}
		}
		return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
	}
}
