import Foundation

struct BrowserSnapshot: Codable, Equatable {
	var selectedTabID: UUID

	init(selectedTabID: UUID = UUID()) {
		self.selectedTabID = selectedTabID
	}

	private enum CodingKeys: String, CodingKey {
		case selectedTabID
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID) ?? UUID()
	}
}
