#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import AstraAutomationCore
import Foundation

@AppEntity(schema: .browser.bookmark)
struct AstraBookmarkEntity {
    static let defaultQuery = Query()
    let id: String
    @Property(title: "Name") var name: String
    @Property(title: "URL") var url: URL

    init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(url.absoluteString)")
    }

    struct Query: EntityStringQuery {
        func entities(for identifiers: [String]) async throws -> [AstraBookmarkEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            let lookup = Set(identifiers)
            return browser.bookmarks.filter { lookup.contains($0.id.uuidString) }.map {
                AstraBookmarkEntity(id: $0.id.uuidString, name: $0.name, url: $0.url)
            }
        }
        func entities(matching string: String) async throws -> [AstraBookmarkEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            return browser.bookmarks.filter {
                $0.name.localizedCaseInsensitiveContains(string)
                    || $0.url.absoluteString.localizedCaseInsensitiveContains(string)
                    || $0.folder.localizedCaseInsensitiveContains(string)
            }.prefix(40).map {
                AstraBookmarkEntity(id: $0.id.uuidString, name: $0.name, url: $0.url)
            }
        }
        func suggestedEntities() async throws -> [AstraBookmarkEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            return browser.bookmarks.prefix(25).map {
                AstraBookmarkEntity(id: $0.id.uuidString, name: $0.name, url: $0.url)
            }
        }
    }
}

@AppEntity(schema: .browser.tab)
struct AstraTabEntity {
    static let defaultQuery = Query()
    let id: String
    @Property(title: "Name") var name: String
    @Property(title: "URL") var url: URL?
    @Property(title: "Private") var isPrivate: Bool

    init(id: String, name: String, url: URL?, isPrivate: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.isPrivate = isPrivate
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    struct Query: EntityStringQuery {
        @MainActor
        private func live() -> [AstraTabEntity] {
            AstraSystemActions.normalBrowsers().flatMap { browser in
                browser.tabs.compactMap { tab in
                    guard BrowserWindowRegistry.shared.ownsTab(tab.id, in: browser) else { return nil }
                    return AstraTabEntity(
                        id: AstraTabReference(windowID: browser.windowID, tabID: tab.id).rawValue,
                        name: tab.title, url: tab.currentURL
                    )
                }
            }
        }

        func entities(for identifiers: [String]) async throws -> [AstraTabEntity] {
            _ = try await AstraSystemActions.existingBrowser()
            let requested = Set(identifiers)
            return await live().filter { requested.contains($0.id) }
        }
        func entities(matching string: String) async throws -> [AstraTabEntity] {
            _ = try await AstraSystemActions.existingBrowser()
            return await live().filter {
                $0.name.localizedCaseInsensitiveContains(string)
                    || ($0.url?.absoluteString.localizedCaseInsensitiveContains(string) ?? false)
            }.prefix(40).map { $0 }
        }
        func suggestedEntities() async throws -> [AstraTabEntity] {
            _ = try await AstraSystemActions.existingBrowser()
            return Array(await live().prefix(30))
        }
    }
}

struct AstraSpaceEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Astra Space" }
    static let defaultQuery = Query()
    let id: String
    @Property(title: "Name") var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    struct Query: EntityStringQuery {
        func entities(for identifiers: [String]) async throws -> [AstraSpaceEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            let desired = Set(identifiers)
            return browser.workspace.spaces.filter { desired.contains($0.id.uuidString) }
                .map { AstraSpaceEntity(id: $0.id.uuidString, name: $0.name) }
        }
        func entities(matching string: String) async throws -> [AstraSpaceEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            return browser.workspace.spaces.filter { $0.name.localizedCaseInsensitiveContains(string) }
                .map { AstraSpaceEntity(id: $0.id.uuidString, name: $0.name) }
        }
        func suggestedEntities() async throws -> [AstraSpaceEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            return browser.workspace.spaces.map { AstraSpaceEntity(id: $0.id.uuidString, name: $0.name) }
        }
    }
}

@AppEntity(schema: .browser.readingListItem)
struct AstraReadingEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Astra Reading List Page" }
    static let defaultQuery = Query()
    let id: String
    @Property(title: "Title") var title: String
    @Property(title: "URL") var url: URL
    @Property(title: "Read") var isRead: Bool

    init(id: String, title: String, url: URL, isRead: Bool) {
        self.id = id
        self.title = title
        self.url = url
        self.isRead = isRead
    }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(url.absoluteString)")
    }
    struct Query: EntityStringQuery {
        func entities(for identifiers: [String]) async throws -> [AstraReadingEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            let requested = Set(identifiers)
            return browser.readingList.filter { requested.contains($0.id.uuidString) }
                .map { AstraReadingEntity(id: $0.id.uuidString, title: $0.title, url: $0.url, isRead: $0.isRead) }
        }
        func entities(matching string: String) async throws -> [AstraReadingEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            return browser.readingList.filter {
                $0.title.localizedCaseInsensitiveContains(string)
                    || $0.url.absoluteString.localizedCaseInsensitiveContains(string)
            }.prefix(40).map {
                AstraReadingEntity(id: $0.id.uuidString, title: $0.title, url: $0.url, isRead: $0.isRead)
            }
        }
        func suggestedEntities() async throws -> [AstraReadingEntity] {
            let browser = try await AstraSystemActions.existingBrowser()
            return browser.readingList.prefix(25).map {
                AstraReadingEntity(id: $0.id.uuidString, title: $0.title, url: $0.url, isRead: $0.isRead)
            }
        }
    }
}
#endif
