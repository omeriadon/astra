import Foundation

struct PinnedTabFolder: Codable, Equatable, Identifiable, Sendable {
	var id = UUID()
	var name: String
	var tabIDs: [UUID] = []
	var modifiedAt: Date = .now

	init(id: UUID = UUID(), name: String, tabIDs: [UUID] = [], modifiedAt: Date = .now) {
		self.id = id
		self.name = name
		self.tabIDs = tabIDs
		self.modifiedAt = modifiedAt
	}

	private enum CodingKeys: String, CodingKey {
		case id, name, tabIDs, modifiedAt
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decode(UUID.self, forKey: .id)
		name = try values.decode(String.self, forKey: .name)
		tabIDs = try values.decodeIfPresent([UUID].self, forKey: .tabIDs) ?? []
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
	}
}

struct BrowserSpace: Codable, Equatable, Identifiable, Sendable {
	nonisolated static let firstID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
	static let symbols = [
		"circle.grid.2x2.fill", "star.fill", "moon.stars.fill", "sun.max.fill", "cloud.sun.fill",
		"leaf.fill", "flame.fill", "drop.fill", "bolt.fill", "heart.fill",
		"sparkles", "globe", "globe.americas.fill", "mountain.2.fill", "tree.fill",
		"house.fill", "building.2.fill", "desktopcomputer", "laptopcomputer", "gamecontroller.fill",
		"headphones", "music.note", "film.fill", "camera.fill", "book.fill",
		"graduationcap.fill", "pencil", "paintbrush.fill", "briefcase.fill", "folder.fill",
		"archivebox.fill", "tray.fill", "paperplane.fill", "envelope.fill", "bubble.left.and.bubble.right.fill",
		"person.2.fill", "pawprint.fill", "bicycle", "car.fill", "airplane",
		"ferry.fill", "sailboat.fill", "cup.and.saucer.fill", "fork.knife", "gift.fill",
		"cart.fill", "bag.fill", "key.fill", "lock.fill", "wand.and.stars",
	]

	var id: UUID
	var name: String
	var symbol: String
	var theme: BrowserTheme
	var tabIDs: [UUID]
	var pinnedTabIDs: [UUID]
	var pinnedFolders: [PinnedTabFolder]
	var deletedPinnedFoldersAt: [UUID: Date]
	var selectedTabID: UUID?
	var modifiedAt: Date

	nonisolated init(
		id: UUID = UUID(),
		name: String = "Space",
		symbol: String = "circle.grid.2x2.fill",
		theme: BrowserTheme = BrowserTheme(),
		tabIDs: [UUID] = [],
		pinnedTabIDs: [UUID] = [],
		pinnedFolders: [PinnedTabFolder] = [],
		deletedPinnedFoldersAt: [UUID: Date] = [:],
		selectedTabID: UUID? = nil,
		modifiedAt: Date = .now
	) {
		self.id = id
		self.name = name
		self.symbol = symbol
		self.theme = theme
		self.tabIDs = tabIDs
		self.pinnedTabIDs = pinnedTabIDs
		self.pinnedFolders = pinnedFolders
		self.deletedPinnedFoldersAt = deletedPinnedFoldersAt
		self.selectedTabID = selectedTabID
		self.modifiedAt = modifiedAt
	}

	private enum CodingKeys: String, CodingKey {
		case id, name, symbol, theme, tabIDs, pinnedTabIDs, pinnedFolders, deletedPinnedFoldersAt, selectedTabID, modifiedAt
	}

	nonisolated init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		id = try values.decode(UUID.self, forKey: .id)
		name = try values.decode(String.self, forKey: .name)
		symbol = try values.decode(String.self, forKey: .symbol)
		theme = try values.decode(BrowserTheme.self, forKey: .theme)
		tabIDs = try values.decode([UUID].self, forKey: .tabIDs)
		pinnedTabIDs = try values.decode([UUID].self, forKey: .pinnedTabIDs)
		pinnedFolders = try values.decodeIfPresent([PinnedTabFolder].self, forKey: .pinnedFolders) ?? []
		deletedPinnedFoldersAt = try values.decodeIfPresent([UUID: Date].self, forKey: .deletedPinnedFoldersAt) ?? [:]
		selectedTabID = try values.decodeIfPresent(UUID.self, forKey: .selectedTabID)
		modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
	}
}
