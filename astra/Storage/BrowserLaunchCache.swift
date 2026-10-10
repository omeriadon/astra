import Defaults
import Foundation

/// Disposable metadata used to paint the browser shell while the authoritative session loads.
enum BrowserLaunchCache {
	// shortcut: 256 tabs, 32 spaces, 64 favicons, and 2 MB total bound startup decoding; increase if normal sessions exceed these limits.
	nonisolated static let maximumTabs = 256
	nonisolated static let maximumSpaces = 32
	nonisolated static let maximumFavicons = 64
	nonisolated static let maximumFaviconBytes = 512 * 1024
	nonisolated static let maximumEncodedBytes = 2 * 1024 * 1024

	struct Snapshot: Codable, Equatable, Sendable {
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

	struct Tab: Codable, Equatable, Sendable {
		var id: UUID
		var url: URL?
		var title: String
		var order: Int

		init(
			id: UUID,
			url: URL?,
			title: String,
			order: Int
		) {
			self.id = id
			self.url = url
			self.title = title
			self.order = order
		}
	}

	struct Space: Codable, Equatable, Sendable {
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

	static func load() -> Snapshot? {
		let data = Defaults[.browserLaunchCache]
		if let lastDecodedData, lastDecodedData == data {
			return lastDecodedSnapshot
		}
		let snapshot = decoded(data)
		lastDecodedData = data
		lastDecodedSnapshot = snapshot
		return snapshot
	}

	static func save(_ snapshot: Snapshot) {
		guard let data = encoded(snapshot) else { return }
		Defaults[.browserLaunchCache] = data
		lastDecodedData = data
		lastDecodedSnapshot = snapshot
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

	static func encoded(_ snapshot: Snapshot) -> Data? {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary
		guard let data = try? encoder.encode(snapshot), data.count <= maximumEncodedBytes else { return nil }
		return data
	}

	static func decoded(_ data: Data) -> Snapshot? {
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
