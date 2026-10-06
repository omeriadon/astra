import Defaults
import Foundation

nonisolated enum BrowserAIFeatureID: String, CaseIterable, Identifiable, Sendable {
	case downloads
	case linkPreview
	case tabGroups
	case find
	case chat
	case tabTitles

	var id: String {
		rawValue
	}

	var title: String {
		switch self {
			case .downloads: "Rename Downloads"
			case .linkPreview: "Link Previews"
			case .tabGroups: "Tidy Today Tabs"
			case .find: "Ask in Find"
			case .chat: "AI Sidebar"
			case .tabTitles: "Clean Tab Titles"
		}
	}

	var defaultModel: BrowserAIModel {
		switch self {
			case .downloads, .tabTitles: .appleIntelligence
			case .linkPreview, .find, .chat, .tabGroups: .openRouter(modelID: "openai/gpt-4o-mini")
		}
	}

	@MainActor var model: BrowserAIModel {
		let presets = BrowserAISettings.presets
		return presets[rawValue].flatMap(BrowserAIModel.init(identifier:)) ?? defaultModel
	}
}

extension BrowserAIModel {
	nonisolated init?(identifier: String) {
		if identifier == "apple" {
			self = .appleIntelligence
		} else if identifier == "pcc" {
			self = .privateCloudCompute
		} else if identifier.hasPrefix("openrouter:") {
			self = .openRouter(modelID: String(identifier.dropFirst(11)))
		} else if identifier.hasPrefix("codex:") {
			self = .codex(modelID: String(identifier.dropFirst(6)))
		} else if identifier.hasPrefix("claude:") {
			self = .claude(modelID: String(identifier.dropFirst(7)))
		} else {
			return nil
		}
	}

	nonisolated var identifier: String {
		switch self {
			case .appleIntelligence: "apple"
			case .privateCloudCompute: "pcc"
			case let .openRouter(id): "openrouter:\(id)"
			case let .codex(id): "codex:\(id)"
			case let .claude(id): "claude:\(id)"
		}
	}
}

@MainActor
enum BrowserAISettings {
	static var presets: [String: String] {
		get {
			guard let data = Defaults[.aiFeaturePresets].data(using: .utf8) else { return [:] }
			return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
		}
		set {
			guard let data = try? JSONEncoder().encode(newValue), let text = String(data: data, encoding: .utf8) else { return }
			Defaults[.aiFeaturePresets] = text
		}
	}

	static func effectiveModel(_ preset: BrowserAIModel) -> BrowserAIModel {
		#if os(macOS)
			switch Defaults[.aiProvider] {
				case "codex": return .codex(modelID: Defaults[.aiCodexModel])
				case "claude": return .claude(modelID: Defaults[.aiClaudeModel])
				default: break
			}
		#endif
		return preset
	}
}

extension Defaults.Keys {
	static let aiFeaturesEnabled = Key<Bool>("aiFeaturesEnabled", default: true)
	static let aiLinkPreviews = Key<Bool>("aiLinkPreviews", default: true)
	static let aiTabGroups = Key<Bool>("aiTabGroups", default: true)
	static let aiFind = Key<Bool>("aiFind", default: true)
	static let aiFindContextLimit = Key<Bool>("aiFindContextLimit", default: true)
	static let aiSidebar = Key<Bool>("aiSidebar", default: true)
	static let aiTabTitles = Key<Bool>("aiTabTitles", default: true)
	static let aiProvider = Key<String>("aiProvider", default: "presets")
	static let aiCodexModel = Key<String>("aiCodexModel", default: "")
	static let aiClaudeModel = Key<String>("aiClaudeModel", default: "")
	static let aiFeaturePresets = Key<String>("aiFeaturePresets", default: "{}")
}
