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
		id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		url = try values.decode(URL.self, forKey: .url)
		title = try values.decode(String.self, forKey: .title)
		visitedAt = try values.decodeIfPresent(Date.self, forKey: .visitedAt) ?? .distantPast
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? visitedAt
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
