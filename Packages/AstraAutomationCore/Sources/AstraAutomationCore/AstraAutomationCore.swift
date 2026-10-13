import Foundation

/// Stable identifier for an existing tab in one specific browser window.
/// This is not a URL: it cannot be used to load a website or infer a tab by title.
public struct AstraTabReference: Hashable, Sendable, Codable, RawRepresentable {
	public let windowID: UUID
	public let tabID: UUID

	public init(windowID: UUID, tabID: UUID) {
		self.windowID = windowID
		self.tabID = tabID
	}

	public init?(rawValue: String) {
		let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
		guard parts.count == 2,
		      let windowID = UUID(uuidString: String(parts[0])),
		      let tabID = UUID(uuidString: String(parts[1])) else { return nil }
		self.init(windowID: windowID, tabID: tabID)
	}

	public var rawValue: String {
		windowID.uuidString + ":" + tabID.uuidString
	}
}

public enum AstraLibraryItem: Hashable, Sendable, Codable {
	case bookmark(UUID)
	case readingList(UUID)
	case space(UUID)

	public init?(url: URL) {
		guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      parts.scheme?.lowercased() == "astra",
		      parts.user == nil, parts.password == nil, parts.port == nil,
		      parts.query == nil, parts.fragment == nil,
		      let rawID = parts.path.split(separator: "/", omittingEmptySubsequences: true).only,
		      let uuid = UUID(uuidString: String(rawID)) else { return nil }

		switch parts.host?.lowercased() {
			case "bookmark": self = .bookmark(uuid)
			case "reading": self = .readingList(uuid)
			case "space": self = .space(uuid)
			default: return nil
		}
	}

	public var url: URL {
		let (kind, id): (String, UUID) = switch self {
			case let .bookmark(id): ("bookmark", id)
			case let .readingList(id): ("reading", id)
			case let .space(id): ("space", id)
		}
		// UUIDs and fixed path components are always safe as URL path segments.
		return URL(string: "astra://" + kind + "/" + id.uuidString)!
	}

	public var spotlightIdentifier: String {
		switch self {
			case let .bookmark(id): "bookmark:" + id.uuidString
			case let .readingList(id): "reading:" + id.uuidString
			case let .space(id): "space:" + id.uuidString
		}
	}

	public init?(spotlightIdentifier: String) {
		let parts = spotlightIdentifier.split(separator: ":", omittingEmptySubsequences: false)
		guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
		switch parts[0] {
			case "bookmark": self = .bookmark(id)
			case "reading": self = .readingList(id)
			case "space": self = .space(id)
			default: return nil
		}
	}
}

public enum AstraAutomationValidationError: Error, LocalizedError, Sendable {
	case invalidWebURL
	case oversizedInput

	public var errorDescription: String? {
		switch self {
			case .invalidWebURL: "Astra accepts only HTTP and HTTPS URLs without embedded credentials."
			case .oversizedInput: "The text or URL is too large."
		}
	}
}

/// A checked URL shared by macOS Services, App Intents, and future targets.
/// Never turn arbitrary selected text into an executable script URL.
public struct AstraWebAddress: Hashable, Sendable {
	public let url: URL

	public init(_ url: URL) throws {
		guard url.absoluteString.utf8.count <= 16384 else {
			throw AstraAutomationValidationError.oversizedInput
		}
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
		      components.user == nil, components.password == nil,
		      let host = components.host, !host.isEmpty,
		      components.port.map({ (1 ... 65535).contains($0) }) ?? true,
		      !host.unicodeScalars.contains(where: {
		      	CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
		      })
		else {
			throw AstraAutomationValidationError.invalidWebURL
		}
		self.url = url
	}
}

private extension Collection {
	var only: Element? {
		count == 1 ? first : nil
	}
}
