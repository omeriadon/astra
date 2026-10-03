import CoreGraphics
import simd
import SwiftUI
#if os(macOS)
	import AppKit
#endif

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
	@State private var showsInnerTick = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	#if os(macOS)
		@State private var escapeMonitor: Any?
	#endif

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
		_hue = State(initialValue: SVFieldRenderer.hsv(color.wrappedValue).hue)
	}

	var body: some View {
		ZStack {
			SVFieldView(
				color: $color,
				fieldImage: fieldImage,
				expansion: expansion,
				openingScale: openingScale,
				fieldSize: fieldSize,
				diameter: Self.diameter,
				onSaturationValue: { updateSaturationValue(at: $0, animated: $1) },
				onAdjustSaturationValue: { adjust(saturation: $0, value: $1) }
			)

			GlassEffectContainer(spacing: 4) {
				if showsOuterGlass {
					ZStack {
						HueArcView(
							hue: hue,
							expansion: expansion,
							openingScale: openingScale,
							arcStart: arcStart,
							arcLength: arcLength,
							diameter: Self.diameter,
							onUpdateHue: { updateHue(at: $0, animated: $1) },
							onSetHue: { setHue($0, animated: $1) }
						)
						HueDeleteButton(
							arcRadius: arcRadius,
							expansion: expansion,
							openingScale: openingScale,
							onDelete: deleteColor
						)
					}
					.frame(width: Self.diameter, height: Self.diameter)
				}
			}

			GlassEffectContainer(spacing: 4) {
				ZStack {
					if showsInnerTick {
						InnerTickView(
							selectionOffset: selectionOffset,
							expansion: expansion,
							onSaturationValue: { updateSaturationValue(at: $0, animated: $1) }
						)
					}
					if showsOuterGlass {
						OuterTickView(
							hueOffset: hueOffset,
							expansion: expansion,
							openingScale: openingScale,
							onUpdateHue: { updateHue(at: $0, animated: $1) }
						)
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
			#if os(macOS)
				if escapeMonitor == nil {
					escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
						guard event.keyCode == 53 else { return event }
						dismiss()
						return nil
					}
				}
			#endif
			fieldImage = SVFieldRenderer.renderField(hue: hue)
			withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.66)) {
				expansion = 1
				showsOuterGlass = true
				showsInnerTick = true
			}
		}
		.onDisappear {
			#if os(macOS)
				if let escapeMonitor {
					NSEvent.removeMonitor(escapeMonitor)
					self.escapeMonitor = nil
				}
			#endif
		}
		.onChange(of: hue) { _, newHue in
			fieldImage = SVFieldRenderer.renderField(hue: newHue)
		}
		.onChange(of: dismissalSignal) { _, _ in
			dismiss()
		}
	}

	private var openingScale: CGFloat {
		(34 + (fieldSize - 34) * expansion) / fieldSize
	}

	private var selectionOffset: CGSize {
		let hsv = SVFieldRenderer.hsv(color)
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
			showsInnerTick = false
		} completion: {
			completion()
		}
	}

	private func updateSaturationValue(at location: CGPoint, animated: Bool) {
		let radius = fieldSize / 2
		let center = Self.diameter / 2
		var point = SIMD2<Double>(
			Double((location.x - center) / radius),
			Double((center - location.y) / radius)
		)
		let distance = simd_length(point)
		if distance > 1 {
			point /= distance
		}
		let result = CircularSVPicker.saturationValue(for: point)
		let nextColor = Color(hue: hue, saturation: result.saturation, brightness: result.value)
		if animated {
			withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
				color.color = nextColor
			}
		} else {
			color.color = nextColor
		}
	}

	private func updateHue(at location: CGPoint, animated: Bool) {
		let center = Self.diameter / 2
		let angle = atan2(location.y - center, location.x - center) * 180 / .pi
		let arcPosition = (Double(angle) - arcStart + 360).truncatingRemainder(dividingBy: 360)
		if arcPosition <= arcLength {
			setHue(arcPosition / arcLength, animated: animated)
		} else {
			let gapPosition = arcPosition - arcLength
			setHue(gapPosition < (360 - arcLength) / 2 ? 1 : 0, animated: false)
		}
	}

	private func setHue(_ newHue: Double, animated: Bool) {
		let current = SVFieldRenderer.hsv(color)
		let nextHue = min(max(newHue, 0), 1)
		let nextColor = Color(hue: nextHue, saturation: current.saturation, brightness: current.value)
		if animated {
			withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
				hue = nextHue
				color.color = nextColor
			}
		} else {
			withTransaction(Transaction(animation: nil)) {
				hue = nextHue
				color.color = nextColor
			}
		}
	}

	private func adjust(saturation: Double, value: Double) {
		let current = SVFieldRenderer.hsv(color)
		color.color = Color(
			hue: hue,
			saturation: min(max(current.saturation + saturation, 0), 1),
			brightness: min(max(current.value + value, 0), 1)
		)
	}
}

private struct SVFieldView: View {
	@Binding var color: BrowserColor
	var fieldImage: CGImage?
	var expansion: CGFloat
	var openingScale: CGFloat
	var fieldSize: CGFloat
	var diameter: CGFloat
	var onSaturationValue: (CGPoint, Bool) -> Void
	var onAdjustSaturationValue: (Double, Double) -> Void

	var body: some View {
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
		.gesture(colorDrag.simultaneously(with: colorTap))
		.accessibilityLabel("Saturation and brightness")
		.accessibilityHint("Drag within the circle to choose a color")
		.accessibilityIdentifier("theme-point-color-field")
		.accessibilityValue("Saturation \(Int(SVFieldRenderer.hsv(color).saturation * 100)) percent, brightness \(Int(SVFieldRenderer.hsv(color).value * 100)) percent")
		.accessibilityAction(named: "Increase saturation") { onAdjustSaturationValue(0.05, 0) }
		.accessibilityAction(named: "Decrease saturation") { onAdjustSaturationValue(-0.05, 0) }
		.accessibilityAction(named: "Increase brightness") { onAdjustSaturationValue(0, 0.05) }
		.accessibilityAction(named: "Decrease brightness") { onAdjustSaturationValue(0, -0.05) }
	}

	private var colorDrag: some Gesture {
		DragGesture(minimumDistance: 1, coordinateSpace: .named("theme-color-picker"))
			.onChanged { onSaturationValue($0.location, false) }
	}

	private var colorTap: some Gesture {
		SpatialTapGesture(coordinateSpace: .named("theme-color-picker"))
			.onEnded { onSaturationValue($0.location, true) }
	}
}

private struct HueArcView: View {
	var hue: Double
	var expansion: CGFloat
	var openingScale: CGFloat
	var arcStart: Double
	var arcLength: Double
	var diameter: CGFloat
	var onUpdateHue: (CGPoint, Bool) -> Void
	var onSetHue: (Double, Bool) -> Void

	var body: some View {
		hueArc
			.scaleEffect(openingScale)
			.opacity(expansion)
			.blur(radius: (1 - expansion) * 9)
			.gesture(hueDrag.simultaneously(with: hueTap))
			.accessibilityLabel("Hue")
			.accessibilityValue("\(Int(hue * 360)) degrees")
			.accessibilityIdentifier("theme-point-hue-arc")
			.accessibilityAdjustableAction { direction in
				switch direction {
					case .increment: onSetHue(hue + 0.02, true)
					case .decrement: onSetHue(hue - 0.02, true)
					@unknown default: break
				}
			}
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
					.saturation(1.2)
					.allowsHitTesting(false)
			}
			.frame(width: diameter, height: diameter)
			.contentShape(arcShape)
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

	private var hueDrag: some Gesture {
		DragGesture(minimumDistance: 1, coordinateSpace: .named("theme-color-picker"))
			.onChanged { onUpdateHue($0.location, false) }
	}

	private var hueTap: some Gesture {
		SpatialTapGesture(coordinateSpace: .named("theme-color-picker"))
			.onEnded { onUpdateHue($0.location, true) }
	}
}

private struct HueDeleteButton: View {
	var arcRadius: CGFloat
	var expansion: CGFloat
	var openingScale: CGFloat
	var onDelete: () -> Void

	var body: some View {
		Button {
			onDelete()
		} label: {
			Label("Delete color point", systemImage: "trash")
				.font(.caption)
				.labelStyle(.iconOnly)
				.frame(width: 22, height: 22)
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
}

private struct PickerTickShape: View {
	var size: CGFloat

	var body: some View {
		Circle()
			.fill(.clear)
			.frame(width: size, height: size)
			.glassEffect(.clear.interactive(), in: Circle())
			.glassEffectTransition(.materialize)
	}
}

private struct InnerTickView: View {
	var selectionOffset: CGSize
	var expansion: CGFloat
	var onSaturationValue: (CGPoint, Bool) -> Void

	var body: some View {
		PickerTickShape(size: 42)
			.offset(selectionOffset)
			.opacity(expansion)
			.gesture(
				DragGesture(minimumDistance: 1, coordinateSpace: .named("theme-color-picker"))
					.onChanged { onSaturationValue($0.location, false) }
			)
			.accessibilityHidden(true)
	}
}

private struct OuterTickView: View {
	var hueOffset: CGSize
	var expansion: CGFloat
	var openingScale: CGFloat
	var onUpdateHue: (CGPoint, Bool) -> Void

	var body: some View {
		PickerTickShape(size: 38)
			.offset(hueOffset)
			.opacity(expansion)
			.scaleEffect(openingScale)
			.blur(radius: (1 - expansion) * 9)
			.gesture(
				DragGesture(minimumDistance: 1, coordinateSpace: .named("theme-color-picker"))
					.onChanged { onUpdateHue($0.location, false) }
			)
			.accessibilityHidden(true)
	}
}
