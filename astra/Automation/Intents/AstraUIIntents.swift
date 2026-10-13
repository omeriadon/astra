#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import AstraAutomationCore
import Foundation

struct AstraCreateEaselIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Astra Easel"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.createEasel()
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

struct AstraShowDownloadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Astra Downloads"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        NotificationCenter.default.post(name: .showBrowserDownloads, object: browser.windowID)
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
#endif
