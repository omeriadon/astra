import Foundation
import Observation

@MainActor
@Observable
final class BrowserWindowRegistry {
	static let shared = BrowserWindowRegistry()

	private(set) var activeBrowserID: UUID?
	@ObservationIgnored private var browsers: [WeakBrowser] = []
	@ObservationIgnored private var detachedTabs: [UUID: UUID] = [:]

	func prepareDetachedWindow(for tabID: UUID) -> UUID {
		let windowID = UUID()
		detachedTabs[windowID] = tabID
		return windowID
	}

	func takeDetachedTab(for windowID: UUID) -> UUID? {
		detachedTabs.removeValue(forKey: windowID)
	}

	var activeBrowser: Browser? {
		browsers.first { $0.browser?.windowID == activeBrowserID }?.browser
			?? browsers.first { $0.browser != nil }?.browser
	}

	func register(_ browser: Browser) {
		browsers.removeAll { $0.browser == nil }
		browsers.append(WeakBrowser(browser))
	}

	func activate(_ browser: Browser) {
		activeBrowserID = browser.windowID
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
