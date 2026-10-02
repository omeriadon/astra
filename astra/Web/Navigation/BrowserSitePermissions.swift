import Foundation
import Observation

@MainActor
@Observable
final class BrowserSitePermissions {
	enum Capability: String, Codable, CaseIterable {
		case camera
		case microphone
		case location
		case motion
		case notifications
		case popups
		case automaticDownloads

		var title: String {
			switch self {
				case .camera: "Camera"
				case .microphone: "Microphone"
				case .location: "Location"
				case .motion: "Motion"
				case .notifications: "Notifications"
				case .popups: "Pop-ups"
				case .automaticDownloads: "Automatic Downloads"
			}
		}
	}

	enum Decision: String, Codable, CaseIterable {
		case allowOnce
		case allowAlways
		case deny

		init?(response: PromptResponse) {
			switch response {
				case .allowOnce: self = .allowOnce
				case .allowAlways: self = .allowAlways
				case .deny: self = .deny
				case .cancel: return nil
			}
		}
	}

	enum PromptResponse {
		case allowOnce
		case allowAlways
		case deny
		case cancel
	}

	struct AutomaticDownloadPolicy {
		private(set) var hasAttemptedDownload = false

		mutating func reserveAttempt() -> Bool {
			let requiresPermission = hasAttemptedDownload
			hasAttemptedDownload = true
			return requiresPermission
		}

		mutating func didCommitDocument() {
			hasAttemptedDownload = false
		}
	}

	struct Entry: Codable, Identifiable {
		let origin: String
		let topOrigin: String
		let capability: Capability
		let decision: Decision

		var id: String {
			"\(topOrigin)|\(origin)|\(capability.rawValue)"
		}

		var allowed: Bool {
			decision == .allowAlways
		}

		private enum CodingKeys: String, CodingKey {
			case origin
			case topOrigin
			case capability
			case allowed
			case decision
		}

		init(origin: String, topOrigin: String, capability: Capability, decision: Decision) {
			self.origin = origin
			self.topOrigin = topOrigin
			self.capability = capability
			self.decision = decision
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			origin = try container.decode(String.self, forKey: .origin)
			topOrigin = try container.decode(String.self, forKey: .topOrigin)
			capability = try container.decode(Capability.self, forKey: .capability)
			if let decision = try container.decodeIfPresent(Decision.self, forKey: .decision) {
				self.decision = decision
			} else {
				self.decision = try container.decode(Bool.self, forKey: .allowed) ? .allowAlways : .deny
			}
		}

		func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(origin, forKey: .origin)
			try container.encode(topOrigin, forKey: .topOrigin)
			try container.encode(capability, forKey: .capability)
			try container.encode(decision, forKey: .decision)
		}
	}

	private struct TemporaryKey: Hashable {
		let origin: String
		let topOrigin: String
		let capability: Capability
		let controllerID: UUID
		let documentID: Int
	}

	private static let defaultsKey = "websitePermissions"
	static var websiteCapabilities: [Capability] {
		#if os(iOS)
			[.camera, .microphone, .location, .motion, .popups, .automaticDownloads]
		#else
			[.camera, .microphone, .location, .popups, .automaticDownloads]
		#endif
	}
	private let isPrivate: Bool
	private let defaults: UserDefaults
	private var canReplaceSavedData = true
	private var hasUnrecognizedSavedData = false
	private var temporaryDecisions: [TemporaryKey: Decision] = [:]
	private(set) var entries: [Entry]
	var hasDecisions: Bool {
		!entries.isEmpty || !temporaryDecisions.isEmpty || hasUnrecognizedSavedData
	}
	var isSavedDataReadOnly: Bool {
		hasUnrecognizedSavedData
	}
	@ObservationIgnored
	var didChange: (() -> Void)?
	@ObservationIgnored
	var didUpdate: ((Entry?) -> Void)?
	private(set) var revision = 0

	init(isPrivate: Bool, defaults: UserDefaults = .standard) {
		self.isPrivate = isPrivate
		self.defaults = defaults
		if !isPrivate,
		   let data = defaults.data(forKey: Self.defaultsKey)
		{
			let savedEntries = try? JSONDecoder().decode([Entry].self, from: data)
			let canRewriteSavedData = savedEntries != nil && Self.canRewrite(data)
			canReplaceSavedData = canRewriteSavedData
			hasUnrecognizedSavedData = !canRewriteSavedData
			if let savedEntries {
				entries = Self.normalized(savedEntries)
			} else {
				entries = []
			}
		} else {
			entries = []
		}
		#if DEBUG
			assert(Self.origin(for: URL(string: "https://EXAMPLE.com/path")!) == "https://example.com")
			assert(Self.origin(for: URL(string: "https://example.com:443")!) == "https://example.com")
			assert(Self.origin(for: URL(string: "https://example.com:8443")!) == "https://example.com:8443")
			assert(Self.origin(for: URL(string: "file:///tmp/page.html")!) == nil)
		#endif
	}

	static func origin(for url: URL) -> String? {
		BrowserSiteOrigin.canonical(for: url)
	}

	func decision(origin: String, topOrigin: String, capability: Capability) -> Bool? {
		switch effectiveDecision(origin: origin, topOrigin: topOrigin, capability: capability) {
			case .allowAlways: true
			case .deny: false
			case .allowOnce, nil: nil
		}
	}

	func effectiveDecision(
		origin: String,
		topOrigin: String,
		capability: Capability,
		controllerID: UUID? = nil,
		documentID: Int? = nil
	) -> Decision? {
		guard let origin = Self.normalizedOrigin(origin),
		      let topOrigin = Self.normalizedOrigin(topOrigin) else { return nil }
		if let controllerID, let documentID {
			let key = TemporaryKey(
				origin: origin,
				topOrigin: topOrigin,
				capability: capability,
				controllerID: controllerID,
				documentID: documentID
			)
			if let decision = temporaryDecisions[key] {
				return decision
			}
		}
		return entries.first {
			$0.origin == origin && $0.topOrigin == topOrigin && $0.capability == capability
		}?.decision
	}

	func set(
		_ decision: Decision,
		origin: String,
		topOrigin: String,
		capability: Capability,
		controllerID: UUID? = nil,
		documentID: Int? = nil
	) {
		guard let origin = Self.normalizedOrigin(origin),
		      let topOrigin = Self.normalizedOrigin(topOrigin) else { return }
		if decision == .allowOnce {
			guard let controllerID, let documentID else { return }
			temporaryDecisions[TemporaryKey(
				origin: origin,
				topOrigin: topOrigin,
				capability: capability,
				controllerID: controllerID,
				documentID: documentID
			)] = decision
			revision &+= 1
			didUpdate?(Entry(origin: origin, topOrigin: topOrigin, capability: capability, decision: decision))
			return
		}
		let entry = Entry(origin: origin, topOrigin: topOrigin, capability: capability, decision: decision)
		entries.removeAll { $0.id == entry.id }
		entries.append(entry)
		temporaryDecisions = temporaryDecisions.filter {
			$0.key.origin != origin || $0.key.topOrigin != topOrigin || $0.key.capability != capability
		}
		save(changed: entry)
	}

	func set(_ allowed: Bool, origin: String, topOrigin: String, capability: Capability) {
		set(allowed ? .allowAlways : .deny, origin: origin, topOrigin: topOrigin, capability: capability)
	}

	func remove(_ entry: Entry) {
		entries.removeAll { $0.id == entry.id }
		temporaryDecisions = temporaryDecisions.filter {
			$0.key.origin != entry.origin || $0.key.topOrigin != entry.topOrigin || $0.key.capability != entry.capability
		}
		save(changed: entry)
	}

	func removeTemporaryDecisions(controllerID: UUID) {
		temporaryDecisions = temporaryDecisions.filter { $0.key.controllerID != controllerID }
	}

	func reset() {
		entries.removeAll()
		temporaryDecisions.removeAll()
		canReplaceSavedData = true
		hasUnrecognizedSavedData = false
		save(changed: nil)
	}

	private func save(changed: Entry?) {
		revision &+= 1
		didChange?()
		didUpdate?(changed)
		guard !isPrivate, canReplaceSavedData, let data = try? JSONEncoder().encode(entries) else { return }
		defaults.set(data, forKey: Self.defaultsKey)
	}

	private static func normalized(_ entries: [Entry]) -> [Entry] {
		var byID: [String: Entry] = [:]
		for entry in entries {
			guard entry.decision != .allowOnce else { continue }
			guard let origin = normalizedOrigin(entry.origin),
			      let topOrigin = normalizedOrigin(entry.topOrigin) else { continue }
			let value = Entry(origin: origin, topOrigin: topOrigin, capability: entry.capability, decision: entry.decision)
			byID[value.id] = value
		}
		return byID.values.sorted { $0.id < $1.id }
	}

	private static func normalizedOrigin(_ origin: String) -> String? {
		guard let url = URL(string: origin) else { return nil }
		return self.origin(for: url)
	}

	private static func canRewrite(_ data: Data) -> Bool {
		guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
		let knownKeys: Set<String> = ["origin", "topOrigin", "capability", "allowed", "decision"]
		let capabilities = Set(Capability.allCases.map(\.rawValue))
		let decisions = Set(Decision.allCases.map(\.rawValue))
		return entries.allSatisfy { entry in
			guard Set(entry.keys).isSubset(of: knownKeys),
			      let origin = entry["origin"] as? String,
			      let topOrigin = entry["topOrigin"] as? String,
			      normalizedOrigin(origin) != nil,
			      normalizedOrigin(topOrigin) != nil,
			      let capability = entry["capability"] as? String,
			      capabilities.contains(capability) else { return false }
			if let decision = entry["decision"] as? String {
				return entry["allowed"] == nil
					&& decisions.contains(decision)
					&& decision != Decision.allowOnce.rawValue
			}
			return entry["allowed"] is Bool
		}
	}
}
