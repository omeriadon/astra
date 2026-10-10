import Foundation

nonisolated struct Bookmark: Codable, Identifiable, Equatable, Sendable {
	var id: UUID
	var name: String
	var url: URL
	var modifiedAt: Date
	var folder: String
	var isFavorite: Bool
	var order: Int

	init(id: UUID = UUID(), name: String, url: URL, modifiedAt: Date = .now, folder: String = "", isFavorite: Bool = false, order: Int = 0) {
		self.id = id
		self.name = name
		self.url = url
		self.modifiedAt = modifiedAt
		self.folder = folder
		self.isFavorite = isFavorite
		self.order = order
	}

	private enum CodingKeys: String, CodingKey {
		case id, name, url, modifiedAt, folder, isFavorite, order
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decode(UUID.self, forKey: .id)
		name = try values.decode(String.self, forKey: .name)
		url = try values.decode(URL.self, forKey: .url)
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
		folder = try values.decodeIfPresent(String.self, forKey: .folder) ?? ""
		isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
		order = try values.decodeIfPresent(Int.self, forKey: .order) ?? Int.min
	}

	static func preservingLegacyOrder(_ bookmarks: [Self]) -> [Self] {
		bookmarks.enumerated().map { index, source in
			guard source.order == Int.min else { return source }
			var bookmark = source
			bookmark.order = index
			return bookmark
		}
	}
}

nonisolated struct ReadingListItem: Codable, Identifiable, Equatable, Sendable {
	var id: UUID
	var url: URL
	var title: String
	var addedAt: Date
	var modifiedAt: Date
	var isRead: Bool

	static func admitsOfflineOpen(_ candidate: Self?, id: UUID, url: URL, isPrivate: Bool) -> Bool {
		guard !isPrivate, url.absoluteString.utf8.count <= 16384,
		      let candidate, candidate.id == id,
		      candidate.url.absoluteString == url.absoluteString,
		      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
		      let host = components.host, !host.isEmpty,
		      components.user == nil, components.password == nil,
		      !host.unicodeScalars.contains(where: {
		      	CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
		      }),
		      components.port.map({ (1 ... 65535).contains($0) }) ?? true else { return false }
		return true
	}

	init(id: UUID = UUID(), url: URL, title: String, addedAt: Date = .now, modifiedAt: Date = .now, isRead: Bool = false) {
		self.id = id
		self.url = url
		self.title = title
		self.addedAt = addedAt
		self.modifiedAt = modifiedAt
		self.isRead = isRead
	}
}

nonisolated enum BrowserUserDataMutation {
	static func nextDate(after modifiedAt: Date, deletion: Date = .distantPast) -> Date {
		let latest = max(modifiedAt, deletion)
		let now = Date.now
		return now > latest ? now : latest.addingTimeInterval(0.001)
	}
}

/// Immutable value projection for the library UI. Build it away from SwiftUI's
/// main-actor body evaluation and abandon obsolete searches cooperatively.
nonisolated struct BrowserLibraryProjection: Sendable {
	let bookmarkGroups: [String: [Bookmark]]
	let readingItems: [ReadingListItem]

	static let empty = Self(bookmarkGroups: [:], readingItems: [])

	static func build(bookmarks: [Bookmark], readingList: [ReadingListItem], query: String) -> Self? {
		guard !Task.isCancelled else { return nil }
		var matchingBookmarks: [Bookmark] = []
		matchingBookmarks.reserveCapacity(bookmarks.count)
		for bookmark in bookmarks {
			guard !Task.isCancelled else { return nil }
			if query.isEmpty || bookmark.name.localizedCaseInsensitiveContains(query)
				|| bookmark.url.absoluteString.localizedCaseInsensitiveContains(query)
				|| bookmark.folder.localizedCaseInsensitiveContains(query)
			{
				matchingBookmarks.append(bookmark)
			}
		}
		matchingBookmarks.sort {
			if $0.folder != $1.folder {
				return $0.folder.localizedStandardCompare($1.folder) == .orderedAscending
			}
			if $0.order != $1.order {
				return $0.order < $1.order
			}
			return $0.name.localizedStandardCompare($1.name) == .orderedAscending
		}
		guard !Task.isCancelled else { return nil }
		var matchingReadingItems: [ReadingListItem] = []
		matchingReadingItems.reserveCapacity(readingList.count)
		for item in readingList {
			guard !Task.isCancelled else { return nil }
			if query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
				|| item.url.absoluteString.localizedCaseInsensitiveContains(query)
			{
				matchingReadingItems.append(item)
			}
		}
		matchingReadingItems.sort {
			$0.addedAt == $1.addedAt
				? $0.id.uuidString < $1.id.uuidString
				: $0.addedAt > $1.addedAt
		}
		guard !Task.isCancelled else { return nil }
		return Self(
			bookmarkGroups: Dictionary(grouping: matchingBookmarks, by: \.folder),
			readingItems: matchingReadingItems
		)
	}
}
