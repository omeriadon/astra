import Foundation

struct BrowserSnapshot: Codable, Equatable {
	var selectedTabID: UUID
	var closedTabIDs: Set<UUID>
	var deletedBookmarkIDs: Set<UUID>

	init(
		selectedTabID: UUID = UUID(),
		closedTabIDs: Set<UUID> = [],
		deletedBookmarkIDs: Set<UUID> = []
	) {
		self.selectedTabID = selectedTabID
		self.closedTabIDs = closedTabIDs
		self.deletedBookmarkIDs = deletedBookmarkIDs
	}

	private enum CodingKeys: String, CodingKey {
		case selectedTabID
		case closedTabIDs
		case deletedBookmarkIDs
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID) ?? UUID()
		closedTabIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .closedTabIDs) ?? []
		deletedBookmarkIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .deletedBookmarkIDs) ?? []
	}
}
