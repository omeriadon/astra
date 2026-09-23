import Foundation
import simd

enum CircularSVPicker {
	private static let sqrt3 = sqrt(3.0)
	private static let whiteVertex = SIMD2<Double>(-sqrt3 / 2, 0.5)
	private static let hueVertex = SIMD2<Double>(sqrt3 / 2, 0.5)
	private static let blackVertex = SIMD2<Double>(0, -1)

	static func circleToTriangle(_ point: SIMD2<Double>) -> SIMD2<Double> {
		let radius = simd_length(point)
		guard radius > 0 else { return .zero }
		let direction = point / radius
		let boundary = triangleRadius(in: direction)
		return point * boundary
	}

	static func saturationValue(for point: SIMD2<Double>) -> (saturation: Double, value: Double) {
		let triangle = circleToTriangle(point)
		let hue = (1 + triangle.y) / 3 + triangle.x / sqrt3
		let black = (1 - 2 * triangle.y) / 3
		let value = min(max(1 - black, 0), 1)
		let saturation = value > 0 ? hue / value : 0
		return (min(max(saturation, 0), 1), value)
	}

	static func circlePosition(saturation: Double, value: Double) -> SIMD2<Double> {
		let hueWeight = saturation * value
		let whiteWeight = value * (1 - saturation)
		let blackWeight = 1 - value
		let triangle = whiteWeight * whiteVertex
			+ hueWeight * hueVertex
			+ blackWeight * blackVertex
		let radius = simd_length(triangle)
		guard radius > 0 else { return .zero }
		let direction = triangle / radius
		return triangle / triangleRadius(in: direction)
	}

	private static func triangleRadius(in direction: SIMD2<Double>) -> Double {
		let m = max(
			direction.y,
			(sqrt3 / 2) * direction.x - 0.5 * direction.y,
			-(sqrt3 / 2) * direction.x - 0.5 * direction.y
		)
		return 0.5 / m
	}
}
