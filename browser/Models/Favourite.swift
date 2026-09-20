import Foundation

struct Favourite: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var url: URL

    init(id: UUID = UUID(), name: String = "", url: URL = URL(string: "about:blank")!) {
        self.id = id
        self.name = name
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try container.decodeIfPresent(URL.self, forKey: .url) ?? URL(string: "about:blank")!
    }
}
