#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import Foundation

// Intents use small, value-type projections rather than retaining Browser or WebKit objects.
// A stale identifier fails explicitly; no action silently operates on a different tab.
@AppEntity(schema: .browser.bookmark)
struct AstraBookmarkEntity {
    static let defaultQuery = Query()
    let id: String
    var name: String
    var url: URL

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
            let browser = try await AstraSystemActions.browser()
            let lookup = Set(identifiers)
            return browser.bookmarks.filter { lookup.contains($0.id.uuidString) }.map {
                AstraBookmarkEntity(id: $0.id.uuidString, name: $0.name, url: $0.url)
            }
        }
        func entities(matching string: String) async throws -> [AstraBookmarkEntity] {
            let browser = try await AstraSystemActions.browser()
            return browser.bookmarks.filter {
                $0.name.localizedCaseInsensitiveContains(string)
                    || $0.url.absoluteString.localizedCaseInsensitiveContains(string)
                    || $0.folder.localizedCaseInsensitiveContains(string)
            }.prefix(40).map {
                AstraBookmarkEntity(id: $0.id.uuidString, name: $0.name, url: $0.url)
            }
        }
        func suggestedEntities() async throws -> [AstraBookmarkEntity] {
            let browser = try await AstraSystemActions.browser()
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
    var name: String
    var url: URL?
    var isPrivate: Bool

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
                        id: browser.windowID.uuidString + ":" + tab.id.uuidString,
                        name: tab.title, url: tab.currentURL
                    )
                }
            }
        }

        func entities(for identifiers: [String]) async throws -> [AstraTabEntity] {
            _ = try await AstraSystemActions.browser()
            let requested = Set(identifiers)
            return await live().filter { requested.contains($0.id) }
        }
        func entities(matching string: String) async throws -> [AstraTabEntity] {
            _ = try await AstraSystemActions.browser()
            return await live().filter {
                $0.name.localizedCaseInsensitiveContains(string)
                    || ($0.url?.absoluteString.localizedCaseInsensitiveContains(string) ?? false)
            }.prefix(40).map { $0 }
        }
        func suggestedEntities() async throws -> [AstraTabEntity] {
            _ = try await AstraSystemActions.browser()
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
            let browser = try await AstraSystemActions.browser()
            let desired = Set(identifiers)
            return browser.workspace.spaces.filter { desired.contains($0.id.uuidString) }
                .map { AstraSpaceEntity(id: $0.id.uuidString, name: $0.name) }
        }
        func entities(matching string: String) async throws -> [AstraSpaceEntity] {
            let browser = try await AstraSystemActions.browser()
            return browser.workspace.spaces.filter { $0.name.localizedCaseInsensitiveContains(string) }
                .map { AstraSpaceEntity(id: $0.id.uuidString, name: $0.name) }
        }
        func suggestedEntities() async throws -> [AstraSpaceEntity] {
            let browser = try await AstraSystemActions.browser()
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
            let browser = try await AstraSystemActions.browser()
            let requested = Set(identifiers)
            return browser.readingList.filter { requested.contains($0.id.uuidString) }
                .map { AstraReadingEntity(id: $0.id.uuidString, title: $0.title, url: $0.url, isRead: $0.isRead) }
        }
        func entities(matching string: String) async throws -> [AstraReadingEntity] {
            let browser = try await AstraSystemActions.browser()
            return browser.readingList.filter {
                $0.title.localizedCaseInsensitiveContains(string)
                    || $0.url.absoluteString.localizedCaseInsensitiveContains(string)
            }.prefix(40).map {
                AstraReadingEntity(id: $0.id.uuidString, title: $0.title, url: $0.url, isRead: $0.isRead)
            }
        }
        func suggestedEntities() async throws -> [AstraReadingEntity] {
            let browser = try await AstraSystemActions.browser()
            return browser.readingList.prefix(25).map {
                AstraReadingEntity(id: $0.id.uuidString, title: $0.title, url: $0.url, isRead: $0.isRead)
            }
        }
    }
}

struct AstraOpenURLIntent: AppIntent {
    static var title: LocalizedStringResource = "Open URL in Astra"
    static var description = IntentDescription("Open a website in a new Astra tab.")
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "URL") var url: URL
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.open(url)
        return .result()
    }
}

struct AstraSearchWebIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Web with Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Search Text") var query: String
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.search(query)
        return .result()
    }
}

struct AstraNewTabIntent: AppIntent {
    static var title: LocalizedStringResource = "New Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.newTab()
        return .result()
    }
}

struct AstraNewWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "New Astra Window"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Private", default: false) var isPrivate: Bool
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.newWindow(isPrivate: isPrivate)
        return .result()
    }
}

struct AstraMiniAstraIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Mini Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.mini(nil)
        return .result()
    }
}

@AppIntent(schema: .browser.bookmarkURL)
struct AstraBookmarkURLIntent {
    static var title: LocalizedStringResource = "Bookmark URL in Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    var url: URL
    var name: String?

    func perform() async throws -> some ReturnsValue<AstraBookmarkEntity> {
        try await AstraSystemActions.bookmark(url, title: name)
        let browser = try await AstraSystemActions.browser()
        let checked = try AstraSystemActions.validated(url)
        guard let bookmark = browser.bookmarks.first(where: { $0.url == checked }) else {
            throw AstraSystemActions.Failure.missingItem
        }
        return .result(value: AstraBookmarkEntity(id: bookmark.id.uuidString,
                                                   name: bookmark.name, url: bookmark.url))
    }
}

struct AstraBookmarkCurrentPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Bookmark Current Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let url = try await AstraSystemActions.selectedURL()
        try await AstraSystemActions.bookmark(url)
        return .result()
    }
}

struct AstraOpenBookmarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Astra Bookmark"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Bookmark") var bookmark: AstraBookmarkEntity
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.openBookmark(id: bookmark.id)
        return .result()
    }
}

struct AstraSaveToReadingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Save URL to Astra Reading List"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "URL") var url: URL
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.readLater(url)
        return .result()
    }
}

struct AstraSaveCurrentPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Current Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let url = try await AstraSystemActions.selectedURL()
        try await AstraSystemActions.readLater(url)
        return .result()
    }
}

struct AstraOpenReadingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Astra Reading List Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Saved Page") var page: AstraReadingEntity
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.openReadingList(id: page.id)
        return .result()
    }
}

struct AstraSwitchSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Space") var space: AstraSpaceEntity
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.switchSpace(id: space.id)
        return .result()
    }
}

struct AstraSwitchTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.switchTab(id: tab.id)
        return .result()
    }
}

struct AstraCreateSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        browser.createSpace()
        return .result()
    }
}

struct AstraCreateEaselIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Astra Easel"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.createEasel()
        return .result()
    }
}

struct AstraCurrentURLIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Current Astra URL"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some ReturnsValue<URL> {
        let url = try await AstraSystemActions.selectedURL()
        return .result(value: url)
    }
}

struct AstraReloadIntent: AppIntent {
    static var title: LocalizedStringResource = "Reload Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.reload()
        return .result()
    }
}

struct AstraGoBackIntent: AppIntent {
    static var title: LocalizedStringResource = "Go Back in Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.goBack()
        return .result()
    }
}

struct AstraGoForwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Go Forward in Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.goForward()
        return .result()
    }
}

struct AstraReaderModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Astra Reader Mode"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.toggleReader()
        return .result()
    }
}

struct AstraReopenClosedTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Reopen Closed Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        browser.reopenLastClosedTab()
        return .result()
    }
}

struct AstraToggleSidebarIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Astra Sidebar"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        browser.sidebarShown.toggle()
        return .result()
    }
}

struct AstraToggleAISidebarIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Astra AI Sidebar"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard browser.canShowAISidebar else { throw AstraSystemActions.Failure.unsupportedAction }
        browser.showsAISidebar.toggle()
        return .result()
    }
}

enum AstraInternalPage: String, AppEnum {
    case bookmarks, history, settings, theme
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Astra Page" }
    static var caseDisplayRepresentations: [AstraInternalPage: DisplayRepresentation] {
        [.bookmarks: "Bookmarks", .history: "History", .settings: "Settings", .theme: "Theme Editor"]
    }
}

struct AstraShowPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Page") var page: AstraInternalPage
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        switch page {
        case .bookmarks: browser.openInternalPage(.bookmarks)
        case .history: browser.openInternalPage(.history)
        case .settings: browser.openInternalPage(.settings)
        case .theme: browser.openInternalPage(.themeEditor)
        }
        return .result()
    }
}

struct AstraListTabsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Astra Tabs"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some ReturnsValue<[AstraTabEntity]> {
        let tabs = try await AstraTabEntity.Query().suggestedEntities()
        return .result(value: tabs)
    }
}

struct AstraListSpacesIntent: AppIntent {
    static var title: LocalizedStringResource = "List Astra Spaces"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some ReturnsValue<[AstraSpaceEntity]> {
        let spaces = try await AstraSpaceEntity.Query().suggestedEntities()
        return .result(value: spaces)
    }
}

struct AstraListBookmarksIntent: AppIntent {
    static var title: LocalizedStringResource = "List Astra Bookmarks"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some ReturnsValue<[AstraBookmarkEntity]> {
        let bookmarks = try await AstraBookmarkEntity.Query().suggestedEntities()
        return .result(value: bookmarks)
    }
}

/// App Shortcuts are a small, curated subset. Every AppIntent above remains
/// individually discoverable as an action inside the Shortcuts app.
struct AstraAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AstraOpenURLIntent(),
                    phrases: ["Open a website in \(.applicationName)", "Open a URL in \(.applicationName)"],
                    shortTitle: "Open Website", systemImageName: "globe")
        AppShortcut(intent: AstraSearchWebIntent(),
                    phrases: ["Search the web with \(.applicationName)"],
                    shortTitle: "Search Web", systemImageName: "magnifyingglass")
        AppShortcut(intent: AstraNewTabIntent(),
                    phrases: ["New tab in \(.applicationName)"],
                    shortTitle: "New Tab", systemImageName: "plus.square")
        AppShortcut(intent: AstraNewWindowIntent(),
                    phrases: ["New window in \(.applicationName)"],
                    shortTitle: "New Window", systemImageName: "macwindow.badge.plus")
        AppShortcut(intent: AstraMiniAstraIntent(),
                    phrases: ["Open Mini \(.applicationName)"],
                    shortTitle: "Mini Astra", systemImageName: "macwindow")
        AppShortcut(intent: AstraBookmarkCurrentPageIntent(),
                    phrases: ["Bookmark this page in \(.applicationName)"],
                    shortTitle: "Bookmark Page", systemImageName: "bookmark")
        AppShortcut(intent: AstraSaveCurrentPageIntent(),
                    phrases: ["Save this page in \(.applicationName)"],
                    shortTitle: "Save Page", systemImageName: "text.book.closed")
        AppShortcut(intent: AstraCreateEaselIntent(),
                    phrases: ["Create an easel in \(.applicationName)"],
                    shortTitle: "New Easel", systemImageName: "square.on.square")
        AppShortcut(intent: AstraSwitchSpaceIntent(),
                    phrases: ["Switch spaces in \(.applicationName)"],
                    shortTitle: "Switch Space", systemImageName: "square.stack.3d.up")
        AppShortcut(intent: AstraToggleAISidebarIntent(),
                    phrases: ["Open AI in \(.applicationName)"],
                    shortTitle: "AI Sidebar", systemImageName: "bubble.left.and.text.bubble.right")
    }
}
#endif
