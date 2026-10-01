import Foundation

struct BrowserWorkspace: Codable, Equatable, Sendable {
	var spaces: [BrowserSpace]
	var favouriteTabIDs: [UUID]
	var favouritesModifiedAt: Date
	var selectedSpaceID: UUID
	var deletedSpaceIDs: Set<UUID>
	var deletedSpacesAt: [UUID: Date]
	var modifiedAt: Date
	var selectionModifiedAt: Date

	init(
		spaces: [BrowserSpace],
		favouriteTabIDs: [UUID],
		favouritesModifiedAt: Date = .now,
		selectedSpaceID: UUID,
		deletedSpaceIDs: Set<UUID> = [],
		deletedSpacesAt: [UUID: Date] = [:],
		modifiedAt: Date = .now,
		selectionModifiedAt: Date = .now
	) {
		self.spaces = spaces
		self.favouriteTabIDs = favouriteTabIDs
		self.favouritesModifiedAt = favouritesModifiedAt
		self.selectedSpaceID = selectedSpaceID
		self.deletedSpaceIDs = deletedSpaceIDs
		self.deletedSpacesAt = deletedSpacesAt
		self.modifiedAt = modifiedAt
		self.selectionModifiedAt = selectionModifiedAt
	}

	private enum CodingKeys: String, CodingKey {
		case spaces, favouriteTabIDs, favouritesModifiedAt, selectedSpaceID
		case deletedSpaceIDs, deletedSpacesAt, modifiedAt, selectionModifiedAt
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		spaces = try values.decode([BrowserSpace].self, forKey: .spaces)
		favouriteTabIDs = try values.decode([UUID].self, forKey: .favouriteTabIDs)
		favouritesModifiedAt = try values.decodeIfPresent(Date.self, forKey: .favouritesModifiedAt) ?? .distantPast
		selectedSpaceID = try values.decode(UUID.self, forKey: .selectedSpaceID)
		deletedSpaceIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .deletedSpaceIDs) ?? []
		deletedSpacesAt = try values.decodeIfPresent([UUID: Date].self, forKey: .deletedSpacesAt) ?? [:]
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
		selectionModifiedAt = try values.decodeIfPresent(Date.self, forKey: .selectionModifiedAt) ?? .distantPast
	}

	nonisolated func encode(to encoder: Encoder) throws {
		var values = encoder.container(keyedBy: CodingKeys.self)
		try values.encode(spaces, forKey: .spaces)
		try values.encode(favouriteTabIDs, forKey: .favouriteTabIDs)
		try values.encode(favouritesModifiedAt, forKey: .favouritesModifiedAt)
		try values.encode(selectedSpaceID, forKey: .selectedSpaceID)
		try values.encode(deletedSpaceIDs, forKey: .deletedSpaceIDs)
		try values.encode(deletedSpacesAt, forKey: .deletedSpacesAt)
		try values.encode(modifiedAt, forKey: .modifiedAt)
		try values.encode(selectionModifiedAt, forKey: .selectionModifiedAt)
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
			selectedTabID: selectedTabID,
			modifiedAt: .distantPast
		)
		return Self(
			spaces: [space],
			favouriteTabIDs: [],
			favouritesModifiedAt: .distantPast,
			selectedSpaceID: space.id,
			modifiedAt: .distantPast,
			selectionModifiedAt: .distantPast
		)
	}
}
