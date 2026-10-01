import Foundation

nonisolated struct BrowserVisit: Codable, Identifiable, Equatable, Sendable {
	var id: UUID = .init()
	var url: URL
	var title: String
	var visitedAt: Date = .now
	var modifiedAt: Date = .now

	nonisolated init(id: UUID = UUID(), url: URL, title: String, visitedAt: Date = .now, modifiedAt: Date = .now) {
		self.id = id
		self.url = url
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
}
