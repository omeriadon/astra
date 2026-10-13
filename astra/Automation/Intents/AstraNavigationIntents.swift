#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import AstraAutomationCore
import Foundation

struct AstraOpenURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Open URL in Astra"
    static let description = IntentDescription("Open a website in a new Astra tab.")
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "URL") var url: URL
    @MainActor
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.open(url)
        return .result()
    }
}

struct AstraSearchWebIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Web with Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Search Text") var query: String
    @MainActor
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.search(query)
        return .result()
    }
}

struct AstraNewTabIntent: AppIntent {
    static let title: LocalizedStringResource = "New Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.newTab()
        return .result()
    }
}

struct AstraNewWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "New Astra Window"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Private", default: false) var isPrivate: Bool
    @MainActor
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.newWindow(isPrivate: isPrivate)
        return .result()
    }
}

struct AstraMiniAstraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Mini Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.mini(nil)
        return .result()
    }
}

@AppIntent(schema: .browser.openURLInTab)
struct AstraNavigateTabIntent {
    static let title: LocalizedStringResource = "Open URL in Astra Tab"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    var url: URL
    var tab: AstraTabEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let checked = try AstraSystemActions.validated(url)
        let (browser, target) = try await AstraSystemActions.resolveTab(id: tab.id)
        guard target.internalPage == nil else { throw AstraSystemActions.Failure.unsupportedAction }
        browser.selectTab(target.id)
        target.activeController?.load(checked)
        return .result()
    }
}

struct AstraCurrentURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Astra URL"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some ReturnsValue<URL> {
        let url = try await AstraSystemActions.selectedURL()
        return .result(value: url)
    }
}

struct AstraGetPageTitleIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Astra Page Title"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let tab = browser.selectedTab else { throw AstraSystemActions.Failure.missingItem }
        return .result(value: tab.title)
    }
}

struct AstraReloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Reload Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.reload()
        return .result()
    }
}

struct AstraHardReloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Hard Reload Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.reloadFromOrigin()
        return .result()
    }
}

struct AstraGoBackIntent: AppIntent {
    static let title: LocalizedStringResource = "Go Back in Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.goBack()
        return .result()
    }
}

struct AstraGoForwardIntent: AppIntent {
    static let title: LocalizedStringResource = "Go Forward in Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.goForward()
        return .result()
    }
}

struct AstraReaderModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Astra Reader Mode"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.toggleReader()
        return .result()
    }
}

struct AstraZoomInIntent: AppIntent {
    static let title: LocalizedStringResource = "Zoom In Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.zoomIn()
        return .result()
    }
}

struct AstraZoomOutIntent: AppIntent {
    static let title: LocalizedStringResource = "Zoom Out Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.zoomOut()
        return .result()
    }
}

struct AstraResetZoomIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Astra Page Zoom"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.resetZoom()
        return .result()
    }
}

struct AstraTranslatePageIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Current Astra Page"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard browser.selectedTab?.activeController?.hasCurrentPageDocument == true else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        NotificationCenter.default.post(name: .astraTranslatePage, object: browser)
        return .result()
    }
}

struct AstraTogglePictureInPictureIntent: AppIntent {
    static let title: LocalizedStringResource = "Picture in Picture in Astra"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.currentBrowser()
        guard let controller = browser.selectedTab?.activeController,
              controller.canEnterPictureInPicture else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        controller.enterPictureInPicture()
        return .result()
    }
}
#endif
