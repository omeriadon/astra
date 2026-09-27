import Foundation

struct BrowserWorkspace: Codable, Equatable {
	var spaces: [BrowserSpace]
	var favouriteTabIDs: [UUID]
	var favouritesModifiedAt: Date
	var selectedSpaceID: UUID

	init(
		spaces: [BrowserSpace],
		favouriteTabIDs: [UUID],
		favouritesModifiedAt: Date = .now,
		selectedSpaceID: UUID
	) {
		self.spaces = spaces
		self.favouriteTabIDs = favouriteTabIDs
		self.favouritesModifiedAt = favouritesModifiedAt
		self.selectedSpaceID = selectedSpaceID
	}

	private enum CodingKeys: String, CodingKey {
		case spaces
		case favouriteTabIDs
		case favouritesModifiedAt
		case selectedSpaceID
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		spaces = try values.decode([BrowserSpace].self, forKey: .spaces)
		favouriteTabIDs = try values.decode([UUID].self, forKey: .favouriteTabIDs)
		favouritesModifiedAt = try values.decodeIfPresent(Date.self, forKey: .favouritesModifiedAt) ?? .distantPast
		selectedSpaceID = try values.decode(UUID.self, forKey: .selectedSpaceID)
	}

	static func migrated(
		tabs: [OpenTab],
		selectedTabID: UUID,
		theme: BrowserTheme
	) -> Self {
		let space = BrowserSpace(
			id: BrowserSpace.firstID,
			theme: theme,
			tabIDs: tabs.map(\.id),
			selectedTabID: selectedTabID
		)
		return Self(spaces: [space], favouriteTabIDs: [], selectedSpaceID: space.id)
	}
}
