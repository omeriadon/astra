import Foundation
import Observation
import WebKit

/// Writes snapshots off the UI actor, rejecting stale writes even when
/// concurrent jobs arrive out of order.
private actor BoostPreferencesWriter {
	private var latestRevision = 0
	func write(_ data: Data, revision: Int) {
		guard revision > latestRevision else { return }
		latestRevision = revision
		UserDefaults.standard.set(data, forKey: "astra.boosts.v1")
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
	private(set) var validationMessage: String?
	@ObservationIgnored private var webViews: [WeakWebView] = []
	@ObservationIgnored private let storageKey = "astra.boosts.v1"
	@ObservationIgnored private let preferencesWriter = BoostPreferencesWriter()
	@ObservationIgnored private var preferencesRevision = 0

	private struct Snapshot: Codable {
		var boosts: [BrowserBoost]
		var deletedAt: [UUID: Date]
	}

	private final class WeakWebView {
		weak var webView: WKWebView?
		init(_ webView: WKWebView) {
			self.webView = webView
		}
	}

	private init() {
		if let data = UserDefaults.standard.data(forKey: storageKey),
		   let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
		{
			boosts = snapshot.boosts.filter(\.isValidForSync)
			deletedAt = snapshot.deletedAt.filter(\.value.isFiniteBoostTimestamp)
		}
	}

	@discardableResult
	func create(domain: String?) -> BrowserBoost {
		let boost = BrowserBoost(name: "Untitled Boost", domain: domain.flatMap(BrowserBoost.normalizedDomain))
		update(boost)
		return boost
	}

	func update(_ boost: BrowserBoost) {
		guard boost.isValidForSync else {
			validationMessage = "Boost exceeds the size limit or has an invalid domain."
			return
		}
		let prospectiveByteCount = boost.codeByteCount + boosts.reduce(0) {
			$0 + ($1.id == boost.id ? 0 : $1.codeByteCount)
		}
		guard prospectiveByteCount <= BrowserBoost.maximumCollectionCodeBytes else {
			validationMessage = "Boosts have a combined 1 MB sync limit."
			return
		}
		guard boosts.contains(where: { $0.id == boost.id }) || boosts.count < 512 else {
			validationMessage = "Astra supports up to 512 Boosts."
			return
		}
		validationMessage = nil
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
		var byID = Dictionary(boosts.map { ($0.id, $0) }, uniquingKeysWith: { Self.preferred($0, $1) })
		for value in incoming {
			if let previous = byID[value.id] {
				byID[value.id] = Self.preferred(previous, value)
			} else {
				byID[value.id] = value
			}
		}
		let next = byID.values.filter { value in
			value.modifiedAt > (mergedDeleted[value.id] ?? .distantPast)
		}.sorted { $0.id.uuidString < $1.id.uuidString }
		guard next.reduce(0, { $0 + $1.codeByteCount }) <= BrowserBoost.maximumCollectionCodeBytes else {
			validationMessage = "Synced Boosts exceed the combined 1 MB limit."
			return
		}
		guard next != boosts || mergedDeleted != deletedAt else { return }
		boosts = next
		deletedAt = mergedDeleted
		changed(scheduleSync: false)
	}

	/// Match BrowserSyncDocument's deterministic Codable tie breaker so
	/// equal-timestamp edits converge identically across devices.
	private static func preferred(_ first: BrowserBoost, _ second: BrowserBoost) -> BrowserBoost {
		if first.modifiedAt != second.modifiedAt {
			return first.modifiedAt > second.modifiedAt ? first : second
		}
		if first == second {
			return first
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		let lhs = (try? encoder.encode(first)) ?? Data()
		let rhs = (try? encoder.encode(second)) ?? Data()
		return lhs.lexicographicallyPrecedes(rhs) ? second : first
	}

	func register(_ webView: WKWebView) {
		webViews.removeAll { $0.webView == nil }
		guard !webViews.contains(where: { $0.webView === webView }) else { return }
		webViews.append(WeakWebView(webView))
		install(in: webView, styles: scriptSource,
		        scripts: boosts.filter { $0.isEnabled && !$0.javascript.isEmpty }.map(nativeJavaScriptSource))
	}

	private func changed(scheduleSync: Bool) {
		let snapshot = Snapshot(boosts: boosts, deletedAt: deletedAt)
		if let data = try? JSONEncoder().encode(snapshot) {
			preferencesRevision &+= 1
			let revision = preferencesRevision
			let writer = preferencesWriter
			Task.detached(priority: .utility) {
				await writer.write(data, revision: revision)
			}
		}
		let styles = scriptSource
		let scripts = boosts.filter { $0.isEnabled && !$0.javascript.isEmpty }.map(nativeJavaScriptSource)
		webViews.removeAll { $0.webView == nil }
		for wrapper in webViews {
			if let webView = wrapper.webView {
				install(in: webView, styles: styles, scripts: scripts)
				// Hot-swap existing pages, including disabled/deleted CSS.
				// Arbitrary JavaScript side effects cannot be rolled back.
				webView.evaluateJavaScript(styles, in: nil, in: .page, completionHandler: nil)
				for script in scripts {
					webView.evaluateJavaScript(script, in: nil, in: .page, completionHandler: nil)
				}
			}
		}
		if scheduleSync {
			BrowserSync.shared.scheduleSync()
		}
	}

	private func install(in webView: WKWebView, styles: String, scripts: [String]) {
		let controller = webView.configuration.userContentController
		let existing = controller.userScripts.filter { !$0.source.hasPrefix(Self.scriptMarker) }
		controller.removeAllUserScripts()
		for script in existing {
			controller.addUserScript(script)
		}
		controller.addUserScript(WKUserScript(
			source: styles,
			injectionTime: .atDocumentStart,
			forMainFrameOnly: true,
			in: .page
		))
		for script in scripts {
			controller.addUserScript(WKUserScript(
				source: script,
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
		  const signature = "\(boost.javascript.hashValue)";
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
		    if (applicable.length === 0 && !window.__astraBoostState) return;
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
