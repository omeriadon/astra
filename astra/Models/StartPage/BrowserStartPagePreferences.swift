import Foundation

nonisolated struct BrowserStartPagePreferences: Codable, Equatable, Sendable {
	var version = 1
	var moduleOrder = Module.allCases
	var hiddenModules: Set<Module> = []

	enum Module: String, CaseIterable, Codable, Identifiable, Sendable {
		case favourites
		case frequent
		case recent
		case recentlyClosed

		var id: String { rawValue }

		var title: String {
			switch self {
				case .favourites: "Favorites"
				case .frequent: "Frequently Visited"
				case .recent: "Recently Visited"
				case .recentlyClosed: "Recently Closed"
			}
		}

		var symbol: String {
			switch self {
				case .favourites: "star"
				case .frequent: "chart.bar"
				case .recent: "clock.arrow.circlepath"
				case .recentlyClosed: "arrow.uturn.backward"
			}
		}
	}

	static let `default` = Self()

	private enum CodingKeys: String, CodingKey {
		case version, moduleOrder, hiddenModules
	}

	static func decode(_ value: String) -> Self? {
		guard let data = value.data(using: .utf8),
			  let preferences = try? JSONDecoder().decode(Self.self, from: data),
			  preferences.version == 1,
			  preferences.moduleOrder.count == Module.allCases.count,
			  Set(preferences.moduleOrder) == Set(Module.allCases),
			  preferences.hiddenModules.isSubset(of: Set(Module.allCases))
		else { return nil }
		return preferences
	}

	var encoded: String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		guard let data = try? encoder.encode(self) else { return "" }
		return String(decoding: data, as: UTF8.self)
	}

	nonisolated func encode(to encoder: Encoder) throws {
		var values = encoder.container(keyedBy: CodingKeys.self)
		try values.encode(version, forKey: .version)
		try values.encode(moduleOrder, forKey: .moduleOrder)
		try values.encode(hiddenModules.sorted { $0.rawValue < $1.rawValue }, forKey: .hiddenModules)
	}

	func isVisible(_ module: Module) -> Bool {
		!hiddenModules.contains(module)
	}

	mutating func move(_ module: Module, by offset: Int) {
		guard let index = moduleOrder.firstIndex(of: module) else { return }
		let destination = index + offset
		guard moduleOrder.indices.contains(destination) else { return }
		moduleOrder.swapAt(index, destination)
	}
}
