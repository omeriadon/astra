import Foundation

struct BrowserSyncDocument: Codable, Equatable, Sendable {
	var version: Int = 2
	var tabs: [OpenTab]
	var workspace: BrowserWorkspace?
	var bookmarks: [Bookmark]
	var browser: BrowserSnapshot
	var settings: [String: SyncedSetting]

	init(
		tabs: [OpenTab],
		workspace: BrowserWorkspace,
		bookmarks: [Bookmark],
		browser: BrowserSnapshot,
		settings: [String: SyncedSetting]
	) {
		self.tabs = tabs
		self.workspace = workspace
		self.bookmarks = bookmarks
		self.browser = browser
		self.settings = settings
	}

	nonisolated var hasValidStructure: Bool {
		Set(tabs.map(\.id)).count == tabs.count
			&& Set(bookmarks.map(\.id)).count == bookmarks.count
			&& tabs.allSatisfy { tab in
				tab.pageZoom.isFinite && (0.25 ... 5).contains(tab.pageZoom)
					&& tab.restorationState == nil && tab.fileAccessBookmark == nil
					&& (tab.history + [tab.url].compactMap(\.self) + tab.peeks.compactMap(\.url)).allSatisfy {
						["http", "https"].contains($0.scheme?.lowercased() ?? "")
					}
			}
			&& bookmarks.allSatisfy { ["http", "https"].contains($0.url.scheme?.lowercased() ?? "") }
			&& (workspace.map { value in
				Set(value.spaces.map(\.id)).count == value.spaces.count
					&& value.spaces.allSatisfy { Set($0.pinnedFolders.map(\.id)).count == $0.pinnedFolders.count }
			} ?? true)
	}

	private enum CodingKeys: String, CodingKey {
		case version
		case tabs
		case workspace
		case bookmarks
		case browser
		case settings
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
		tabs = try values.decode([OpenTab].self, forKey: .tabs)
		workspace = try values.decodeIfPresent(BrowserWorkspace.self, forKey: .workspace)
		bookmarks = try values.decode([Bookmark].self, forKey: .bookmarks)
		browser = try values.decode(BrowserSnapshot.self, forKey: .browser)
		settings = try values.decode([String: SyncedSetting].self, forKey: .settings)
	}

	nonisolated func encode(to encoder: Encoder) throws {
		var values = encoder.container(keyedBy: CodingKeys.self)
		try values.encode(version, forKey: .version)
		try values.encode(tabs, forKey: .tabs)
		try values.encodeIfPresent(workspace, forKey: .workspace)
		try values.encode(bookmarks, forKey: .bookmarks)
		try values.encode(browser, forKey: .browser)
		try values.encode(settings, forKey: .settings)
	}

	nonisolated func merging(_ other: Self) -> Self {
		var merged = self
		merged.browser.closedTabIDs.formUnion(other.browser.closedTabIDs)
		merged.browser.deletedBookmarkIDs.formUnion(other.browser.deletedBookmarkIDs)

		var tabsByID = tabs.reduce(into: [UUID: OpenTab]()) { $0[$1.id] = $1 }
		for tab in other.tabs {
			if let existing = tabsByID[tab.id], existing.modifiedAt >= tab.modifiedAt {
				continue
			}
			tabsByID[tab.id] = tab
		}
		let closedTabIDs = merged.browser.closedTabIDs
		merged.tabs = (tabs.map(\.id) + other.tabs.map(\.id))
			.uniqued()
			.compactMap { tabsByID[$0] }
			.filter { !closedTabIDs.contains($0.id) }

		if var workspace = workspace ?? other.workspace {
			if let otherWorkspace = other.workspace {
				workspace.deletedSpaceIDs.formUnion(otherWorkspace.deletedSpaceIDs)
				for space in otherWorkspace.spaces {
					guard !workspace.deletedSpaceIDs.contains(space.id) else { continue }
					if let index = workspace.spaces.firstIndex(where: { $0.id == space.id }) {
						if space.modifiedAt > workspace.spaces[index].modifiedAt {
							workspace.spaces[index] = space
						}
					} else {
						workspace.spaces.append(space)
					}
				}
				if otherWorkspace.favouritesModifiedAt > workspace.favouritesModifiedAt {
					workspace.favouriteTabIDs = otherWorkspace.favouriteTabIDs
					workspace.favouritesModifiedAt = otherWorkspace.favouritesModifiedAt
				}
			}
			workspace.spaces.removeAll { workspace.deletedSpaceIDs.contains($0.id) }
			if workspace.spaces.isEmpty {
				workspace.spaces = [BrowserSpace()]
			}
			if !workspace.spaces.contains(where: { $0.id == workspace.selectedSpaceID }) {
				workspace.selectedSpaceID = workspace.spaces[0].id
			}
			var assigned = Set(workspace.favouriteTabIDs)
			let newestSpacesFirst = workspace.spaces.indices.sorted {
				workspace.spaces[$0].modifiedAt > workspace.spaces[$1].modifiedAt
			}
			for index in newestSpacesFirst {
				workspace.spaces[index].tabIDs.removeAll { !assigned.insert($0).inserted }
				let tabIDs = Set(workspace.spaces[index].tabIDs)
				workspace.spaces[index].pinnedTabIDs.removeAll { !tabIDs.contains($0) }
				let pinnedIDs = Set(workspace.spaces[index].pinnedTabIDs)
				for folderIndex in workspace.spaces[index].pinnedFolders.indices {
					workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.removeAll { !pinnedIDs.contains($0) }
				}
			}
			let unassignedIDs = merged.tabs.map(\.id).filter { !assigned.contains($0) }
			let firstIndex = workspace.spaces.firstIndex(where: { $0.id == BrowserSpace.firstID }) ?? 0
			workspace.spaces[firstIndex].tabIDs.append(contentsOf: unassignedIDs)
			merged.workspace = workspace
		}

		var bookmarksByID = bookmarks.reduce(into: [UUID: Bookmark]()) { $0[$1.id] = $1 }
		bookmarksByID.merge(other.bookmarks.map { ($0.id, $0) }) { current, _ in current }
		let deletedBookmarkIDs = merged.browser.deletedBookmarkIDs
		merged.bookmarks = (bookmarks.map(\.id) + other.bookmarks.map(\.id))
			.uniqued()
			.compactMap { bookmarksByID[$0] }
			.filter { !deletedBookmarkIDs.contains($0.id) }

		for (key, setting) in other.settings {
			if let existing = merged.settings[key], existing.modifiedAt >= setting.modifiedAt {
				continue
			}
			merged.settings[key] = setting
		}
		return merged
	}
}

struct SyncedSetting: Codable, Equatable, Sendable {
	var value: Data?
	var modifiedAt: Date
}

private extension Sequence where Element: Hashable {
	nonisolated func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
