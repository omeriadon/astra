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
		let normalBrowsers = openBrowsers.filter { !$0.isPrivate && !$0.isMini }
		guard normalBrowsers.count > 1 else { return true }

		if let owner = tabOwners[id],
		   let ownerBrowser = normalBrowsers.first(where: { $0.windowID == owner }),
		   ownerBrowser.tabs.contains(where: { $0.id == id })
		{
			return owner == browser.windowID
		}
		return normalBrowsers.first { $0.tabs.contains(where: { $0.id == id }) }?.windowID == browser.windowID
			|| !normalBrowsers.contains { $0.tabs.contains(where: { $0.id == id }) }
	}

	/// Resolve ownership for an entire window in one pass. Hot rendering paths
	/// must use this instead of calling ownsTab once per tab: the fallback owner
	/// rule otherwise rescans every window's tab array for every row.
	func ownedTabIDs(in browser: Browser) -> Set<UUID> {
		let browserIDs = Set(browser.tabs.map(\.id))
		guard !browser.isPrivate, !browser.isMini else { return browserIDs }

		let normalBrowsers = openBrowsers.filter { !$0.isPrivate && !$0.isMini }
		guard normalBrowsers.count > 1 else { return browserIDs }

		var idsByWindow: [UUID: Set<UUID>] = [:]
		idsByWindow.reserveCapacity(normalBrowsers.count)
		var firstOwner: [UUID: UUID] = [:]
		firstOwner.reserveCapacity(normalBrowsers.reduce(0) { $0 + $1.tabs.count })

		for candidate in normalBrowsers {
			let ids = Set(candidate.tabs.map(\.id))
			idsByWindow[candidate.windowID] = ids
			for id in ids where firstOwner[id] == nil {
				firstOwner[id] = candidate.windowID
			}
		}

		var result = Set<UUID>()
		result.reserveCapacity(browserIDs.count)
		for id in browserIDs {
			let explicitOwner = tabOwners[id].flatMap { owner in
				idsByWindow[owner]?.contains(id) == true ? owner : nil
			}
			if (explicitOwner ?? firstOwner[id] ?? browser.windowID) == browser.windowID {
				result.insert(id)
			}
		}
		return result
	}

	func claimSelectedTab(in browser: Browser) {
		guard !browser.isPrivate, !browser.isMini,
		      activeBrowserID == browser.windowID else { return }
		browser.prepareSelectedTabDisplayOwner()
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
