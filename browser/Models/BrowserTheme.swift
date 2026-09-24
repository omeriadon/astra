import SwiftUI

struct BrowserTheme: Codable, Equatable {
	var usesGradient = false
	var firstColor = BrowserColor(red: 0, green: 0, blue: 1)
	var secondColor = BrowserColor(red: 0.13, green: 0.37, blue: 0.92)
	var gradientDirection = ThemeGradientDirection.topLeading
	var meshColorPoints = [
		ThemeColorPoint(
			id: ThemeColorPoint.migratedFirstID,
			color: BrowserColor(red: 0, green: 0, blue: 1),
			x: 0.5,
			y: 0.5
		),
	]
	var meshOpacity = 1.0
	var shaderNoiseEnabled = false
	var shaderNoiseAmount = 0.25
	var shaderNoiseMonochrome = true
	var appearanceMode = ThemeAppearanceMode.auto

	init() {}

	private enum CodingKeys: String, CodingKey {
		case usesGradient
		case firstColor
		case secondColor
		case gradientDirection
		case meshColorPoints
		case meshOpacity
		case shaderNoiseEnabled
		case shaderNoiseAmount
		case shaderNoiseMonochrome
		case appearanceMode
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		usesGradient = try values.decodeIfPresent(Bool.self, forKey: .usesGradient) ?? false
		firstColor = try values.decodeIfPresent(BrowserColor.self, forKey: .firstColor) ?? BrowserColor(red: 0, green: 0, blue: 1)
		secondColor = try values.decodeIfPresent(BrowserColor.self, forKey: .secondColor) ?? BrowserColor(red: 0.13, green: 0.37, blue: 0.92)
		gradientDirection = try values.decodeIfPresent(ThemeGradientDirection.self, forKey: .gradientDirection) ?? .topLeading
		meshOpacity = try values.decodeIfPresent(Double.self, forKey: .meshOpacity) ?? 1
		if let savedPoints = try values.decodeIfPresent([ThemeColorPoint].self, forKey: .meshColorPoints) {
			meshColorPoints = Array(savedPoints.prefix(4))
		} else if usesGradient {
			meshColorPoints = [
				ThemeColorPoint(id: ThemeColorPoint.migratedFirstID, color: firstColor, x: 0.28, y: 0.32),
				ThemeColorPoint(id: ThemeColorPoint.migratedSecondID, color: secondColor, x: 0.72, y: 0.68),
			]
		} else {
			meshColorPoints = [
				ThemeColorPoint(id: ThemeColorPoint.migratedFirstID, color: firstColor, x: 0.5, y: 0.5),
			]
		}
		shaderNoiseEnabled = try values.decodeIfPresent(Bool.self, forKey: .shaderNoiseEnabled) ?? false
		shaderNoiseMonochrome = try values.decodeIfPresent(Bool.self, forKey: .shaderNoiseMonochrome) ?? true
		let maximumNoiseOpacity = shaderNoiseMonochrome ? 0.25 : 0.5
		let savedNoiseOpacity = try values.decodeIfPresent(Double.self, forKey: .shaderNoiseAmount) ?? 0.25
		shaderNoiseAmount = min(max(savedNoiseOpacity, 0), maximumNoiseOpacity)
		appearanceMode = try values.decodeIfPresent(ThemeAppearanceMode.self, forKey: .appearanceMode) ?? .auto
	}

	var gradientEndDirection: ThemeGradientDirection {
		get { gradientDirection.opposite }
		set { gradientDirection = newValue.opposite }
	}

	var tabColor: Color {
		nearestMeshColor(to: .zero)?.color ?? .white.opacity(0.2)
	}

	func contentShade(for systemScheme: ColorScheme) -> Color {
		let isDark = switch appearanceMode {
			case .dark: true
			case .light: false
			case .auto: systemScheme == .dark
		}
		return (isDark ? Color.black : .white).opacity(0.2)
	}

	var progressColor: Color {
		(meshColorPoints.dropFirst().first ?? meshColorPoints.first)?.color.color ?? .clear
	}

	var foregroundColor: Color {
		switch appearanceMode {
			case .light:
				return Color.black
			case .dark:
				return Color.white
			case .auto:
				guard let topLeftColor = nearestMeshColor(to: .zero) else { return .black }
				return topLeftColor.luminance > 0.6 ? .black : .white
		}
	}

	var shaderNoiseMaximumOpacity: Double {
		shaderNoiseMonochrome ? 0.25 : 0.5
	}

	private func nearestMeshColor(to position: CGPoint) -> BrowserColor? {
		let targetX = Double(position.x)
		let targetY = Double(position.y)
		return meshColorPoints.min { first, second in
			let firstX = first.x - targetX
			let firstY = first.y - targetY
			let secondX = second.x - targetX
			let secondY = second.y - targetY
			return firstX * firstX + firstY * firstY < secondX * secondX + secondY * secondY
		}?.color
	}

	mutating func addMeshColorPoint(at position: CGPoint? = nil) -> UUID? {
		guard meshColorPoints.count < 4 else { return nil }

		let nextPosition = position ?? CGPoint(x: 0.5, y: 0.5)
		let newPoint: ThemeColorPoint

		switch meshColorPoints.count {
			case 0:
				newPoint = ThemeColorPoint(
					color: firstColor,
					x: clamped(nextPosition.x),
					y: clamped(nextPosition.y)
				)
			case 1:
				newPoint = ThemeColorPoint(
					color: BrowserColor(red: 0.1, green: 0.75, blue: 0.2),
					x: 0.7,
					y: 0.7
				)
			case 2:
				newPoint = ThemeColorPoint(
					color: BrowserColor(red: 0.92, green: 0.12, blue: 0.1),
					x: 0.3,
					y: 0.7
				)
			case 3:
				newPoint = ThemeColorPoint(
					color: BrowserColor(red: 1, green: 1, blue: 1),
					x: 0.7,
					y: 0.3
				)
			default:
				return nil
		}

		meshColorPoints.append(newPoint)
		return newPoint.id
	}

	mutating func removeMeshColorPoint(id: UUID) {
		meshColorPoints.removeAll { $0.id == id }
	}

	mutating func moveMeshColorPoint(id: UUID, to position: CGPoint) {
		guard let index = meshColorPoints.firstIndex(where: { $0.id == id }) else { return }
		let x = clamped(position.x)
		let y = clamped(position.y)

		meshColorPoints[index].x = x
		meshColorPoints[index].y = y
	}

	private func clamped(_ value: CGFloat) -> Double {
		min(max(Double(value), 0), 1)
	}
}

enum ThemeAppearanceMode: String, Codable, CaseIterable, Identifiable {
	case light
	case dark
	case auto

	var id: Self {
		self
	}

	var title: String {
		switch self {
			case .light: "Light"
			case .dark: "Dark"
			case .auto: "Auto"
		}
	}

	var symbol: String {
		switch self {
			case .light: "sun.max.fill"
			case .dark: "moon.stars"
			case .auto: "sparkles"
		}
	}
}

struct ThemeColorPoint: Codable, Equatable, Identifiable {
	static let migratedFirstID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
	static let migratedSecondID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))

	let id: UUID
	var color: BrowserColor
	var x: Double
	var y: Double

	init(
		id: UUID = UUID(),
		color: BrowserColor,
		x: Double,
		y: Double
	) {
		self.id = id
		self.color = color
		self.x = x
		self.y = y
	}
}

struct BrowserColor: Codable, Equatable {
	var red: Double
	var green: Double
	var blue: Double

	var color: Color {
		get {
			Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
		}
		set {
			#if os(macOS)
				guard let converted = NSColor(newValue).usingColorSpace(.deviceRGB) else { return }
				red = converted.redComponent
				green = converted.greenComponent
				blue = converted.blueComponent
			#elseif os(iOS)
				var red: CGFloat = 0
				var green: CGFloat = 0
				var blue: CGFloat = 0
				var alpha: CGFloat = 0
				guard UIColor(newValue).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
				self.red = red
				self.green = green
				self.blue = blue
			#endif
		}
	}

	var luminance: Double {
		func linear(_ component: Double) -> Double {
			component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
	}
}

enum ThemeGradientDirection: String, Codable, CaseIterable, Identifiable {
	case top
	case bottom
	case leading
	case trailing
	case topLeading
	case bottomTrailing
	case topTrailing
	case bottomLeading

	var id: Self {
		self
	}

	var title: String {
		switch self {
			case .top: "Top"
			case .bottom: "Bottom"
			case .leading: "Leading"
			case .trailing: "Trailing"
			case .topLeading: "Top Leading"
			case .bottomTrailing: "Bottom Trailing"
			case .topTrailing: "Top Trailing"
			case .bottomLeading: "Bottom Leading"
		}
	}

	var opposite: Self {
		switch self {
			case .top: .bottom
			case .bottom: .top
			case .leading: .trailing
			case .trailing: .leading
			case .topLeading: .bottomTrailing
			case .bottomTrailing: .topLeading
			case .topTrailing: .bottomLeading
			case .bottomLeading: .topTrailing
		}
	}

	var startPoint: UnitPoint {
		switch self {
			case .top: .top
			case .bottom: .bottom
			case .leading: .leading
			case .trailing: .trailing
			case .topLeading: .topLeading
			case .bottomTrailing: .bottomTrailing
			case .topTrailing: .topTrailing
			case .bottomLeading: .bottomLeading
		}
	}

	var endPoint: UnitPoint {
		opposite.startPoint
	}
}
