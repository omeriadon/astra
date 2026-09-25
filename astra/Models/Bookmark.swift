import Foundation

struct Bookmark: Codable, Identifiable, Equatable {
	var id: UUID
	var name: String
	var url: URL

	init(id: UUID = UUID(), name: String, url: URL) {
		self.id = id
		self.name = name
		self.url = url
	}
}
