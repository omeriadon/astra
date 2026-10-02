import Foundation

struct BrowserSnapshot: Codable, Equatable, Sendable {
	var selectedTabID: UUID
	var selectedTabModifiedAt: Date
	var closedTabIDs: Set<UUID>
	var deletedBookmarkIDs: Set<UUID>
	// ponytail: retain tombstones indefinitely; add peer-watermark compaction if snapshot growth becomes material.
	var deletedBookmarksAt: [UUID: Date]
	var deletedReadingListAt: [UUID: Date]
	var closedTabsAt: [UUID: Date]
	var deletedSpacesAt: [UUID: Date]
	var deletedVisitsAt: [UUID: Date]
	var historyClearedAt: Date

	init(
		selectedTabID: UUID = UUID(),
		selectedTabModifiedAt: Date = .distantPast,
		closedTabIDs: Set<UUID> = [],
		deletedBookmarkIDs: Set<UUID> = [],
		deletedBookmarksAt: [UUID: Date] = [:],
		deletedReadingListAt: [UUID: Date] = [:],
		closedTabsAt: [UUID: Date] = [:],
		deletedSpacesAt: [UUID: Date] = [:],
		deletedVisitsAt: [UUID: Date] = [:],
		historyClearedAt: Date = .distantPast
	) {
		self.selectedTabID = selectedTabID
		self.selectedTabModifiedAt = selectedTabModifiedAt
		self.closedTabIDs = closedTabIDs
		self.deletedBookmarkIDs = deletedBookmarkIDs
		self.deletedBookmarksAt = deletedBookmarksAt
		self.deletedReadingListAt = deletedReadingListAt
		self.closedTabsAt = closedTabsAt
		self.deletedSpacesAt = deletedSpacesAt
		self.deletedVisitsAt = deletedVisitsAt
		self.historyClearedAt = historyClearedAt
	}

	private enum CodingKeys: String, CodingKey {
		case selectedTabID
		case selectedTabModifiedAt
		case closedTabIDs
		case deletedBookmarkIDs
		case deletedBookmarksAt, deletedReadingListAt, closedTabsAt, deletedSpacesAt, deletedVisitsAt, historyClearedAt
	}

	nonisolated init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID) ?? UUID()
		selectedTabModifiedAt = try container.decodeIfPresent(Date.self, forKey: .selectedTabModifiedAt) ?? .distantPast
		closedTabIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .closedTabIDs) ?? []
		deletedBookmarkIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .deletedBookmarkIDs) ?? []
		deletedBookmarksAt = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedBookmarksAt) ?? [:]
		deletedReadingListAt = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedReadingListAt) ?? [:]
		closedTabsAt = try container.decodeIfPresent([UUID: Date].self, forKey: .closedTabsAt) ?? [:]
		deletedSpacesAt = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedSpacesAt) ?? [:]
		deletedVisitsAt = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedVisitsAt) ?? [:]
		historyClearedAt = try container.decodeIfPresent(Date.self, forKey: .historyClearedAt) ?? .distantPast
	}

	nonisolated func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(selectedTabID, forKey: .selectedTabID)
		try container.encode(selectedTabModifiedAt, forKey: .selectedTabModifiedAt)
		try container.encode(closedTabIDs, forKey: .closedTabIDs)
		try container.encode(deletedBookmarkIDs, forKey: .deletedBookmarkIDs)
		try container.encode(deletedBookmarksAt, forKey: .deletedBookmarksAt)
		try container.encode(deletedReadingListAt, forKey: .deletedReadingListAt)
		try container.encode(closedTabsAt, forKey: .closedTabsAt)
		try container.encode(deletedSpacesAt, forKey: .deletedSpacesAt)
		try container.encode(deletedVisitsAt, forKey: .deletedVisitsAt)
		try container.encode(historyClearedAt, forKey: .historyClearedAt)
	}
}
