import Foundation

/// Product presets are immutable: previous slider values never affect rendering.
nonisolated enum NewTabEffectSettings {
	static let floatSpeed: Float = 0.66
	static let floatBlur: Double = 63
}

nonisolated enum NewTabBackgroundPreferences {
	static func migratedStyle(_ style: String) -> String {
		switch style {
			case "default", "float", "dither", "ripple", "datamosh", "topographic": style
			default: "default"
		}
	}

	static func removeLegacyParameters(in defaults: UserDefaults = .standard) {
		for key in ["astra.newTabDitherConfiguration", "astra.newTabEffectSettings", "astra.newTabTopographicImage"] {
			if defaults.object(forKey: key) != nil { defaults.removeObject(forKey: key) }
		}
	}
}
