import Foundation

struct BrowserSyncDocument: Codable, Equatable, Sendable {
	var version: Int = 3
	var tabs: [OpenTab]
	var workspace: BrowserWorkspace?
	var bookmarks: [Bookmark]
	var readingList: [ReadingListItem]
	var history: [BrowserVisit]
	var browser: BrowserSnapshot
	var settings: [String: SyncedSetting]

	init(
		tabs: [OpenTab],
		workspace: BrowserWorkspace,
		bookmarks: [Bookmark],
		readingList: [ReadingListItem] = [],
		history: [BrowserVisit] = [],
		browser: BrowserSnapshot,
		settings: [String: SyncedSetting]
	) {
		self.tabs = tabs
		self.workspace = workspace
		self.bookmarks = bookmarks
		self.readingList = readingList
		self.history = history
		self.browser = browser
		self.settings = settings
	}

	private enum CodingKeys: String, CodingKey {
		case version, tabs, workspace, bookmarks, readingList, history, browser, settings
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
		tabs = try values.decode([OpenTab].self, forKey: .tabs)
		workspace = try values.decodeIfPresent(BrowserWorkspace.self, forKey: .workspace)
		bookmarks = try Bookmark.preservingLegacyOrder(values.decode([Bookmark].self, forKey: .bookmarks))
		readingList = try values.decodeIfPresent([ReadingListItem].self, forKey: .readingList) ?? []
		history = try values.decodeIfPresent([BrowserVisit].self, forKey: .history) ?? []
		browser = try values.decode(BrowserSnapshot.self, forKey: .browser)
		settings = try values.decode([String: SyncedSetting].self, forKey: .settings)
	}

	nonisolated func encode(to encoder: Encoder) throws {
		var values = encoder.container(keyedBy: CodingKeys.self)
		try values.encode(version, forKey: .version)
		try values.encode(tabs, forKey: .tabs)
		try values.encodeIfPresent(workspace, forKey: .workspace)
		try values.encode(bookmarks, forKey: .bookmarks)
		try values.encode(readingList, forKey: .readingList)
		try values.encode(history, forKey: .history)
		try values.encode(browser, forKey: .browser)
		try values.encode(settings, forKey: .settings)
	}

	nonisolated func portableProjection() -> Self {
		var projected = self
		let localOnlyTabIDs = Set(tabs.filter { !isPortableSyncTab($0) }.map(\.id))
		let localOnlyBookmarkIDs = Set(bookmarks.filter { !isPortableSyncURL($0.url) }.map(\.id))
		let portableTabs = tabs.filter { isPortableSyncTab($0) }
		let portableTabIDs = Set(portableTabs.map(\.id))
		projected.tabs = portableTabs.map { tab in
			var tab = tab
			tab.url = tab.url.map(credentialFreeSyncURL)
			tab.history = tab.url.map { [$0] } ?? []
			tab.historyIndex = 0
			tab.restorationState = nil
			tab.fileAccessBookmark = nil
			tab.peeks = []
			return tab
		}
		projected.bookmarks = bookmarks.filter { isPortableSyncURL($0.url) }.map { bookmark in
			var bookmark = bookmark
			bookmark.url = credentialFreeSyncURL(bookmark.url)
			return bookmark
		}
		projected.readingList = readingList.filter { isPortableSyncURL($0.url) }.map { item in
			var item = item
			item.url = credentialFreeSyncURL(item.url)
			return item
		}
		projected.history = history.filter { isPortableSyncURL($0.url) }.map { visit in
			var visit = visit
			visit.url = credentialFreeSyncURL(visit.url)
			return visit
		}
		projected.browser.closedTabIDs.subtract(localOnlyTabIDs)
		projected.browser.closedTabsAt = projected.browser.closedTabsAt.filter { !localOnlyTabIDs.contains($0.key) }
		projected.browser.deletedBookmarkIDs.subtract(localOnlyBookmarkIDs)
		projected.browser.deletedBookmarksAt = projected.browser.deletedBookmarksAt.filter { !localOnlyBookmarkIDs.contains($0.key) }
		if var workspace {
			workspace.favouriteTabIDs.removeAll { !portableTabIDs.contains($0) }
			for index in workspace.spaces.indices {
				let foldersWithMembers = Set(workspace.spaces[index].pinnedFolders.filter { !$0.tabIDs.isEmpty }.map(\.id))
				workspace.spaces[index].tabIDs.removeAll { !portableTabIDs.contains($0) }
				workspace.spaces[index].pinnedTabIDs.removeAll { !portableTabIDs.contains($0) }
				for folderIndex in workspace.spaces[index].pinnedFolders.indices {
					workspace.spaces[index].pinnedFolders[folderIndex].tabIDs.removeAll { !portableTabIDs.contains($0) }
				}
				workspace.spaces[index].pinnedFolders.removeAll { folder in
					foldersWithMembers.contains(folder.id) && folder.tabIDs.isEmpty
				}
				if let selectedID = workspace.spaces[index].selectedTabID,
				   !portableTabIDs.contains(selectedID)
				{
					workspace.spaces[index].selectedTabID = workspace.spaces[index].tabIDs.first
				}
			}
			let deletedSpaceDates = workspace.deletedSpacesAt
			let deletedSpaceIDs = workspace.deletedSpaceIDs
			workspace.spaces.removeAll { space in
				isDeleted(space.id, modifiedAt: space.modifiedAt, dates: deletedSpaceDates, legacyIDs: deletedSpaceIDs)
			}
			projected.workspace = workspace
		}
		if !portableTabIDs.contains(projected.browser.selectedTabID) {
			projected.browser.selectedTabID = projected.tabs.first?.id ?? BrowserSpace.firstID
		}
		return projected
	}

	nonisolated func preservingLocalOnlyData(from local: Self) -> Self {
		var projected = self
		let localTabs = local.tabs.filter { !isPortableSyncTab($0) && $0.internalPage == nil }
		let localTabIDs = Set(localTabs.map(\.id))
		var tabsByID = Dictionary(projected.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		for tab in localTabs {
			tabsByID[tab.id] = tab
		}
		projected.tabs = tabsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }

		var bookmarksByID = Dictionary(projected.bookmarks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		for bookmark in local.bookmarks where !isPortableSyncURL(bookmark.url) {
			bookmarksByID[bookmark.id] = bookmark
		}
		projected.bookmarks = bookmarksByID.values.sorted {
			$0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
		}

		guard let localWorkspace = local.workspace else { return projected }
		var target = projected.workspace ?? localWorkspace
		let localFavouriteIDs = localWorkspace.favouriteTabIDs.filter(localTabIDs.contains)
		target.favouriteTabIDs = appendUnique(target.favouriteTabIDs, localFavouriteIDs)
		target.favouritesModifiedAt = max(target.favouritesModifiedAt, localWorkspace.favouritesModifiedAt)

		for localSpace in localWorkspace.spaces {
			let localMembers = localSpace.tabIDs.filter(localTabIDs.contains)
			let localPinned = localSpace.pinnedTabIDs.filter(localTabIDs.contains)
			let localFolders = localSpace.pinnedFolders.compactMap { folder -> PinnedTabFolder? in
				let members = folder.tabIDs.filter(localTabIDs.contains)
				guard !members.isEmpty else { return nil }
				var folder = folder
				folder.tabIDs = members
				return folder
			}
			guard !localMembers.isEmpty || !localPinned.isEmpty || !localFolders.isEmpty else { continue }
			guard !isDeleted(
				localSpace.id,
				modifiedAt: localSpace.modifiedAt,
				dates: target.deletedSpacesAt,
				legacyIDs: target.deletedSpaceIDs
			) else { continue }

			if let index = target.spaces.firstIndex(where: { $0.id == localSpace.id }) {
				target.spaces[index].tabIDs = appendUnique(target.spaces[index].tabIDs, localMembers)
				target.spaces[index].pinnedTabIDs = appendUnique(target.spaces[index].pinnedTabIDs, localPinned)
				for localFolder in localFolders {
					if let folderIndex = target.spaces[index].pinnedFolders.firstIndex(where: { $0.id == localFolder.id }) {
						target.spaces[index].pinnedFolders[folderIndex].tabIDs = appendUnique(
							target.spaces[index].pinnedFolders[folderIndex].tabIDs,
							localFolder.tabIDs
						)
						target.spaces[index].pinnedFolders[folderIndex].modifiedAt = max(
							target.spaces[index].pinnedFolders[folderIndex].modifiedAt,
							localFolder.modifiedAt
						)
					} else if localFolder.modifiedAt > (target.spaces[index].deletedPinnedFoldersAt[localFolder.id] ?? .distantPast) {
						target.spaces[index].pinnedFolders.append(localFolder)
					}
				}
				target.spaces[index].modifiedAt = max(target.spaces[index].modifiedAt, localSpace.modifiedAt)
				if let selected = localSpace.selectedTabID, localTabIDs.contains(selected), localSpace.modifiedAt >= target.spaces[index].modifiedAt {
					target.spaces[index].selectedTabID = selected
				}
			} else {
				var localOnlySpace = localSpace
				localOnlySpace.tabIDs = localMembers
				localOnlySpace.pinnedTabIDs = localPinned
				localOnlySpace.pinnedFolders = localFolders
				target.spaces.append(localOnlySpace)
			}
		}

		let localSelectedSpaceHasLocalTab = localWorkspace.spaces.contains { space in
			space.id == localWorkspace.selectedSpaceID
				&& (space.tabIDs + space.pinnedTabIDs + space.pinnedFolders.flatMap(\.tabIDs)).contains(where: localTabIDs.contains)
		}
		if localSelectedSpaceHasLocalTab, localWorkspace.selectionModifiedAt >= target.selectionModifiedAt {
			target.selectedSpaceID = localWorkspace.selectedSpaceID
			target.selectionModifiedAt = localWorkspace.selectionModifiedAt
		}
		target.modifiedAt = max(target.modifiedAt, localWorkspace.modifiedAt)
		projected.workspace = target

		if localTabIDs.contains(local.browser.selectedTabID),
		   local.browser.selectedTabModifiedAt >= projected.browser.selectedTabModifiedAt
		{
			projected.browser.selectedTabID = local.browser.selectedTabID
			projected.browser.selectedTabModifiedAt = local.browser.selectedTabModifiedAt
		}
		return projected
	}

	nonisolated var hasSupportedVersion: Bool {
		(1 ... 3).contains(version)
	}

	nonisolated var hasValidStructure: Bool {
		Set(tabs.map(\.id)).count == tabs.count
			&& Set(bookmarks.map(\.id)).count == bookmarks.count
			&& Set(history.map(\.id)).count == history.count
			&& tabs.allSatisfy { tab in
				tab.internalPage == nil
					&& tab.pageZoom.isFinite && (0.25 ... 5).contains(tab.pageZoom)
					&& tab.restorationState == nil && tab.fileAccessBookmark == nil
					&& (tab.history + [tab.url].compactMap(\.self) + tab.peeks.compactMap(\.url)).allSatisfy(isSafeSyncURL)
					&& tab.modifiedAt.isSaneSyncTimestamp
			}
			&& bookmarks.allSatisfy { bookmark in
				isSafeSyncURL(bookmark.url)
					&& (bookmark.order == Int.min || (0 ... 100_000).contains(bookmark.order))
					&& bookmark.name.utf8.count <= 16384
					&& bookmark.folder.utf8.count <= 4096
					&& bookmark.modifiedAt.isSaneSyncTimestamp
			}
			&& Set(readingList.map(\.id)).count == readingList.count
			&& readingList.allSatisfy { item in
				isSafeSyncURL(item.url)
					&& item.url.absoluteString.utf8.count <= 16384
					&& item.title.utf8.count <= 16384
					&& item.modifiedAt.isSaneSyncTimestamp
					&& item.addedAt.isSaneSyncTimestamp
			}
			&& history.allSatisfy { isSafeSyncURL($0.url) && $0.modifiedAt.isSaneSyncTimestamp && $0.visitedAt.isSaneSyncTimestamp }
			&& settings.values.allSatisfy { $0.modifiedAt.isSaneSyncTimestamp && $0.hasValidPropertyListValue }
			&& (settings[BrowserSiteZoomDocument.defaultsKey].map {
				$0.value == nil
					|| BrowserSiteZoomDocument.mergeSyncValues($0.value, $0.value) != nil
					|| BrowserSiteZoomDocument.isPreservableSyncValue($0.value)
			} ?? true)
			&& browser.selectedTabModifiedAt.isSaneSyncTimestamp
			&& browser.historyClearedAt.isSaneSyncTimestamp
			&& (Array(browser.closedTabsAt.values) + Array(browser.deletedBookmarksAt.values) + Array(browser.deletedReadingListAt.values) + Array(browser.deletedSpacesAt.values) + Array(browser.deletedVisitsAt.values)).allSatisfy(\.isSaneSyncTimestamp)
			&& (workspace.map { value in
				Set(value.spaces.map(\.id)).count == value.spaces.count
					&& value.spaces.allSatisfy { space in
						Set(space.pinnedFolders.map(\.id)).count == space.pinnedFolders.count
							&& space.modifiedAt.isSaneSyncTimestamp
							&& space.pinnedFolders.allSatisfy(\.modifiedAt.isSaneSyncTimestamp)
							&& space.deletedPinnedFoldersAt.values.allSatisfy(\.isSaneSyncTimestamp)
					}
					&& value.modifiedAt.isSaneSyncTimestamp
					&& value.selectionModifiedAt.isSaneSyncTimestamp
					&& value.favouritesModifiedAt.isSaneSyncTimestamp
					&& value.deletedSpacesAt.values.allSatisfy(\.isSaneSyncTimestamp)
			} ?? true)
	}

	nonisolated func merging(_ other: Self) -> Self {
		var result = self
		result.version = max(version, other.version)
		result.browser.closedTabIDs.formUnion(other.browser.closedTabIDs)
		result.browser.deletedBookmarkIDs.formUnion(other.browser.deletedBookmarkIDs)
		result.browser.closedTabsAt.merge(other.browser.closedTabsAt) { max($0, $1) }
		result.browser.deletedBookmarksAt.merge(other.browser.deletedBookmarksAt) { max($0, $1) }
		result.browser.deletedReadingListAt.merge(other.browser.deletedReadingListAt) { max($0, $1) }
		result.browser.deletedSpacesAt.merge(other.browser.deletedSpacesAt) { max($0, $1) }
		result.browser.deletedVisitsAt.merge(other.browser.deletedVisitsAt) { max($0, $1) }
		result.browser.historyClearedAt = max(browser.historyClearedAt, other.browser.historyClearedAt)
		if other.browser.selectedTabModifiedAt > browser.selectedTabModifiedAt
			|| (other.browser.selectedTabModifiedAt == browser.selectedTabModifiedAt
				&& other.browser.selectedTabID.uuidString < browser.selectedTabID.uuidString)
		{
			result.browser.selectedTabID = other.browser.selectedTabID
			result.browser.selectedTabModifiedAt = other.browser.selectedTabModifiedAt
		}

		let tabsByID = Dictionary((tabs + other.tabs).map { ($0.id, $0) }, uniquingKeysWith: { first, next in
			preferred(first, first.modifiedAt, next, next.modifiedAt)
		})
		result.tabs = tabsByID.values.filter { tab in
			!isDeleted(tab.id, modifiedAt: tab.modifiedAt, dates: result.browser.closedTabsAt, legacyIDs: result.browser.closedTabIDs)
		}.sorted { $0.id.uuidString < $1.id.uuidString }

		let bookmarksByID = Dictionary((bookmarks + other.bookmarks).map { ($0.id, $0) }, uniquingKeysWith: { first, next in
			preferred(first, first.modifiedAt, next, next.modifiedAt)
		})
		result.bookmarks = bookmarksByID.values.filter { item in
			!isDeleted(item.id, modifiedAt: item.modifiedAt, dates: result.browser.deletedBookmarksAt, legacyIDs: result.browser.deletedBookmarkIDs)
		}.sorted {
			$0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
		}

		let readingListByID = Dictionary((readingList + other.readingList).map { ($0.id, $0) }, uniquingKeysWith: { first, next in
			preferred(first, first.modifiedAt, next, next.modifiedAt)
		})
		result.readingList = readingListByID.values.filter { item in
			!isDeleted(item.id, modifiedAt: item.modifiedAt, dates: result.browser.deletedReadingListAt, legacyIDs: [])
		}.sorted { $0.id.uuidString < $1.id.uuidString }

		let visitsByID = Dictionary((history + other.history).map { ($0.id, $0) }, uniquingKeysWith: { first, next in
			preferred(first, first.modifiedAt, next, next.modifiedAt)
		})
		result.history = visitsByID.values.filter { visit in
			(result.browser.historyClearedAt == .distantPast || visit.modifiedAt > result.browser.historyClearedAt)
				&& !isDeleted(visit.id, modifiedAt: visit.modifiedAt, dates: result.browser.deletedVisitsAt, legacyIDs: [])
		}.sorted {
			$0.visitedAt == $1.visitedAt ? $0.id.uuidString < $1.id.uuidString : $0.visitedAt > $1.visitedAt
		}

		if let left = workspace, let right = other.workspace {
			var merged = left
			merged.deletedSpaceIDs.formUnion(right.deletedSpaceIDs)
			merged.deletedSpaceIDs.formUnion(result.browser.deletedSpacesAt.keys)
			merged.deletedSpacesAt.merge(right.deletedSpacesAt) { max($0, $1) }
			merged.deletedSpacesAt.merge(result.browser.deletedSpacesAt) { max($0, $1) }
			var spacesByID = Dictionary(left.spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, next in
				preferredSpace(first, next)
			})
			for incoming in right.spaces {
				if let current = spacesByID[incoming.id] {
					spacesByID[incoming.id] = mergeSpace(current, incoming)
				} else {
					spacesByID[incoming.id] = incoming
				}
			}
			let preferredOrder = workspaceOrder(right, over: left) ? right.spaces : left.spaces
			let orderedIDs = preferredOrder.map(\.id) + spacesByID.keys.filter { id in !preferredOrder.contains(where: { $0.id == id }) }.sorted { $0.uuidString < $1.uuidString }
			merged.spaces = orderedIDs.uniqued().compactMap { id in
				guard let space = spacesByID[id],
				      !isDeleted(id, modifiedAt: space.modifiedAt, dates: merged.deletedSpacesAt, legacyIDs: merged.deletedSpaceIDs)
				else { return nil }
				return space
			}
			let useIncomingFavourites = right.favouritesModifiedAt > left.favouritesModifiedAt
				|| (right.favouritesModifiedAt == left.favouritesModifiedAt
					&& right.favouriteTabIDs.map(\.uuidString).joined(separator: ",")
					< left.favouriteTabIDs.map(\.uuidString).joined(separator: ","))
			if useIncomingFavourites {
				merged.favouriteTabIDs = right.favouriteTabIDs
				merged.favouritesModifiedAt = right.favouritesModifiedAt
			}
			if right.selectionModifiedAt > left.selectionModifiedAt
				|| (right.selectionModifiedAt == left.selectionModifiedAt && right.selectedSpaceID.uuidString < left.selectedSpaceID.uuidString)
			{
				merged.selectedSpaceID = right.selectedSpaceID
				merged.selectionModifiedAt = right.selectionModifiedAt
			}
			merged.modifiedAt = max(left.modifiedAt, right.modifiedAt)
			result.workspace = merged
		} else {
			result.workspace = workspace ?? other.workspace
		}

		if var mergedWorkspace = result.workspace {
			mergedWorkspace.deletedSpacesAt.merge(result.browser.deletedSpacesAt) { max($0, $1) }
			mergedWorkspace.deletedSpaceIDs.formUnion(result.browser.deletedSpacesAt.keys)
			result.workspace = mergedWorkspace
		}

		for key in Set(settings.keys).union(other.settings.keys) {
			guard let incoming = other.settings[key] else { continue }
			guard let current = result.settings[key] else {
				result.settings[key] = incoming
				continue
			}
			if key == BrowserSiteZoomDocument.defaultsKey {
				if let value = BrowserSiteZoomDocument.mergeSyncValues(current.value, incoming.value) {
					result.settings[key] = SyncedSetting(
						value: value,
						modifiedAt: max(current.modifiedAt, incoming.modifiedAt)
					)
				} else {
					result.settings[key] = current
				}
				continue
			}
			result.settings[key] = preferred(incoming, incoming.modifiedAt, current, current.modifiedAt)
		}
		return result
	}
}

private nonisolated func appendUnique(_ existing: [UUID], _ incoming: [UUID]) -> [UUID] {
	var seen = Set(existing)
	return existing + incoming.filter { seen.insert($0).inserted }
}

private nonisolated func isPortableSyncTab(_ tab: OpenTab) -> Bool {
	tab.internalPage == nil
		&& tab.fileAccessBookmark == nil
		&& (tab.url.map(isPortableSyncURL) ?? true)
}

private nonisolated func isPortableSyncURL(_ url: URL) -> Bool {
	guard url.absoluteString.utf8.count <= 16384,
	      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
	      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
	      let host = components.host, !host.isEmpty,
	      components.port.map({ (1 ... 65535).contains($0) }) ?? true,
	      !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { return false }
	return true
}

private nonisolated func credentialFreeSyncURL(_ url: URL) -> URL {
	guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
	components.user = nil
	components.password = nil
	return components.url ?? url
}

private extension Date {
	nonisolated var isSaneSyncTimestamp: Bool {
		self == .distantPast
			|| (timeIntervalSince1970.isFinite
				&& timeIntervalSince1970 >= -2_208_988_800
				&& timeIntervalSince1970 <= Date.now.timeIntervalSince1970 + 300.001)
	}
}

private nonisolated func isSafeSyncURL(_ url: URL) -> Bool {
	guard url.absoluteString.utf8.count <= 16384,
	      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
	      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
	      let host = components.host, !host.isEmpty,
	      components.user == nil, components.password == nil,
	      components.port.map({ (1 ... 65535).contains($0) }) ?? true,
	      !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) })
	else { return false }
	return true
}

private nonisolated func isDeleted(
	_ id: UUID,
	modifiedAt: Date,
	dates: [UUID: Date],
	legacyIDs: Set<UUID>
) -> Bool {
	if let deletedAt = dates[id] {
		return modifiedAt <= deletedAt
	}
	return legacyIDs.contains(id)
}

private nonisolated func preferredSpace(_ first: BrowserSpace, _ second: BrowserSpace) -> BrowserSpace {
	if first.modifiedAt != second.modifiedAt {
		return first.modifiedAt > second.modifiedAt ? first : second
	}
	return spaceKey(first) >= spaceKey(second) ? first : second
}

private nonisolated func mergeSpace(_ first: BrowserSpace, _ second: BrowserSpace) -> BrowserSpace {
	var winner = preferredSpace(first, second)
	winner.deletedPinnedFoldersAt.merge(first.deletedPinnedFoldersAt) { max($0, $1) }
	winner.deletedPinnedFoldersAt.merge(second.deletedPinnedFoldersAt) { max($0, $1) }
	let folders = Dictionary((first.pinnedFolders + second.pinnedFolders).map { ($0.id, $0) }, uniquingKeysWith: { a, b in
		preferred(a, a.modifiedAt, b, b.modifiedAt)
	})
	winner.pinnedFolders = folders.values.filter { folder in
		!isDeleted(folder.id, modifiedAt: folder.modifiedAt, dates: winner.deletedPinnedFoldersAt, legacyIDs: [])
	}.sorted { $0.id.uuidString < $1.id.uuidString }
	return winner
}

private nonisolated func workspaceOrder(_ first: BrowserWorkspace, over second: BrowserWorkspace) -> Bool {
	if first.modifiedAt != second.modifiedAt {
		return first.modifiedAt > second.modifiedAt
	}
	return first.spaces.map(\.id.uuidString).joined(separator: ",")
		< second.spaces.map(\.id.uuidString).joined(separator: ",")
}

private nonisolated func spaceKey(_ space: BrowserSpace) -> String {
	let folders = space.pinnedFolders.sorted { $0.id.uuidString < $1.id.uuidString }
		.map { "\($0.id)|\($0.name)|\($0.modifiedAt.timeIntervalSince1970)|\($0.tabIDs.map(\.uuidString).joined(separator: ","))" }
	let deleted = space.deletedPinnedFoldersAt.sorted { $0.key.uuidString < $1.key.uuidString }
		.map { "\($0.key)|\($0.value.timeIntervalSince1970)" }
	return [space.id.uuidString, space.name, space.symbol, String(space.modifiedAt.timeIntervalSince1970),
	        space.tabIDs.map(\.uuidString).joined(separator: ","), space.pinnedTabIDs.map(\.uuidString).joined(separator: ","),
	        space.selectedTabID?.uuidString ?? "", folders.joined(separator: ";"), deleted.joined(separator: ";"),
	        themeKey(space.theme)].joined(separator: "|")
}

private nonisolated func themeKey(_ theme: BrowserTheme) -> String {
	let points = theme.meshColorPoints.map { point in
		"\(point.id.uuidString):\(colorKey(point.color)):\(point.x):\(point.y)"
	}.joined(separator: ";")
	return [
		String(theme.usesGradient),
		colorKey(theme.firstColor),
		colorKey(theme.secondColor),
		String(describing: theme.gradientDirection),
		points,
		String(theme.meshOpacity),
		String(theme.shaderNoiseEnabled),
		String(theme.shaderNoiseAmount),
		String(theme.shaderNoiseMonochrome),
		String(describing: theme.appearanceMode),
	].joined(separator: ",")
}

private nonisolated func colorKey(_ color: BrowserColor) -> String {
	"\(color.red),\(color.green),\(color.blue)"
}

private nonisolated func preferred<Value: Codable & Equatable>(
	_ first: Value,
	_ firstDate: Date,
	_ second: Value,
	_ secondDate: Date
) -> Value {
	if firstDate != secondDate {
		return firstDate > secondDate ? first : second
	}
	return stableData(first).lexicographicallyPrecedes(stableData(second)) ? second : first
}

private nonisolated func stableData(_ value: some Codable) -> [UInt8] {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.sortedKeys]
	return Array((try? encoder.encode(value)) ?? Data())
}

nonisolated struct SyncedSetting: Codable, Equatable, Sendable {
	var value: Data?
	var modifiedAt: Date

	nonisolated func shouldApply(over localValue: Data?, newerThan localDate: Date) -> Bool {
		modifiedAt > localDate || (modifiedAt == localDate && value != localValue)
	}

	nonisolated var hasValidPropertyListValue: Bool {
		guard let value else { return true }
		guard let propertyList = try? PropertyListSerialization.propertyList(from: value, format: nil),
		      let dictionary = propertyList as? [String: Any],
		      dictionary["value"] != nil
		else { return false }
		return true
	}
}

private extension Sequence where Element: Hashable {
	nonisolated func uniqued() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}
