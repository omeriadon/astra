#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppKit
import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
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
                                    url: AstraLibraryItem.bookmark($0.id).url.absoluteString, kind: "bookmark")
            }
            let reading = browser.readingList.map {
                AstraSpotlightRecord(identifier: "reading:" + $0.id.uuidString,
                                    title: $0.title, detail: $0.url.absoluteString,
                                    url: AstraLibraryItem.readingList($0.id).url.absoluteString, kind: "reading")
            }
            let spaces = browser.workspace.spaces.map {
                AstraSpotlightRecord(identifier: "space:" + $0.id.uuidString,
                                    title: $0.name, detail: "Astra Space",
                                    url: AstraLibraryItem.space($0.id).url.absoluteString, kind: "space")
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
#endif
