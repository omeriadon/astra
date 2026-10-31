import SwiftUI
#if os(macOS)
	import AppKit
#endif

struct NewTabDitherSettingsView: View {
	@Binding var configuration: DitherConfiguration
	let theme: BrowserTheme
	@Environment(\.dismiss) private var dismiss
	@Environment(\.scenePhase) private var scenePhase
	@State private var draft: DitherConfiguration
	@State private var paletteText: String
	@State private var paletteError: String?

	init(configuration: Binding<DitherConfiguration>, theme: BrowserTheme) {
		_configuration = configuration
		self.theme = theme
		_draft = State(initialValue: configuration.wrappedValue)
		_paletteText = State(initialValue: configuration.wrappedValue.palette.map(Self.hex).joined(separator: ", "))
	}

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				DitherBackground(theme: theme, configuration: previewConfiguration, canAnimate: scenePhase == .active)
					.frame(height: 180)
					.clipShape(.rect(cornerRadius: 16))
					.padding()
					.accessibilityHidden(true)
				List {
					Section("Motion") {
						SliderRow(title: "Speed", value: $draft.waveSpeed, range: 0 ... 1)
						Picker("Direction", selection: Binding(get: {
							DitherConfiguration.compassDirection(for: draft.waveDirection)
						}, set: { direction in
							draft.waveDirection = Self.directionValue(direction)
						})) {
							ForEach(["N", "NE", "E", "SE", "S", "SW", "W", "NW"], id: \.self) { Text($0).tag($0) }
						}
						SliderRow(title: "Frequency", value: $draft.waveFrequency, range: 0.01 ... 12)
						SliderRow(title: "Amplitude", value: $draft.waveAmplitude, range: 0 ... 1)
						Toggle("Intro reveal", isOn: Binding(get: { draft.intro }, set: { draft.intro = $0 }))
						Toggle("Animation", isOn: Binding(get: { !draft.disableAnimation }, set: { draft.disableAnimation = !$0 }))
					}

					Section("Pattern") {
						Picker("Dither mode", selection: $draft.ditherMode) {
							ForEach(Array(zip(0 ... 7, ["Bayer", "Bayer 4", "Bayer 2", "Halftone", "Lines", "Crosshatch", "Noise", "None"])), id: \.0) { item in
								Text(item.1).tag(item.0)
							}
						}
						SliderRow(title: "Color levels", value: $draft.colorNum, range: 2 ... 16)
						SliderRow(title: "Strength", value: $draft.ditherStrength, range: 0 ... 1)
						SliderRow(title: "Pixel size", value: $draft.pixelSize, range: 1 ... 4096)
						SliderRow(title: "Gap", value: $draft.gap, range: 0 ... 0.45)
						SliderRow(title: "Corners", value: $draft.cornerRadius, range: 0 ... 0.5)
						Toggle("Join adjacent squares", isOn: $draft.joinAdjacentSquares)
					}

					Section("Color") {
						ColorPicker("Wave color", selection: colorBinding(for: \.waveColor), supportsOpacity: false)
						ColorPicker("Custom background", selection: colorBinding(for: \.backgroundColor), supportsOpacity: false)
						Toggle("Use Space theme colors", isOn: $draft.useThemeColors)
						Toggle("Multicolor palette", isOn: Binding(get: {
							Self.parsePalette(paletteText).colors.count > 1
						}, set: { enabled in
							if enabled {
								paletteText = paletteText.contains(",") ? paletteText : "#808080, #FFFFFF"
							} else {
								paletteText = paletteText.split(separator: ",").first.map(String.init) ?? "#808080"
							}
						}))
						TextField("Palette hex colors", text: $paletteText)
							.textFieldStyle(.roundedBorder)
							.accessibilityLabel("Palette hex colors")
							.accessibilityIdentifier("new-tab-dither-palette")
						if let paletteError {
							Text(paletteError)
								.font(.caption)
								.foregroundStyle(.red)
								.accessibilityLabel(paletteError)
						}
						Picker("Color placement", selection: $draft.colorPlacement) {
							Text("Squares").tag("squares")
							Text("Background").tag("background")
						}
						Picker("Background", selection: $draft.backgroundStyle) {
							Text("Custom").tag("custom")
							Text("Black").tag("black")
							Text("White").tag("white")
							Text("Dim").tag("dim")
						}
						Picker("Square color", selection: $draft.squareStyle) {
							Text("White").tag("white")
							Text("Black").tag("black")
						}
						SliderRow(title: "Scale", value: $draft.scale, range: 0.05 ... 32)
						SliderRow(title: "Contrast", value: $draft.contrast, range: 0.01 ... 8)
						SliderRow(title: "Brightness", value: $draft.brightness, range: -1 ... 1)
						SliderRow(title: "Opacity", value: $draft.opacity, range: 0 ... 1)
						Toggle("Transparent background", isOn: $draft.transparent)
						Toggle("Top blur", isOn: $draft.topBlur)
					}

					Section("Cursor") {
						Toggle("Enable cursor", isOn: $draft.cursorInteractionEnabled)
						SliderRow(title: "Radius", value: doubleBinding(for: \.cursorRadius), range: 0.05 ... 2)
						SliderRow(title: "Strength", value: doubleBinding(for: \.cursorStrength), range: -2 ... 2)
						SliderRow(title: "Response", value: doubleBinding(for: \.cursorResponse), range: 0.05 ... 1)
						SliderRow(title: "Trail", value: doubleBinding(for: \.cursorTrailDuration), range: 0 ... 2)
						SliderRow(title: "Fade", value: doubleBinding(for: \.cursorFadeDuration), range: 0.1 ... 3)
						SliderRow(title: "Warp", value: doubleBinding(for: \.cursorWarp), range: 0 ... 1)
					}
				}
			}
			.navigationTitle("Configure Dither")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) { dismiss() }
						.accessibilityLabel("Cancel dither changes")
						.accessibilityIdentifier("new-tab-dither-cancel")
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						var saved = draft
						saved.palette = validPalette
						configuration = saved.bounded()
						dismiss()
					} label: {
						Label("Save", systemImage: "checkmark")
					}
					.buttonStyle(.glassProminent)
					.disabled(paletteError != nil)
					.accessibilityLabel("Save dither settings")
					.accessibilityIdentifier("new-tab-dither-save")
				}
			}
		}
		.presentationDetents([.fraction(0.7)])
		.onChange(of: paletteText, initial: true) { _, _ in validatePalette() }
	}

	private var previewConfiguration: DitherConfiguration {
		var value = draft
		value.palette = validPalette
		return value.bounded()
	}

	private var validPalette: [SIMD3<Float>] {
		Self.parsePalette(paletteText).colors
	}

	private func validatePalette() {
		let result = Self.parsePalette(paletteText)
		paletteError = result.invalidCount == 0 ? nil : "Remove \(result.invalidCount) invalid palette color\(result.invalidCount == 1 ? "" : "s") before saving."
	}

	private func colorBinding(for keyPath: WritableKeyPath<DitherConfiguration, SIMD3<Float>>) -> Binding<Color> {
		Binding(
			get: { color(for: draft[keyPath: keyPath]) },
			set: { draft[keyPath: keyPath] = vector(for: $0, fallback: draft[keyPath: keyPath]) }
		)
	}

	private func doubleBinding(for keyPath: WritableKeyPath<DitherConfiguration, Double>) -> Binding<Float> {
		Binding(
			get: { Float(draft[keyPath: keyPath]) },
			set: { draft[keyPath: keyPath] = Double($0) }
		)
	}

	private func color(for value: SIMD3<Float>) -> Color {
		Color(.sRGB, red: Double(value.x), green: Double(value.y), blue: Double(value.z))
	}

	private func vector(for color: Color, fallback: SIMD3<Float>) -> SIMD3<Float> {
		#if os(macOS)
			guard let resolved = NSColor(color).usingColorSpace(.sRGB) else { return fallback }
			return SIMD3(Float(resolved.redComponent), Float(resolved.greenComponent), Float(resolved.blueComponent))
		#else
			return fallback
		#endif
	}

	private static func directionValue(_ direction: String) -> Float {
		Float(["N", "NE", "E", "SE", "S", "SW", "W", "NW"].firstIndex(of: direction) ?? 3) * 45
	}

	private static func parsePalette(_ text: String) -> (colors: [SIMD3<Float>], invalidCount: Int) {
		let values = text.split(separator: ",", omittingEmptySubsequences: false)
		var invalidCount = 0
		let colors = values.prefix(DitherConfiguration.supportedPaletteCount).compactMap { value -> SIMD3<Float>? in
			let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).replacing("#", with: "")
			guard !hex.isEmpty else { return nil }
			guard hex.count == 6, let number = UInt32(hex, radix: 16) else {
				invalidCount += 1
				return nil
			}
			return SIMD3(Float((number >> 16) & 255) / 255, Float((number >> 8) & 255) / 255, Float(number & 255) / 255)
		}
		if values.count > DitherConfiguration.supportedPaletteCount {
			invalidCount += values.count - DitherConfiguration.supportedPaletteCount
		}
		return (colors, invalidCount)
	}

	private static func hex(_ color: SIMD3<Float>) -> String {
		let red = Int((color.x * 255).rounded())
		let green = Int((color.y * 255).rounded())
		let blue = Int((color.z * 255).rounded())
		return "#\(component(red))\(component(green))\(component(blue))"
	}

	private static func component(_ value: Int) -> String {
		let text = String(value, radix: 16, uppercase: true)
		return text.count == 1 ? "0\(text)" : text
	}
}

private struct SliderRow: View {
	let title: String
	@Binding var value: Float
	let range: ClosedRange<Float>

	var body: some View {
		LabeledContent(title) {
			HStack {
				Slider(value: $value, in: range)
					.accessibilityLabel(title)
				TextField(title, value: $value, format: .number.precision(.fractionLength(0 ... 3)))
					.frame(width: 72)
					.accessibilityLabel("\(title) value")
			}
		}
		.accessibilityIdentifier("new-tab-dither-\(title.lowercased().replacing(" ", with: "-"))")
	}
}
