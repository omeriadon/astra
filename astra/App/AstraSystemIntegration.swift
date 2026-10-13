#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import CoreSpotlight
import UniformTypeIdentifiers
import Foundation

/// The only entry point used by App Intents, Services, and Spotlight navigation.
/// Never infer a browser from a SwiftUI view or mutate a restoring session.
@MainActor
enum AstraSystemActions {
    enum Failure: LocalizedError {
        case unavailable
        case invalidURL
        case missingItem
        case unsupportedAction

        var errorDescription: String? {
            switch self {
            case .unavailable: "Astra is still opening. Try again once its windows are ready."
            case .invalidURL: "Only HTTP and HTTPS web addresses are supported."
            case .missingItem: "This item no longer exists in Astra."
            case .unsupportedAction: "This action is unavailable for the selected page."
            }
        }
    }

    private static var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    static func normalBrowsers() -> [Browser] {
        BrowserWindowRegistry.shared.openBrowsers.filter {
            !$0.isPrivate && !$0.isMini && $0.isHydrationFinished
        }
    }

    static func browser() async throws -> Browser {
        guard let delegate, await delegate.awaitSystemActionsReady() else {
            throw Failure.unavailable
        }
        if let preferred = BrowserWindowRegistry.shared.activeBrowser,
           !preferred.isPrivate && !preferred.isMini && preferred.isHydrationFinished {
            return preferred
        }
        if let existing = normalBrowsers().first { return existing }
        let created = delegate.openBrowserWindow().browser
        for _ in 0 ..< 200 {
            if created.isHydrationFinished { return created }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure.unavailable
    }

    static func validated(_ raw: URL) throws -> URL {
        guard let url = BrowserHomepage.validURL(raw.absoluteString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw Failure.invalidURL
        }
        return BrowserAddress.withoutCredentials(url)
    }

    @discardableResult
    static func open(_ raw: URL, background: Bool = false) async throws -> BrowserTab {
        let url = try validated(raw)
        let browser = try await browser()
        let tab = browser.addTab(inBackground: background)
        tab.controller?.load(url)
        if !background { delegate?.focusSystemBrowser(browser) }
        return tab
    }

    static func newTab() async throws {
        let browser = try await browser()
        browser.addTab()
        delegate?.focusSystemBrowser(browser)
    }

    static func newWindow(isPrivate: Bool) async throws {
        guard let delegate, await delegate.awaitSystemActionsReady() else {
            throw Failure.unavailable
        }
        delegate.openBrowserWindow(isPrivate: isPrivate)
    }

    static func mini(_ url: URL?) async throws {
        guard let delegate, await delegate.awaitSystemActionsReady() else {
            throw Failure.unavailable
        }
        let checked = try url.map(validated)
        delegate.openMiniAstra(url: checked)
    }

    static func search(_ text: String) async throws {
        let browser = try await browser()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.utf8.count <= 4096,
              let url = browser.browserSearchConfiguration.searchURL(for: query, isPrivate: false) else {
            throw Failure.invalidURL
        }
        try await open(url)
    }

    static func bookmark(_ raw: URL, title: String? = nil) async throws {
        let url = try validated(raw)
        let browser = try await browser()
        if !browser.bookmarks.contains(where: { $0.url == url }) {
            browser.importBookmarks([Bookmark(name: title ?? url.host ?? url.absoluteString, url: url)])
        }
    }

    static func readLater(_ raw: URL, title: String? = nil) async throws {
        let url = try validated(raw)
        let browser = try await browser()
        if browser.canAddToReadingList(url) {
            browser.addToReadingList(url, title: title ?? url.host ?? url.absoluteString)
        }
    }

    static func selectedURL() async throws -> URL {
        let browser = try await browser()
        guard let url = browser.selectedTab?.copyableURL else { throw Failure.missingItem }
        return try validated(url)
    }

    static func openBookmark(id: String) async throws {
        let browser = try await browser()
        guard let uuid = UUID(uuidString: id),
              let item = browser.bookmarks.first(where: { $0.id == uuid }) else {
            throw Failure.missingItem
        }
        browser.openBookmark(item)
        delegate?.focusSystemBrowser(browser)
    }

    static func openReadingList(id: String) async throws {
        let browser = try await browser()
        guard let uuid = UUID(uuidString: id),
              let item = browser.readingList.first(where: { $0.id == uuid }) else {
            throw Failure.missingItem
        }
        browser.openReadingListItem(item, offline: false)
        delegate?.focusSystemBrowser(browser)
    }

    static func switchSpace(id: String) async throws {
        let browser = try await browser()
        guard let uuid = UUID(uuidString: id),
              browser.workspace.spaces.contains(where: { $0.id == uuid }) else {
            throw Failure.missingItem
        }
        browser.selectSpace(uuid)
        delegate?.focusSystemBrowser(browser)
    }

    static func resolveTab(id: String) async throws -> (Browser, BrowserTab) {
        let components = id.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              let windowID = UUID(uuidString: String(components[0])),
              let tabID = UUID(uuidString: String(components[1])) else {
            throw Failure.missingItem
        }
        guard let delegate, await delegate.awaitSystemActionsReady(),
              let browser = normalBrowsers().first(where: { $0.windowID == windowID }),
              BrowserWindowRegistry.shared.ownsTab(tabID, in: browser),
              let tab = browser.tab(withID: tabID) else {
            throw Failure.missingItem
        }
        return (browser, tab)
    }

    static func switchTab(id: String) async throws {
        let components = id.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              let windowID = UUID(uuidString: String(components[0])),
              let tabID = UUID(uuidString: String(components[1])) else {
            throw Failure.missingItem
        }
        guard let delegate, await delegate.awaitSystemActionsReady(),
              let browser = normalBrowsers().first(where: { $0.windowID == windowID }),
              BrowserWindowRegistry.shared.ownsTab(tabID, in: browser),
              browser.tab(withID: tabID) != nil else {
            throw Failure.missingItem
        }
        // Selecting a tab in another space already updates its space membership.
        browser.selectTab(tabID)
        delegate.focusSystemBrowser(browser)
    }

    static func createEasel(with selection: String? = nil, link: URL? = nil) async throws {
        let browser = try await browser()
        guard let tab = browser.createEasel() else { throw Failure.unsupportedAction }
        if let selection, !selection.isEmpty {
            var document = tab.easelDocument
            let text = String(selection.prefix(8000))
            document.items.append(.init(kind: .text, text: text))
            guard tab.updateEasel(document) else { throw Failure.unsupportedAction }
        } else if let link {
            var document = tab.easelDocument
            document.items.append(.init(kind: .link, url: try validated(link)))
            guard tab.updateEasel(document) else { throw Failure.unsupportedAction }
        }
        delegate?.focusSystemBrowser(browser)
    }

    static func openSpotlightURL(_ url: URL) async {
        guard url.scheme == "astra", let kind = url.host,
              let id = url.pathComponents.dropFirst().first else { return }
        do {
            switch kind {
            case "bookmark": try await openBookmark(id: id)
            case "reading": try await openReadingList(id: id)
            case "space": try await switchSpace(id: id)
            default: break
            }
        } catch {
            BrowserLog.error(.navigation, "system.spotlight-open-failed",
                             metadata: ["error": BrowserLog.errorDescription(error)])
        }
    }
}

/// Indexed metadata is deliberately small. Neither page bodies nor private windows
/// are copied to Spotlight, and history is not indexed implicitly.
private struct AstraSpotlightRecord: Sendable {
    let identifier: String
    let title: String
    let detail: String
    let url: String
    let kind: String
}

@MainActor
enum AstraSpotlightIndexer {
    private static var pending: Task<Void, Never>?

    static func scheduleRefresh() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let browser = AstraSystemActions.normalBrowsers().first else { return }
            let bookmarks = browser.bookmarks.map {
                AstraSpotlightRecord(identifier: "bookmark:" + $0.id.uuidString,
                                    title: $0.name, detail: $0.folder.isEmpty ? $0.url.absoluteString : $0.folder,
                                    url: "astra://bookmark/" + $0.id.uuidString, kind: "bookmark")
            }
            let reading = browser.readingList.map {
                AstraSpotlightRecord(identifier: "reading:" + $0.id.uuidString,
                                    title: $0.title, detail: $0.url.absoluteString,
                                    url: "astra://reading/" + $0.id.uuidString, kind: "reading")
            }
            let spaces = browser.workspace.spaces.map {
                AstraSpotlightRecord(identifier: "space:" + $0.id.uuidString,
                                    title: $0.name, detail: "Astra Space",
                                    url: "astra://space/" + $0.id.uuidString, kind: "space")
            }
            await AstraSpotlightWriter.shared.replace(bookmarks + reading + spaces)
        }
    }
}

private actor AstraSpotlightWriter {
    static let shared = AstraSpotlightWriter()
    private var identifiers: Set<String>?
    private let domain = "com.omeriadon.astra.library"

    func replace(_ records: [AstraSpotlightRecord]) async {
        let current = Set(records.map(\.identifier))
        if identifiers == nil {
            identifiers = Set(UserDefaults.standard.stringArray(forKey: "AstraSpotlightIDs") ?? [])
        }
        let obsolete = Array((identifiers ?? []).subtracting(current))
        let items = records.map { record in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = record.title
            attributes.contentDescription = record.detail
            attributes.relatedUniqueIdentifier = record.url
            attributes.keywords = ["Astra", record.kind]
            let item = CSSearchableItem(uniqueIdentifier: record.identifier,
                                        domainIdentifier: domain, attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
        // Serialise updates: deletion must not race a replacement on another refresh.
        let index = CSSearchableIndex.default()
        let indexed = await withCheckedContinuation { continuation in
            index.indexSearchableItems(items) { error in
                continuation.resume(returning: error == nil)
            }
        }
        guard indexed else { return }
        if !obsolete.isEmpty {
            let deleted = await withCheckedContinuation { continuation in
                index.deleteSearchableItems(withIdentifiers: obsolete) { error in
                    continuation.resume(returning: error == nil)
                }
            }
            guard deleted else { return }
        }
        identifiers = current
        UserDefaults.standard.set(Array(current), forKey: "AstraSpotlightIDs")
    }
}

@MainActor
final class AstraServicesProvider: NSObject {
    static let shared = AstraServicesProvider()

    private func value(_ pasteboard: NSPasteboard) -> String? {
        let string = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let string, !string.isEmpty, string.utf8.count <= 16384 else { return nil }
        return string
    }

    private func url(_ pasteboard: NSPasteboard) -> URL? {
        if let raw = pasteboard.string(forType: .URL), let candidate = URL(string: raw) {
            return try? AstraSystemActions.validated(candidate)
        }
        guard let string = value(pasteboard), let candidate = URL(string: string) else { return nil }
        return try? AstraSystemActions.validated(candidate)
    }

    @objc(searchInAstra:userData:error:)
    func searchInAstra(_ pasteboard: NSPasteboard, userData: String?,
                       error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let text = value(pasteboard) else {
            error?.pointee = "Select some text to search." as NSString
            return
        }
        Task { @MainActor in
            do { try await AstraSystemActions.search(text) }
            catch { BrowserLog.error(.navigation, "service.search-failed", metadata: ["error": BrowserLog.errorDescription(error)]) }
        }
    }

    @objc(openInAstra:userData:error:)
    func openInAstra(_ pasteboard: NSPasteboard, userData: String?,
                     error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let link = url(pasteboard) else {
            error?.pointee = "Select a valid HTTP or HTTPS URL." as NSString
            return
        }
        Task { @MainActor in
            do { try await AstraSystemActions.open(link) }
            catch { BrowserLog.error(.navigation, "service.open-failed", metadata: ["error": BrowserLog.errorDescription(error)]) }
        }
    }

    @objc(openInMiniAstra:userData:error:)
    func openInMiniAstra(_ pasteboard: NSPasteboard, userData: String?,
                         error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let link = url(pasteboard) else {
            error?.pointee = "Select a valid HTTP or HTTPS URL." as NSString
            return
        }
        Task { @MainActor in
            do { try await AstraSystemActions.mini(link) }
            catch { BrowserLog.error(.navigation, "service.mini-failed", metadata: ["error": BrowserLog.errorDescription(error)]) }
        }
    }

    @objc(saveToAstraReadingList:userData:error:)
    func saveToAstraReadingList(_ pasteboard: NSPasteboard, userData: String?,
                                error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let link = url(pasteboard) else {
            error?.pointee = "Select a valid HTTP or HTTPS URL." as NSString
            return
        }
        Task { @MainActor in
            do { try await AstraSystemActions.readLater(link) }
            catch { BrowserLog.error(.navigation, "service.reading-failed", metadata: ["error": BrowserLog.errorDescription(error)]) }
        }
    }

    @objc(createAstraEasel:userData:error:)
    func createAstraEasel(_ pasteboard: NSPasteboard, userData: String?,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let text = value(pasteboard) else {
            error?.pointee = "Select text or a URL to add to an easel." as NSString
            return
        }
        let link = url(pasteboard)
        Task { @MainActor in
            do {
                if let link { try await AstraSystemActions.createEasel(link: link) }
                else { try await AstraSystemActions.createEasel(with: text) }
            } catch {
                BrowserLog.error(.navigation, "service.easel-failed", metadata: ["error": BrowserLog.errorDescription(error)])
            }
        }
    }
}
#endif
