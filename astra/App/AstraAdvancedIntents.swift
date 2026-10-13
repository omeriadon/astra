#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import Foundation

/// Additional composable Shortcuts actions for real browser operations.
/// Tabs carry the owning window ID to prevent cross-window or stale-ID mutations.

@AppIntent(schema: .browser.openURLInTab)
struct AstraNavigateTabIntent {
    static var title: LocalizedStringResource = "Open URL in Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    var url: URL
    var tab: AstraTabEntity

    func perform() async throws -> some IntentResult {
        let checked = try AstraSystemActions.validated(url)
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard target.internalPage == nil else { throw AstraSystemActions.Failure.unsupportedAction }
        browser.selectTab(target.id)
        target.activeController?.load(checked)
        return .result()
    }
}

struct AstraCloseTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Close Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        browser.closeTab(target.id)
        return .result()
    }
}

struct AstraCloseCurrentTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Close Current Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        browser.closeTab(browser.selectedTabID)
        return .result()
    }
}

struct AstraDuplicateTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Duplicate Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard browser.duplicateTab(target.id) != nil else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        return .result()
    }
}

enum AstraTabDestination: String, AppEnum {
    case favourites, pinned, normal
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Tab Area" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.favourites: "Favourites", .pinned: "Pinned", .normal: "Normal Tabs"]
    }
}

struct AstraMoveTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Move Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    @Parameter(title: "Destination") var destination: AstraTabDestination
    @Parameter(title: "Space") var space: AstraSpaceEntity?
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        let area: Browser.TabArea = switch destination {
        case .favourites: .favourite
        case .pinned: .pinned
        case .normal: .normal
        }
        let spaceID = space.flatMap { UUID(uuidString: $0.id) }
        if let spaceID, !browser.workspace.spaces.contains(where: { $0.id == spaceID }) {
            throw AstraSystemActions.Failure.missingItem
        }
        browser.moveTab(target.id, to: area, in: spaceID)
        return .result()
    }
}

struct AstraHibernateTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Hibernate Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard target.canHibernate else { throw AstraSystemActions.Failure.unsupportedAction }
        browser.hibernateTab(target.id)
        return .result()
    }
}

struct AstraBookmarkTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Bookmark Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard target.currentURL != nil else { throw AstraSystemActions.Failure.unsupportedAction }
        browser.bookmarkTabs([target.id])
        return .result()
    }
}

struct AstraReadTabLaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Astra Tab to Reading List"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard browser.canAddToReadingList(tabID: target.id) else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        browser.addToReadingList(tabID: target.id)
        return .result()
    }
}

struct AstraNewNamedSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Named Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Name") var name: String
    func perform() async throws -> some IntentResult {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 128 else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        let browser = try await AstraSystemActions.browser()
        browser.createSpace()
        browser.renameSelectedSpace(text)
        return .result()
    }
}

struct AstraRenameSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Rename Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Space") var space: AstraSpaceEntity
    @Parameter(title: "New Name") var newName: String
    func perform() async throws -> some IntentResult {
        let text = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 128,
              let id = UUID(uuidString: space.id) else {
            throw AstraSystemActions.Failure.missingItem
        }
        let browser = try await AstraSystemActions.browser()
        guard browser.workspace.spaces.contains(where: { $0.id == id }) else {
            throw AstraSystemActions.Failure.missingItem
        }
        browser.selectSpace(id)
        browser.renameSelectedSpace(text)
        return .result()
    }
}

struct AstraSetReadingStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Astra Reading List Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Saved Page") var page: AstraReadingEntity
    @Parameter(title: "Read") var isRead: Bool
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let id = UUID(uuidString: page.id),
              browser.readingList.contains(where: { $0.id == id }) else {
            throw AstraSystemActions.Failure.missingItem
        }
        browser.setReadingListRead(id, isRead: isRead)
        return .result()
    }
}

struct AstraListReadingListIntent: AppIntent {
    static var title: LocalizedStringResource = "List Astra Reading List"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some ReturnsValue<[AstraReadingEntity]> {
        let browser = try await AstraSystemActions.browser()
        let records = browser.readingList.map {
            AstraReadingEntity(id: $0.id.uuidString, title: $0.title, url: $0.url, isRead: $0.isRead)
        }
        return .result(value: records)
    }
}

struct AstraGetPageTitleIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Current Astra Page Title"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some ReturnsValue<String> {
        let browser = try await AstraSystemActions.browser()
        guard let tab = browser.selectedTab else { throw AstraSystemActions.Failure.missingItem }
        return .result(value: tab.title)
    }
}

struct AstraHardReloadIntent: AppIntent {
    static var title: LocalizedStringResource = "Hard Reload Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.reloadFromOrigin()
        return .result()
    }
}

struct AstraZoomInIntent: AppIntent {
    static var title: LocalizedStringResource = "Zoom In Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.zoomIn()
        return .result()
    }
}

struct AstraZoomOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Zoom Out Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.zoomOut()
        return .result()
    }
}

struct AstraResetZoomIntent: AppIntent {
    static var title: LocalizedStringResource = "Reset Astra Page Zoom"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.resetZoom()
        return .result()
    }
}

struct AstraShowDownloadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Astra Downloads"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        NotificationCenter.default.post(name: .showBrowserDownloads, object: browser.windowID)
        return .result()
    }
}

struct AstraTranslatePageIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Current Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard browser.selectedTab?.activeController?.hasCurrentPageDocument == true else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        NotificationCenter.default.post(name: .astraTranslatePage, object: browser)
        return .result()
    }
}

struct AstraToggleTopBarIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Astra Top Bar"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        NotificationCenter.default.post(name: .toggleBrowserTopBar, object: browser.windowID)
        return .result()
    }
}

struct AstraTogglePictureInPictureIntent: AppIntent {
    static var title: LocalizedStringResource = "Picture in Picture in Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        guard let controller = browser.selectedTab?.activeController,
              controller.canEnterPictureInPicture else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.enterPictureInPicture()
        return .result()
    }
}

struct AstraDownloadEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Astra Download" }
    static let defaultQuery = Query()
    let id: String
    @Property(title: "Filename") var name: String
    @Property(title: "Status") var status: String

    init(id: String, name: String, status: String) {
        self.id = id
        self.name = name
        self.status = status
    }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(status)") }

    struct Query: EntityStringQuery {
        private func live() -> [AstraDownloadEntity] {
            BrowserDownloadManager.shared.items.map {
                AstraDownloadEntity(id: $0.id.uuidString, name: $0.name, status: $0.status.rawValue)
            }
        }
        func entities(for identifiers: [String]) async throws -> [AstraDownloadEntity] {
            let wanted = Set(identifiers)
            return live().filter { wanted.contains($0.id) }
        }
        func entities(matching string: String) async throws -> [AstraDownloadEntity] {
            live().filter { $0.name.localizedCaseInsensitiveContains(string) }
        }
        func suggestedEntities() async throws -> [AstraDownloadEntity] { Array(live().prefix(30)) }
    }
}

struct AstraListDownloadsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Astra Downloads"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some ReturnsValue<[AstraDownloadEntity]> {
        return .result(value: try await AstraDownloadEntity.Query().suggestedEntities())
    }
}

struct AstraPauseDownloadIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Astra Download"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Download") var download: AstraDownloadEntity
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: download.id),
              BrowserDownloadManager.shared.items.contains(where: { $0.id == id && $0.status == .downloading }) else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        BrowserDownloadManager.shared.pause(id)
        return .result()
    }
}

struct AstraResumeDownloadIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Astra Download"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Download") var download: AstraDownloadEntity
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: download.id),
              BrowserDownloadManager.shared.items.contains(where: { $0.id == id && $0.canResume }) else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        BrowserDownloadManager.shared.resume(id)
        return .result()
    }
}
#endif
