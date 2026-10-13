import Foundation

struct OpenPeek: Codable, Equatable, Identifiable, Sendable {
	let id: UUID
	let depth: Int
	let sourceX: Double
	let sourceY: Double
	let url: URL?
	let history: [URL]
	let historyIndex: Int
	let pageZoom: Double
	let scrollPosition: BrowserScrollPosition
	let easelQuote: BrowserEaselQuote?

	private enum CodingKeys: String, CodingKey {
		case id
		case depth
		case sourceX
		case sourceY
		case url
		case history
		case historyIndex
		case pageZoom
		case scrollPosition
		case easelQuote
	}

	init(
		id: UUID,
		depth: Int,
		sourceX: Double,
		sourceY: Double,
		url: URL?,
		history: [URL],
		historyIndex: Int,
		pageZoom: Double,
		scrollPosition: BrowserScrollPosition,
		easelQuote: BrowserEaselQuote? = nil
	) {
		self.id = id
		self.depth = depth
		self.sourceX = sourceX
		self.sourceY = sourceY
		self.url = url
		self.history = history
		self.historyIndex = historyIndex
		self.pageZoom = pageZoom
		self.scrollPosition = scrollPosition
		self.easelQuote = easelQuote
	}

	nonisolated init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(UUID.self, forKey: .id)
		depth = try container.decode(Int.self, forKey: .depth)
		sourceX = try container.decode(Double.self, forKey: .sourceX)
		sourceY = try container.decode(Double.self, forKey: .sourceY)
		url = try container.decodeIfPresent(URL.self, forKey: .url)
		history = try container.decode([URL].self, forKey: .history)
		historyIndex = try container.decode(Int.self, forKey: .historyIndex)
		pageZoom = try container.decode(Double.self, forKey: .pageZoom)
		scrollPosition = try container.decodeIfPresent(BrowserScrollPosition.self, forKey: .scrollPosition) ?? .zero
		easelQuote = try container.decodeIfPresent(BrowserEaselQuote.self, forKey: .easelQuote)
		if let easelQuote, !easelQuote.isValid {
			throw DecodingError.dataCorruptedError(forKey: .easelQuote, in: container, debugDescription: "Invalid Easel quote")
		}
	}
}
