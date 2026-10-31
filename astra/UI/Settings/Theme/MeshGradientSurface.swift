import SwiftUI

struct MeshGradientSurface: View {
	private let colors: [Color]
	private nonisolated static let meshLocations: [SIMD2<Float>] = (0 ..< 100).map { index in
		SIMD2<Float>(Float(index % 10) / 9, Float(index / 10) / 9)
	}

	init(points: [ThemeColorPoint]) {
		colors = Self.colors(for: points)
	}

	init(colors: [Color]) {
		self.colors = colors
	}

	var body: some View {
		MeshGradient(
			width: 10,
			height: 10,
			points: Self.meshLocations,
			colors: colors,
			background: .clear,
			smoothsColors: true
		)
	}

	nonisolated static func colors(for points: [ThemeColorPoint]) -> [Color] {
		guard !points.isEmpty else { return Array(repeating: .clear, count: meshLocations.count) }
		return meshLocations.map { location in
			let weightedColors = points.map { point -> (Double, BrowserColor) in
				let deltaX = Double(location.x) - point.x
				let deltaY = Double(location.y) - point.y
				let weight = 1 / (deltaX * deltaX + deltaY * deltaY + 0.015)
				return (weight, point.color)
			}
			let totalWeight = weightedColors.reduce(0) { $0 + $1.0 }
			let red = weightedColors.reduce(0) { $0 + $1.0 * $1.1.red } / totalWeight
			let green = weightedColors.reduce(0) { $0 + $1.0 * $1.1.green } / totalWeight
			let blue = weightedColors.reduce(0) { $0 + $1.0 * $1.1.blue } / totalWeight
			return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
		}
	}
}
