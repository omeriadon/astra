import Foundation

struct OpenTab: Codable, Identifiable, Equatable {
	var id: UUID
	var title: String
	var url: URL?
	var history: [URL]
	var historyIndex: Int

	init(
		id: UUID = UUID(),
		title: String = "",
		url: URL? = nil,
		history: [URL] = [],
		historyIndex: Int = 0
	) {
		self.id = id
		self.title = title
		self.url = url
		self.history = history
		self.historyIndex = Self.clampedIndex(historyIndex, count: history.count)
	}

	private enum CodingKeys: String, CodingKey {
		case id
		case title
		case url
		case history
		case historyIndex
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
		url = try container.decodeIfPresent(URL.self, forKey: .url)
		history = try container.decodeIfPresent([URL].self, forKey: .history) ?? url.map { [$0] } ?? []
		historyIndex = try Self.clampedIndex(
			container.decodeIfPresent(Int.self, forKey: .historyIndex) ?? 0,
			count: history.count
		)
	}

	private static func clampedIndex(_ index: Int, count: Int) -> Int {
		guard count > 0 else { return 0 }
		return min(max(index, 0), count - 1)
	}
}
