import Foundation

struct WatchLink: Codable, Identifiable, Equatable, Sendable {
	let id: UUID
	let title: String
	let url: URL

	var canOpen: Bool {
		["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
	}
}
