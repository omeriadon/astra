import Defaults
import SwiftUI

struct BrowserThemeEditorView: View {
	@Default(.browserTheme) private var theme
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			MeshGradientEditorView(theme: $theme)
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button(role: .confirm) {
							dismiss()
						} label: {
							Label("Done", systemImage: "checkmark")
						}
						.buttonStyle(.glassProminent)
						.accessibilityIdentifier("theme-editor-done")
					}
				}
		}
	}
}

private struct MeshGradientEditorView: View {
	@Binding var theme: BrowserTheme
	@State private var selectedPointID: UUID?

	private var selectedColor: Binding<Color>? {
		guard let selectedPointID else { return nil }
		return Binding(
			get: {
				theme.meshColorPoints.first(where: { $0.id == selectedPointID })?.color.color ?? .clear
			},
			set: { color in
				guard let index = theme.meshColorPoints.firstIndex(where: { $0.id == selectedPointID }) else { return }
				theme.meshColorPoints[index].color.color = color
			}
		)
	}

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

	var body: some View {
		VStack(spacing: 12) {
			#if os(macOS)
				Picker("Theme Appearance", selection: $theme.appearanceMode) {
					ForEach(ThemeAppearanceMode.allCases) { mode in
						Image(systemName: mode.symbol)
							.accessibilityLabel(mode.title)
							.tag(mode)
					}
				}
				.labelsHidden()
				.pickerStyle(.segmented)
				.accessibilityLabel("Theme appearance")
				.accessibilityIdentifier("theme-appearance-picker")
			#endif

			MeshGradientCanvas(
				theme: $theme,
				selectedPointID: $selectedPointID
			)
			.aspectRatio(1, contentMode: .fit)
			.clipShape(.rect(cornerRadius: 16))
			.accessibilityIdentifier("theme-mesh-editor")

			HStack(spacing: 18) {
				Button {
					guard let selectedPointID else { return }
					theme.removeMeshColorPoint(id: selectedPointID)
				} label: {
					Image(systemName: "minus")
				}
				.buttonStyle(.plain)
				.disabled(selectedPointID == nil || theme.meshColorPoints.isEmpty)
				.accessibilityLabel("Remove color point")
				.accessibilityIdentifier("theme-mesh-remove-point")

				if let selectedColor {
					ColorPicker("Selected color", selection: selectedColor, supportsOpacity: false)
						.labelsHidden()
						.accessibilityLabel("Selected color")
						.accessibilityIdentifier("theme-mesh-selected-color")
				} else {
					Image(systemName: "circle.fill")
						.hidden()
						.accessibilityHidden(true)
				}

				Button {
					selectedPointID = theme.addMeshColorPoint()
				} label: {
					Image(systemName: "plus")
				}
				.buttonStyle(.plain)
				.disabled(theme.meshColorPoints.count >= 3)
				.accessibilityLabel("Add color point")
				.accessibilityIdentifier("theme-mesh-add-point")
			}
			.frame(maxWidth: .infinity)

			HStack(spacing: 10) {
				Image(systemName: "circle.dotted.and.circle")
					.accessibilityHidden(true)
				Slider(value: $theme.meshOpacity, in: 0 ... 1)
					.accessibilityLabel("Translucency")
					.accessibilityValue(Text(theme.meshOpacity, format: .percent))
					.accessibilityIdentifier("theme-mesh-opacity")
			}

			HStack(spacing: 10) {
				Button {
					theme.shaderNoiseEnabled.toggle()
				} label: {
					Image(systemName: "circle.bottomhalf.filled.pattern.checkered")
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Noise")
				.accessibilityValue(theme.shaderNoiseEnabled ? "On" : "Off")
				.accessibilityIdentifier("theme-noise-toggle")

				Slider(value: normalizedNoiseAmount, in: 0 ... 1)
					.disabled(!theme.shaderNoiseEnabled)
					.accessibilityLabel("Noise amount")
					.accessibilityValue(Text(normalizedNoiseAmount.wrappedValue, format: .percent))
					.accessibilityIdentifier("theme-noise-amount")

				Toggle(isOn: monochromeNoise) {
					Image(systemName: "cloud.rain.crop")
				}
				.labelsHidden()
				.disabled(!theme.shaderNoiseEnabled)
				.accessibilityLabel("Monochrome noise")
				.accessibilityIdentifier("theme-noise-monochrome-toggle")
			}
		}
		.padding()
		.onAppear {
			selectedPointID = theme.meshColorPoints.first?.id
		}
		.onChange(of: theme.meshColorPoints.map(\.id)) { _, pointIDs in
			if let selectedPointID, pointIDs.contains(selectedPointID) {
				return
			}
			selectedPointID = pointIDs.first
		}
	}
}

private struct MeshGradientCanvas: View {
	@Binding var theme: BrowserTheme
	@Binding var selectedPointID: UUID?
	@State private var dragPointID: UUID?
	@State private var dragOrigin = CGPoint.zero
	@State private var dragStartedOnPoint = false

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .topLeading) {
				MeshGradientSurface(points: theme.meshColorPoints)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.opacity(theme.meshOpacity)

				ForEach(theme.meshColorPoints) { point in
					let pointIndex = theme.meshColorPoints.firstIndex(where: { $0.id == point.id }) ?? 0
					let isSelected = point.id == selectedPointID
					Button {
						selectedPointID = point.id
					} label: {
						Circle()
							.fill(point.color.color.opacity(0.35))
							.overlay {
								Circle()
									.strokeBorder(.white.opacity(0.9), lineWidth: 2)
							}
							.frame(width: isSelected ? 30 : 22, height: isSelected ? 30 : 22)
							.glassEffect(
								.clear.tint(point.color.color).interactive(),
								in: Circle()
							)
							.frame(width: 44, height: 44)
					}
					.buttonStyle(.plain)
					.position(
						x: CGFloat(point.x) * geometry.size.width,
						y: CGFloat(point.y) * geometry.size.height
					)
					.accessibilityLabel("Color point \(pointIndex + 1)")
					.accessibilityValue(isSelected ? "Selected" : "Not selected")
					.accessibilityIdentifier("theme-color-point-\(point.id.uuidString)")
					.accessibilityAction(named: "Move left") {
						theme.moveMeshColorPoint(
							id: point.id,
							to: CGPoint(x: CGFloat(point.x - 0.02), y: CGFloat(point.y))
						)
					}
					.accessibilityAction(named: "Move right") {
						theme.moveMeshColorPoint(
							id: point.id,
							to: CGPoint(x: CGFloat(point.x + 0.02), y: CGFloat(point.y))
						)
					}
					.accessibilityAction(named: "Move up") {
						theme.moveMeshColorPoint(
							id: point.id,
							to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y - 0.02))
						)
					}
					.accessibilityAction(named: "Move down") {
						theme.moveMeshColorPoint(
							id: point.id,
							to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y + 0.02))
						)
					}
				}
			}
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { value in
						movePoint(during: value, in: geometry.size)
					}
					.onEnded { value in
						if theme.meshColorPoints.isEmpty {
							let position = normalized(value.location, in: geometry.size)
							selectedPointID = theme.addMeshColorPoint(at: position)
						}
						dragPointID = nil
						dragStartedOnPoint = false
					}
			)
		}
	}

	private func movePoint(during value: DragGesture.Value, in size: CGSize) {
		guard size.width > 0, size.height > 0 else { return }
		if dragPointID == nil {
			let start = value.startLocation
			let hitPoint = theme.meshColorPoints.first { point in
				let pointLocation = CGPoint(
					x: CGFloat(point.x) * size.width,
					y: CGFloat(point.y) * size.height
				)
				return hypot(pointLocation.x - start.x, pointLocation.y - start.y) <= 24
			}
			if let hitPoint {
				dragPointID = hitPoint.id
				selectedPointID = hitPoint.id
				dragOrigin = CGPoint(x: hitPoint.x, y: hitPoint.y)
				dragStartedOnPoint = true
			} else if let selectedPointID,
			          let selectedPoint = theme.meshColorPoints.first(where: { $0.id == selectedPointID })
			{
				dragPointID = selectedPoint.id
				dragOrigin = CGPoint(x: selectedPoint.x, y: selectedPoint.y)
				dragStartedOnPoint = false
			}
		}

		guard let dragPointID else { return }
		let position: CGPoint = if dragStartedOnPoint {
			CGPoint(
				x: dragOrigin.x + value.translation.width / size.width,
				y: dragOrigin.y + value.translation.height / size.height
			)
		} else {
			normalized(value.location, in: size)
		}
		theme.moveMeshColorPoint(id: dragPointID, to: position)
	}

	private func normalized(_ position: CGPoint, in size: CGSize) -> CGPoint {
		CGPoint(x: position.x / size.width, y: position.y / size.height)
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
