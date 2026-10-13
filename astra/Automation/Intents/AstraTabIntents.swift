#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import AstraAutomationCore
import Foundation

struct AstraSwitchTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    @MainActor
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.switchTab(id: tab.id)
        return .result()
    }
}

struct AstraListTabsIntent: AppIntent {
    static let title: LocalizedStringResource = "List Astra Tabs"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some ReturnsValue<[AstraTabEntity]> {
        let tabs = try await AstraTabEntity.Query().suggestedEntities()
        return .result(value: tabs)
    }
}

struct AstraReopenClosedTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Reopen Closed Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        browser.reopenLastClosedTab()
        return .result()
    }
}

struct AstraCloseTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Close Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    @MainActor
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        browser.closeTab(target.id)
        return .result()
    }
}

struct AstraCloseCurrentTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Close Current Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        browser.closeTab(browser.selectedTabID)
        return .result()
    }
}

struct AstraDuplicateTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Duplicate Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    @MainActor
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
    static let title: LocalizedStringResource = "Move Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    @Parameter(title: "Destination") var destination: AstraTabDestination
    @Parameter(title: "Space") var space: AstraSpaceEntity?
    @MainActor
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
    static let title: LocalizedStringResource = "Hibernate Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    @MainActor
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard target.canHibernate else { throw AstraSystemActions.Failure.unsupportedAction }
        browser.hibernateTab(target.id)
        return .result()
    }
}

struct AstraBookmarkTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Bookmark Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    @MainActor
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard target.currentURL != nil else { throw AstraSystemActions.Failure.unsupportedAction }
        browser.bookmarkTabs([target.id])
        return .result()
    }
}

struct AstraReadTabLaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Astra Tab to Reading List"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Tab") var tab: AstraTabEntity
    @MainActor
    func perform() async throws -> some IntentResult {
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard browser.canAddToReadingList(tabID: target.id) else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        browser.addToReadingList(tabID: target.id)
        return .result()
    }
}
#endif
