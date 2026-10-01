import CryptoKit
import Foundation

nonisolated struct BrowserVisit: Codable, Identifiable, Equatable, Sendable {
	var id: UUID = .init()
	var url: URL
	var title: String
	var visitedAt: Date = .now
	var modifiedAt: Date = .now

	nonisolated init(id: UUID = UUID(), url: URL, title: String, visitedAt: Date = .now, modifiedAt: Date = .now) {
		self.id = id
		self.url = Self.normalizedURL(url) ?? url
		self.title = title
		self.visitedAt = visitedAt
		self.modifiedAt = modifiedAt
	}

	private enum CodingKeys: String, CodingKey {
		case id, url, title, visitedAt, modifiedAt
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		let decodedURL = try values.decode(URL.self, forKey: .url)
		let decodedTitle = try values.decode(String.self, forKey: .title)
		let decodedVisitedAt = try values.decodeIfPresent(Date.self, forKey: .visitedAt) ?? .distantPast
		id = try values.decodeIfPresent(UUID.self, forKey: .id)
			?? Self.legacyID(url: decodedURL, title: decodedTitle, visitedAt: decodedVisitedAt)
		url = Self.normalizedURL(decodedURL) ?? decodedURL
		title = decodedTitle
		visitedAt = decodedVisitedAt
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
	}

	private static func legacyID(url: URL, title: String, visitedAt: Date) -> UUID {
		let safeURL = normalizedURL(url)?.absoluteString ?? url.absoluteString
		let identity = "\(safeURL)\u{1f}\(visitedAt.timeIntervalSince1970.bitPattern)\u{1f}\(title)"
		var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
		bytes[6] = (bytes[6] & 0x0f) | 0x50
		bytes[8] = (bytes[8] & 0x3f) | 0x80
		let tuple: uuid_t = (
			bytes[0], bytes[1], bytes[2], bytes[3],
			bytes[4], bytes[5], bytes[6], bytes[7],
			bytes[8], bytes[9], bytes[10], bytes[11],
			bytes[12], bytes[13], bytes[14], bytes[15]
		)
		return UUID(uuid: tuple)
	}

	static func retained(_ visits: [Self], days: Int, now: Date = .now) -> [Self] {
		guard days > 0 else { return visits }
		let cutoff = now.addingTimeInterval(-Double(days) * 86400)
		return visits.filter { $0.visitedAt >= cutoff }
	}

	static func isEligible(_ url: URL) -> Bool {
		["http", "https"].contains(url.scheme?.lowercased() ?? "")
			&& url.host?.isEmpty == false
	}

	static func normalizedURL(_ url: URL) -> URL? {
		guard isEligible(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return nil
		}
		components.user = nil
		components.password = nil
		return components.url
	}

	static func matching(_ visits: [Self], query: String) -> [Self] {
		guard !query.isEmpty else { return visits }
		return visits.filter {
			$0.title.localizedCaseInsensitiveContains(query)
				|| $0.url.absoluteString.localizedCaseInsensitiveContains(query)
		}
	}

	static func inRange(_ visits: [Self], from start: Date?, until end: Date?) -> [Self] {
		visits.filter { visit in
			(start.map { visit.visitedAt >= $0 } ?? true)
				&& (end.map { visit.visitedAt < $0 } ?? true)
		}
	}

	static func matchesRecordedVisit(
		url: URL,
		navigationID: Int,
		lastURL: URL?,
		lastNavigationID: Int?,
		visitID: UUID?
	) -> Bool {
		visitID != nil && lastURL == url && lastNavigationID == navigationID
	}

	static func summaries(_ visits: [Self]) -> [BrowserVisitSummary] {
		let groups = Dictionary(grouping: visits, by: \.url)
		return groups.map { url, visits in
			let latest = visits.max { lhs, rhs in
				lhs.visitedAt == rhs.visitedAt
					? lhs.id.uuidString > rhs.id.uuidString
					: lhs.visitedAt < rhs.visitedAt
			}
			return BrowserVisitSummary(url: url, title: latest?.title ?? url.host ?? url.absoluteString,
				visitCount: visits.count, lastVisitedAt: latest?.visitedAt ?? .distantPast)
		}.sorted {
			$0.lastVisitedAt == $1.lastVisitedAt
				? $0.url.absoluteString < $1.url.absoluteString
				: $0.lastVisitedAt > $1.lastVisitedAt
		}
	}

	mutating func updateTitle(_ title: String, at date: Date = .now) {
		guard self.title != title else { return }
		self.title = title
		modifiedAt = date
	}
}

nonisolated struct BrowserVisitSummary: Equatable, Sendable {
	let url: URL
	let title: String
	let visitCount: Int
	let lastVisitedAt: Date
}

struct BrowserVisitPolicy {
	private var suppressInitialVisit: Bool
	private var lastURL: URL?
	private var lastNavigationID: Int?

	init(suppressInitialVisit: Bool = false) {
		self.suppressInitialVisit = suppressInitialVisit
	}

	mutating func didCommit(_ url: URL, navigationID: Int) -> Bool {
		if suppressInitialVisit {
			suppressInitialVisit = false
			if BrowserVisit.isEligible(url) {
				lastURL = url
				lastNavigationID = navigationID
			}
			return false
		}
		guard BrowserVisit.isEligible(url) else { return false }
		lastURL = url
		lastNavigationID = navigationID
		return true
	}

	mutating func userInitiatedNavigation() {
		suppressInitialVisit = false
	}

	mutating func didChangeSameDocument(to url: URL, navigationID: Int) -> Bool {
		guard BrowserVisit.isEligible(url),
		      lastURL != url || lastNavigationID != navigationID else { return false }
		lastURL = url
		lastNavigationID = navigationID
		return true
	}
}
