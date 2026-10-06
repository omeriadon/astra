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

	mutating func reconcileMembership(existingTabIDs: Set<UUID>, unassignedTabIDs: [UUID]) {
		var seenFavourites = Set<UUID>()
		favouriteTabIDs = favouriteTabIDs.filter {
			existingTabIDs.contains($0) && seenFavourites.insert($0).inserted
		}

		var owners: [UUID: (modifiedAt: Date, key: String)] = [:]
		for id in favouriteTabIDs {
			owners[id] = (favouritesModifiedAt, "0-favourites")
		}
		for space in spaces {
			let key = "1-\(space.id.uuidString)"
			for id in space.tabIDs where existingTabIDs.contains(id) {
				if let owner = owners[id],
				   owner.modifiedAt > space.modifiedAt
				   || (owner.modifiedAt == space.modifiedAt && owner.key <= key)
				{
					continue
				}
				owners[id] = (space.modifiedAt, key)
			}
		}
		favouriteTabIDs.removeAll { owners[$0]?.key != "0-favourites" }

		for index in spaces.indices {
			let ownerKey = "1-\(spaces[index].id.uuidString)"
			var seenTabs = Set<UUID>()
			spaces[index].tabIDs = spaces[index].tabIDs.filter { id in
				guard existingTabIDs.contains(id),
				      owners[id]?.key == ownerKey
				else { return false }
				return seenTabs.insert(id).inserted
			}

			let tabIDs = Set(spaces[index].tabIDs)
			var seenPinned = Set<UUID>()
			spaces[index].pinnedTabIDs = spaces[index].pinnedTabIDs.filter {
				tabIDs.contains($0) && seenPinned.insert($0).inserted
			}

			let normalIDs = tabIDs.subtracting(spaces[index].pinnedTabIDs)
			var groupedIDs = Set<UUID>()
			spaces[index].todayTabGroups = spaces[index].todayTabGroups.compactMap { group in
				let ids = group.tabIDs.filter { normalIDs.contains($0) && groupedIDs.insert($0).inserted }
				return ids.isEmpty ? nil : BrowserTabGroupingFeature.Group(name: group.name, tabIDs: ids)
			}

			let pinnedIDs = Set(spaces[index].pinnedTabIDs)
			var folderIndexes: [UUID: Int] = [:]
			var folders: [PinnedTabFolder] = []
			for folder in spaces[index].pinnedFolders {
				guard let existingIndex = folderIndexes[folder.id] else {
					folderIndexes[folder.id] = folders.count
					folders.append(folder)
					continue
				}
				let current = folders[existingIndex]
				let currentKey = "\(current.name)|\(current.tabIDs.map(\.uuidString).joined(separator: ","))"
				let incomingKey = "\(folder.name)|\(folder.tabIDs.map(\.uuidString).joined(separator: ","))"
				if folder.modifiedAt > current.modifiedAt
					|| (folder.modifiedAt == current.modifiedAt && incomingKey < currentKey)
				{
					folders[existingIndex] = folder
				}
			}
			var folderOwners: [UUID: (modifiedAt: Date, folderID: UUID)] = [:]
			for folder in folders {
				for tabID in folder.tabIDs where pinnedIDs.contains(tabID) {
					if let current = folderOwners[tabID],
					   current.modifiedAt > folder.modifiedAt
					   || (current.modifiedAt == folder.modifiedAt && current.folderID.uuidString < folder.id.uuidString)
					{
						continue
					}
					folderOwners[tabID] = (folder.modifiedAt, folder.id)
				}
			}
			spaces[index].pinnedFolders = folders.map { folder in
				var folder = folder
				var seenFolderTabs = Set<UUID>()
				folder.tabIDs = folder.tabIDs.filter {
					pinnedIDs.contains($0)
						&& folderOwners[$0]?.folderID == folder.id
						&& seenFolderTabs.insert($0).inserted
				}
				return folder
			}
			if let selectedTabID = spaces[index].selectedTabID,
			   !tabIDs.contains(selectedTabID),
			   !favouriteTabIDs.contains(selectedTabID)
			{
				spaces[index].selectedTabID = spaces[index].tabIDs.first
			}
		}

		if let index = spaces.firstIndex(where: { $0.id == selectedSpaceID }) {
			var assigned = Set(favouriteTabIDs + spaces.flatMap(\.tabIDs))
			spaces[index].tabIDs.append(contentsOf: unassignedTabIDs.filter {
				existingTabIDs.contains($0) && assigned.insert($0).inserted
			})
		}
	}

	static func tabSwitchCandidates(
		visibleTabIDs: [UUID],
		recentlyUsedTabIDs: [UUID],
		selectedTabID: UUID,
		forward: Bool
	) -> [UUID] {
		var seen = Set<UUID>()
		let ids = recentlyUsedTabIDs.filter { visibleTabIDs.contains($0) && seen.insert($0).inserted }
			+ visibleTabIDs.filter { seen.insert($0).inserted }
		guard ids.count > 1, let selectedIndex = ids.firstIndex(of: selectedTabID) else { return [] }
		return (1 ... ids.count).map { offset in
			let direction = forward ? offset : ids.count - offset
			return ids[(selectedIndex + direction) % ids.count]
		}
	}

	static func tabSelectionAfterClosing(
		tabID: UUID,
		normalTabIDs: [UUID],
		visibleTabIDs: [UUID]
	) -> UUID? {
		if let index = normalTabIDs.firstIndex(of: tabID), normalTabIDs.count > 1 {
			return normalTabIDs[index > 0 ? index - 1 : index + 1]
		}
		return visibleTabIDs.first { $0 != tabID }
	}
}
