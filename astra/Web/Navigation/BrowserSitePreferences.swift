import Defaults
import Foundation
import Observation
import WebKit

enum BrowserSiteContentMode: String, CaseIterable, Identifiable {
	case recommended
	case desktop
	case mobile

	var id: Self { self }

	var title: String {
		switch self {
			case .recommended: "Recommended"
			case .desktop: "Desktop"
			case .mobile: "Mobile"
		}
	}

	var webKitMode: WKWebpagePreferences.ContentMode? {
		switch self {
			case .recommended: nil
			case .desktop: .desktop
			case .mobile: .mobile
		}
	}
}

@MainActor
@Observable
final class BrowserSitePreferences {
	static let shared = BrowserSitePreferences(isPrivate: false)

	let isPrivate: Bool
	private let defaults: UserDefaults
	private var zoomData: Data?
	private(set) var zoomDocument: BrowserSiteZoomDocument
	private var localDocument: BrowserLocalSitePreferencesDocument
	private(set) var isZoomDataReadOnly = false
	private(set) var isLocalDataReadOnly = false
	@ObservationIgnored
	private var defaultsObserver: NSObjectProtocol?
	@ObservationIgnored
	var didUpdateZoom: ((String, Double?) -> Void)?

	init(isPrivate: Bool, defaults: UserDefaults = .standard) {
		self.isPrivate = isPrivate
		self.defaults = defaults
		if isPrivate {
			zoomData = nil
			zoomDocument = BrowserSiteZoomDocument()
			localDocument = BrowserLocalSitePreferencesDocument()
		} else {
			let zoomData = defaults.data(forKey: BrowserSiteZoomDocument.defaultsKey)
			self.zoomData = zoomData
			if let zoomData, let document = BrowserSiteZoomDocument.decodeSupported(zoomData) {
				zoomDocument = document
			} else {
				zoomDocument = BrowserSiteZoomDocument()
				isZoomDataReadOnly = zoomData != nil
			}
			let localData = defaults.data(forKey: BrowserLocalSitePreferencesDocument.defaultsKey)
			if let localData, let document = BrowserLocalSitePreferencesDocument.decodeSupported(localData) {
				localDocument = document
			} else {
				localDocument = BrowserLocalSitePreferencesDocument()
				isLocalDataReadOnly = localData != nil
			}
			defaultsObserver = NotificationCenter.default.addObserver(
				forName: UserDefaults.didChangeNotification,
				object: defaults,
				queue: .main
			) { [weak self] _ in
				Task { @MainActor [weak self] in
					self?.reloadZoomFromDefaults()
				}
			}
		}
	}

	func zoom(for origin: String) -> Double? {
		zoomDocument.entries[origin]?.zoom
	}

	func setZoom(_ zoom: Double, for origin: String) {
		guard !isZoomDataReadOnly,
		      let canonicalOrigin = Self.canonicalOrigin(origin),
		      zoom.isFinite else { return }
		let boundedZoom = min(max(zoom, 0.25), 5)
		guard self.zoom(for: canonicalOrigin) != boundedZoom else { return }
		zoomDocument.entries[canonicalOrigin] = BrowserSiteZoomEntry(zoom: boundedZoom, modifiedAt: .now)
		persistZoomDocument()
		didUpdateZoom?(canonicalOrigin, boundedZoom)
	}

	func resetZoom(for origin: String) {
		guard !isZoomDataReadOnly,
		      let canonicalOrigin = Self.canonicalOrigin(origin),
		      zoomDocument.entries[canonicalOrigin]?.zoom != nil else { return }
		zoomDocument.entries[canonicalOrigin] = BrowserSiteZoomEntry(zoom: nil, modifiedAt: .now)
		persistZoomDocument()
		didUpdateZoom?(canonicalOrigin, nil)
	}

	func resetAll() {
		let changedOrigins = zoomDocument.entries.compactMap { origin, entry in
			entry.zoom == nil ? nil : origin
		}
		if !isZoomDataReadOnly, !changedOrigins.isEmpty {
			let resetAt = Date.now
			for origin in changedOrigins {
				zoomDocument.entries[origin] = BrowserSiteZoomEntry(zoom: nil, modifiedAt: resetAt)
			}
			persistZoomDocument()
			for origin in changedOrigins.sorted() {
				didUpdateZoom?(origin, nil)
			}
		}
		if !isLocalDataReadOnly, !localDocument.entries.isEmpty {
			localDocument.entries.removeAll()
			persistLocalDocument()
		}
	}

	func hasPreferences(for origin: String) -> Bool {
		zoom(for: origin) != nil
			|| localDocument.entries[origin].map { !$0.isEmpty } == true
	}

	var hasPreferences: Bool {
		zoomDocument.entries.values.contains { $0.zoom != nil } || !localDocument.entries.isEmpty
	}

	func contentMode(for origin: String) -> BrowserSiteContentMode? {
		localDocument.entries[origin]?.contentMode.flatMap(BrowserSiteContentMode.init(rawValue:))
	}

	func webKitContentMode(for origin: String) -> WKWebpagePreferences.ContentMode? {
		contentMode(for: origin)?.webKitMode
	}

	func customUserAgent(for origin: String) -> String? {
		localDocument.entries[origin]?.customUserAgent
	}

	func setContentMode(_ mode: BrowserSiteContentMode, for origin: String) {
		guard !isLocalDataReadOnly, let canonicalOrigin = Self.canonicalOrigin(origin) else { return }
		var preference = localDocument.entries[canonicalOrigin] ?? BrowserLocalSitePreference()
		preference.contentMode = mode == .recommended ? nil : mode.rawValue
		setLocalPreference(preference, for: canonicalOrigin)
	}

	func setCustomUserAgent(_ userAgent: String?, for origin: String) {
		guard !isLocalDataReadOnly, let canonicalOrigin = Self.canonicalOrigin(origin) else { return }
		let normalized = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
		guard normalized.map({ $0.utf8.count <= 2048 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) ?? true else { return }
		var preference = localDocument.entries[canonicalOrigin] ?? BrowserLocalSitePreference()
		preference.customUserAgent = normalized?.isEmpty == true ? nil : normalized
		setLocalPreference(preference, for: canonicalOrigin)
	}

	func resetLocalPreferences(for origin: String) {
		guard !isLocalDataReadOnly,
		      let canonicalOrigin = Self.canonicalOrigin(origin),
		      localDocument.entries[canonicalOrigin] != nil else { return }
		localDocument.entries[canonicalOrigin] = nil
		persistLocalDocument()
	}

	private func setLocalPreference(_ preference: BrowserLocalSitePreference, for origin: String) {
		guard localDocument.entries[origin] != preference else { return }
		localDocument.entries[origin] = preference.isEmpty ? nil : preference
		persistLocalDocument()
	}

	private func persistZoomDocument() {
		guard let data = zoomDocument.encoded() else { return }
		zoomData = data
		guard !isPrivate else { return }
		defaults.set(data, forKey: BrowserSiteZoomDocument.defaultsKey)
	}

	private func persistLocalDocument() {
		guard let data = localDocument.encoded() else { return }
		guard !isPrivate else { return }
		defaults.set(data, forKey: BrowserLocalSitePreferencesDocument.defaultsKey)
	}

	private func reloadZoomFromDefaults() {
		guard !isPrivate else { return }
		let nextData = defaults.data(forKey: BrowserSiteZoomDocument.defaultsKey)
		guard nextData != zoomData else { return }
		if nextData == nil {
			let previous = zoomDocument
			zoomData = nil
			zoomDocument = BrowserSiteZoomDocument()
			isZoomDataReadOnly = false
			for origin in previous.entries.keys.sorted() where previous.entries[origin]?.zoom != nil {
				didUpdateZoom?(origin, nil)
			}
			return
		}
		guard let nextData, let nextDocument = BrowserSiteZoomDocument.decodeSupported(nextData) else {
			zoomData = nextData
			isZoomDataReadOnly = true
			return
		}
		let previous = zoomDocument
		zoomData = nextData
		zoomDocument = nextDocument
		isZoomDataReadOnly = false
		for origin in Set(previous.entries.keys).union(nextDocument.entries.keys).sorted() {
			let oldZoom = previous.entries[origin]?.zoom
			let newZoom = nextDocument.entries[origin]?.zoom
			if oldZoom != newZoom {
				didUpdateZoom?(origin, newZoom)
			}
		}
	}

	private static func canonicalOrigin(_ value: String) -> String? {
		guard let url = URL(string: value) else { return nil }
		return BrowserSiteOrigin.canonical(for: url)
	}

	deinit {
		if let defaultsObserver {
			NotificationCenter.default.removeObserver(defaultsObserver)
		}
	}
}
