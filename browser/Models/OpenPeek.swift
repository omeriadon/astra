import Foundation

struct OpenPeek: Codable, Equatable, Identifiable {
	let id: UUID
	let depth: Int
	let sourceX: Double
	let sourceY: Double
	let url: URL?
	let history: [URL]
	let historyIndex: Int
	let pageZoom: Double
}
