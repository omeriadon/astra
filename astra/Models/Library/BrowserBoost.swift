import Foundation

/// A portable, per-domain user stylesheet and userscript. A nil domain applies everywhere.
struct BrowserBoost: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var domain: String?
    var css: String = ""
    var javascript: String = ""
    var isEnabled: Bool = true
    var modifiedAt: Date = .now

    nonisolated var isValidForSync: Bool {
        name.utf8.count <= 512
            && (domain?.utf8.count ?? 0) <= 253
            && css.utf8.count <= 131_072
            && javascript.utf8.count <= 131_072
            && modifiedAt.isFiniteBoostTimestamp
            && (domain == nil || Self.normalizedDomain(domain!) == domain)
    }

    nonisolated static func normalizedDomain(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hostname = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)?.host ?? trimmed
        let host = hostname.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !host.isEmpty, host.utf8.count <= 253,
              !host.contains(".."),
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.").contains($0) })
        else { return nil }
        return host
    }
}

private extension Date {
    nonisolated var isFiniteBoostTimestamp: Bool {
        timeIntervalSince1970.isFinite && timeIntervalSince1970 >= 0
            && timeIntervalSince1970 < 4_102_444_800
    }
}

