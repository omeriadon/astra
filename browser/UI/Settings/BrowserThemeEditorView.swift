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
					Toggle("Pastel", isOn: $theme.noiseEnabled)
						.accessibilityIdentifier("theme-pastel-toggle")
					if theme.noiseEnabled {
						LabeledContent("Pastel Amount") {
							Slider(value: $theme.noiseAmount, in: 0 ... 1)
								.accessibilityLabel("Pastel amount")
								.accessibilityValue(Text(theme.noiseAmount, format: .percent))
								.accessibilityIdentifier("theme-pastel-amount")
						}
					}
					Toggle("Noise", isOn: $theme.shaderNoiseEnabled)
						.accessibilityIdentifier("theme-noise-toggle")
					if theme.shaderNoiseEnabled {
						Picker("Style", selection: $theme.shaderNoiseStyle) {
							ForEach(ThemeNoiseStyle.allCases) { style in
								Text(style.title)
									.tag(style)
							}
						}
						.accessibilityIdentifier("theme-noise-style")
						LabeledContent("Color Variation") {
							Slider(value: $theme.shaderNoiseAmount, in: 0 ... 1)
								.accessibilityLabel("Noise color variation")
								.accessibilityValue(Text(theme.shaderNoiseAmount, format: .percent))
								.accessibilityIdentifier("theme-noise-amount")
						}
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
