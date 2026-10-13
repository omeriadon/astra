import Foundation

/// Stable links from Spotlight to persisted Astra library items.
/// These are identifiers, not permission to access browser state.
public enum AstraSystemResource: String, CaseIterable, Codable, Sendable {
    case bookmark
    case reading
    case space
}

public struct AstraSystemLink: Sendable, Hashable {
    public let resource: AstraSystemResource
    public let id: UUID

    public init(resource: AstraSystemResource, id: UUID) {
        self.resource = resource
        self.id = id
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "astra",
              let host = url.host?.lowercased(),
              let resource = AstraSystemResource(rawValue: host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else { return nil }

        let segments = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count == 1,
              let id = UUID(uuidString: String(segments[0])) else { return nil }
        self.init(resource: resource, id: id)
    }

    public var url: URL {
        // Both the host and ID are drawn from checked enum/UUID values.
        URL(string: "astra://\(resource.rawValue)/\(id.uuidString)")!
    }

    public var spotlightIdentifier: String {
        resource.rawValue + ":" + id.uuidString
    }

    public init?(spotlightIdentifier: String) {
        let parts = spotlightIdentifier.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let resource = AstraSystemResource(rawValue: String(parts[0])),
              let id = UUID(uuidString: String(parts[1])) else { return nil }
        self.init(resource: resource, id: id)
    }
}

/// Tab identifiers are qualified by their owning window to prevent accidental
/// operations against a different window containing the same restored tab.
public struct AstraSystemTabID: Hashable, Sendable {
    public let windowID: UUID
    public let tabID: UUID

    public init(windowID: UUID, tabID: UUID) {
        self.windowID = windowID
        self.tabID = tabID
    }

    public init?(rawValue: String) {
        let segments = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard segments.count == 2,
              let windowID = UUID(uuidString: String(segments[0])),
              let tabID = UUID(uuidString: String(segments[1])) else { return nil }
        self.init(windowID: windowID, tabID: tabID)
    }

    public var rawValue: String {
        windowID.uuidString + ":" + tabID.uuidString
    }
}

public enum AstraSystemURLPolicy {
    /// Validates the input as a navigable web address, without constructing a
    /// WebKit view or using the application's broader address-bar heuristics.
    public static func validate(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              url.absoluteString.utf8.count <= 16_384 else { return nil }
        return url
    }
}
