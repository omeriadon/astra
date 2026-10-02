import Foundation

nonisolated struct Bookmark: Codable, Identifiable, Equatable, Sendable {
	var id: UUID
	var name: String
	var url: URL
	var modifiedAt: Date
	var folder: String
	var isFavorite: Bool
	var order: Int

	init(id: UUID = UUID(), name: String, url: URL, modifiedAt: Date = .now, folder: String = "", isFavorite: Bool = false, order: Int = 0) {
		self.id = id
		self.name = name
		self.url = url
		self.modifiedAt = modifiedAt
		self.folder = folder
		self.isFavorite = isFavorite
		self.order = order
	}

	private enum CodingKeys: String, CodingKey {
		case id, name, url, modifiedAt, folder, isFavorite, order
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decode(UUID.self, forKey: .id)
		name = try values.decode(String.self, forKey: .name)
		url = try values.decode(URL.self, forKey: .url)
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
		folder = try values.decodeIfPresent(String.self, forKey: .folder) ?? ""
		isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
		order = try values.decodeIfPresent(Int.self, forKey: .order) ?? Int.min
	}

	static func preservingLegacyOrder(_ bookmarks: [Self]) -> [Self] {
		bookmarks.enumerated().map { index, source in
			guard source.order == Int.min else { return source }
			var bookmark = source
			bookmark.order = index
			return bookmark
		}
	}
}

nonisolated struct ReadingListItem: Codable, Identifiable, Equatable, Sendable {
	var id: UUID
	var url: URL
	var title: String
	var addedAt: Date
	var modifiedAt: Date
	var isRead: Bool

	init(id: UUID = UUID(), url: URL, title: String, addedAt: Date = .now, modifiedAt: Date = .now, isRead: Bool = false) {
		self.id = id
		self.url = url
		self.title = title
		self.addedAt = addedAt
		self.modifiedAt = modifiedAt
		self.isRead = isRead
	}
}

nonisolated enum BrowserUserDataMutation {
	static func nextDate(after modifiedAt: Date, deletion: Date = .distantPast) -> Date {
		let latest = max(modifiedAt, deletion)
		let now = Date.now
		return now > latest ? now : latest.addingTimeInterval(0.001)
	}
}
