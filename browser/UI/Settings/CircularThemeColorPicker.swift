import CoreGraphics
import simd
import SwiftUI

struct CircularThemeColorPicker: View {
	@Binding var color: BrowserColor
	let dismissalSignal: Int
	let centerShift: CGSize
	let onClose: () -> Void
	let onDelete: () -> Void

	@State private var hue: Double
	@State private var fieldImage: CGImage?
	@State private var expansion: CGFloat = 0
	@State private var isDismissing = false
	@State private var showsOuterGlass = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	static let diameter: CGFloat = 196
	private let fieldSize: CGFloat = 120
	private let arcRadius: CGFloat = 85
	private let arcStart = 145.0
	private let arcLength = 250.0

	init(
		color: Binding<BrowserColor>,
		dismissalSignal: Int,
		centerShift: CGSize,
		onClose: @escaping () -> Void,
		onDelete: @escaping () -> Void
	) {
		_color = color
		self.dismissalSignal = dismissalSignal
		self.centerShift = centerShift
		self.onClose = onClose
		self.onDelete = onDelete
		_hue = State(initialValue: Self.hsv(color.wrappedValue).hue)
	}

	var body: some View {
		ZStack {
			colorField

			GlassEffectContainer(spacing: 4) {
				if showsOuterGlass {
					ZStack {
						hueLayer
						deleteButton
					}
					.frame(width: Self.diameter, height: Self.diameter)
				}
			}

			GlassEffectContainer(spacing: 4) {
				ZStack {
					innerTick
					if showsOuterGlass {
						outerTick
					}
				}
				.frame(width: Self.diameter, height: Self.diameter)
			}
		}
		.frame(width: Self.diameter, height: Self.diameter)
		.offset(
			x: centerShift.width * expansion,
			y: centerShift.height * expansion
		)
		.coordinateSpace(name: "theme-color-picker")
		.onAppear {
			fieldImage = Self.renderField(hue: hue)
			withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.66)) {
				expansion = 1
				showsOuterGlass = true
			}
		}
		.onChange(of: hue) { _, newHue in
			fieldImage = Self.renderField(hue: newHue)
		}
		.onChange(of: dismissalSignal) { _, _ in
			dismiss()
		}
		#if os(macOS)
		.onExitCommand(perform: dismiss)
		#endif
	}

	private var colorField: some View {
		ZStack {
			GlassEffectContainer(spacing: 0) {
				Circle()
					.fill(color.color.opacity(0.35))
					.glassEffect(.clear.tint(color.color).interactive(), in: Circle())
					.glassEffectTransition(.materialize)
			}

			if let fieldImage {
				Image(decorative: fieldImage, scale: 1, orientation: .up)
					.resizable()
					.interpolation(.high)
					.opacity(expansion)
			}
		}
		.frame(width: fieldSize, height: fieldSize)
		.clipShape(Circle())
		.scaleEffect(openingScale)
		.gesture(
			DragGesture(minimumDistance: 0, coordinateSpace: .named("theme-color-picker"))
				.onChanged { gesture in
					let inset = (Self.diameter - fieldSize) / 2
					updateSaturationValue(at: CGPoint(
						x: gesture.location.x - inset,
						y: gesture.location.y - inset
					))
				}
		)
		.accessibilityLabel("Saturation and brightness")
		.accessibilityHint("Drag within the circle to choose a color")
		.accessibilityIdentifier("theme-point-color-field")
		.accessibilityValue("Saturation \(Int(Self.hsv(color).saturation * 100)) percent, brightness \(Int(Self.hsv(color).value * 100)) percent")
		.accessibilityAction(named: "Increase saturation") { adjust(saturation: 0.05, value: 0) }
		.accessibilityAction(named: "Decrease saturation") { adjust(saturation: -0.05, value: 0) }
		.accessibilityAction(named: "Increase brightness") { adjust(saturation: 0, value: 0.05) }
		.accessibilityAction(named: "Decrease brightness") { adjust(saturation: 0, value: -0.05) }
	}

	private var hueLayer: some View {
		hueArc
			.scaleEffect(openingScale)
			.opacity(expansion)
			.blur(radius: (1 - expansion) * 9)
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
	}

	private var deleteButton: some View {
		Button {
			deleteColor()
		} label: {
			Label("Delete color point", systemImage: "trash")
				.labelStyle(.iconOnly)
				.frame(width: 30, height: 30)
		}
		.buttonStyle(.glass)
		.buttonBorderShape(.circle)
		.glassEffectTransition(.materialize)
		.offset(y: arcRadius)
		.opacity(expansion)
		.scaleEffect(openingScale)
		.blur(radius: (1 - expansion) * 9)
		.accessibilityIdentifier("theme-point-color-delete")
	}

	private var innerTick: some View {
		selectionTick(size: 42)
			.offset(selectionOffset)
			.opacity(expansion)
			.gesture(
				DragGesture(minimumDistance: 0, coordinateSpace: .named("theme-color-picker"))
					.onChanged { gesture in
						let inset = (Self.diameter - fieldSize) / 2
						updateSaturationValue(at: CGPoint(
							x: gesture.location.x - inset,
							y: gesture.location.y - inset
						))
					}
			)
			.accessibilityHidden(true)
	}

	private var outerTick: some View {
		selectionTick(size: 38)
			.offset(hueOffset)
			.opacity(expansion)
			.scaleEffect(openingScale)
			.blur(radius: (1 - expansion) * 9)
			.gesture(
				DragGesture(minimumDistance: 0, coordinateSpace: .named("theme-color-picker"))
					.onChanged { updateHue(at: $0.location) }
			)
			.accessibilityHidden(true)
	}

	private var openingScale: CGFloat {
		(34 + (fieldSize - 34) * expansion) / fieldSize
	}

	private var arcShape: ThemeHueArc {
		ThemeHueArc(start: arcStart, length: arcLength, lineWidth: 26)
	}

	private var hueArc: some View {
		arcShape
			.fill(.clear)
			.glassEffect(.regular.interactive(), in: arcShape)
			.glassEffectTransition(.materialize)
			.overlay {
				arcShape
					.fill(hueGradient)
					.opacity(0.78)
					.allowsHitTesting(false)
			}
			.frame(width: Self.diameter, height: Self.diameter)
			.contentShape(arcShape)
	}

	private func selectionTick(size: CGFloat) -> some View {
		Circle()
			.fill(.clear)
			.frame(width: size, height: size)
			.glassEffect(.clear.interactive(), in: Circle())
			.glassEffectTransition(.materialize)
	}

	private var hueGradient: AngularGradient {
		let colors: [Color] = [.red, .yellow, .green, .cyan, .blue, .purple, .red]
		let stops = colors.enumerated().map { index, color in
			Gradient.Stop(color: color, location: Double(index) / 6 * arcLength / 360)
		}
		return AngularGradient(
			stops: stops,
			center: .center,
			startAngle: .degrees(arcStart),
			endAngle: .degrees(arcStart + 360)
		)
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

	private func dismiss() {
		collapse(then: onClose)
	}

	private func deleteColor() {
		collapse(then: onDelete)
	}

	private func collapse(then completion: @escaping () -> Void) {
		guard !isDismissing else { return }
		isDismissing = true
		withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), completionCriteria: .logicallyComplete) {
			expansion = 0
			showsOuterGlass = false
		} completion: {
			completion()
		}
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
		let center = Self.diameter / 2
		let angle = atan2(location.y - center, location.x - center) * 180 / .pi
		let arcPosition = (Double(angle) - arcStart + 360).truncatingRemainder(dividingBy: 360)
		if arcPosition <= arcLength {
			setHue(arcPosition / arcLength)
		} else {
			let gapPosition = arcPosition - arcLength
			setHue(gapPosition < (360 - arcLength) / 2 ? 1 : 0)
		}
	}

	private func setHue(_ newHue: Double) {
		let current = Self.hsv(color)
		let nextHue = min(max(newHue, 0), 1)
		if abs(nextHue - hue) > 0.5 {
			withTransaction(Transaction(animation: nil)) {
				hue = nextHue
			}
		} else {
			withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
				hue = nextHue
			}
		}
		color.color = Color(hue: nextHue, saturation: current.saturation, brightness: current.value)
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

private struct ThemeHueArc: Shape {
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
