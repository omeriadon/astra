import Foundation
import Observation

@MainActor
@Observable
final class BrowserWindowRegistry {
	static let shared = BrowserWindowRegistry()

	private(set) var activeBrowserID: UUID?
	private var tabOwners: [UUID: UUID] = [:]
	@ObservationIgnored private var browsers: [WeakBrowser] = []
	@ObservationIgnored private var publishTask: Task<Void, Never>?
	@ObservationIgnored private weak var pendingPublishSource: Browser?
	@ObservationIgnored private var pendingRestorationRecords: [UUID: BrowserWindowRecord]?

	var activeBrowser: Browser? {
		browsers.first { $0.browser?.windowID == activeBrowserID }?.browser
			?? browsers.first { $0.browser != nil }?.browser
	}

	var openBrowsers: [Browser] {
		browsers.compactMap(\.browser)
	}

	var recordsForPersistence: [BrowserWindowRecord] {
		let browsers = openBrowsers.filter { !$0.isPrivate && !$0.isMini }
		let live = browsers.map { browser in
			BrowserWindowRecord(
				windowID: browser.windowID,
				tabIDs: browser.tabs.map(\.id),
				selectedTabID: browser.selectedTabID,
				frame: browser.savedWindowFrame
			)
		}
		guard let pendingRestorationRecords else { return live }
		var records = Dictionary(uniqueKeysWithValues: pendingRestorationRecords.values.map { ($0.windowID, $0) })
		for (browser, record) in zip(browsers, live) {
			guard browser.isHydrationFinished || records[browser.windowID] == nil else { continue }
			records[browser.windowID] = record
		}
		return Array(records.values)
	}

	func beginWindowRestoration(_ records: [BrowserWindowRecord]) {
		pendingRestorationRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.windowID, $0) })
	}

	func finishWindowRestoration() {
		pendingRestorationRecords = nil
	}

	func register(_ browser: Browser) {
		browsers.removeAll { $0.browser == nil }
		browsers.append(WeakBrowser(browser))
		BrowserExtensionManager.shared.sync(browser)
	}

	func unregister(_ browser: Browser) {
		if pendingPublishSource === browser {
			publishTask?.cancel()
			publishTask = nil
			pendingPublishSource = nil
			publishNow(from: browser)
		}
		browsers.removeAll { $0.browser == nil || $0.browser === browser }
		tabOwners = tabOwners.filter { $0.value != browser.windowID }
		for remaining in openBrowsers {
			remaining.configureOwnedTabs()
		}
		pendingRestorationRecords?.removeValue(forKey: browser.windowID)
		if activeBrowserID == browser.windowID {
			activeBrowserID = browsers.first?.browser?.windowID
		}
	}

	func activate(_ browser: Browser) {
		// WindowFocusReader and didBecomeKeyNotification both fire for one
		// focus change; every operation below is idempotent, so skip the
		// repeat unless there is a hibernated tab to wake.
		if activeBrowserID == browser.windowID, browser.selectedTab?.isHibernated != true {
			return
		}
		activeBrowserID = browser.windowID
		claimSelectedTab(in: browser)
		BrowserExtensionManager.shared.focus(browser)
		if browser.selectedTab?.isHibernated == true {
			browser.selectTab(browser.selectedTabID)
		}
		if !browser.isPrivate {
			BrowserSync.shared.attach(browser)
		}
	}

	func sharedTab(withID id: UUID, for browser: Browser) -> BrowserTab? {
		guard !browser.isPrivate, !browser.isMini else { return nil }
		return openBrowsers.first {
			$0 !== browser && !$0.isPrivate && !$0.isMini && $0.session === browser.session && $0.tab(withID: id) != nil
		}?.tab(withID: id)
	}

	func ownsTab(_ id: UUID, in browser: Browser) -> Bool {
		guard !browser.isPrivate, !browser.isMini else { return true }
		if let owner = tabOwners[id], openBrowsers.contains(where: { $0.windowID == owner && $0.tab(withID: id) != nil }) {
			return owner == browser.windowID
		}
		return openBrowsers.first { !$0.isPrivate && !$0.isMini && $0.tab(withID: id) != nil }?.windowID == browser.windowID
			|| !openBrowsers.contains { !$0.isPrivate && !$0.isMini && $0.tab(withID: id) != nil }
	}

	func claimSelectedTab(in browser: Browser) {
		guard !browser.isPrivate, !browser.isMini,
		      activeBrowserID == browser.windowID else { return }
		tabOwners[browser.selectedTabID] = browser.windowID
		browser.configureSelectedTab()
		Task { @MainActor [weak self] in
			await Task.yield()
			guard let self else { return }
			for window in openBrowsers {
				BrowserExtensionManager.shared.sync(window)
			}
		}
	}

	func hasActiveDuplicate(of browser: Browser) -> Bool {
		!ownsTab(browser.selectedTabID, in: browser)
	}

	func isOpenInAnotherWindow(_ id: UUID, than browser: Browser) -> Bool {
		guard !browser.isPrivate, !browser.isMini else { return false }
		return openBrowsers.contains {
			$0 !== browser && !$0.isPrivate && !$0.isMini && $0.selectedTabID == id && ownsTab(id, in: $0)
		}
	}

	func isReferenced(_ tab: BrowserTab) -> Bool {
		openBrowsers.contains { $0.tabs.contains { $0 === tab } }
	}

	func publish(from source: Browser) {
		publishSoon(from: source, immediate: true)
	}

	/// Coalesced async fan-out so a persist never blocks the tab-creating
	/// window on N other windows' state reconstruction.
	func publishSoon(from source: Browser, immediate: Bool = false) {
		if immediate {
			publishNow(from: source)
			return
		}
		pendingPublishSource = source
		publishTask?.cancel()
		publishTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(500))
			guard !Task.isCancelled, let self, let source = pendingPublishSource else { return }
			pendingPublishSource = nil
			publishTask = nil
			publishNow(from: source)
		}
	}

	private func publishNow(from source: Browser) {
		browsers.removeAll { $0.browser == nil }
		for entry in browsers {
			guard !source.isPrivate, let browser = entry.browser, !browser.isPrivate, browser !== source else { continue }
			browser.receiveSharedState(from: source)
		}
	}
}

@MainActor
private final class WeakBrowser {
	weak var browser: Browser?

	init(_ browser: Browser) {
		self.browser = browser
	}
}
