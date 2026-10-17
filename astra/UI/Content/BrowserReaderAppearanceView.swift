import Defaults
import SwiftUI

struct BrowserReaderAppearanceView: View {
	@Default(.readerAppearance) private var appearance
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List {
				Section("Font") {
					Picker("Typeface", selection: $appearance.font) {
						ForEach(BrowserReaderAppearance.Font.allCases) { font in
							Text(font.rawValue).tag(font)
						}
					}
					.accessibilityIdentifier("reader-font-picker")

					VStack(alignment: .leading) {
						HStack {
							Text("Text Size")
							Spacer()
							Text(appearance.resolvedFontSize, format: .number.precision(.fractionLength(0)))
								.monospacedDigit()
						}
						Slider(value: $appearance.fontSize, in: 14 ... 32, step: 1)
							.accessibilityLabel("Reader text size")
							.accessibilityValue("\(Int(appearance.resolvedFontSize)) points")
							.accessibilityIdentifier("reader-font-size-slider")
					}
				}

				Section("Layout") {
					Picker("Text Spacing", selection: $appearance.spacing) {
						ForEach(BrowserReaderAppearance.Spacing.allCases) { spacing in
							Text(spacing.rawValue).tag(spacing)
						}
					}
					.accessibilityIdentifier("reader-spacing-picker")
					Picker("Page Margins", selection: $appearance.margins) {
						ForEach(BrowserReaderAppearance.Margins.allCases) { margins in
							Text(margins.rawValue).tag(margins)
						}
					}
					.accessibilityIdentifier("reader-margins-picker")
				}

				Section("Colors") {
					colorPicker("Text", selection: $appearance.foreground)
						.accessibilityLabel("Reader text color")
						.accessibilityIdentifier("reader-foreground-picker")
					colorPicker("Background", selection: $appearance.background)
						.accessibilityLabel("Reader background color")
						.accessibilityIdentifier("reader-background-picker")
				}

				Section {
					Button("Reset Appearance", systemImage: "arrow.counterclockwise") {
						appearance = BrowserReaderAppearance()
					}
					.accessibilityIdentifier("reader-appearance-reset")
				}
			}
			.listStyle(.sidebar)
			.scrollContentBackground(.hidden)
			.navigationTitle("Reader Appearance")
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done", systemImage: "checkmark", role: .confirm) {
						dismiss()
					}
					.buttonStyle(.glassProminent)
					.accessibilityLabel("Done")
					.accessibilityIdentifier("reader-appearance-done")
				}
			}
		}
		#if os(macOS)
		.frame(minWidth: 380, minHeight: 480)
		#endif
		.accessibilityIdentifier("reader-appearance-panel")
	}

	private func colorPicker(_ title: String, selection: Binding<BrowserReaderAppearance.Palette>) -> some View {
		Picker(title, selection: selection) {
			ForEach(BrowserReaderAppearance.Palette.allCases) { palette in
				HStack {
					Circle()
						.fill(swatchColor(palette))
						.overlay(Circle().strokeBorder(.secondary, lineWidth: 1))
						.frame(width: 14, height: 14)
						.accessibilityHidden(true)
					Text(palette.title)
				}
				.tag(palette)
			}
		}
	}

	private func swatchColor(_ palette: BrowserReaderAppearance.Palette) -> Color {
		let rgb = Int(palette.rawValue, radix: 16) ?? 0
		return Color(
			red: Double((rgb >> 16) & 255) / 255,
			green: Double((rgb >> 8) & 255) / 255,
			blue: Double(rgb & 255) / 255
		)
	}
}
