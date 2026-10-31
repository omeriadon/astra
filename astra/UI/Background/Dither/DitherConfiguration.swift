import Foundation
import simd

nonisolated struct DitherConfiguration: Codable, Equatable, Sendable {
	static let defaultWaveDirection: Float = 135
	static let supportedPaletteCount = 8

	var waveSpeed: Float = 0.05
	var waveDirection: Float = Self.defaultWaveDirection
	var waveFrequency: Float = 3
	var waveAmplitude: Float = 0.3
	var waveColor = SIMD3<Float>(repeating: 0.5)
	var backgroundColor = SIMD3<Float>(repeating: 0)
	var colorNum: Float = 4
	var pixelSize: Float = 2
	var disableAnimation = false
	var ditherMode = 0
	var ditherStrength: Float = 1
	var palette: [SIMD3<Float>] = []
	var scale: Float = 1
	var contrast: Float = 1
	var brightness: Float = 0
	var intro = true
	var transparent = false
	var gap: Float = 0
	var cornerRadius: Float = 0
	var joinAdjacentSquares = false
	var backgroundStyle = "custom"
	var colorPlacement = "squares"
	var squareStyle = "white"
	var useThemeColors = true
	var opacity: Float = 1
	var topBlur = true

	var gridSize: Double {
		Double(pixelSize)
	}

	var waveScale: Double {
		Double(scale)
	}

	var colorLevels: Double {
		Double(colorNum)
	}

	var minimumIntensity: Double {
		0
	}

	var animationEnabled: Bool {
		!disableAnimation
	}

	var cursorInteractionEnabled = true
	var cursorRadius: Double = 0.5
	var cursorStrength: Double = 1
	var cursorResponse: Double = 0.28
	var cursorTrailDuration: Double = 0.7
	var cursorFadeDuration: Double = 0.8
	var cursorWarp: Double = 0.15
	var framesPerSecond: Double {
		30
	}

	private enum CodingKeys: String, CodingKey {
		case waveSpeed, waveDirection, waveFrequency, waveAmplitude, waveColor, backgroundColor
		case colorNum, pixelSize, disableAnimation, ditherMode, ditherStrength, palette
		case scale, contrast, brightness, intro, transparent, gap, cornerRadius
		case joinAdjacentSquares, backgroundStyle, colorPlacement, squareStyle, useThemeColors
		case opacity, topBlur, cursorInteractionEnabled, cursorRadius, cursorStrength
		case cursorResponse, cursorTrailDuration, cursorFadeDuration, cursorWarp
		case gridSize, gridSpacing, colorLevels, waveScale, animationEnabled
	}

	init() {}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		self.init()
		waveSpeed = try values.decodeIfPresent(Float.self, forKey: .waveSpeed) ?? 0.05
		waveDirection = try values.decodeIfPresent(Float.self, forKey: .waveDirection) ?? Self.defaultWaveDirection
		waveFrequency = try values.decodeIfPresent(Float.self, forKey: .waveFrequency) ?? 3
		waveAmplitude = try values.decodeIfPresent(Float.self, forKey: .waveAmplitude) ?? 0.3
		waveColor = try values.decodeIfPresent(SIMD3<Float>.self, forKey: .waveColor) ?? .init(repeating: 0.5)
		backgroundColor = try values.decodeIfPresent(SIMD3<Float>.self, forKey: .backgroundColor) ?? .zero
		colorNum = try values.decodeIfPresent(Float.self, forKey: .colorNum)
			?? values.decodeIfPresent(Float.self, forKey: .colorLevels) ?? 4
		let legacyGridSize = try values.decodeIfPresent(Double.self, forKey: .gridSize)
		let legacyGridSpacing = try values.decodeIfPresent(Double.self, forKey: .gridSpacing)
		pixelSize = try values.decodeIfPresent(Float.self, forKey: .pixelSize)
			?? Float((legacyGridSize ?? 2) + (legacyGridSpacing ?? 0))
		let oldGap = (legacyGridSpacing ?? 0) / (2 * max(Double(pixelSize), 1))
		gap = try values.decodeIfPresent(Float.self, forKey: .gap) ?? Float(oldGap)
		disableAnimation = try values.decodeIfPresent(Bool.self, forKey: .disableAnimation)
			?? !(values.decodeIfPresent(Bool.self, forKey: .animationEnabled) ?? true)
		ditherMode = try values.decodeIfPresent(Int.self, forKey: .ditherMode) ?? 0
		ditherStrength = try values.decodeIfPresent(Float.self, forKey: .ditherStrength) ?? 1
		palette = try values.decodeIfPresent([SIMD3<Float>].self, forKey: .palette) ?? []
		scale = try values.decodeIfPresent(Float.self, forKey: .scale)
			?? values.decodeIfPresent(Float.self, forKey: .waveScale) ?? 1
		contrast = try values.decodeIfPresent(Float.self, forKey: .contrast) ?? 1
		brightness = try values.decodeIfPresent(Float.self, forKey: .brightness) ?? 0
		intro = try values.decodeIfPresent(Bool.self, forKey: .intro) ?? true
		transparent = try values.decodeIfPresent(Bool.self, forKey: .transparent) ?? false
		let storedRadius = try values.decodeIfPresent(Float.self, forKey: .cornerRadius) ?? 0
		cornerRadius = legacyGridSize == nil ? storedRadius : storedRadius / max(pixelSize, 1)
		joinAdjacentSquares = try values.decodeIfPresent(Bool.self, forKey: .joinAdjacentSquares) ?? false
		backgroundStyle = try Self.validBackgroundStyle(values.decodeIfPresent(String.self, forKey: .backgroundStyle))
		colorPlacement = try Self.validColorPlacement(values.decodeIfPresent(String.self, forKey: .colorPlacement))
		squareStyle = try Self.validSquareStyle(values.decodeIfPresent(String.self, forKey: .squareStyle))
		useThemeColors = try values.decodeIfPresent(Bool.self, forKey: .useThemeColors) ?? true
		opacity = try values.decodeIfPresent(Float.self, forKey: .opacity) ?? 1
		topBlur = try values.decodeIfPresent(Bool.self, forKey: .topBlur) ?? true
		cursorInteractionEnabled = try values.decodeIfPresent(Bool.self, forKey: .cursorInteractionEnabled) ?? true
		cursorRadius = try values.decodeIfPresent(Double.self, forKey: .cursorRadius) ?? 0.5
		cursorStrength = try values.decodeIfPresent(Double.self, forKey: .cursorStrength) ?? 1
		cursorResponse = try values.decodeIfPresent(Double.self, forKey: .cursorResponse) ?? 0.28
		cursorTrailDuration = try values.decodeIfPresent(Double.self, forKey: .cursorTrailDuration) ?? 0.7
		cursorFadeDuration = try values.decodeIfPresent(Double.self, forKey: .cursorFadeDuration) ?? 0.8
		cursorWarp = try values.decodeIfPresent(Double.self, forKey: .cursorWarp) ?? 0.15
		if waveSpeed < 0 {
			waveSpeed = abs(waveSpeed)
			waveDirection = Self.normalizedWaveDirection(waveDirection + 180) ?? Self.defaultWaveDirection
		}
	}

	func encode(to encoder: Encoder) throws {
		var values = encoder.container(keyedBy: CodingKeys.self)
		try values.encode(waveSpeed, forKey: .waveSpeed)
		try values.encode(waveDirection, forKey: .waveDirection)
		try values.encode(waveFrequency, forKey: .waveFrequency)
		try values.encode(waveAmplitude, forKey: .waveAmplitude)
		try values.encode(waveColor, forKey: .waveColor)
		try values.encode(backgroundColor, forKey: .backgroundColor)
		try values.encode(colorNum, forKey: .colorNum)
		try values.encode(pixelSize, forKey: .pixelSize)
		try values.encode(disableAnimation, forKey: .disableAnimation)
		try values.encode(ditherMode, forKey: .ditherMode)
		try values.encode(ditherStrength, forKey: .ditherStrength)
		try values.encode(palette, forKey: .palette)
		try values.encode(scale, forKey: .scale)
		try values.encode(contrast, forKey: .contrast)
		try values.encode(brightness, forKey: .brightness)
		try values.encode(intro, forKey: .intro)
		try values.encode(transparent, forKey: .transparent)
		try values.encode(gap, forKey: .gap)
		try values.encode(cornerRadius, forKey: .cornerRadius)
		try values.encode(joinAdjacentSquares, forKey: .joinAdjacentSquares)
		try values.encode(backgroundStyle, forKey: .backgroundStyle)
		try values.encode(colorPlacement, forKey: .colorPlacement)
		try values.encode(squareStyle, forKey: .squareStyle)
		try values.encode(useThemeColors, forKey: .useThemeColors)
		try values.encode(opacity, forKey: .opacity)
		try values.encode(topBlur, forKey: .topBlur)
		try values.encode(cursorInteractionEnabled, forKey: .cursorInteractionEnabled)
		try values.encode(cursorRadius, forKey: .cursorRadius)
		try values.encode(cursorStrength, forKey: .cursorStrength)
		try values.encode(cursorResponse, forKey: .cursorResponse)
		try values.encode(cursorTrailDuration, forKey: .cursorTrailDuration)
		try values.encode(cursorFadeDuration, forKey: .cursorFadeDuration)
		try values.encode(cursorWarp, forKey: .cursorWarp)
	}

	static func normalizedWaveDirection(_ degrees: Float) -> Float? {
		guard degrees.isFinite else { return nil }
		let normalized = degrees.truncatingRemainder(dividingBy: 360)
		let positive = normalized >= 0 ? normalized : normalized + 360
		let snapped = (positive / 45).rounded() * 45
		return snapped >= 360 ? 0 : snapped
	}

	static func waveDirectionVector(for degrees: Float) -> SIMD2<Float> {
		let normalized = normalizedWaveDirection(degrees) ?? defaultWaveDirection
		let radians = normalized * .pi / 180
		return SIMD2<Float>(sin(radians), -cos(radians)) * sqrt(2)
	}

	static func compassDirection(for degrees: Float) -> String {
		let normalized = normalizedWaveDirection(degrees) ?? defaultWaveDirection
		return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((normalized / 45).rounded()) % 8]
	}

	func bounded() -> Self {
		var value = self
		value.waveSpeed = finite(waveSpeed, 0.05, 0 ... 1)
		value.waveDirection = Self.normalizedWaveDirection(waveDirection) ?? Self.defaultWaveDirection
		value.waveFrequency = finite(waveFrequency, 3, 0.01 ... 12)
		value.waveAmplitude = finite(waveAmplitude, 0.3, 0 ... 1)
		value.colorNum = finite(colorNum, 4, 2 ... 16)
		value.pixelSize = finite(pixelSize, 2, 1 ... 4096)
		value.ditherStrength = finite(ditherStrength, 1, 0 ... 1)
		value.scale = finite(scale, 1, 0.05 ... 32)
		value.contrast = finite(contrast, 1, 0.01 ... 8)
		value.brightness = finite(brightness, 0, -1 ... 1)
		value.gap = finite(gap, 0, 0 ... 0.45)
		value.cornerRadius = finite(cornerRadius, 0, 0 ... 0.5)
		value.opacity = finite(opacity, 1, 0 ... 1)
		value.waveColor = finiteColor(waveColor, .init(repeating: 0.5))
		value.backgroundColor = finiteColor(backgroundColor, .zero)
		value.palette = palette.prefix(Self.supportedPaletteCount).map { finiteColor($0, .init(repeating: 0.5)) }
		value.ditherMode = min(max(ditherMode, 0), 7)
		value.backgroundStyle = Self.validBackgroundStyle(backgroundStyle)
		value.colorPlacement = Self.validColorPlacement(colorPlacement)
		value.squareStyle = Self.validSquareStyle(squareStyle)
		value.cursorRadius = safe(cursorRadius, 0.05 ... 2, fallback: 0.5)
		value.cursorStrength = safe(cursorStrength, -2 ... 2, fallback: 1)
		value.cursorResponse = safe(cursorResponse, 0.05 ... 1, fallback: 0.28)
		value.cursorTrailDuration = safe(cursorTrailDuration, 0 ... 2, fallback: 0.7)
		value.cursorFadeDuration = safe(cursorFadeDuration, 0.1 ... 3, fallback: 0.8)
		value.cursorWarp = safe(cursorWarp, 0 ... 1, fallback: 0.15)
		return value
	}

	static func validBackgroundStyle(_ value: String?) -> String {
		switch value {
			case "custom", "black", "white", "dim": value!
			default: "custom"
		}
	}

	static func validColorPlacement(_ value: String?) -> String {
		value == "background" ? "background" : "squares"
	}

	static func validSquareStyle(_ value: String?) -> String {
		value == "black" ? "black" : "white"
	}

	func safe(_ value: Double, _ range: ClosedRange<Double>, fallback: Double = 0) -> Double {
		min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
	}

	private func finite(_ value: Float, _ fallback: Float, _ range: ClosedRange<Float>) -> Float {
		min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
	}

	private func finiteColor(_ value: SIMD3<Float>, _ fallback: SIMD3<Float>) -> SIMD3<Float> {
		SIMD3<Float>(finite(value.x, fallback.x, 0 ... 1), finite(value.y, fallback.y, 0 ... 1), finite(value.z, fallback.z, 0 ... 1))
	}
}
