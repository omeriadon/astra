import Defaults
import SwiftUI

struct BrowserThemeEditorView: View {
	@Default(.browserTheme) private var theme
	@State private var editingPointID: UUID?
	@State private var pickerDismissalSignal = 0

	var body: some View {
		VStack(spacing: 0) {
			Spacer(minLength: 0)
			MeshGradientEditorView(
				theme: $theme,
				editingPointID: $editingPointID,
				pickerDismissalSignal: $pickerDismissalSignal
			)
			.frame(maxWidth: 380)
			Spacer(minLength: 0)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.contentShape(Rectangle())
		.onTapGesture {
			if editingPointID != nil {
				pickerDismissalSignal += 1
			}
		}
	}
}

private struct MeshGradientEditorView: View {
	@Binding var theme: BrowserTheme
	@Binding var editingPointID: UUID?
	@Binding var pickerDismissalSignal: Int

	private var normalizedNoiseAmount: Binding<Double> {
		Binding(
			get: {
				theme.shaderNoiseEnabled
					? theme.shaderNoiseAmount / theme.shaderNoiseMaximumOpacity
					: 0
			},
			set: { position in
				theme.shaderNoiseEnabled = position > 0
				theme.shaderNoiseAmount = position * theme.shaderNoiseMaximumOpacity
			}
		)
	}

	private var monochromeNoise: Binding<Bool> {
		Binding(
			get: { theme.shaderNoiseMonochrome },
			set: { isMonochrome in
				let sliderPosition = normalizedNoiseAmount.wrappedValue
				theme.shaderNoiseMonochrome = isMonochrome
				theme.shaderNoiseAmount = sliderPosition * theme.shaderNoiseMaximumOpacity
			}
		)
	}

	private var translucency: Binding<Double> {
		Binding(
			get: { 1 - theme.meshOpacity },
			set: { theme.meshOpacity = 1 - $0 }
		)
	}

	var body: some View {
		VStack(spacing: 12) {
			MeshGradientCanvas(
				theme: $theme,
				editingPointID: $editingPointID,
				pickerDismissalSignal: $pickerDismissalSignal
			)
			.aspectRatio(1, contentMode: .fit)
			.zIndex(1)
			.overlay(alignment: .top) {
				GlassEffectContainer(spacing: 4) {
					if editingPointID == nil {
						HStack(spacing: 8) {
							ForEach(ThemeAppearanceMode.allCases) { mode in
								Button {
									withAnimation(.smooth(duration: 0.2)) {
										theme.appearanceMode = mode
									}
								} label: {
									Label(mode.title, systemImage: mode.symbol)
										.labelStyle(.iconOnly)
										.frame(width: 25, height: 25)
								}
								.buttonStyle(.glass(.clear))
								.buttonBorderShape(.circle)
								.tint(theme.appearanceMode == mode ? .white.opacity(0.3) : .clear)
								.glassEffectTransition(.materialize)
								.accessibilityAddTraits(theme.appearanceMode == mode ? .isSelected : [])
								.accessibilityIdentifier("theme-appearance-\(mode.rawValue)")
							}
						}
						.transition(.opacity.combined(with: .scale(scale: 0.7)))
					}
				}
				.padding(12)
				.animation(.smooth(duration: 0.2), value: editingPointID)
			}
			.overlay(alignment: .bottom) {
				GlassEffectContainer(spacing: 4) {
					if theme.meshColorPoints.count < 4, editingPointID == nil {
						Button {
							withAnimation(.smooth(duration: 0.2)) {
								_ = theme.addMeshColorPoint()
							}
						} label: {
							Label("Add color point", systemImage: "plus")
								.labelStyle(.iconOnly)
								.frame(width: 25, height: 25)
						}
						.buttonStyle(.glass(.clear.interactive()))
						.buttonBorderShape(.circle)
						.glassEffectTransition(.materialize)
						.accessibilityIdentifier("theme-mesh-add-point")
					}
				}
				.frame(width: 44, height: 44)
				.padding(12)
				.animation(.smooth(duration: 0.2), value: theme.meshColorPoints.count)
				.animation(.smooth(duration: 0.2), value: editingPointID)
			}
			.accessibilityIdentifier("theme-mesh-editor")

			#if os(macOS)
				ThemeControlSlider(
					value: translucency,
					label: "Translucency",
					symbol: "circle.dotted.and.circle",
					identifier: "theme-window-translucency",
					tickCount: 7
				)
				.padding(.horizontal, -23)
				.allowsHitTesting(editingPointID == nil)
			#endif

			GeometryReader { geometry in
				ZStack(alignment: .topLeading) {
					ThemeControlSlider(
						value: normalizedNoiseAmount,
						label: "Noise amount",
						symbol: "app.background.dotted",
						identifier: "theme-noise-amount",
						tickCount: 6
					)
					.frame(width: (geometry.size.width - 28) * 5 / 6 + 74)
					.offset(x: -23)

					Button {
						withAnimation(.smooth(duration: 0.2)) {
							monochromeNoise.wrappedValue.toggle()
						}
					} label: {
						Label(
							"Monochrome noise",
							systemImage: theme.shaderNoiseMonochrome ? "lightspectrum.horizontal" : "circle"
						)
						.font(.system(size: 20, weight: .medium))
						.labelStyle(.iconOnly)
						.frame(width: 34, height: 34)
					}
					.buttonStyle(.glass)
					.buttonBorderShape(.circle)
					.tint(theme.shaderNoiseMonochrome ? theme.tabColor.opacity(0.8) : .clear)
					.accessibilityValue(theme.shaderNoiseMonochrome ? "On" : "Off")
					.accessibilityIdentifier("theme-noise-monochrome-toggle")
					.animation(.smooth(duration: 0.2), value: theme.shaderNoiseMonochrome)
					.position(x: geometry.size.width - 17, y: 23)
				}
			}
			.frame(height: 46)
			.allowsHitTesting(editingPointID == nil)
		}
		.padding(.horizontal, 12)
		.padding(.top, 12)
		.padding(.bottom)
		.containerShape(.rect(cornerRadius: 36))
		.onChange(of: theme.meshColorPoints.map(\.id)) { _, ids in
			if let editingPointID, !ids.contains(editingPointID) {
				self.editingPointID = nil
			}
		}
	}
}

private struct ThemeControlSlider: View {
	@Binding var value: Double
	let label: String
	let symbol: String
	let identifier: String
	let tickCount: Int
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var isDragging = false

	private let thumbSize: CGFloat = 46

	var body: some View {
		GeometryReader { geometry in
			let trackWidth = max(geometry.size.width - thumbSize, 1)
			let tickInset: CGFloat = 11
			let drag = DragGesture(minimumDistance: 1, coordinateSpace: .named("theme-control-slider"))
				.onChanged { gesture in
					isDragging = true
					value = min(max(Double((gesture.location.x - thumbSize / 2) / trackWidth), 0), 1)
				}
				.onEnded { _ in
					isDragging = false
				}
			ZStack(alignment: .leading) {
				Capsule()
					.fill(.white.opacity(0.18))
					.frame(width: trackWidth, height: 20)
					.overlay(alignment: .leading) {
						Capsule()
							.fill(.white.opacity(0.24))
							.frame(width: max(CGFloat(value) * trackWidth, 1), height: 20)
					}
					.overlay {
						ForEach(0 ..< tickCount, id: \.self) { index in
							Circle()
								.fill(.white.opacity(0.6))
								.frame(width: 3, height: 3)
								.position(
									x: tickInset + CGFloat(index) * (trackWidth - 2 * tickInset) / CGFloat(tickCount - 1),
									y: 10
								)
						}
					}
					.offset(x: thumbSize / 2)
					.contentShape(Rectangle())
					.onTapGesture(coordinateSpace: .named("theme-control-slider")) { location in
						value = min(max(Double((location.x - thumbSize / 2) / trackWidth), 0), 1)
					}

				Image(systemName: symbol)
					.font(.system(size: 17, weight: .medium))
					.frame(width: thumbSize, height: thumbSize)
					.glassEffect(.regular.tint(.white.opacity(0.18)).interactive(), in: Circle())
					.contentShape(Circle())
					.position(
						x: thumbSize / 2 + CGFloat(value) * trackWidth,
						y: thumbSize / 2
					)
					.zIndex(1)
			}
			.frame(width: geometry.size.width, height: thumbSize)
			.contentShape(Rectangle())
			.gesture(drag)
			.animation(reduceMotion || isDragging ? nil : .smooth(duration: 0.2), value: value)
			.coordinateSpace(name: "theme-control-slider")
		}
		.frame(height: thumbSize)
		.accessibilityElement()
		.accessibilityLabel(label)
		.accessibilityValue(Text(value, format: .percent))
		.accessibilityAdjustableAction { direction in
			switch direction {
				case .increment: value = min(value + 0.05, 1)
				case .decrement: value = max(value - 0.05, 0)
				@unknown default: break
			}
		}
		.accessibilityIdentifier(identifier)
	}
}

private struct MeshGradientCanvas: View {
	@Binding var theme: BrowserTheme
	@Binding var editingPointID: UUID?
	@Binding var pickerDismissalSignal: Int
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var dragPointID: UUID?
	@State private var dragOrigin = CGPoint.zero

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .topLeading) {
				MeshGradientSurface(points: theme.meshColorPoints)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.overlay {
						ZStack {
							Canvas { context, size in
								for x in stride(from: CGFloat(11), to: size.width, by: 22) {
									for y in stride(from: CGFloat(11), to: size.height, by: 22) {
										let dot = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
										context.fill(dot, with: .color(.white.opacity(0.2)))
									}
								}
							}
							.allowsHitTesting(false)
							.accessibilityHidden(true)
						}
						.padding([.top, .leading], 3)
						.padding([.bottom, .trailing], 2)
					}
					.clipShape(ContainerRelativeShape())
					.contentShape(Rectangle())
					.onTapGesture(coordinateSpace: .local) { location in
						if editingPointID != nil {
							pickerDismissalSignal += 1
							return
						}
						if theme.meshColorPoints.isEmpty {
							_ = theme.addMeshColorPoint(at: normalized(location, in: geometry.size))
							return
						}
						guard theme.meshColorPoints.count == 1,
						      let point = theme.meshColorPoints.first else { return }
						withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.45)) {
							theme.moveMeshColorPoint(id: point.id, to: normalized(location, in: geometry.size))
						}
					}

				ForEach(theme.meshColorPoints) { point in
					let pointIndex = theme.meshColorPoints.firstIndex(where: { $0.id == point.id }) ?? 0
					let pointPosition = CGPoint(
						x: CGFloat(point.x) * geometry.size.width,
						y: CGFloat(point.y) * geometry.size.height
					)
					if editingPointID == point.id {
						let target = pickerCenter(for: point, in: geometry.size)
						CircularThemeColorPicker(
							color: colorBinding(for: point.id),
							dismissalSignal: pickerDismissalSignal,
							centerShift: CGSize(
								width: target.x - pointPosition.x,
								height: target.y - pointPosition.y
							),
							onClose: {
								if editingPointID == point.id {
									withAnimation(reduceMotion ? nil : .smooth(duration: 0.15)) {
										editingPointID = nil
									}
								}
							},
							onDelete: {
								withAnimation(.smooth(duration: 0.2)) {
									theme.removeMeshColorPoint(id: point.id)
									if editingPointID == point.id {
										editingPointID = nil
									}
								}
							}
						)
						.position(pointPosition)
						.zIndex(1)
					} else {
						Button {
							withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.66)) {
								editingPointID = point.id
							}
						} label: {
							Image(systemName: "circle.fill")
								.font(.system(size: 22))
								.foregroundStyle(point.color.color)
								.frame(width: 25, height: 25)
						}
						.buttonStyle(.glass(.clear))
						.buttonBorderShape(.circle)
						.tint(point.color.color.opacity(0.4))
						.glassEffectTransition(.materialize)
						.opacity(editingPointID == nil ? 1 : 0)
						.scaleEffect(editingPointID == nil ? 1 : 0.65)
						.allowsHitTesting(editingPointID == nil)
						.animation(.smooth(duration: 0.2), value: editingPointID)
						.highPriorityGesture(
							DragGesture(minimumDistance: 3, coordinateSpace: .named("theme-mesh-canvas"))
								.onChanged { value in
									if dragPointID != point.id {
										dragPointID = point.id
										dragOrigin = CGPoint(x: point.x, y: point.y)
									}
									theme.moveMeshColorPoint(
										id: point.id,
										to: CGPoint(
											x: dragOrigin.x + value.translation.width / geometry.size.width,
											y: dragOrigin.y + value.translation.height / geometry.size.height
										)
									)
								}
								.onEnded { _ in dragPointID = nil }
						)
						.position(pointPosition)
						.accessibilityLabel("Color point \(pointIndex + 1)")
						.accessibilityHint("Drag to move. Click to change color.")
						.accessibilityIdentifier("theme-color-point-\(point.id.uuidString)")
						.accessibilityAction(named: "Move left") {
							theme.moveMeshColorPoint(id: point.id, to: CGPoint(x: point.x - 0.02, y: point.y))
						}
						.accessibilityAction(named: "Move right") {
							theme.moveMeshColorPoint(id: point.id, to: CGPoint(x: point.x + 0.02, y: point.y))
						}
						.accessibilityAction(named: "Move up") {
							theme.moveMeshColorPoint(id: point.id, to: CGPoint(x: point.x, y: point.y - 0.02))
						}
						.accessibilityAction(named: "Move down") {
							theme.moveMeshColorPoint(id: point.id, to: CGPoint(x: point.x, y: point.y + 0.02))
						}
					}
				}
			}
			.coordinateSpace(name: "theme-mesh-canvas")
		}
	}

	private func normalized(_ position: CGPoint, in size: CGSize) -> CGPoint {
		CGPoint(x: position.x / size.width, y: position.y / size.height)
	}

	private func pickerCenter(for point: ThemeColorPoint, in size: CGSize) -> CGPoint {
		let margin = min(CircularThemeColorPicker.diameter / 2, size.width / 2, size.height / 2)
		return CGPoint(
			x: min(max(CGFloat(point.x) * size.width, margin), size.width - margin),
			y: min(max(CGFloat(point.y) * size.height, margin), size.height - margin)
		)
	}

	private func colorBinding(for id: UUID) -> Binding<BrowserColor> {
		Binding(
			get: { theme.meshColorPoints.first(where: { $0.id == id })?.color ?? BrowserColor(red: 0, green: 0, blue: 0) },
			set: { color in
				guard let index = theme.meshColorPoints.firstIndex(where: { $0.id == id }) else { return }
				theme.meshColorPoints[index].color = color
			}
		)
	}
}

struct MeshGradientSurface: View {
	let points: [ThemeColorPoint]
	private static let meshLocations: [SIMD2<Float>] = (0 ..< 100).map { index in
		SIMD2<Float>(Float(index % 10) / 9, Float(index / 10) / 9)
	}

	var body: some View {
		if points.isEmpty {
			Color.clear
		} else {
			MeshGradient(
				width: 10,
				height: 10,
				points: Self.meshLocations,
				colors: meshColors,
				background: .clear,
				smoothsColors: true
			)
		}
	}

	private var meshColors: [Color] {
		Self.meshLocations.map { location in
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
