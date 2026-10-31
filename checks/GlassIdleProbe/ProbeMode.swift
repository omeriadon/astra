import Foundation

enum ProbeMode: String, CaseIterable, Identifiable {
	case plain = "Plain"
	case bordered = "Bordered"
	case glass = "Glass"
	case interactiveGlass = "Interactive glass"
	case staticMedia = "Static media"
	case mediaWaveform = "Media waveform"
	case visibilityGatedWaveform = "Visibility gated waveform"

	var id: String {
		rawValue
	}

	static func initialFromEnvironment(_ environment: [String: String]) -> ProbeMode {
		guard let value = environment["ASTRA_GLASS_PROBE_MODE"] else {
			return .plain
		}
		guard let mode = ProbeMode(rawValue: value) else {
			preconditionFailure("ASTRA_GLASS_PROBE_MODE must match a ProbeMode raw value")
		}
		return mode
	}
}
