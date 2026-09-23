import Defaults
import SwiftUI

struct BrowserThemeEditorView: View {
	@Default(.browserTheme) private var theme

	var body: some View {
		VStack(spacing: 0) {
			Spacer(minLength: 0)
			MeshGradientEditorView(theme: $theme)
				.frame(maxWidth: 380)
			Spacer(minLength: 0)
		}
	}
}

private struct MeshGradientEditorView: View {
	@Binding var theme: BrowserTheme
	@State private var editingPointID: UUID?

	private var normalizedNoiseAmount: Binding<Double> {
		Binding(
			get: {
				theme.shaderNoiseAmount / theme.shaderNoiseMaximumOpacity
			},
			set: { position in
				theme.shaderNoiseAmount = position * theme.shaderNoiseMaximumOpacity
			}
		)
	}

	private var monochromeNoise: Binding<Bool> {
		Binding(
			get: { theme.shaderNoiseMonochrome },
			set: { isMonochrome in
				let sliderPosition = theme.shaderNoiseAmount / theme.shaderNoiseMaximumOpacity
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
			MeshGradientCanvas(theme: $theme, editingPointID: $editingPointID)
				.aspectRatio(1, contentMode: .fit)
				.zIndex(1)
				.overlay(alignment: .top) {
					HStack(spacing: 8) {
						ForEach(ThemeAppearanceMode.allCases) { mode in
							Button {
								withAnimation(.smooth(duration: 0.1)) {
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
							.accessibilityAddTraits(theme.appearanceMode == mode ? .isSelected : [])
							.accessibilityIdentifier("theme-appearance-\(mode.rawValue)")
						}
					}
					.padding(12)
					.opacity(editingPointID == nil ? 1 : 0)
					.allowsHitTesting(editingPointID == nil)
				}
				.overlay(alignment: .bottom) {
					GlassEffectContainer(spacing: 4) {
						if theme.meshColorPoints.count < 3, editingPointID == nil {
							Button {
								withAnimation(.smooth(duration: 0.2)) {
									_ = theme.addMeshColorPoint()
								}
							} label: {
								Label("Add color point", systemImage: "plus")
									.labelStyle(.iconOnly)
									.frame(width: 44, height: 44)
							}
							.buttonStyle(.glass)
							.buttonBorderShape(.circle)
							.glassEffectTransition(.materialize)
							.transition(.opacity.combined(with: .scale(scale: 0.5)))
							.accessibilityIdentifier("theme-mesh-add-point")
						}
					}
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
					identifier: "theme-window-translucency"
				)
			#endif

			HStack(spacing: 10) {
				Button {
					theme.shaderNoiseEnabled.toggle()
				} label: {
					Label("Noise", systemImage: "circle.bottomhalf.filled.pattern.checkered")
						.labelStyle(.iconOnly)
						.frame(width: 46, height: 46)
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.tint(theme.shaderNoiseEnabled ? theme.tabColor.opacity(0.45) : .clear)
				.accessibilityValue(theme.shaderNoiseEnabled ? "On" : "Off")
				.accessibilityIdentifier("theme-noise-toggle")

				Button {
					monochromeNoise.wrappedValue.toggle()
				} label: {
					Label(
						"Monochrome noise",
						systemImage: theme.shaderNoiseMonochrome ? "lightspectrum.horizontal" : "cloud.rain.crop"
					)
					.labelStyle(.iconOnly)
					.frame(width: 46, height: 46)
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.tint(theme.shaderNoiseEnabled && theme.shaderNoiseMonochrome ? theme.tabColor.opacity(0.8) : .clear)
				.accessibilityValue(theme.shaderNoiseMonochrome ? "On" : "Off")
				.accessibilityIdentifier("theme-noise-monochrome-toggle")

				ThemeControlSlider(
					value: normalizedNoiseAmount,
					label: "Noise amount",
					symbol: "circle.bottomhalf.filled.pattern.checkered",
					identifier: "theme-noise-amount"
				)
			}
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

	private let thumbSize: CGFloat = 46

	var body: some View {
		GeometryReader { geometry in
			let trackWidth = max(geometry.size.width - thumbSize, 1)
			ZStack(alignment: .leading) {
				Capsule()
					.fill(.white.opacity(0.18))
					.frame(width: trackWidth, height: 20)
					.overlay(alignment: .leading) {
						Capsule()
							.fill(.white.opacity(0.24))
							.frame(width: max(CGFloat(value) * trackWidth, 1), height: 20)
					}
					.offset(x: thumbSize / 2)

				Image(systemName: symbol)
					.font(.system(size: 17, weight: .medium))
					.frame(width: thumbSize, height: thumbSize)
					.glassEffect(.regular.interactive(), in: Circle())
					.offset(x: CGFloat(value) * trackWidth)
			}
			.frame(height: thumbSize)
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0, coordinateSpace: .named("theme-control-slider"))
					.onChanged { gesture in
						value = min(max(Double((gesture.location.x - thumbSize / 2) / trackWidth), 0), 1)
					}
			)
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
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var pickerDismissalSignal = 0
	@State private var dragPointID: UUID?
	@State private var dragOrigin = CGPoint.zero

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .topLeading) {
				MeshGradientSurface(points: theme.meshColorPoints)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.overlay {
						Canvas { context, size in
							for x in stride(from: CGFloat(11), to: size.width, by: 22) {
								for y in stride(from: CGFloat(11), to: size.height, by: 22) {
									let dot = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
									context.fill(dot, with: .color(.white.opacity(0.2)))
								}
							}
						}
						.padding([.top, .leading], 10)
						.padding([.bottom, .trailing], 6)
						.allowsHitTesting(false)
						.accessibilityHidden(true)
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
							)
						) {
							if editingPointID == point.id {
								editingPointID = nil
							}
						}
						.position(pointPosition)
						.zIndex(1)
					} else {
						Button {
							editingPointID = point.id
						} label: {
							Image(systemName: "circle.fill")
								.font(.system(size: 22))
								.foregroundStyle(point.color.color)
								.frame(width: 25, height: 25)
						}
						.buttonStyle(.glass(.clear))
						.buttonBorderShape(.circle)
						.tint(point.color.color.opacity(0.4))
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

	private let meshLocations: [SIMD2<Float>] = [
		.init(0, 0), .init(0.5, 0), .init(1, 0),
		.init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
		.init(0, 1), .init(0.5, 1), .init(1, 1),
	]

	var body: some View {
		if points.isEmpty {
			Color.clear
		} else {
			MeshGradient(
				width: 3,
				height: 3,
				points: meshLocations,
				colors: meshColors,
				background: .clear,
				smoothsColors: true
			)
		}
	}

	private var meshColors: [Color] {
		meshLocations.map { location in
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
