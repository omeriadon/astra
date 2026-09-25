import Foundation

struct OpenTab: Codable, Identifiable, Equatable {
	var id: UUID
	var internalPage: String?
	var pageTitle: String
	var customTitle: String?
	var url: URL?
	var history: [URL]
	var historyIndex: Int
	var pageZoom: Double
	var scrollPosition: BrowserScrollPosition
	var isHibernated: Bool
	var modifiedAt: Date
	var peeks: [OpenPeek]

	init(
		id: UUID = UUID(),
		internalPage: String? = nil,
		pageTitle: String = "New Tab",
		customTitle: String? = nil,
		url: URL? = nil,
		history: [URL] = [],
		historyIndex: Int = 0,
		pageZoom: Double = 1,
		scrollPosition: BrowserScrollPosition = .zero,
		isHibernated: Bool = false,
		modifiedAt: Date = .now,
		peeks: [OpenPeek] = []
	) {
		self.id = id
		self.internalPage = internalPage
		self.pageTitle = pageTitle
		self.customTitle = customTitle
		self.url = url
		self.history = history
		self.historyIndex = Self.clampedIndex(historyIndex, count: history.count)
		self.peeks = peeks
		self.pageZoom = pageZoom
		self.scrollPosition = scrollPosition
		self.isHibernated = isHibernated
		self.modifiedAt = modifiedAt
	}

	private enum CodingKeys: String, CodingKey {
		case id
		case internalPage
		case title
		case pageTitle
		case customTitle
		case url
		case history
		case historyIndex
		case peeks
		case pageZoom
		case scrollPosition
		case isHibernated
		case modifiedAt
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		internalPage = try container.decodeIfPresent(String.self, forKey: .internalPage)
		let legacyTitle = try container.decodeIfPresent(String.self, forKey: .title)
		pageTitle = try container.decodeIfPresent(String.self, forKey: .pageTitle) ?? "New Tab"
		if container.contains(.customTitle) {
			customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
		} else if let legacyTitle, !legacyTitle.isEmpty, legacyTitle != "New Tab" {
			customTitle = legacyTitle
		} else {
			customTitle = nil
		}
		url = try container.decodeIfPresent(URL.self, forKey: .url)
		history = try container.decodeIfPresent([URL].self, forKey: .history) ?? url.map { [$0] } ?? []
		historyIndex = try Self.clampedIndex(
			container.decodeIfPresent(Int.self, forKey: .historyIndex) ?? 0,
			count: history.count
		)
		peeks = try container.decodeIfPresent([OpenPeek].self, forKey: .peeks) ?? []
		pageZoom = try container.decodeIfPresent(Double.self, forKey: .pageZoom) ?? 1
		scrollPosition = try container.decodeIfPresent(BrowserScrollPosition.self, forKey: .scrollPosition) ?? .zero
		isHibernated = try container.decodeIfPresent(Bool.self, forKey: .isHibernated) ?? false
		modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(id, forKey: .id)
		try container.encodeIfPresent(internalPage, forKey: .internalPage)
		try container.encode(pageTitle, forKey: .pageTitle)
		try container.encodeIfPresent(customTitle, forKey: .customTitle)
		try container.encodeIfPresent(url, forKey: .url)
		try container.encode(history, forKey: .history)
		try container.encode(historyIndex, forKey: .historyIndex)
		try container.encode(peeks, forKey: .peeks)
		try container.encode(pageZoom, forKey: .pageZoom)
		try container.encode(scrollPosition, forKey: .scrollPosition)
		try container.encode(isHibernated, forKey: .isHibernated)
		try container.encode(modifiedAt, forKey: .modifiedAt)
	}

	private static func clampedIndex(_ index: Int, count: Int) -> Int {
		guard count > 0 else { return 0 }
		return min(max(index, 0), count - 1)
	}
}
