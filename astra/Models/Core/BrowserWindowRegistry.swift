import Foundation
import Observation

@MainActor
@Observable
final class BrowserWindowRegistry {
	static let shared = BrowserWindowRegistry()

	private(set) var activeBrowserID: UUID?
	@ObservationIgnored private var browsers: [WeakBrowser] = []
	@ObservationIgnored private var publishTask: Task<Void, Never>?
	@ObservationIgnored private weak var pendingPublishSource: Browser?

	var activeBrowser: Browser? {
		browsers.first { $0.browser?.windowID == activeBrowserID }?.browser
			?? browsers.first { $0.browser != nil }?.browser
	}

	var openBrowsers: [Browser] {
		browsers.compactMap(\.browser)
	}

	func register(_ browser: Browser) {
		browsers.removeAll { $0.browser == nil }
		browsers.append(WeakBrowser(browser))
		BrowserExtensionManager.shared.sync(browser)
	}

	func activate(_ browser: Browser) {
		// WindowFocusReader and didBecomeKeyNotification both fire for one
		// focus change; every operation below is idempotent, so skip the
		// repeat unless there is a hibernated tab to wake.
		if activeBrowserID == browser.windowID, browser.selectedTab?.isHibernated != true {
			return
		}
		activeBrowserID = browser.windowID
		BrowserExtensionManager.shared.focus(browser)
		if browser.selectedTab?.isHibernated == true {
			browser.selectTab(browser.selectedTabID)
		}
		BrowserSync.shared.attach(browser)
	}

	func hasActiveDuplicate(of browser: Browser) -> Bool {
		guard let activeBrowser, activeBrowser !== browser else { return false }
		return activeBrowser.selectedTabID == browser.selectedTabID
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
			publishNow(from: source)
		}
	}

	private func publishNow(from source: Browser) {
		browsers.removeAll { $0.browser == nil }
		for entry in browsers {
			guard let browser = entry.browser, browser !== source else { continue }
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
