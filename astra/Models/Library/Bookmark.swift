import Foundation

nonisolated struct Bookmark: Codable, Identifiable, Equatable, Sendable {
	var id: UUID
	var name: String
	var url: URL
	var modifiedAt: Date

	init(id: UUID = UUID(), name: String, url: URL, modifiedAt: Date = .now) {
		self.id = id
		self.name = name
		self.url = url
		self.modifiedAt = modifiedAt
	}

	private enum CodingKeys: String, CodingKey {
		case id, name, url, modifiedAt
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decode(UUID.self, forKey: .id)
		name = try values.decode(String.self, forKey: .name)
		url = try values.decode(URL.self, forKey: .url)
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
	}
}
