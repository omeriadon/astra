import SwiftUI

struct GlassIdleProbeView: View {
	@State private var mode: ProbeMode
	@State private var windowCanRender = false

	init(environment: [String: String] = ProcessInfo.processInfo.environment) {
		_mode = State(initialValue: ProbeMode.initialFromEnvironment(environment))
	}

	var body: some View {
		List {
			Section("Rendering mode") {
				Picker("Rendering mode", selection: $mode) {
					ForEach(ProbeMode.allCases) { option in
						Text(option.rawValue).tag(option)
					}
				}
				.pickerStyle(.segmented)
				.accessibilityIdentifier("probe-mode-picker")
				.onChange(of: mode) { _, value in
					probeLogger.info("mode=\(value.rawValue, privacy: .public) fixedInput=true")
				}
			}

			Section("Fixed input") {
				fixedInput
					.accessibilityIdentifier("probe-fixed-input")
			}

			if mode == .staticMedia || mode == .mediaWaveform || mode == .visibilityGatedWaveform {
				Section("Media activity") {
					mediaActivityCard
				}
			}

			Section("Actions") {
				testButton
			}
		}
		.listStyle(.inset)
		.frame(minWidth: 560, minHeight: 320)
		.navigationTitle("Glass Idle Probe")
		.background {
			WindowVisibilityReader { value in
				windowCanRender = value
				probeLogger.info("windowCanRender=\(value, privacy: .public)")
			}
		}
	}

	private var fixedInput: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Fixed title")
				.font(.headline)
			Text("The same content is rendered for every selected mode.")
				.foregroundStyle(.secondary)
			HStack(spacing: 12) {
				Image(systemName: "rectangle.stack")
				Text("Input value: 42")
				Spacer()
				Text(mode.rawValue)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background { modeBackground }
	}

	private var mediaActivityCard: some View {
		HStack(spacing: 8) {
			Button {
				probeLogger.info("media card activated")
			} label: {
				Label {
					VStack(alignment: .leading, spacing: 3) {
						Text("Fixed media title")
							.font(.caption.weight(.semibold))
							.lineLimit(1)
						Text("Playing media")
							.font(.caption2)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				} icon: {
					Image(systemName: "waveform")
						.symbolEffect(.variableColor, isActive: mode == .mediaWaveform || (mode == .visibilityGatedWaveform && windowCanRender))
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open fixed media")
			.accessibilityIdentifier("probe-media-open")

			Button("Pause", systemImage: "pause.fill") {
				probeLogger.info("media pause activated")
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.glass)
			.accessibilityIdentifier("probe-media-pause")

			Button("Mute players", systemImage: "speaker.slash.fill") {
				probeLogger.info("media mute activated")
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.glass)
			.accessibilityIdentifier("probe-media-mute")
		}
		.padding(10)
		.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
		.accessibilityIdentifier("probe-media-activity")
	}

	@ViewBuilder
	private var modeBackground: some View {
		switch mode {
			case .plain:
				RoundedRectangle(cornerRadius: 12)
					.fill(.background.secondary)
			case .bordered:
				RoundedRectangle(cornerRadius: 12)
					.fill(.background.secondary)
					.overlay {
						RoundedRectangle(cornerRadius: 12)
							.stroke(.separator, lineWidth: 1)
					}
			case .glass:
				RoundedRectangle(cornerRadius: 12)
					.fill(.clear)
					.glassEffect(.regular, in: .rect(cornerRadius: 12))
			case .interactiveGlass:
				RoundedRectangle(cornerRadius: 12)
					.fill(.clear)
					.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
			case .staticMedia, .mediaWaveform, .visibilityGatedWaveform:
				RoundedRectangle(cornerRadius: 12)
					.fill(.background.secondary)
		}
	}

	@ViewBuilder
	private var testButton: some View {
		switch mode {
			case .plain:
				button.buttonStyle(.borderless)
			case .bordered:
				button.buttonStyle(.bordered)
			case .glass:
				button.buttonStyle(.glass)
			case .interactiveGlass:
				button.buttonStyle(.glassProminent)
			case .staticMedia, .mediaWaveform, .visibilityGatedWaveform:
				button.buttonStyle(.borderless)
		}
	}

	private var button: some View {
		Button {
			probeLogger.info("probe button activated")
		} label: {
			Label("Test button", systemImage: "sparkles")
		}
		.accessibilityIdentifier("probe-test-button")
		.accessibilityLabel("Test button")
	}
}
