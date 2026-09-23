import Defaults
import SwiftUI

struct BrowserThemeEditorView: View {
	@Default(.browserTheme) private var theme
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List {
				Section("Preview") {
					BrowserThemeBackground(theme: theme)
						.frame(height: 80)
						.clipShape(.rect(cornerRadius: 12))
						.accessibilityLabel("Theme background preview")
						.accessibilityIdentifier("theme-background-preview")
				}

				Section("Background") {
					Toggle("Two-Color Gradient", isOn: $theme.usesGradient)
						.accessibilityIdentifier("theme-gradient-toggle")
					ColorPicker("First Color", selection: $theme.firstColor.color, supportsOpacity: false)
						.accessibilityIdentifier("theme-first-color")
					if theme.usesGradient {
						ColorPicker("Second Color", selection: $theme.secondColor.color, supportsOpacity: false)
							.accessibilityIdentifier("theme-second-color")
						Picker("Start Point", selection: $theme.gradientDirection) {
							ForEach(ThemeGradientDirection.allCases) { direction in
								Text(direction.title)
									.tag(direction)
							}
						}
						.accessibilityIdentifier("theme-gradient-start")
						Picker("End Point", selection: $theme.gradientEndDirection) {
							ForEach(ThemeGradientDirection.allCases) { direction in
								Text(direction.title)
									.tag(direction)
							}
						}
						.accessibilityIdentifier("theme-gradient-end")
					}
				}

				Section("Texture") {
					Toggle("Noise", isOn: $theme.shaderNoiseEnabled)
						.accessibilityIdentifier("theme-noise-toggle")
					if theme.shaderNoiseEnabled {
						Toggle("Monochrome", isOn: $theme.shaderNoiseMonochrome)
							.accessibilityIdentifier("theme-noise-monochrome-toggle")
							.onChange(of: theme.shaderNoiseMonochrome) { _, isMonochrome in
								let maximumAmount = isMonochrome ? 0.25 : 0.5
								theme.shaderNoiseAmount = min(theme.shaderNoiseAmount, maximumAmount)
							}
						LabeledContent("Noise Amount") {
							Slider(
								value: $theme.shaderNoiseAmount,
								in: 0 ... (theme.shaderNoiseMonochrome ? 0.25 : 0.5)
							)
							.accessibilityLabel("Noise amount")
							.accessibilityValue(Text(theme.shaderNoiseAmount, format: .percent))
							.accessibilityIdentifier("theme-noise-amount")
						}
						Stepper(
							"Noise Blur: \(theme.shaderNoiseBlur.formatted())",
							value: $theme.shaderNoiseBlur,
							in: 0 ... 10,
							step: 0.5
						)
						.accessibilityIdentifier("theme-noise-blur")
					}
				}

				Section("Browser Controls") {
					ColorPicker("Tab Color", selection: $theme.tabColor.color, supportsOpacity: false)
						.accessibilityIdentifier("theme-tab-color")
					ColorPicker("Progress Bar Color", selection: $theme.progressColor.color, supportsOpacity: false)
						.accessibilityIdentifier("theme-progress-color")
				}
			}
			.presentationSizing(.form)
			.navigationTitle("Theme")
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
