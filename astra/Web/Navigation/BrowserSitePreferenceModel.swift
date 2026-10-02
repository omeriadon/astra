import Foundation
#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#endif

nonisolated enum BrowserSiteOrigin {
	static func canonical(for url: URL) -> String? {
		guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let scheme = parts.scheme?.lowercased(),
		      ["https", "http"].contains(scheme),
		      var host = parts.host?.lowercased(),
		      !host.isEmpty else { return nil }
		if host.hasPrefix("["), host.hasSuffix("]"), !host.contains("%") {
			let addressText = String(host.dropFirst().dropLast())
			var address = in6_addr()
			guard addressText.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
			var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
			guard buffer.withUnsafeMutableBufferPointer({
				inet_ntop(AF_INET6, &address, $0.baseAddress, socklen_t($0.count))
			}) != nil else { return nil }
			host = "[\(String(cString: buffer).lowercased())]"
		}
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
}

enum BrowserWebsiteDataRange: String, CaseIterable, Identifiable {
	case lastHour
	case today
	case allTime

	var id: Self { self }

	var title: String {
		switch self {
			case .lastHour: "Last Hour"
			case .today: "Today"
			case .allTime: "All Time"
		}
	}

	func modifiedSince(now: Date = .now, calendar: Calendar = .current) -> Date {
		switch self {
			case .lastHour:
				now.addingTimeInterval(-60 * 60)
			case .today:
				calendar.startOfDay(for: now)
			case .allTime:
				.distantPast
		}
	}
}

nonisolated struct BrowserSiteZoomEntry: Codable, Equatable, Sendable {
	let zoom: Double?
	let modifiedAt: Date
	private enum CodingKeys: String, CodingKey {
		case zoom
		case modifiedAt
	}

	init(zoom: Double?, modifiedAt: Date) {
		self.zoom = zoom
		self.modifiedAt = modifiedAt
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		zoom = try values.decodeIfPresent(Double.self, forKey: .zoom)
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
	}

	static func preferred(_ first: Self, _ second: Self) -> Self {
		if first.modifiedAt != second.modifiedAt {
			return first.modifiedAt > second.modifiedAt ? first : second
		}
		if first.zoom == nil || second.zoom == nil {
			return first.zoom == nil ? first : second
		}
		if let firstZoom = first.zoom,
		   let secondZoom = second.zoom
		{
			return firstZoom >= secondZoom ? first : second
		}
		return first
	}
}

nonisolated struct BrowserSiteZoomDocument: Codable, Equatable, Sendable {
	static let currentVersion = 1
	static let defaultsKey = "siteZoomPreferences"

	var version = currentVersion
	var entries: [String: BrowserSiteZoomEntry] = [:]

	private enum CodingKeys: String, CodingKey {
		case version
		case entries
	}

	init(entries: [String: BrowserSiteZoomEntry] = [:]) {
		self.entries = entries
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
		entries = try values.decodeIfPresent([String: BrowserSiteZoomEntry].self, forKey: .entries) ?? [:]
	}

	var hasSupportedVersion: Bool {
		version == Self.currentVersion
	}

	var hasValidStructure: Bool {
		entries.allSatisfy { origin, entry in
			BrowserSiteOrigin.canonical(for: URL(string: origin) ?? URL(fileURLWithPath: "/")) == origin
				&& Self.isSaneSyncTimestamp(entry.modifiedAt)
				&& (entry.zoom.map { $0.isFinite && (0.25 ... 5).contains($0) } ?? true)
		}
	}

	static func isSaneSyncTimestamp(_ date: Date) -> Bool {
		date == .distantPast
			|| (date.timeIntervalSince1970.isFinite
				&& date.timeIntervalSince1970 >= -2_208_988_800
				&& date.timeIntervalSince1970 <= Date.now.timeIntervalSince1970 + 300.001)
	}

	func merging(_ other: Self) -> Self {
		var merged = self
		merged.version = max(version, other.version)
		for (origin, incoming) in other.entries {
			guard let current = merged.entries[origin] else {
				merged.entries[origin] = incoming
				continue
			}
			merged.entries[origin] = BrowserSiteZoomEntry.preferred(incoming, current)
		}
		return merged
	}

	static func decodeSupported(_ data: Data) -> Self? {
		guard let document = try? JSONDecoder().decode(Self.self, from: data),
		      document.hasSupportedVersion,
		      document.hasValidStructure,
		      canRewrite(data) else { return nil }
		return document
	}

	static func mergeSyncValues(_ first: Data?, _ second: Data?) -> Data? {
		guard let first = decodeSyncDocument(first),
		      let second = decodeSyncDocument(second),
		      let merged = first.merging(second).encoded(),
		      let value = try? PropertyListSerialization.data(
			fromPropertyList: ["value": merged],
			format: .binary,
			options: 0
		      ) else { return nil }
		return value
	}

	static func isPreservableSyncValue(_ value: Data?) -> Bool {
		guard let value,
		      value.count <= 16 * 1024 * 1024,
		      let object = try? PropertyListSerialization.propertyList(from: value, format: nil) as? [String: Data],
		      Set(object.keys) == ["value"],
		      let document = object["value"] else { return false }
		return document.count <= 16 * 1024 * 1024
	}

	private static func decodeSyncDocument(_ data: Data?) -> Self? {
		guard let data,
		      let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Data],
		      let documentData = object["value"] else { return nil }
		return decodeSupported(documentData)
	}

	func encoded() -> Data? {
		guard hasSupportedVersion, hasValidStructure else { return nil }
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return try? encoder.encode(self)
	}

	private static func canRewrite(_ data: Data) -> Bool {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      Set(object.keys).isSubset(of: ["version", "entries"]),
		      let entries = object["entries"] as? [String: [String: Any]] else { return false }
		return entries.values.allSatisfy { Set($0.keys).isSubset(of: ["zoom", "modifiedAt"]) }
	}
}

struct BrowserLocalSitePreference: Codable, Equatable, Sendable {
	var contentMode: String?
	var customUserAgent: String?
	var nativeContentBlockingDisabled: Bool? = nil

	var isEmpty: Bool {
		contentMode == nil && customUserAgent == nil && nativeContentBlockingDisabled != true
	}
}

struct BrowserLocalSitePreferencesDocument: Codable, Equatable, Sendable {
	static let currentVersion = 1
	static let defaultsKey = "siteBrowsingPreferences"

	var version = currentVersion
	var entries: [String: BrowserLocalSitePreference] = [:]

	private enum CodingKeys: String, CodingKey {
		case version
		case entries
	}

	init(entries: [String: BrowserLocalSitePreference] = [:]) {
		self.entries = entries
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
		entries = try values.decodeIfPresent([String: BrowserLocalSitePreference].self, forKey: .entries) ?? [:]
	}

	var hasSupportedVersion: Bool {
		version == Self.currentVersion
	}

	var hasValidStructure: Bool {
		entries.allSatisfy { origin, preference in
			BrowserSiteOrigin.canonical(for: URL(string: origin) ?? URL(fileURLWithPath: "/")) == origin
				&& (preference.contentMode.map { ["recommended", "desktop", "mobile"].contains($0) } ?? true)
				&& (preference.customUserAgent.map { $0.utf8.count <= 2048 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) } ?? true)
		}
	}

	func encoded() -> Data? {
		guard hasSupportedVersion, hasValidStructure else { return nil }
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return try? encoder.encode(self)
	}

	static func decodeSupported(_ data: Data) -> Self? {
		guard let document = try? JSONDecoder().decode(Self.self, from: data),
		      document.hasSupportedVersion,
		      document.hasValidStructure,
		      canRewrite(data) else { return nil }
		return document
	}

	private static func canRewrite(_ data: Data) -> Bool {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      Set(object.keys).isSubset(of: ["version", "entries"]),
		      let entries = object["entries"] as? [String: [String: Any]] else { return false }
		return entries.values.allSatisfy { entry in
			Set(entry.keys).isSubset(of: ["contentMode", "customUserAgent", "nativeContentBlockingDisabled"])
		}
	}
}
