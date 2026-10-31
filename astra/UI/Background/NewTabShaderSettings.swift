import Foundation

nonisolated enum NewTabEffectSettings {
	static let floatSpeed: Float = 0.66
	static let floatBlur: Double = 63
}

nonisolated enum NewTabBackgroundPreferences {
	static let ditherKey = "astra.newTabDitherConfiguration"

	static func migratedStyle(_ style: String) -> String {
		switch style {
			case "default", "float", "dither", "ripple", "datamosh", "topographic": style
			default: "default"
		}
	}

	static func loadDitherConfiguration(from defaults: UserDefaults = .standard) -> DitherConfiguration {
		guard let data = defaults.data(forKey: ditherKey),
		      let configuration = try? JSONDecoder().decode(DitherConfiguration.self, from: data)
		else {
			return DitherConfiguration().bounded()
		}
		return configuration.bounded()
	}

	static func saveDitherConfiguration(_ configuration: DitherConfiguration, to defaults: UserDefaults = .standard) {
		var migrated = configuration
		if migrated.waveSpeed < 0 {
			migrated.waveSpeed = abs(migrated.waveSpeed)
			migrated.waveDirection = DitherConfiguration.normalizedWaveDirection(migrated.waveDirection + 180)
				?? DitherConfiguration.defaultWaveDirection
		}
		let bounded = migrated.bounded()
		guard let data = try? JSONEncoder().encode(bounded) else { return }
		defaults.set(data, forKey: ditherKey)
	}

	static func removeLegacyParameters(in defaults: UserDefaults = .standard) {
		for key in ["astra.newTabEffectSettings", "astra.newTabTopographicImage"] {
			defaults.removeObject(forKey: key)
		}
	}
}
