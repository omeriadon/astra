import Foundation

@MainActor
final class BrowserPersistence {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "browser"
        directory = applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadFavourites() throws -> [Favourite] {
        try read([Favourite].self, named: "favourites.json") ?? []
    }

    func saveFavourites(_ favourites: [Favourite]) throws {
        try write(favourites, named: "favourites.json")
    }

    func loadOpenTabs() throws -> [OpenTab] {
        try read([OpenTab].self, named: "open-tabs.json") ?? [OpenTab()]
    }

    func saveOpenTabs(_ tabs: [OpenTab]) throws {
        try write(tabs, named: "open-tabs.json")
    }

    func loadBrowserSnapshot() throws -> BrowserSnapshot? {
        try read(BrowserSnapshot.self, named: "browser-snapshot.json")
    }

    func saveBrowserSnapshot(_ snapshot: BrowserSnapshot) throws {
        try write(snapshot, named: "browser-snapshot.json")
    }

    private func read<Value: Decodable>(_ type: Value.Type, named fileName: String) throws -> Value? {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func write<Value: Encodable>(_ value: Value, named fileName: String) throws {
        let data = try encoder.encode(value)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }
}
