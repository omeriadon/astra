import Foundation

struct WatchSpace: Codable, Identifiable, Equatable, Sendable {
	let id: UUID
	let name: String
	let symbol: String
	let theme: BrowserTheme
	let pinned: [WatchLink]
	let favourites: [WatchLink]
	let today: [WatchLink]
}
