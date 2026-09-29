import Foundation

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
	var selectedTabID: UUID?
	var modifiedAt: Date

	nonisolated init(
		id: UUID = UUID(),
		name: String = "Space",
		symbol: String = "circle.grid.2x2.fill",
		theme: BrowserTheme = BrowserTheme(),
		tabIDs: [UUID] = [],
		pinnedTabIDs: [UUID] = [],
		selectedTabID: UUID? = nil,
		modifiedAt: Date = .now
	) {
		self.id = id
		self.name = name
		self.symbol = symbol
		self.theme = theme
		self.tabIDs = tabIDs
		self.pinnedTabIDs = pinnedTabIDs
		self.selectedTabID = selectedTabID
		self.modifiedAt = modifiedAt
	}
}
