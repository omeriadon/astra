import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserSitePermissions {
	enum Capability: String, Codable, CaseIterable {
		case camera
		case microphone
		case location
		case notifications

		var title: String {
			switch self {
				case .camera: "Camera"
				case .microphone: "Microphone"
				case .location: "Location"
				case .notifications: "Notifications"
			}
		}
	}

	struct Entry: Codable, Identifiable {
		let origin: String
		let topOrigin: String
		let capability: Capability
		let allowed: Bool

		var id: String {
			"\(topOrigin)|\(origin)|\(capability.rawValue)"
		}
	}

	private static let defaultsKey = "websitePermissions"
	private let isPrivate: Bool
	private(set) var entries: [Entry]
	@ObservationIgnored
	var didChange: (() -> Void)?

	init(isPrivate: Bool) {
		self.isPrivate = isPrivate
		if !isPrivate,
		   let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
		   let saved = try? JSONDecoder().decode([Entry].self, from: data)
		{
			entries = saved
		} else {
			entries = []
		}
		#if DEBUG
			assert(Self.origin(for: URL(string: "https://example.com/path")!) == "https://example.com")
			assert(Self.origin(for: URL(string: "https://example.com:443")!) == "https://example.com")
			assert(Self.origin(for: URL(string: "https://example.com:8443")!) == "https://example.com:8443")
			assert(Self.origin(for: URL(string: "file:///tmp/page.html")!) == nil)
		#endif
	}

	static func origin(for url: URL) -> String? {
		guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let scheme = parts.scheme?.lowercased(),
		      ["https", "http"].contains(scheme),
		      let host = parts.host?.lowercased(),
		      !host.isEmpty else { return nil }
		parts.scheme = scheme
		parts.host = host
		parts.user = nil
		parts.password = nil
		parts.path = ""
		parts.query = nil
		parts.fragment = nil
		if parts.port == (scheme == "https" ? 443 : 80) {
			parts.port = nil
		}
		return parts.string
	}

	func decision(origin: String, topOrigin: String, capability: Capability) -> Bool? {
		entries.first {
			$0.origin == origin && $0.topOrigin == topOrigin && $0.capability == capability
		}?.allowed
	}

	func set(_ allowed: Bool, origin: String, topOrigin: String, capability: Capability) {
		let entry = Entry(origin: origin, topOrigin: topOrigin, capability: capability, allowed: allowed)
		entries.removeAll { $0.id == entry.id }
		entries.append(entry)
		save()
	}

	func remove(_ entry: Entry) {
		entries.removeAll { $0.id == entry.id }
		save()
	}

	func reset() {
		entries.removeAll()
		save()
	}

	private func save() {
		didChange?()
		guard !isPrivate, let data = try? JSONEncoder().encode(entries) else { return }
		UserDefaults.standard.set(data, forKey: Self.defaultsKey)
	}
}
