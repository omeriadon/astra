import Defaults
import SwiftUI

struct BrowserThemeEditorView: View {
	@Default(.browserTheme) private var theme
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(spacing: 0) {
			MeshGradientEditorView(theme: $theme)

			Button(role: .confirm) {
				dismiss()
			} label: {
				Label("Done", systemImage: "checkmark")
			}
			.buttonStyle(.glassProminent)
			.accessibilityIdentifier("theme-editor-done")
			.frame(maxWidth: .infinity, alignment: .trailing)
			.padding(.horizontal, 12)
			.padding(.bottom, 12)
		}
		.containerShape(.rect(cornerRadius: 24))
	}
}

private struct MeshGradientEditorView: View {
	@Binding var theme: BrowserTheme

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
			MeshGradientCanvas(theme: $theme)
				.aspectRatio(1, contentMode: .fit)
				.clipShape(ContainerRelativeShape())
				.overlay(alignment: .top) {
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
						.frame(width: 110)
						.padding(12)
						.accessibilityLabel("Theme appearance")
						.accessibilityIdentifier("theme-appearance-picker")
					#endif
				}
				.overlay(alignment: .bottom) {
					HStack(spacing: 24) {
						Button("Remove color point", systemImage: "minus") {
							theme.meshColorPoints.removeLast()
						}
						.labelStyle(.iconOnly)
						.buttonStyle(.bordered)
						.disabled(theme.meshColorPoints.isEmpty)
						.accessibilityIdentifier("theme-mesh-remove-point")

						Button("Add color point", systemImage: "plus") {
							_ = theme.addMeshColorPoint()
						}
						.labelStyle(.iconOnly)
						.buttonStyle(.bordered)
						.disabled(theme.meshColorPoints.count >= 3)
						.accessibilityIdentifier("theme-mesh-add-point")
					}
					.padding(12)
				}
				.accessibilityIdentifier("theme-mesh-editor")

			#if os(macOS)
				HStack(spacing: 10) {
					Image(systemName: "circle.dotted.and.circle")
						.accessibilityHidden(true)
					Slider(value: translucency, in: 0 ... 1)
						.accessibilityLabel("Translucency")
						.accessibilityValue(Text(translucency.wrappedValue, format: .percent))
						.accessibilityIdentifier("theme-window-translucency")
				}
			#endif

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
		.padding(.horizontal, 12)
		.padding(.top, 12)
		.padding(.bottom)
	}
}

private struct MeshGradientCanvas: View {
	@Binding var theme: BrowserTheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var colorPointID: UUID?
	@State private var dragPointID: UUID?
	@State private var dragOrigin = CGPoint.zero

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .topLeading) {
				MeshGradientSurface(points: theme.meshColorPoints)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.contentShape(Rectangle())
					.onTapGesture(coordinateSpace: .local) { location in
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
					Button {
						colorPointID = point.id
					} label: {
						Circle()
							.fill(point.color.color.opacity(0.35))
							.overlay {
								Circle()
									.strokeBorder(.white.opacity(0.9), lineWidth: 2)
							}
							.frame(width: 24, height: 24)
							.glassEffect(
								.clear.tint(point.color.color).interactive(),
								in: Circle()
							)
							.frame(width: 44, height: 44)
					}
					.buttonStyle(.plain)
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
					.position(
						x: CGFloat(point.x) * geometry.size.width,
						y: CGFloat(point.y) * geometry.size.height
					)
					.accessibilityLabel("Color point \(pointIndex + 1)")
					.accessibilityHint("Drag to move. Click to change color.")
					.accessibilityIdentifier("theme-color-point-\(point.id.uuidString)")
					#if os(macOS)
						.background {
							FloatingThemeColorWheel(
								isPresented: colorPresentation(for: point.id),
								color: colorBinding(for: point.id)
							)
							.allowsHitTesting(false)
						}
					#else
						.popover(isPresented: colorPresentation(for: point.id)) {
							ThemePointColorWheel(color: colorBinding(for: point.id))
								.padding(12)
								.presentationCompactAdaptation(.popover)
						}
					#endif
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
			.coordinateSpace(name: "theme-mesh-canvas")
		}
	}

	private func normalized(_ position: CGPoint, in size: CGSize) -> CGPoint {
		CGPoint(x: position.x / size.width, y: position.y / size.height)
	}

	private func colorPresentation(for id: UUID) -> Binding<Bool> {
		Binding(
			get: { colorPointID == id },
			set: {
				if !$0 {
					colorPointID = nil
				}
			}
		)
	}

	private func colorBinding(for id: UUID) -> Binding<Color> {
		Binding(
			get: { theme.meshColorPoints.first(where: { $0.id == id })?.color.color ?? .clear },
			set: { color in
				guard let index = theme.meshColorPoints.firstIndex(where: { $0.id == id }) else { return }
				theme.meshColorPoints[index].color.color = color
			}
		)
	}
}

#if os(macOS)
	private struct FloatingThemeColorWheel: NSViewRepresentable {
		@Binding var isPresented: Bool
		@Binding var color: Color

		func makeNSView(context _: Context) -> ThemeWheelAnchorView {
			ThemeWheelAnchorView()
		}

		func updateNSView(_ nsView: ThemeWheelAnchorView, context: Context) {
			let coordinator = context.coordinator
			nsView.onLayout = { [weak nsView, weak coordinator] in
				guard let nsView else { return }
				coordinator?.reposition(anchor: nsView)
			}
			coordinator.update(
				anchor: nsView,
				isPresented: isPresented,
				color: $color,
				onDismiss: { isPresented = false }
			)
		}

		func makeCoordinator() -> Coordinator {
			Coordinator()
		}

		static func dismantleNSView(_: ThemeWheelAnchorView, coordinator: Coordinator) {
			coordinator.close()
		}

		final class Coordinator: NSObject {
			private weak var parent: NSWindow?
			private var panel: ThemeColorPanel?
			private var mouseMonitor: Any?
			private var onDismiss: (() -> Void)?
			private let panelSize = NSSize(width: 184, height: 216)

			func update(
				anchor: NSView,
				isPresented: Bool,
				color: Binding<Color>,
				onDismiss: @escaping () -> Void
			) {
				self.onDismiss = onDismiss
				guard isPresented, let window = anchor.window else {
					close()
					return
				}
				if panel == nil {
					let panel = ThemeColorPanel(
						contentRect: NSRect(origin: .zero, size: panelSize),
						styleMask: [.borderless, .nonactivatingPanel],
						backing: .buffered,
						defer: false
					)
					panel.isOpaque = false
					panel.backgroundColor = .clear
					panel.hasShadow = true
					panel.contentView = NSHostingView(rootView: ThemePointColorWheel(color: color)
						.padding(12)
						.background(.regularMaterial, in: .rect(cornerRadius: 24)))
					window.addChildWindow(panel, ordered: .above)
					panel.orderFront(nil)
					parent = window
					self.panel = panel
					mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
						if event.window !== panel {
							self?.onDismiss?()
						}
						return event
					}
				}
				reposition(anchor: anchor)
			}

			func reposition(anchor: NSView) {
				guard let panel, let parent, anchor.window === parent else { return }
				let anchorFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
				let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorFrame
				let origin = NSPoint(
					x: min(max(anchorFrame.midX - panelSize.width / 2, visibleFrame.minX), visibleFrame.maxX - panelSize.width),
					y: min(max(anchorFrame.midY - panelSize.height / 2, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
				)
				panel.setFrameOrigin(origin)
			}

			func close() {
				if let mouseMonitor {
					NSEvent.removeMonitor(mouseMonitor)
					self.mouseMonitor = nil
				}
				if let panel {
					parent?.removeChildWindow(panel)
					panel.close()
					self.panel = nil
				}
				parent = nil
			}
		}
	}

	private final class ThemeWheelAnchorView: NSView {
		var onLayout: (() -> Void)?

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			onLayout?()
		}

		override func layout() {
			super.layout()
			onLayout?()
		}
	}

	private final class ThemeColorPanel: NSPanel {
		override var canBecomeKey: Bool {
			true
		}

		override var canBecomeMain: Bool {
			false
		}
	}
#endif

private struct ThemePointColorWheel: View {
	@Binding var color: Color

	private var components: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
		var hue: CGFloat = 0
		var saturation: CGFloat = 0
		var brightness: CGFloat = 0
		var alpha: CGFloat = 0
		#if os(macOS)
			let platformColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
			platformColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
		#else
			_ = UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
		#endif
		return (hue, saturation, brightness)
	}

	var body: some View {
		VStack(spacing: 10) {
			GeometryReader { geometry in
				let radius = geometry.size.width / 2
				let angle = components.hue * 2 * .pi
				ZStack {
					Circle()
						.fill(AngularGradient(
							colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
							center: .center
						))
						.overlay {
							Circle()
								.fill(RadialGradient(
									colors: [.white, .white.opacity(0)],
									center: .center,
									startRadius: 0,
									endRadius: radius
								))
						}
						.gesture(
							DragGesture(minimumDistance: 0)
								.onChanged { value in
									let dx = value.location.x - radius
									let dy = value.location.y - radius
									let hue = (atan2(dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
									let saturation = min(hypot(dx, dy) / radius, 1)
									color = Color(
										hue: Double(hue),
										saturation: Double(saturation),
										brightness: Double(components.brightness)
									)
								}
						)

					Circle()
						.fill(color)
						.frame(width: 16, height: 16)
						.overlay { Circle().strokeBorder(.white, lineWidth: 2) }
						.shadow(radius: 2)
						.position(
							x: radius + cos(angle) * components.saturation * radius,
							y: radius + sin(angle) * components.saturation * radius
						)
						.allowsHitTesting(false)
				}
			}
			.frame(width: 160, height: 160)
			.accessibilityLabel("Color wheel")
			.accessibilityHint("Drag to change hue and saturation")
			.accessibilityIdentifier("theme-point-color-wheel")

			Slider(value: Binding(
				get: { Double(components.brightness) },
				set: {
					color = Color(
						hue: Double(components.hue),
						saturation: Double(components.saturation),
						brightness: $0
					)
				}
			), in: 0 ... 1)
				.accessibilityLabel("Color brightness")
				.accessibilityIdentifier("theme-point-color-brightness")
		}
		.frame(width: 160)
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
