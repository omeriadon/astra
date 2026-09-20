import Foundation

struct OpenTab: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: URL?

    init(id: UUID = UUID(), title: String = "", url: URL? = nil) {
        self.id = id
        self.title = title
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(URL.self, forKey: .url)
    }
}
