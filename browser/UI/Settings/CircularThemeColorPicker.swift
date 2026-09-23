import CoreGraphics
import simd
import SwiftUI

struct CircularThemeColorPicker: View {
	@Binding var color: BrowserColor
	let pointID: UUID
	let namespace: Namespace.ID
	let onClose: () -> Void

	@State private var hue: Double
	@State private var fieldImage: CGImage?
	@State private var arcProgress = 0.0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@FocusState private var isFocused: Bool

	private let size: CGFloat = 220
	private let fieldSize: CGFloat = 144
	private let arcRadius: CGFloat = 100
	private let arcStart = 145.0
	private let arcLength = 250.0

	init(color: Binding<BrowserColor>, pointID: UUID, namespace: Namespace.ID, onClose: @escaping () -> Void) {
		_color = color
		self.pointID = pointID
		self.namespace = namespace
		self.onClose = onClose
		let initialHue = Self.hsv(color.wrappedValue).hue
		_hue = State(initialValue: initialHue)
	}

	var body: some View {
		ZStack {
			Group {
				if let fieldImage {
					Image(decorative: fieldImage, scale: 1, orientation: .up)
						.resizable()
						.interpolation(.high)
				} else {
					Circle().fill(color.color)
				}
			}
			.frame(width: fieldSize, height: fieldSize)
			.clipShape(Circle())
			.matchedGeometryEffect(id: pointID, in: namespace)
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { updateSaturationValue(at: $0.location) }
			)
			.accessibilityLabel("Saturation and brightness")
			.accessibilityHint("Drag within the circle to choose a color")
			.accessibilityIdentifier("theme-point-color-field")
			.accessibilityValue("Saturation \(Int(Self.hsv(color).saturation * 100)) percent, brightness \(Int(Self.hsv(color).value * 100)) percent")
			.accessibilityAction(named: "Increase saturation") { adjust(saturation: 0.05, value: 0) }
			.accessibilityAction(named: "Decrease saturation") { adjust(saturation: -0.05, value: 0) }
			.accessibilityAction(named: "Increase brightness") { adjust(saturation: 0, value: 0.05) }
			.accessibilityAction(named: "Decrease brightness") { adjust(saturation: 0, value: -0.05) }

			selectionTick
				.offset(selectionOffset)
				.gesture(
					DragGesture(minimumDistance: 0, coordinateSpace: .named("theme-color-picker"))
						.onChanged { gesture in
							let inset = (size - fieldSize) / 2
							updateSaturationValue(at: CGPoint(
								x: gesture.location.x - inset,
								y: gesture.location.y - inset
							))
						}
				)
				.accessibilityHidden(true)

			Circle()
				.trim(from: 0, to: arcLength / 360)
				.stroke(hueGradient, style: StrokeStyle(lineWidth: 20, lineCap: .round))
				.rotationEffect(.degrees(arcStart))
				.frame(width: arcRadius * 2, height: arcRadius * 2)
				.opacity(arcProgress)
				.scaleEffect(CGFloat(0.72 + 0.28 * arcProgress))
				.blur(radius: CGFloat((1 - arcProgress) * 10))
				.gesture(
					DragGesture(minimumDistance: 0, coordinateSpace: .named("theme-color-picker"))
						.onChanged { updateHue(at: $0.location) }
				)
				.accessibilityLabel("Hue")
				.accessibilityValue("\(Int(hue * 360)) degrees")
				.accessibilityIdentifier("theme-point-hue-arc")
				.accessibilityAdjustableAction { direction in
					switch direction {
						case .increment: setHue(hue + 0.02)
						case .decrement: setHue(hue - 0.02)
						@unknown default: break
					}
				}

			selectionTick
				.offset(hueOffset)
				.opacity(arcProgress)
				.scaleEffect(CGFloat(0.72 + 0.28 * arcProgress))
				.blur(radius: CGFloat((1 - arcProgress) * 10))
				.gesture(
					DragGesture(minimumDistance: 0, coordinateSpace: .named("theme-color-picker"))
						.onChanged { updateHue(at: $0.location) }
				)
				.accessibilityHidden(true)
		}
		.frame(width: size, height: size)
		.coordinateSpace(name: "theme-color-picker")
		.focusable()
		.focused($isFocused)
		.onKeyPress(.escape) {
			onClose()
			return .handled
		}
		.onAppear {
			isFocused = true
			fieldImage = Self.renderField(hue: hue)
			withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.72).delay(0.06)) {
				arcProgress = 1
			}
		}
		.onChange(of: hue) { _, newHue in
			fieldImage = Self.renderField(hue: newHue)
		}
	}

	private var selectionTick: some View {
		Circle()
			.fill(.clear)
			.frame(width: 22, height: 22)
			.glassEffect(.regular.tint(color.color).interactive(), in: Circle())
			.overlay { Circle().strokeBorder(.white, lineWidth: 2) }
			.shadow(color: .black.opacity(0.55), radius: 2)
	}

	private var hueGradient: AngularGradient {
		let colors: [Color] = [.red, .yellow, .green, .cyan, .blue, .purple, .red]
		let stops = colors.enumerated().map { index, color in
			Gradient.Stop(color: color, location: Double(index) / 6 * arcLength / 360)
		}
		return AngularGradient(stops: stops, center: .center)
	}

	private var selectionOffset: CGSize {
		let hsv = Self.hsv(color)
		let position = CircularSVPicker.circlePosition(saturation: hsv.saturation, value: hsv.value)
		return CGSize(width: position.x * fieldSize / 2, height: -position.y * fieldSize / 2)
	}

	private var hueOffset: CGSize {
		let angle = (arcStart + hue * arcLength) * .pi / 180
		return CGSize(width: cos(angle) * arcRadius, height: sin(angle) * arcRadius)
	}

	private func updateSaturationValue(at location: CGPoint) {
		let radius = fieldSize / 2
		var point = SIMD2<Double>(
			Double((location.x - radius) / radius),
			Double((radius - location.y) / radius)
		)
		let distance = simd_length(point)
		if distance > 1 {
			point /= distance
		}
		let result = CircularSVPicker.saturationValue(for: point)
		color.color = Color(hue: hue, saturation: result.saturation, brightness: result.value)
	}

	private func updateHue(at location: CGPoint) {
		let center = size / 2
		let angle = atan2(location.y - center, location.x - center) * 180 / .pi
		let progress = (Double(angle) - arcStart + 360).truncatingRemainder(dividingBy: 360) / arcLength
		setHue(progress)
	}

	private func setHue(_ newHue: Double) {
		hue = min(max(newHue, 0), 1)
		let current = Self.hsv(color)
		color.color = Color(hue: hue, saturation: current.saturation, brightness: current.value)
	}

	private func adjust(saturation: Double, value: Double) {
		let current = Self.hsv(color)
		color.color = Color(
			hue: hue,
			saturation: min(max(current.saturation + saturation, 0), 1),
			brightness: min(max(current.value + value, 0), 1)
		)
	}

	private static func hsv(_ color: BrowserColor) -> (hue: Double, saturation: Double, value: Double) {
		let maximum = max(color.red, color.green, color.blue)
		let minimum = min(color.red, color.green, color.blue)
		let difference = maximum - minimum
		let saturation = maximum > 0 ? difference / maximum : 0
		guard difference > 0 else { return (0, saturation, maximum) }
		let segment: Double = if maximum == color.red {
			(color.green - color.blue) / difference
		} else if maximum == color.green {
			(color.blue - color.red) / difference + 2
		} else {
			(color.red - color.green) / difference + 4
		}
		return ((segment / 6 + 1).truncatingRemainder(dividingBy: 1), saturation, maximum)
	}

	private static let fieldDimension = 384

	private static func renderField(hue: Double) -> CGImage {
		let dimension = fieldDimension
		let pureHue = pureHueRGB(hue)
		var pixels = [UInt8](repeating: 0, count: dimension * dimension * 4)
		for (pixel, weights) in fieldWeights.enumerated() {
			guard weights.inside else { continue }
			let index = pixel * 4
			let noise = Double(((pixel &* 73) ^ (pixel >> 3)) & 255) / 255 - 0.5
			pixels[index] = UInt8(min(max((weights.white + weights.hue * pureHue.x) * 255 + noise, 0), 255))
			pixels[index + 1] = UInt8(min(max((weights.white + weights.hue * pureHue.y) * 255 + noise, 0), 255))
			pixels[index + 2] = UInt8(min(max((weights.white + weights.hue * pureHue.z) * 255 + noise, 0), 255))
			pixels[index + 3] = 255
		}
		let provider = CGDataProvider(data: Data(pixels) as CFData)!
		return CGImage(
			width: dimension,
			height: dimension,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: dimension * 4,
			space: CGColorSpace(name: CGColorSpace.sRGB)!,
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: true,
			intent: .defaultIntent
		)!
	}

	private static let fieldWeights: [(white: Double, hue: Double, inside: Bool)] = {
		let dimension = fieldDimension
		let radius = Double(dimension) / 2
		let rootThree = sqrt(3.0)
		var weights: [(white: Double, hue: Double, inside: Bool)] = []
		weights.reserveCapacity(dimension * dimension)
		for row in 0 ..< dimension {
			for column in 0 ..< dimension {
				let point = SIMD2<Double>(
					(Double(column) + 0.5 - radius) / radius,
					(radius - Double(row) - 0.5) / radius
				)
				guard simd_length_squared(point) <= 1 else {
					weights.append((0, 0, false))
					continue
				}
				let triangle = CircularSVPicker.circleToTriangle(point)
				weights.append((
					(1 + triangle.y) / 3 - triangle.x / rootThree,
					(1 + triangle.y) / 3 + triangle.x / rootThree,
					true
				))
			}
		}
		return weights
	}()

	private static func pureHueRGB(_ hue: Double) -> SIMD3<Double> {
		let segment = hue * 6
		let x = 1 - abs(segment.truncatingRemainder(dividingBy: 2) - 1)
		switch Int(segment) % 6 {
			case 0: return SIMD3(1, x, 0)
			case 1: return SIMD3(x, 1, 0)
			case 2: return SIMD3(0, 1, x)
			case 3: return SIMD3(0, x, 1)
			case 4: return SIMD3(x, 0, 1)
			default: return SIMD3(1, 0, x)
		}
	}
}
