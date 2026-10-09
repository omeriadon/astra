import Foundation
import Observation
import WebKit
#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif

@MainActor
@Observable
final class BrowserExtensionManager: NSObject, WKWebExtensionControllerDelegate {
	enum Source: String {
		case chrome
		case safari
	}

	static let shared = BrowserExtensionManager()

	let controller = WKWebExtensionController()
	private let bundledNames = ["darkreader-chrome-mv3"]
	private(set) var loadErrors: [String: String] = [:] {
		didSet {
			if loadErrors.contains(where: { oldValue[$0.key] != $0.value }) {
				BrowserDiagnosticEventStore.shared.record(.extensionFailure, code: "extension.load", isPrivate: false)
			}
		}
	}

	private(set) var enabledNames: Set<String> = []
	private(set) var installedNames: [String] = []
	private(set) var safariNames: Set<String> = []
	private(set) var safariAppExtensions: [SafariExtensionCandidate] = []
	private var safariBundlePaths: [String: String] = [:]
	private var unpinnedNames: Set<String> = []
	private(set) var actionsRevision = 0
	private(set) var isInstallingFromStore = false
	private var contexts: [String: WKWebExtensionContext] = [:]
	@ObservationIgnored private var contextPreparationTasks: [String: Task<WKWebExtensionContext, Error>] = [:]
	@ObservationIgnored private var enableIntentRevisions: [String: UInt64] = [:]
	private var cachedDisplayNames: [String: String] = [:]
	private var windows: [UUID: BrowserExtensionWindow] = [:]
	private var tabs: [UUID: [UUID: BrowserExtensionTab]] = [:]
	private var knownTabIDs: [UUID: Set<UUID>] = [:]
	private var selectedTabIDs: [UUID: UUID] = [:]
	private var tabSnapshots: [UUID: [UUID: TabSnapshot]] = [:]
	private var didPrepare = false
	#if os(macOS)
		@ObservationIgnored private var popupWindows: [ObjectIdentifier: BrowserExtensionPopupWindow] = [:]
	#endif

	private struct TabSnapshot: Equatable {
		var url: URL?
		var title: String
		var loading: Bool
		var pinned: Bool
		var zoom: Double
	}

	override private init() {
		if UserDefaults.standard.bool(forKey: "extension.ublock-origin.enabled") {
			UserDefaults.standard.set(true, forKey: "extension.ublock-origin-lite-safari.enabled")
			UserDefaults.standard.removeObject(forKey: "extension.ublock-origin.enabled")
		}
		let savedNames = (UserDefaults.standard.stringArray(forKey: "installedExtensions") ?? []).filter {
			UUID(uuidString: $0) != nil
		}
		installedNames = savedNames
		safariBundlePaths = UserDefaults.standard.dictionary(forKey: "safariExtensionBundles") as? [String: String] ?? [:]
		unpinnedNames = Set(UserDefaults.standard.stringArray(forKey: "unpinnedExtensions") ?? [])
		safariNames = Set(UserDefaults.standard.stringArray(forKey: "safariExtensions") ?? [])
		cachedDisplayNames = UserDefaults.standard.dictionary(forKey: "extensionDisplayNames") as? [String: String] ?? [:]
		enabledNames = Set((["darkreader-chrome-mv3"] + savedNames).filter {
			UserDefaults.standard.bool(forKey: "extension.\($0).enabled")
		})
		super.init()
		#if DEBUG
			ChromeExtensionPackage.checkParsing()
		#endif
		controller.delegate = self
		NotificationCenter.default.addObserver(self, selector: #selector(extensionErrorsChanged(_:)), name: WKWebExtensionContext.errorsDidUpdateNotification, object: nil)
	}

	@objc private func extensionErrorsChanged(_ notification: Notification) {
		BrowserLog.debug(.extensions, "extension.errors-updated")
		guard let context = notification.object as? WKWebExtensionContext,
		      let name = contexts.first(where: { $0.value === context })?.key else { return }
		if context.errors.isEmpty {
			loadErrors.removeValue(forKey: name)
		} else {
			loadErrors[name] = context.errors.map(\.localizedDescription).joined(separator: "\n")
		}
	}

	func extensionWindow(for browser: Browser) -> BrowserExtensionWindow {
		if let existing = windows[browser.windowID] {
			return existing
		}
		let window = BrowserExtensionWindow(browser: browser)
		windows[browser.windowID] = window
		controller.didOpenWindow(window)
		return window
	}

	func extensionTab(for id: UUID, in browser: Browser) -> BrowserExtensionTab? {
		guard !browser.isPrivate, BrowserWindowRegistry.shared.ownsTab(id, in: browser),
		      browser.tab(withID: id)?.internalPage == nil else { return nil }
		if let existing = tabs[browser.windowID]?[id] {
			return existing
		}
		let bridge = BrowserExtensionTab(id: id, browser: browser)
		tabs[browser.windowID, default: [:]][id] = bridge
		return bridge
	}

	func sync(_ browser: Browser) {
		BrowserLog.trace(.extensions, "extensions.sync-window", metadata: ["window": BrowserLog.id(browser.windowID), "tabs": String(browser.tabs.count)])
		guard !browser.isPrivate else { return }
		_ = extensionWindow(for: browser)
		let ownedIDs = BrowserWindowRegistry.shared.ownedTabIDs(in: browser)
		let ownedTabs = browser.tabs.filter {
			$0.internalPage == nil && ownedIDs.contains($0.id)
		}
		let ids = Set(ownedTabs.map(\.id))
		var pinnedIDs = Set(browser.workspace.favouriteTabIDs)
		for space in browser.workspace.spaces {
			pinnedIDs.formUnion(space.pinnedTabIDs)
		}
		let previous = knownTabIDs[browser.windowID] ?? []
		for id in ids.subtracting(previous) {
			if let tab = extensionTab(for: id, in: browser) {
				controller.didOpenTab(tab)
			}
		}
		for id in previous.subtracting(ids) {
			if let tab = tabs[browser.windowID]?[id] {
				controller.didCloseTab(tab, windowIsClosing: false)
				tabs[browser.windowID]?.removeValue(forKey: id)
			}
			tabSnapshots[browser.windowID]?.removeValue(forKey: id)
		}
		knownTabIDs[browser.windowID] = ids
		for tab in ownedTabs {
			let snapshot = TabSnapshot(
				url: tab.currentURL,
				title: tab.title,
				loading: tab.controller?.isLoading == true,
				pinned: pinnedIDs.contains(tab.id),
				zoom: tab.controller?.pageZoom ?? 1
			)
			if let previousSnapshot = tabSnapshots[browser.windowID]?[tab.id],
			   let bridge = tabs[browser.windowID]?[tab.id]
			{
				var changed: WKWebExtension.TabChangedProperties = []
				if previousSnapshot.title != snapshot.title {
					changed.insert(.title)
				}
				if previousSnapshot.url != snapshot.url {
					changed.insert(.URL)
				}
				if previousSnapshot.loading != snapshot.loading {
					changed.insert(.loading)
				}
				if previousSnapshot.pinned != snapshot.pinned {
					changed.insert(.pinned)
				}
				if previousSnapshot.zoom != snapshot.zoom {
					changed.insert(.zoomFactor)
				}
				if !changed.isEmpty {
					controller.didChangeTabProperties(changed, for: bridge)
				}
			}
			tabSnapshots[browser.windowID, default: [:]][tab.id] = snapshot
		}
		selectionDidChange(browser, ownedIDs: ids)
	}

	/// WebKit loading KVO changes a single tab property. Rebuilding every
	/// extension-tab snapshot on each navigation start/finish made foreground
	/// and background page loads walk the whole browser tab collection.
	func loadingDidChange(for id: UUID, in browser: Browser) {
		tabPropertiesDidChange(for: id, in: browser)
	}

	/// Normal tab metadata and WebKit loading events affect one WebExtension
	/// bridge, not every bridge in a window. Structural membership changes
	/// still use sync(_:) from Browser's explicit tab mutation paths.
	func tabPropertiesDidChange(for id: UUID, in browser: Browser, forceWebViewRefresh: Bool = false) {
		guard !browser.isPrivate,
		      BrowserWindowRegistry.shared.ownsTab(id, in: browser),
		      let tab = browser.tab(withID: id),
		      tab.internalPage == nil else { return }
		guard let previous = tabSnapshots[browser.windowID]?[id],
		      let bridge = tabs[browser.windowID]?[id] else {
			sync(browser)
			return
		}
		let next = TabSnapshot(
			url: tab.currentURL,
			title: tab.title,
			loading: tab.controller?.isLoading == true,
			pinned: previous.pinned,
			zoom: tab.controller?.pageZoom ?? 1
		)
		var changed: WKWebExtension.TabChangedProperties = forceWebViewRefresh ? [.URL, .loading] : []
		if previous.title != next.title { changed.insert(.title) }
		if previous.url != next.url { changed.insert(.URL) }
		if previous.loading != next.loading { changed.insert(.loading) }
		if previous.zoom != next.zoom { changed.insert(.zoomFactor) }
		guard !changed.isEmpty else { return }
		tabSnapshots[browser.windowID, default: [:]][id] = next
		controller.didChangeTabProperties(changed, for: bridge)
	}

	/// Selection changes do not require rebuilding every extension-tab snapshot.
	/// This is the hot path for ordinary tab clicks.
	func selectionDidChange(_ browser: Browser) {
		guard !browser.isPrivate else { return }
		let ownedIDs = BrowserWindowRegistry.shared.ownedTabIDs(in: browser)
		selectionDidChange(browser, ownedIDs: ownedIDs)
	}

	private func selectionDidChange(_ browser: Browser, ownedIDs: Set<UUID>) {
		guard let selected = browser.selectedTab,
		      selected.internalPage == nil,
		      ownedIDs.contains(selected.id),
		      selectedTabIDs[browser.windowID] != selected.id
		else { return }

		let prior = selectedTabIDs[browser.windowID].flatMap { tabs[browser.windowID]?[$0] }
		let current: BrowserExtensionTab
		if let existing = tabs[browser.windowID]?[selected.id] {
			current = existing
		} else {
			guard let created = extensionTab(for: selected.id, in: browser) else { return }
			current = created
			knownTabIDs[browser.windowID, default: []].insert(selected.id)
			controller.didOpenTab(created)
		}
		controller.didActivateTab(current, previousActiveTab: prior)
		selectedTabIDs[browser.windowID] = selected.id
	}

	func closeWindow(for browser: Browser) {
		BrowserLog.debug(.extensions, "extensions.close-window", metadata: ["window": BrowserLog.id(browser.windowID)])
		guard let window = windows.removeValue(forKey: browser.windowID) else { return }
		for tab in tabs[browser.windowID]?.values ?? [UUID: BrowserExtensionTab]().values {
			controller.didCloseTab(tab, windowIsClosing: true)
		}
		controller.didCloseWindow(window)
		tabs.removeValue(forKey: browser.windowID)
		knownTabIDs.removeValue(forKey: browser.windowID)
		selectedTabIDs.removeValue(forKey: browser.windowID)
		tabSnapshots.removeValue(forKey: browser.windowID)
	}

	func focus(_ browser: Browser) {
		guard !browser.isPrivate else { return }
		controller.didFocusWindow(extensionWindow(for: browser))
	}

	func webViewDidChange(for id: UUID, in browser: Browser) {
		guard !browser.isPrivate else { return }
		// A WKWebView replacement does not change the identities of every tab.
		// A registered bridge must refresh URL/loading even when their values
		// are unchanged, because its backing WebKit view has changed.
		guard knownTabIDs[browser.windowID]?.contains(id) == true,
		      tabs[browser.windowID]?[id] != nil,
		      BrowserWindowRegistry.shared.ownsTab(id, in: browser) else {
			// Newly created, transferred or closed tabs still need structural
			// open/close notifications with correct window ownership.
			sync(browser)
			return
		}
		tabPropertiesDidChange(for: id, in: browser, forceWebViewRefresh: true)
	}

	func loadedNames() -> [String] {
		availableNames.filter { contexts[$0]?.isLoaded == true }
	}

	var availableNames: [String] {
		bundledNames + installedNames
	}

	func isPinned(_ name: String) -> Bool {
		!unpinnedNames.contains(name)
	}

	func setPinned(_ pinned: Bool, for name: String) {
		if pinned {
			unpinnedNames.remove(name)
		} else {
			unpinnedNames.insert(name)
		}
		UserDefaults.standard.set(Array(unpinnedNames), forKey: "unpinnedExtensions")
		actionsRevision += 1
	}

	func allowsAllSites(_ name: String) -> Bool {
		_ = actionsRevision
		return UserDefaults.standard.object(forKey: "extension.\(name).allSites") as? Bool ?? true
	}

	func setAllowsAllSites(_ allowed: Bool, for name: String) {
		UserDefaults.standard.set(allowed, forKey: "extension.\(name).allSites")
		guard let context = contexts[name] else { return }
		context.grantedPermissionMatchPatterns = [:]
		if allowed {
			for pattern in context.webExtension.requestedPermissionMatchPatterns {
				context.setPermissionStatus(.grantedExplicitly, for: pattern)
			}
		}
		applyFileAccess(for: name, context: context)
		actionsRevision += 1
	}

	func allowsFileAccess(_ name: String) -> Bool {
		_ = actionsRevision
		return UserDefaults.standard.bool(forKey: "extension.\(name).fileAccess")
	}

	func setAllowsFileAccess(_ allowed: Bool, for name: String) {
		UserDefaults.standard.set(allowed, forKey: "extension.\(name).fileAccess")
		if let context = contexts[name] {
			applyFileAccess(for: name, context: context)
		}
		actionsRevision += 1
	}

	private func applyFileAccess(for name: String, context: WKWebExtensionContext) {
		guard let pattern = try? WKWebExtension.MatchPattern(string: "file:///*") else { return }
		context.setPermissionStatus(allowsFileAccess(name) ? .grantedExplicitly : .deniedExplicitly, for: pattern)
	}

	func version(for name: String) -> String {
		contexts[name]?.webExtension.version ?? "Unknown"
	}

	func description(for name: String) -> String {
		contexts[name]?.webExtension.displayDescription ?? ""
	}

	func optionsURL(for name: String) -> URL? {
		contexts[name]?.optionsPageURL
	}

	func sourcePath(for name: String) -> String {
		safariBundlePaths[name] ?? archiveURL(for: name)?.path ?? ""
	}

	func errors(for name: String) -> [String] {
		let errors = contexts[name]?.errors.map(\.localizedDescription) ?? []
		return Array(Set(errors + (loadErrors[name].map { [$0] } ?? []))).sorted()
	}

	func reloadExtension(_ name: String) {
		guard isEnabled(name) else { return }
		setEnabled(false, for: name)
		setEnabled(true, for: name)
	}

	func refreshSafariExtensions() async {
		let discovered = await Task.detached(priority: .utility) { SafariExtensionCandidate.discover() }.value
		safariAppExtensions = discovered.filter { !safariBundlePaths.values.contains($0.bundleURL.path) }
	}

	func installSafariExtension(_ candidate: SafariExtensionCandidate) async {
		do {
			guard let bundle = Bundle(url: candidate.bundleURL) else { return }
			let extensionObject = try await WKWebExtension(appExtensionBundle: bundle)
			let name = UUID().uuidString
			let context = WKWebExtensionContext(for: extensionObject)
			context.uniqueIdentifier = name
			contexts[name] = context
			cacheDisplayName(extensionObject.displayName, for: name)
			installedNames.append(name)
			safariNames.insert(name)
			safariBundlePaths[name] = candidate.bundleURL.path
			UserDefaults.standard.set(installedNames, forKey: "installedExtensions")
			UserDefaults.standard.set(Array(safariNames), forKey: "safariExtensions")
			UserDefaults.standard.set(safariBundlePaths, forKey: "safariExtensionBundles")
			await refreshSafariExtensions()
			promptForAccess(to: permissionSummary(for: name), from: context) { [weak self] allowed in
				if allowed {
					self?.setEnabled(true, for: name)
				}
			}
		} catch {
			ToastManager.shared.show(symbol: "exclamationmark.triangle", message: error.localizedDescription)
		}
	}

	func source(for name: String) -> Source {
		name == "ublock-origin-lite-safari" || safariNames.contains(name) ? .safari : .chrome
	}

	func title(for name: String) -> String {
		if let title = contexts[name]?.webExtension.displayName ?? cachedDisplayNames[name] {
			return title
		}
		switch name {
			case "darkreader-chrome-mv3": return "Dark Reader"
			case "ublock-origin-lite-safari": return "uBlock Origin Lite"
			default: return name
		}
	}

	func permissionSummary(for name: String) -> String {
		guard let extensionObject = contexts[name]?.webExtension else { return "" }
		let permissions = extensionObject.requestedPermissions.map { Self.permissionTitle($0) }.sorted()
		let websites = extensionObject.requestedPermissionMatchPatterns.map {
			$0.matchesAllHosts ? "Read and change data on all websites" : "Read and change data on \($0.host ?? "*")"
		}.sorted()
		return Set(permissions + websites).sorted().map { "• \($0)" }.joined(separator: "\n")
	}

	private static func permissionTitle(_ permission: WKWebExtension.Permission) -> String {
		let titles = [
			"activeTab": "Access the current tab when you use the extension",
			"tabs": "Read information about your open tabs",
			"contextMenus": "Add items to right-click menus",
			"menus": "Add items to menus",
			"scripting": "Run scripts on permitted websites",
			"storage": "Save extension settings",
			"unlimitedStorage": "Store extension data without a size limit",
			"alarms": "Schedule background tasks",
			"nativeMessaging": "Communicate with its companion app",
			"webRequest": "Observe website network requests",
			"declarativeNetRequest": "Block or modify network requests",
			"declarativeNetRequestWithHostAccess": "Block or modify requests on permitted websites",
			"fontSettings": "Read and change font settings",
			"clipboardWrite": "Write to the clipboard",
			"cookies": "Read and change website cookies",
			"webNavigation": "Read website navigation activity",
			"webRequestBlocking": "Block or modify website network requests",
			"privacy": "Change browser privacy settings",
			"downloads": "Manage downloads",
			"notifications": "Show notifications",
			"offscreen": "Run background documents",
			"userScripts": "Run user scripts on permitted websites",
		]
		return titles[permission.rawValue] ?? permission.rawValue
	}

	func action(for name: String, in browser: Browser) -> WKWebExtension.Action? {
		guard !browser.isPrivate else { return nil }
		guard let context = contexts[name], context.isLoaded else { return nil }
		return context.action(for: extensionTab(for: browser.selectedTabID, in: browser))
	}

	func performAction(_ name: String, in browser: Browser) {
		guard !browser.isPrivate else { return }
		guard let context = contexts[name], context.isLoaded else { return }
		if !allowsAllSites(name), let url = browser.selectedTab?.currentURL,
		   url.scheme == "https" || url.scheme == "http"
		{
			context.setPermissionStatus(.grantedExplicitly, for: url, expirationDate: Date.now.addingTimeInterval(300))
		}
		#if os(macOS)
			if let popup = popupWindows[ObjectIdentifier(context)] {
				popup.window?.makeKeyAndOrderFront(nil)
				return
			}
		#endif
		let tab = extensionTab(for: browser.selectedTabID, in: browser)
		Task { [weak self] in
			do {
				if context.webExtension.hasBackgroundContent {
					try await context.loadBackgroundContent()
				}
				context.performAction(for: tab)
			} catch {
				self?.loadErrors[name] = error.localizedDescription
				ToastManager.shared.show(symbol: "exclamationmark.triangle", message: error.localizedDescription)
			}
		}
	}

	func prepare() async {
		guard !didPrepare else {
			BrowserLog.trace(.extensions, "extensions.prepare.skip", metadata: ["reason": "already-prepared"])
			return
		}
		let logStarted = BrowserLog.clock()
		BrowserLog.info(.extensions, "extensions.prepare.begin", metadata: ["available": String(availableNames.count), "enabled": String(enabledNames.count)])
		didPrepare = true

		// Only enabled extensions belong on the launch path. Disabled packages are
		// metadata-only until the user opens extension settings or the staggered
		// idle preparation below reaches them.
		for (index, name) in availableNames.filter({ enabledNames.contains($0) }).enumerated() {
			if index > 0 {
				await Task.yield()
			}
			BrowserLog.debug(.extensions, "extension.prepare-item", metadata: ["name": BrowserLog.value(name), "enabled": "true"])
			do {
				_ = try await prepareContext(for: name)
				// The user may have disabled the extension during an await.
				guard enabledNames.contains(name) else { continue }
				try enable(name)
			} catch {
				loadErrors[name] = error.localizedDescription
			}
		}

		BrowserLog.duration(.extensions, "extensions.prepare.end", since: logStarted, warnAboveMilliseconds: 500, metadata: ["contexts": String(contexts.count), "errors": String(loadErrors.count)])
		// Disabled extensions are prepared only when the user opens extension
		// settings or enables one. Background preparation here was creating
		// WKWebExtension contexts and parsing packages shortly after launch.
	}

	func prepareAllContexts() async {
		await prepare()
		await prepareMissingContexts()
	}

	private func prepareMissingContexts() async {
		for name in availableNames where contexts[name] == nil {
			guard !Task.isCancelled else { return }
			do {
				_ = try await prepareContext(for: name)
			} catch {
				loadErrors[name] = error.localizedDescription
			}
		}
	}

	@discardableResult
	private func prepareContext(for name: String) async throws -> WKWebExtensionContext {
		if let existing = contexts[name] { return existing }
		if let preparing = contextPreparationTasks[name] {
			return try await preparing.value
		}
		// A settings click can overlap the launch-time extension preparation.
		// Share one in-flight WebKit parse rather than creating duplicate contexts.
		let preparing = Task { @MainActor in
			try await createContext(for: name)
		}
		contextPreparationTasks[name] = preparing
		defer { contextPreparationTasks[name] = nil }
		return try await preparing.value
	}

	private func createContext(for name: String) async throws -> WKWebExtensionContext {
		let started = BrowserLog.clock()
		let webExtension: WKWebExtension
		if let path = safariBundlePaths[name], let bundle = Bundle(path: path) {
			webExtension = try await WKWebExtension(appExtensionBundle: bundle)
		} else if let url = archiveURL(for: name) {
			webExtension = try await WKWebExtension(resourceBaseURL: url)
		} else {
			throw NSError(
				domain: "astra.extensions",
				code: 12,
				userInfo: [NSLocalizedDescriptionKey: "Extension package is missing."]
			)
		}
		try Task.checkCancellation()
		// It may have been uninstalled while WebKit parsed the archive.
		guard bundledNames.contains(name) || installedNames.contains(name) || safariBundlePaths[name] != nil
		else { throw CancellationError() }
		let context = WKWebExtensionContext(for: webExtension)
		context.uniqueIdentifier = name
		contexts[name] = context
		cacheDisplayName(webExtension.displayName, for: name)
		BrowserLog.duration(
			.extensions,
			"extension.prepare-item.end",
			since: started,
			warnAboveMilliseconds: 150,
			metadata: ["name": BrowserLog.value(name), "enabled": String(enabledNames.contains(name))]
		)
		return context
	}

	private func cacheDisplayName(_ value: String?, for name: String) {
		guard let value, !value.isEmpty, cachedDisplayNames[name] != value else { return }
		cachedDisplayNames[name] = value
		UserDefaults.standard.set(cachedDisplayNames, forKey: "extensionDisplayNames")
	}

	func installArchive(from archive: URL, source: Source) async throws -> String {
		BrowserLog.info(.extensions, "extension.install-archive", metadata: ["source": source.rawValue, "archive": BrowserLog.path(archive)])
		let access = archive.startAccessingSecurityScopedResource()
		defer {
			if access {
				archive.stopAccessingSecurityScopedResource()
			}
		}
		guard archive.pathExtension.lowercased() == "zip",
		      let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize,
		      size <= 50_000_000
		else {
			throw NSError(domain: "astra.extensions", code: 6)
		}
		let checked = try await WKWebExtension(resourceBaseURL: archive)
		guard checked.manifestVersion == 2 || checked.manifestVersion == 3 else {
			throw NSError(domain: "astra.extensions", code: 4)
		}
		let name = UUID().uuidString
		guard let destination = archiveURL(for: name, creatingDirectory: true) else {
			throw NSError(domain: "astra.extensions", code: 5)
		}
		try FileManager.default.copyItem(at: archive, to: destination)
		do {
			let extensionObject = try await WKWebExtension(resourceBaseURL: destination)
			let context = WKWebExtensionContext(for: extensionObject)
			context.uniqueIdentifier = name
			contexts[name] = context
			cacheDisplayName(extensionObject.displayName, for: name)
			installedNames.append(name)
			UserDefaults.standard.set(installedNames, forKey: "installedExtensions")
			if source == .safari {
				safariNames.insert(name)
				UserDefaults.standard.set(Array(safariNames), forKey: "safariExtensions")
			}
			return name
		} catch {
			try? FileManager.default.removeItem(at: destination)
			throw error
		}
	}

	func installFromChromeStore(_ listing: URL) async {
		BrowserLog.info(.extensions, "extension.install-store", metadata: ["listing": BrowserLog.url(listing)])
		guard !isInstallingFromStore, let id = ChromeExtensionPackage.extensionID(from: listing) else { return }
		isInstallingFromStore = true
		defer { isInstallingFromStore = false }
		do {
			var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
			components.queryItems = [
				URLQueryItem(name: "response", value: "redirect"),
				URLQueryItem(name: "prodversion", value: "153.0.0.0"),
				URLQueryItem(name: "acceptformat", value: "crx3"),
				URLQueryItem(name: "x", value: "id=\(id)&uc"),
			]
			let (download, response) = try await URLSession.shared.download(from: components.url!)
			defer { try? FileManager.default.removeItem(at: download) }
			guard let response = response as? HTTPURLResponse, response.statusCode == 200,
			      response.url?.scheme == "https", let host = response.url?.host,
			      host == "google.com" || host.hasSuffix(".google.com")
			      || host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com"),
			      let size = try download.resourceValues(forKeys: [.fileSizeKey]).fileSize,
			      size <= 50_000_000 else { throw ChromeExtensionPackage.PackageError.invalid }
			let archive = try ChromeExtensionPackage.archive(from: Data(contentsOf: download))
			let temporaryZIP = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
			defer { try? FileManager.default.removeItem(at: temporaryZIP) }
			try archive.write(to: temporaryZIP, options: .atomic)
			let name = try await installArchive(from: temporaryZIP, source: .chrome)
			if let context = contexts[name] {
				promptForAccess(to: permissionSummary(for: name), from: context) { [weak self] allowed in
					if allowed {
						self?.setEnabled(true, for: name)
					}
				}
			}
		} catch {
			ToastManager.shared.show(symbol: "exclamationmark.triangle", message: error.localizedDescription)
		}
	}

	func removeInstalled(_ name: String) {
		BrowserLog.info(.extensions, "extension.remove", metadata: ["name": BrowserLog.value(name)])
		guard installedNames.contains(name) else { return }
		let url = archiveURL(for: name)
		setEnabled(false, for: name)
		guard contexts[name]?.isLoaded != true else { return }
		contextPreparationTasks[name]?.cancel()
		contextPreparationTasks[name] = nil
		contexts.removeValue(forKey: name)
		cachedDisplayNames.removeValue(forKey: name)
		UserDefaults.standard.set(cachedDisplayNames, forKey: "extensionDisplayNames")
		installedNames.removeAll { $0 == name }
		safariBundlePaths.removeValue(forKey: name)
		UserDefaults.standard.set(safariBundlePaths, forKey: "safariExtensionBundles")
		UserDefaults.standard.set(installedNames, forKey: "installedExtensions")
		safariNames.remove(name)
		UserDefaults.standard.set(Array(safariNames), forKey: "safariExtensions")
		UserDefaults.standard.removeObject(forKey: "extension.\(name).enabled")
		if let url {
			try? FileManager.default.removeItem(at: url)
		}
	}

	private func archiveURL(for name: String, creatingDirectory: Bool = false) -> URL? {
		if safariBundlePaths[name] != nil {
			return nil
		}
		if bundledNames.contains(name) {
			return Bundle.main.url(forResource: name, withExtension: "zip")
		}
		guard UUID(uuidString: name) != nil,
		      installedNames.contains(name) || creatingDirectory,
		      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
		let directory = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "astra", isDirectory: true)
			.appendingPathComponent("Extensions", isDirectory: true)
		if creatingDirectory {
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}
		return directory.appendingPathComponent(name).appendingPathExtension("zip")
	}

	func isEnabled(_ name: String) -> Bool {
		enabledNames.contains(name)
	}

	func isLoaded(_ name: String) -> Bool {
		contexts[name]?.isLoaded == true
	}

	func approveRequestedPermissions(for name: String) {
		UserDefaults.standard.set(permissionSummary(for: name), forKey: "extension.\(name).approvedPermissions")
	}

	func setEnabled(_ enabled: Bool, for name: String) {
		BrowserLog.info(.extensions, "extension.set-enabled", metadata: ["name": BrowserLog.value(name), "enabled": String(enabled)])
		let revision = (enableIntentRevisions[name] ?? 0) &+ 1
		enableIntentRevisions[name] = revision
		if enabled, contexts[name] == nil {
			Task { @MainActor [weak self] in
				guard let self else { return }
				do {
					_ = try await prepareContext(for: name)
					// Do not re-enable after a later explicit disable or removal.
					guard enableIntentRevisions[name] == revision,
					      bundledNames.contains(name) || installedNames.contains(name) else { return }
					setEnabled(true, for: name)
				} catch {
					guard enableIntentRevisions[name] == revision else { return }
					loadErrors[name] = error.localizedDescription
				}
			}
			return
		}
		if enabled, !bundledNames.contains(name),
		   UserDefaults.standard.string(forKey: "extension.\(name).approvedPermissions") != permissionSummary(for: name),
		   let context = contexts[name]
		{
			promptForAccess(to: permissionSummary(for: name), from: context) { [weak self] allowed in
				if allowed {
					self?.setEnabled(true, for: name)
				}
			}
			return
		}
		UserDefaults.standard.set(enabled, forKey: "extension.\(name).enabled")
		if enabled {
			enabledNames.insert(name)
		} else {
			enabledNames.remove(name)
		}
		guard let context = contexts[name] else { return }
		do {
			loadErrors.removeValue(forKey: name)
			if enabled {
				try enable(name)
			} else if context.isLoaded {
				#if os(macOS)
					popupWindows[ObjectIdentifier(context)]?.close()
				#endif
				try controller.unload(context)
			}
		} catch {
			loadErrors[name] = error.localizedDescription
		}
	}

	private func enable(_ name: String) throws {
		BrowserLog.debug(.extensions, "extension.enable", metadata: ["name": BrowserLog.value(name)])
		guard let context = contexts[name], !context.isLoaded else { return }
		guard bundledNames.contains(name)
			|| UserDefaults.standard.string(forKey: "extension.\(name).approvedPermissions") == permissionSummary(for: name)
		else {
			throw NSError(domain: "astra.extensions", code: 10, userInfo: [NSLocalizedDescriptionKey: "Review this extension's permissions before enabling it."])
		}
		context.unsupportedAPIs = ["browser.runtime.connectNative", "browser.runtime.sendNativeMessage"]
		for permission in context.webExtension.requestedPermissions {
			context.setPermissionStatus(.grantedExplicitly, for: permission)
		}
		if allowsAllSites(name) {
			for pattern in context.webExtension.requestedPermissionMatchPatterns {
				context.setPermissionStatus(.grantedExplicitly, for: pattern)
			}
		}
		applyFileAccess(for: name, context: context)
		try controller.load(context)
		if let error = (context.webExtension.errors + context.errors).first {
			loadErrors[name] = error.localizedDescription
		}
	}

	func webExtensionController(_: WKWebExtensionController, openWindowsFor _: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
		let browsers = BrowserWindowRegistry.shared.openBrowsers.filter { !$0.isPrivate }
		let focused = BrowserWindowRegistry.shared.activeBrowserID
		return browsers.sorted { $0.windowID == focused && $1.windowID != focused }.map(extensionWindow(for:))
	}

	func webExtensionController(_: WKWebExtensionController, focusedWindowFor _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
		guard let browser = BrowserWindowRegistry.shared.activeBrowser, !browser.isPrivate else { return nil }
		return extensionWindow(for: browser)
	}

	func webExtensionController(
		_: WKWebExtensionController,
		openNewTabUsing configuration: WKWebExtension.TabConfiguration,
		for _: WKWebExtensionContext,
		completionHandler: ((any WKWebExtensionTab)?, Error?) -> Void
	) {
		guard let browser = (configuration.window as? BrowserExtensionWindow)?.browser
			?? BrowserWindowRegistry.shared.activeBrowser,
			!browser.isPrivate
		else {
			completionHandler(nil, NSError(domain: "astra.extensions", code: 2))
			return
		}
		let tab: BrowserTab = if let url = configuration.url {
			browser.openHistoryURL(url, inBackground: !configuration.shouldBeActive)
		} else {
			browser.addTab(inBackground: !configuration.shouldBeActive)
		}
		if configuration.shouldBePinned {
			browser.moveTab(tab.id, to: .pinned)
		}
		completionHandler(extensionTab(for: tab.id, in: browser), nil)
	}

	func webExtensionController(
		_: WKWebExtensionController,
		openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
		for _: WKWebExtensionContext,
		completionHandler: ((any WKWebExtensionWindow)?, Error?) -> Void
	) {
		#if os(macOS)
			guard !configuration.shouldBePrivate,
			      configuration.tabs.isEmpty,
			      let app = NSApp.delegate as? AppDelegate
			else {
				completionHandler(nil, NSError(domain: "astra.extensions", code: 3))
				return
			}
			let window = app.openBrowserWindow()
			if let firstURL = configuration.tabURLs.first {
				window.browser.selectedTab?.controller?.load(firstURL)
				for url in configuration.tabURLs.dropFirst() {
					window.browser.openHistoryURL(url, inBackground: true)
				}
			}
			completionHandler(extensionWindow(for: window.browser), nil)
		#else
			completionHandler(nil, NSError(domain: "astra.extensions", code: 3))
		#endif
	}

	func webExtensionController(
		_: WKWebExtensionController,
		promptForPermissions permissions: Set<WKWebExtension.Permission>,
		in _: (any WKWebExtensionTab)?,
		for context: WKWebExtensionContext,
		completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
	) {
		promptForAccess(to: permissions.map { "• \(Self.permissionTitle($0))" }.sorted().joined(separator: "\n"), from: context) {
			completionHandler($0 ? permissions : [], nil)
		}
	}

	func webExtensionController(
		_: WKWebExtensionController,
		promptForPermissionToAccess urls: Set<URL>,
		in _: (any WKWebExtensionTab)?,
		for context: WKWebExtensionContext,
		completionHandler: @escaping (Set<URL>, Date?) -> Void
	) {
		promptForAccess(to: urls.map(\.absoluteString).sorted().joined(separator: "\n"), from: context) {
			completionHandler($0 ? urls : [], nil)
		}
	}

	func webExtensionController(
		_: WKWebExtensionController,
		promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>,
		in _: (any WKWebExtensionTab)?,
		for context: WKWebExtensionContext,
		completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
	) {
		promptForAccess(to: patterns.map(\.string).sorted().joined(separator: "\n"), from: context) {
			completionHandler($0 ? patterns : [], nil)
		}
	}

	private func promptForAccess(to details: String, from context: WKWebExtensionContext, completion: @escaping (Bool) -> Void) {
		let title = context.webExtension.displayName ?? "Extension"
		#if os(macOS)
			guard let window = NSApp.keyWindow else {
				completion(false)
				return
			}
			let alert = NSAlert()
			alert.messageText = "Allow \(title) access?"
			alert.informativeText = details
			alert.addButton(withTitle: "Allow")
			alert.addButton(withTitle: "Deny")
			Task { @MainActor in
				let response = await BrowserWebsiteUI.present(alert, in: window)
				let allowed = response == .alertFirstButtonReturn
				if allowed,
				   let name = contexts.first(where: { $0.value === context })?.key,
				   details == permissionSummary(for: name)
				{
					UserDefaults.standard.set(details, forKey: "extension.\(name).approvedPermissions")
				}
				completion(allowed)
			}
		#elseif os(iOS)
			guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow),
			      let presenter = window.rootViewController
			else {
				completion(false)
				return
			}
			let alert = UIAlertController(title: "Allow \(title) access?", message: details, preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "Deny", style: .cancel) { _ in completion(false) })
			alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in completion(true) })
			presenter.present(alert, animated: true)
		#endif
	}

	func webExtensionController(
		_: WKWebExtensionController,
		presentActionPopup action: WKWebExtension.Action,
		for context: WKWebExtensionContext,
		completionHandler: (Error?) -> Void
	) {
		#if os(macOS)
			guard let popup = BrowserExtensionPopupWindow(action: action, title: context.webExtension.displayName ?? action.label) else {
				completionHandler(NSError(domain: "astra.extensions", code: 1))
				return
			}
			let identifier = ObjectIdentifier(context)
			popup.onClose = { [weak self] in self?.popupWindows.removeValue(forKey: identifier) }
			popupWindows[identifier] = popup
			popup.window?.makeKeyAndOrderFront(nil)
			completionHandler(nil)
		#elseif os(iOS)
			guard let popup = action.popupViewController,
			      let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow),
			      let presenter = window.rootViewController
			else {
				completionHandler(NSError(domain: "astra.extensions", code: 1))
				return
			}
			presenter.present(popup, animated: true)
			completionHandler(nil)
		#endif
	}

	func webExtensionController(_: WKWebExtensionController, didUpdate _: WKWebExtension.Action, forExtensionContext _: WKWebExtensionContext) {
		actionsRevision += 1
	}
}
