#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import AstraAutomationCore
import Foundation

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
        let browser = try await AstraSystemActions.existingBrowser()
        let records = browser.readingList.map {
            AstraReadingEntity(id: $0.id.uuidString, title: $0.title, url: $0.url, isRead: $0.isRead)
        }
        return .result(value: records)
    }
}
#endif
