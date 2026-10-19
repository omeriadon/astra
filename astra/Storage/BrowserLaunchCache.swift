import Defaults
import Foundation

/// Disposable metadata used to paint the browser shell while the authoritative session loads.
private actor BrowserLaunchCacheWriter {
	private var latestRevision: UInt64 = 0
	func save(_ snapshot: BrowserLaunchCache.Snapshot, revision: UInt64) -> Data? {
		guard revision >= latestRevision, let data = BrowserLaunchCache.encoded(snapshot) else { return nil }
		latestRevision = revision
		UserDefaults.standard.set(data, forKey: "browserLaunchCache")
		return data
	}
}

enum BrowserLaunchCache {
	// shortcut: 256 tabs, 32 spaces, 64 favicons, and 2 MB total bound startup decoding; increase if normal sessions exceed these limits.
	nonisolated static let maximumTabs = 256
	nonisolated static let maximumSpaces = 32
	nonisolated static let maximumFavicons = 64
	nonisolated static let maximumFaviconBytes = 512 * 1024
	nonisolated static let maximumEncodedBytes = 2 * 1024 * 1024

	nonisolated struct Snapshot: Codable, Equatable, Sendable {
		var tabs: [Tab]
		var spaces: [Space]
		var favouriteTabIDs: [UUID]
		var selectedSpaceID: UUID?
		var selectedTabID: UUID?
		var favicons: [String: Data]

		nonisolated init(
			tabs: [Tab] = [],
			spaces: [Space] = [],
			favouriteTabIDs: [UUID] = [],
			selectedSpaceID: UUID? = nil,
			selectedTabID: UUID? = nil,
			favicons: [String: Data] = [:]
		) {
			// Blank New Tabs are part of the session and must retain their IDs
			// and positions during the fast pre-hydration launch shell.
			let leadingTabs = Array(tabs.prefix(BrowserLaunchCache.maximumTabs))
			if let selected = selectedTabID,
			   tabs.count > BrowserLaunchCache.maximumTabs,
			   !leadingTabs.contains(where: { $0.id == selected }),
			   let selectedTab = tabs.first(where: { $0.id == selected })
			{
				self.tabs = Array(tabs.prefix(BrowserLaunchCache.maximumTabs - 1)) + [selectedTab]
			} else {
				self.tabs = leadingTabs
			}
			let leadingSpaces = Array(spaces.prefix(BrowserLaunchCache.maximumSpaces))
			let includedSpaces: [Space] = if let selectedSpaceID,
			                                 spaces.count > BrowserLaunchCache.maximumSpaces,
			                                 !leadingSpaces.contains(where: { $0.id == selectedSpaceID }),
			                                 let selectedSpace = spaces.first(where: { $0.id == selectedSpaceID })
			{
				Array(spaces.prefix(BrowserLaunchCache.maximumSpaces - 1)) + [selectedSpace]
			} else {
				leadingSpaces
			}
			let cachedTabIDs = Set(self.tabs.map(\.id))
			self.spaces = includedSpaces.map { space in
				var space = space
				space.tabIDs = space.tabIDs.filter(cachedTabIDs.contains)
				if let selected = space.selectedTabID, !cachedTabIDs.contains(selected) {
					space.selectedTabID = nil
				}
				return space
			}
			self.favouriteTabIDs = favouriteTabIDs.filter(cachedTabIDs.contains)
			if let selectedSpaceID, self.spaces.contains(where: { $0.id == selectedSpaceID }) {
				self.selectedSpaceID = selectedSpaceID
			} else {
				self.selectedSpaceID = nil
			}
			self.selectedTabID = selectedTabID.flatMap { cachedTabIDs.contains($0) ? $0 : nil }
			self.favicons = BrowserLaunchCache.boundedFavicons(favicons)
		}

		nonisolated init(from decoder: Decoder) throws {
			let values = try decoder.container(keyedBy: CodingKeys.self)
			try self.init(
				tabs: values.decodeIfPresent([Tab].self, forKey: .tabs) ?? [],
				spaces: values.decodeIfPresent([Space].self, forKey: .spaces) ?? [],
				favouriteTabIDs: values.decodeIfPresent([UUID].self, forKey: .favouriteTabIDs) ?? [],
				selectedSpaceID: values.decodeIfPresent(UUID.self, forKey: .selectedSpaceID),
				selectedTabID: values.decodeIfPresent(UUID.self, forKey: .selectedTabID),
				favicons: values.decodeIfPresent([String: Data].self, forKey: .favicons) ?? [:]
			)
		}

		private enum CodingKeys: String, CodingKey {
			case tabs
			case spaces
			case favouriteTabIDs
			case selectedSpaceID
			case selectedTabID
			case favicons
		}
	}

	nonisolated struct Tab: Codable, Equatable, Sendable {
		var id: UUID
		var url: URL?
		var title: String
		var order: Int
		var internalPage: String?

		init(
			id: UUID,
			url: URL?,
			title: String,
			order: Int,
			internalPage: String? = nil
		) {
			self.id = id
			self.url = url
			self.title = title
			self.order = order
			self.internalPage = internalPage
		}
	}

	nonisolated struct Space: Codable, Equatable, Sendable {
		var id: UUID
		var name: String
		var symbol: String
		var theme: BrowserTheme
		var tabIDs: [UUID]
		var selectedTabID: UUID?

		init(
			id: UUID,
			name: String,
			symbol: String,
			theme: BrowserTheme,
			tabIDs: [UUID],
			selectedTabID: UUID?
		) {
			self.id = id
			self.name = name
			self.symbol = symbol
			self.theme = theme
			self.tabIDs = tabIDs
			self.selectedTabID = selectedTabID
		}
	}

	// A single process startup can request this snapshot for each window and
	// again for the favicon store. Decode once until the underlying Defaults
	// data changes; retain equality checks so external settings edits are seen.
	@MainActor private static var lastDecodedData: Data?
	@MainActor private static var lastDecodedSnapshot: Snapshot?
	@MainActor private static var saveRevision: UInt64 = 0
	@MainActor private static var pendingSave = false
	private static let writer = BrowserLaunchCacheWriter()

	static func load() -> Snapshot? {
		if pendingSave { return applyingSelection(to: lastDecodedSnapshot) }
		let data = Defaults[.browserLaunchCache]
		if let lastDecodedData, lastDecodedData == data {
			return applyingSelection(to: lastDecodedSnapshot)
		}
		let snapshot = decoded(data)
		lastDecodedData = data
		lastDecodedSnapshot = snapshot
		return applyingSelection(to: snapshot)
	}

	static func containsSelection(tabID: UUID, spaceID: UUID) -> Bool {
		guard let snapshot = lastDecodedSnapshot else { return false }
		return snapshot.tabs.contains { $0.id == tabID } && snapshot.spaces.contains { $0.id == spaceID }
	}

	/// A selection outside the bounded shell only replaces one metadata entry.
	/// Normal selection writes still touch just the tiny selection journal.
	static func includeSelection(tab: Tab, space: Space, isFavourite: Bool) {
		guard var snapshot = lastDecodedSnapshot else { return }
		if !snapshot.tabs.contains(where: { $0.id == tab.id }) {
			if snapshot.tabs.count >= maximumTabs { snapshot.tabs.removeLast() }
			snapshot.tabs.append(tab)
		}
		if let index = snapshot.spaces.firstIndex(where: { $0.id == space.id }) {
			if !isFavourite, !snapshot.spaces[index].tabIDs.contains(tab.id) { snapshot.spaces[index].tabIDs.append(tab.id) }
			snapshot.spaces[index].selectedTabID = tab.id
		} else {
			if snapshot.spaces.count >= maximumSpaces { snapshot.spaces.removeLast() }
			var space = space
			if isFavourite { space.tabIDs.removeAll { $0 == tab.id } }
			snapshot.spaces.append(space)
		}
		if isFavourite, !snapshot.favouriteTabIDs.contains(tab.id) { snapshot.favouriteTabIDs.append(tab.id) }
		snapshot.selectedTabID = tab.id; snapshot.selectedSpaceID = space.id
		snapshot = Snapshot(tabs: snapshot.tabs, spaces: snapshot.spaces, favouriteTabIDs: snapshot.favouriteTabIDs, selectedSpaceID: space.id, selectedTabID: tab.id, favicons: snapshot.favicons)
		save(snapshot)
	}

	static func save(_ snapshot: Snapshot) {
		saveRevision &+= 1
		let revision = saveRevision
		lastDecodedSnapshot = snapshot
		pendingSave = true
		updateSelection(tabID: snapshot.selectedTabID, spaceID: snapshot.selectedSpaceID)
		Task { @MainActor in
			let data = await writer.save(snapshot, revision: revision)
			guard saveRevision == revision else { return }
			pendingSave = false
			if let data { lastDecodedData = data }
		}
	}

	/// Frequent selection changes persist only two UUIDs, never favicon bytes.
	static func updateSelection(tabID: UUID?, spaceID: UUID?) {
		var selection: [String: String] = [:]
		selection["tab"] = tabID?.uuidString
		selection["space"] = spaceID?.uuidString
		UserDefaults.standard.set(selection, forKey: "browserLaunchSelection")
	}

	private static func applyingSelection(to snapshot: Snapshot?) -> Snapshot? {
		guard var snapshot else { return nil }
		let selection = UserDefaults.standard.dictionary(forKey: "browserLaunchSelection") as? [String: String] ?? [:]
		if let id = selection["tab"].flatMap(UUID.init(uuidString:)), snapshot.tabs.contains(where: { $0.id == id }) {
			snapshot.selectedTabID = id
		}
		if let id = selection["space"].flatMap(UUID.init(uuidString:)), let index = snapshot.spaces.firstIndex(where: { $0.id == id }) {
			snapshot.selectedSpaceID = id
			if let tab = snapshot.selectedTabID, snapshot.spaces[index].tabIDs.contains(tab) || snapshot.favouriteTabIDs.contains(tab) {
				snapshot.spaces[index].selectedTabID = tab
			}
		}
		return snapshot
	}

	static func updateFavicons(_ favicons: [String: Data]) {
		guard let snapshot = load() else { return }
		var cachedFavicons: [String: Data] = [:]
		var bytes = 0
		let orderedTabs = snapshot.tabs.sorted { left, right in
			let leftIsSelected = left.id == snapshot.selectedTabID
			let rightIsSelected = right.id == snapshot.selectedTabID
			if leftIsSelected != rightIsSelected {
				return leftIsSelected
			}
			return left.order < right.order
		}
		for tab in orderedTabs {
			guard let key = FaviconKey.origin(for: tab.url),
			      let data = favicons[key],
			      bytes + data.count <= maximumFaviconBytes
			else { continue }
			cachedFavicons[key] = data
			bytes += data.count
			if cachedFavicons.count == maximumFavicons {
				break
			}
		}
		var updated = snapshot
		updated.favicons = cachedFavicons
		save(updated)
	}

	nonisolated static func encoded(_ snapshot: Snapshot) -> Data? {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary
		guard let data = try? encoder.encode(snapshot), data.count <= maximumEncodedBytes else { return nil }
		return data
	}

	nonisolated static func decoded(_ data: Data) -> Snapshot? {
		guard !data.isEmpty, data.count <= maximumEncodedBytes else { return nil }
		return try? PropertyListDecoder().decode(Snapshot.self, from: data)
	}

	private nonisolated static func boundedFavicons(_ favicons: [String: Data]) -> [String: Data] {
		var result: [String: Data] = [:]
		var bytes = 0
		for key in favicons.keys.sorted() {
			guard result.count < maximumFavicons,
			      let data = favicons[key],
			      bytes + data.count <= maximumFaviconBytes else { continue }
			result[key] = data
			bytes += data.count
		}
		return result
	}
}
