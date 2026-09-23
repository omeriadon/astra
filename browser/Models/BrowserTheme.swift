import SwiftUI

struct BrowserTheme: Codable, Equatable {
	var usesGradient = false
	var firstColor = BrowserColor(red: 0, green: 0, blue: 1)
	var secondColor = BrowserColor(red: 0.13, green: 0.37, blue: 0.92)
	var gradientDirection = ThemeGradientDirection.topLeading
	var noiseEnabled = false
	var noiseAmount = 0.12
	var shaderNoiseEnabled = false
	var shaderNoiseAmount = 0.5
	var shaderNoiseStyle = ThemeNoiseStyle.fineGrain
	var tabColor = BrowserColor(red: 0.10, green: 0.24, blue: 0.75)
	var progressColor = BrowserColor(red: 0, green: 0.78, blue: 0.18)

	init() {}

	private enum CodingKeys: String, CodingKey {
		case usesGradient
		case firstColor
		case secondColor
		case gradientDirection
		case noiseEnabled
		case noiseAmount
		case shaderNoiseEnabled
		case shaderNoiseAmount
		case shaderNoiseStyle
		case tabColor
		case progressColor
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		usesGradient = try values.decodeIfPresent(Bool.self, forKey: .usesGradient) ?? false
		firstColor = try values.decodeIfPresent(BrowserColor.self, forKey: .firstColor) ?? BrowserColor(red: 0, green: 0, blue: 1)
		secondColor = try values.decodeIfPresent(BrowserColor.self, forKey: .secondColor) ?? BrowserColor(red: 0.13, green: 0.37, blue: 0.92)
		gradientDirection = try values.decodeIfPresent(ThemeGradientDirection.self, forKey: .gradientDirection) ?? .topLeading
		noiseEnabled = try values.decodeIfPresent(Bool.self, forKey: .noiseEnabled) ?? false
		noiseAmount = try values.decodeIfPresent(Double.self, forKey: .noiseAmount) ?? 0.12
		shaderNoiseEnabled = try values.decodeIfPresent(Bool.self, forKey: .shaderNoiseEnabled) ?? false
		shaderNoiseAmount = try values.decodeIfPresent(Double.self, forKey: .shaderNoiseAmount) ?? 0.5
		shaderNoiseStyle = try values.decodeIfPresent(ThemeNoiseStyle.self, forKey: .shaderNoiseStyle) ?? .fineGrain
		tabColor = try values.decodeIfPresent(BrowserColor.self, forKey: .tabColor) ?? BrowserColor(red: 0.10, green: 0.24, blue: 0.75)
		progressColor = try values.decodeIfPresent(BrowserColor.self, forKey: .progressColor) ?? BrowserColor(red: 0, green: 0.78, blue: 0.18)
	}

	var gradientEndDirection: ThemeGradientDirection {
		get { gradientDirection.opposite }
		set { gradientDirection = newValue.opposite }
	}

	var tabTextColor: Color {
		tabColor.luminance > 0.179 ? .black : .white
	}
}

enum ThemeNoiseStyle: Int, Codable, CaseIterable, Identifiable {
	case fineGrain
	case soft
	case fractal

	var id: Self {
		self
	}

	var title: String {
		switch self {
			case .fineGrain: "Fine Grain"
			case .soft: "Soft"
			case .fractal: "Fractal"
		}
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
