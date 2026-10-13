#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppKit
import AstraAutomationCore
import Foundation
import CoreSpotlight
import CryptoKit
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
    private var fingerprints: [String: String]?
    private let domain = "com.omeriadon.astra.library"
    private let defaultsKey = "AstraSpotlightFingerprintsV1"

    func replace(_ records: [AstraSpotlightRecord]) async {
        // Fingerprints are stable across launches, unlike Swift's Hasher.
        // Only changed or newly inserted items reach Core Spotlight.
        let fresh = Dictionary(uniqueKeysWithValues: records.map { record in
            let bytes = Data((record.title + "\u{0}" + record.detail + "\u{0}"
                              + record.url + "\u{0}" + record.kind).utf8)
            let digest = SHA256.hash(data: bytes).map { unsafe String(format: "%02x", $0) }.joined()
            return (record.identifier, digest)
        })
        if fingerprints == nil {
            fingerprints = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        }
        let old = fingerprints ?? [:]
        let removed = Array(Set(old.keys).subtracting(fresh.keys))
        let changed = records.filter { old[$0.identifier] != fresh[$0.identifier] }
        if changed.isEmpty && removed.isEmpty { return }

        let index = CSSearchableIndex.default()
        if !changed.isEmpty {
            let items = changed.map { record in
                let attributes = CSSearchableItemAttributeSet(contentType: .text)
                attributes.title = record.title
                attributes.contentDescription = record.detail
                attributes.keywords = ["Astra", record.kind]
                let item = CSSearchableItem(uniqueIdentifier: record.identifier,
                                            domainIdentifier: domain, attributeSet: attributes)
                item.expirationDate = .distantFuture
                return item
            }
            let succeeded: Bool = await withCheckedContinuation { continuation in
                index.indexSearchableItems(items) { error in
                    continuation.resume(returning: error == nil)
                }
            }
            guard succeeded else { return }
        }

        if !removed.isEmpty {
            let succeeded: Bool = await withCheckedContinuation { continuation in
                index.deleteSearchableItems(withIdentifiers: removed) { error in
                    continuation.resume(returning: error == nil)
                }
            }
            guard succeeded else { return }
        }
        fingerprints = fresh
        UserDefaults.standard.set(fresh, forKey: defaultsKey)
    }
}
#endif
