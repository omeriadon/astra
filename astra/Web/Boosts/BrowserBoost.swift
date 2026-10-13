import Foundation
import Observation
import WebKit

/// A portable, per-domain user stylesheet and userscript. A nil domain applies everywhere.
struct BrowserBoost: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var domain: String?
    var css: String = ""
    var javascript: String = ""
    var isEnabled: Bool = true
    var modifiedAt: Date = .now

    nonisolated var isValidForSync: Bool {
        name.utf8.count <= 512
            && (domain?.utf8.count ?? 0) <= 253
            && css.utf8.count <= 131_072
            && javascript.utf8.count <= 131_072
            && modifiedAt.isFiniteBoostTimestamp
            && (domain == nil || Self.normalizedDomain(domain!) == domain)
    }

    nonisolated static func normalizedDomain(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hostname = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)?.host ?? trimmed
        let host = hostname.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !host.isEmpty, host.utf8.count <= 253,
              !host.contains(".."),
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.").contains($0) })
        else { return nil }
        return host
    }
}

private extension Date {
    nonisolated var isFiniteBoostTimestamp: Bool {
        timeIntervalSince1970.isFinite && timeIntervalSince1970 >= 0
            && timeIntervalSince1970 < 4_102_444_800
    }
}

/// A single observable source of truth across windows. Changes are also part of
/// BrowserSyncDocument; separate local storage keeps Boosts off session-save paths.
@MainActor
@Observable
final class BrowserBoostStore {
    static let shared = BrowserBoostStore()
    private(set) var boosts: [BrowserBoost] = []
    private(set) var deletedAt: [UUID: Date] = [:]
    @ObservationIgnored private var webViews: [WeakWebView] = []
    @ObservationIgnored private let storageKey = "astra.boosts.v1"

    private struct Snapshot: Codable {
        var boosts: [BrowserBoost]
        var deletedAt: [UUID: Date]
    }

    private final class WeakWebView {
        weak var webView: WKWebView?
        init(_ webView: WKWebView) { self.webView = webView }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            boosts = snapshot.boosts.filter(\.isValidForSync)
            deletedAt = snapshot.deletedAt.filter { $0.value.isFiniteBoostTimestamp }
        }
    }

    @discardableResult
    func create(domain: String?) -> BrowserBoost {
        let boost = BrowserBoost(name: "Untitled Boost", domain: domain.flatMap(BrowserBoost.normalizedDomain))
        update(boost)
        return boost
    }

    func update(_ boost: BrowserBoost) {
        guard boost.isValidForSync else { return }
        var value = boost
        value.modifiedAt = .now
        deletedAt.removeValue(forKey: value.id)
        if let index = boosts.firstIndex(where: { $0.id == value.id }) {
            boosts[index] = value
        } else {
            boosts.append(value)
        }
        changed(scheduleSync: true)
    }

    func toggle(_ id: UUID) {
        guard var boost = boosts.first(where: { $0.id == id }) else { return }
        boost.isEnabled.toggle()
        update(boost)
    }

    func delete(_ id: UUID) {
        guard boosts.contains(where: { $0.id == id }) else { return }
        boosts.removeAll { $0.id == id }
        deletedAt[id] = .now
        changed(scheduleSync: true)
    }

    /// Merge last-writer-wins records and timestamped tombstones from Astra Sync.
    func merge(remote: [BrowserBoost], deleted remoteDeleted: [UUID: Date]) {
        let incoming = remote.filter(\.isValidForSync)
        var mergedDeleted = deletedAt
        for (id, date) in remoteDeleted where date.isFiniteBoostTimestamp {
            mergedDeleted[id] = max(mergedDeleted[id] ?? .distantPast, date)
        }
        var byID = Dictionary(boosts.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            a.modifiedAt >= b.modifiedAt ? a : b
        })
        for value in incoming {
            if let previous = byID[value.id] {
                if value.modifiedAt > previous.modifiedAt
                    || (value.modifiedAt == previous.modifiedAt && value.name < previous.name) {
                    byID[value.id] = value
                }
            } else {
                byID[value.id] = value
            }
        }
        let next = byID.values.filter { value in
            value.modifiedAt > (mergedDeleted[value.id] ?? .distantPast)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard next != boosts || mergedDeleted != deletedAt else { return }
        boosts = next
        deletedAt = mergedDeleted
        changed(scheduleSync: false)
    }

    func register(_ webView: WKWebView) {
        webViews.removeAll { $0.webView == nil }
        guard !webViews.contains(where: { $0.webView === webView }) else { return }
        webViews.append(WeakWebView(webView))
        install(in: webView)
    }

    private func changed(scheduleSync: Bool) {
        let snapshot = Snapshot(boosts: boosts, deletedAt: deletedAt)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        webViews.removeAll { $0.webView == nil }
        for wrapper in webViews {
            if let webView = wrapper.webView {
                install(in: webView)
                // Hot-swap existing pages, including disabled/deleted CSS.
                // Arbitrary JavaScript side effects cannot be rolled back.
                webView.evaluateJavaScript(scriptSource, in: nil, in: .page, completionHandler: nil)
                for boost in boosts where boost.isEnabled && !boost.javascript.isEmpty {
                    webView.evaluateJavaScript(nativeJavaScriptSource(for: boost), in: nil, in: .page, completionHandler: nil)
                }
            }
        }
        if scheduleSync {
            BrowserSync.shared.scheduleSync()
        }
    }

    private func install(in webView: WKWebView) {
        let controller = webView.configuration.userContentController
        let existing = controller.userScripts.filter { !$0.source.hasPrefix(Self.scriptMarker) }
        controller.removeAllUserScripts()
        for script in existing { controller.addUserScript(script) }
        controller.addUserScript(WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        ))
        for boost in boosts where boost.isEnabled && !boost.javascript.isEmpty {
            controller.addUserScript(WKUserScript(
                source: nativeJavaScriptSource(for: boost),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: .page
            ))
        }
    }

    /// WebKit compiles each user's script separately; we do not rely on eval(),
    /// which is prohibited by the Content Security Policy of many websites.
    private func nativeJavaScriptSource(for boost: BrowserBoost) -> String {
        let id = boost.id.uuidString
        let host = boost.domain ?? ""
        let encodedHost = (try? JSONEncoder().encode(host)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let source = boost.javascript
        return Self.scriptMarker + """
        (() => {
          if (location.protocol !== 'https:' && location.protocol !== 'http:') return;
          const domain = \(encodedHost);
          const hostname = location.hostname.toLowerCase();
          if (domain && hostname !== domain && !hostname.endsWith('.' + domain)) return;
          const state = window.__astraBoostJavaScript || (window.__astraBoostJavaScript = Object.create(null));
          const boostID = "\(id)";
          const signature = "\(boost.javascript.hashValue");
          if (state[boostID] === signature) return;
          state[boostID] = signature;
          try {
            (function() {
              \(source)
            }).call(window);
          } catch (error) {
            console.error('[Astra Boost]', boostID, error);
          }
        })();
        """
    }

    private struct StylePayload: Encodable {
        let id: UUID
        let domain: String?
        let css: String
    }

    private static let scriptMarker = "/* astra-boost-runtime-v1 */"

    /// A snapshot is installed for every future navigation and evaluated in
    /// already-open documents. Only the active domain's code is executed.
    private var scriptSource: String {
        let enabled = boosts.filter(\.isEnabled).map { StylePayload(id: $0.id, domain: $0.domain, css: $0.css) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(enabled)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        // Encode JSON directly as a JS array literal; U+2028/U+2029 must not
        // accidentally terminate JavaScript source strings.
        let json = encoded.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return Self.scriptMarker + """
        (() => {
          const incoming = \(json);
          if (location.protocol !== 'http:' && location.protocol !== 'https:') return;
          const host = location.hostname.toLowerCase();
          const applicable = incoming.filter(b => !b.domain || host === b.domain || host.endsWith('.' + b.domain));
          const run = () => {
            if (!document.documentElement) return;
            const state = window.__astraBoostState || (window.__astraBoostState = Object.create(null));
            const current = new Set(applicable.map(b => b.id));
            for (const [id, entry] of Object.entries(state)) {
              if (!current.has(id)) {
                entry.style?.remove();
                delete state[id];
                if (window.__astraBoostJavaScript) delete window.__astraBoostJavaScript[id];
              }
            }
            for (const boost of applicable) {
              let entry = state[boost.id];
              if (!entry) entry = state[boost.id] = { script: null, style: null };
              if (!entry.style || !entry.style.isConnected) {
                const style = document.createElement('style');
                style.setAttribute('data-astra-boost-id', boost.id);
                document.documentElement.appendChild(style);
                entry.style = style;
              }
              if (entry.style.textContent !== boost.css) entry.style.textContent = boost.css;

            }
          };
          run();
          if (!document.documentElement) document.addEventListener('DOMContentLoaded', run, { once: true });
        })();
        """
    }
}
