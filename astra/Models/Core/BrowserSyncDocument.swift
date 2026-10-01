import Foundation

struct BrowserSyncDocument: Codable, Equatable, Sendable {
	var version: Int = 3
	var tabs: [OpenTab]
	var workspace: BrowserWorkspace?
	var bookmarks: [Bookmark]
	var history: [BrowserVisit]
	var browser: BrowserSnapshot
	var settings: [String: SyncedSetting]

	init(
		tabs: [OpenTab],
		workspace: BrowserWorkspace,
		bookmarks: [Bookmark],
		history: [BrowserVisit] = [],
		browser: BrowserSnapshot,
		settings: [String: SyncedSetting]
	) {
		self.tabs = tabs
		self.workspace = workspace
		self.bookmarks = bookmarks
		self.history = history
		self.browser = browser
		self.settings = settings
	}

	private enum CodingKeys: String, CodingKey {
		case version, tabs, workspace, bookmarks, history, browser, settings
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
		tabs = try values.decode([OpenTab].self, forKey: .tabs)
		workspace = try values.decodeIfPresent(BrowserWorkspace.self, forKey: .workspace)
		bookmarks = try values.decode([Bookmark].self, forKey: .bookmarks)
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
		try values.encode(history, forKey: .history)
		try values.encode(browser, forKey: .browser)
		try values.encode(settings, forKey: .settings)
	}

	nonisolated var hasSupportedVersion: Bool { (1 ... 3).contains(version) }

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
			&& bookmarks.allSatisfy { isSafeSyncURL($0.url) && $0.modifiedAt.isSaneSyncTimestamp }
			&& history.allSatisfy { isSafeSyncURL($0.url) && $0.modifiedAt.isSaneSyncTimestamp && $0.visitedAt.isSaneSyncTimestamp }
			&& settings.values.allSatisfy { $0.modifiedAt.isSaneSyncTimestamp && $0.hasValidPropertyListValue }
			&& browser.selectedTabModifiedAt.isSaneSyncTimestamp
			&& browser.historyClearedAt.isSaneSyncTimestamp
			&& (Array(browser.closedTabsAt.values) + Array(browser.deletedBookmarksAt.values) + Array(browser.deletedSpacesAt.values) + Array(browser.deletedVisitsAt.values)).allSatisfy(\.isSaneSyncTimestamp)
			&& (workspace.map { value in
				Set(value.spaces.map(\.id)).count == value.spaces.count
					&& value.spaces.allSatisfy { space in
						Set(space.pinnedFolders.map(\.id)).count == space.pinnedFolders.count
							&& space.modifiedAt.isSaneSyncTimestamp
							&& space.pinnedFolders.allSatisfy { $0.modifiedAt.isSaneSyncTimestamp }
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
			result.settings[key] = preferred(incoming, incoming.modifiedAt, current, current.modifiedAt)
		}
		return result
	}

}

private extension Date {
	nonisolated var isSaneSyncTimestamp: Bool {
		self == .distantPast
			|| (timeIntervalSince1970.isFinite
				&& timeIntervalSince1970 >= -2_208_988_800
				&& timeIntervalSince1970 <= Date.now.timeIntervalSince1970 + 300)
	}
}

private nonisolated func isSafeSyncURL(_ url: URL) -> Bool {
	guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
		  let host = components.host, !host.isEmpty,
		  components.user == nil, components.password == nil,
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
	if let deletedAt = dates[id] { return modifiedAt <= deletedAt }
	return legacyIDs.contains(id)
}

private nonisolated func preferredSpace(_ first: BrowserSpace, _ second: BrowserSpace) -> BrowserSpace {
	if first.modifiedAt != second.modifiedAt { return first.modifiedAt > second.modifiedAt ? first : second }
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
	if first.modifiedAt != second.modifiedAt { return first.modifiedAt > second.modifiedAt }
	return first.spaces.map { $0.id.uuidString }.joined(separator: ",")
		< second.spaces.map { $0.id.uuidString }.joined(separator: ",")
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
	if firstDate != secondDate { return firstDate > secondDate ? first : second }
	return stableData(first).lexicographicallyPrecedes(stableData(second)) ? second : first
}

private nonisolated func stableData<Value: Codable>(_ value: Value) -> [UInt8] {
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
