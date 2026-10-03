#if os(iOS)
	import SwiftUI
	import UIKit

	@MainActor
	final class BrowserIOSSceneIntegration {
		private weak var browser: Browser?
		private var disconnected = false

		func attach(_ browser: Browser) {
			self.browser = browser
			disconnected = false
			BrowserWindowRegistry.shared.activate(browser)
		}

		@discardableResult
		func openIncomingURL(_ url: URL, in browser: Browser) -> Bool {
			guard let safeURL = BrowserHomepage.validURL(url.absoluteString) else { return false }
			BrowserWindowRegistry.shared.activate(browser)
			let tab = browser.addTab()
			tab.controller?.loadFromAddressBar(safeURL)
			return true
		}

		func scenePhaseDidChange(_ phase: ScenePhase, browser: Browser) {
			switch phase {
				case .active:
					BrowserWindowRegistry.shared.activate(browser)
					Task { @MainActor [weak browser] in
						await browser?.selectedTab?.activeController?.refreshActivity()
					}
				case .inactive, .background:
					browser.flushPersistence()
				@unknown default:
					browser.flushPersistence()
			}
		}

		func handleMemoryWarning(in browser: Browser) {
			for tab in browser.tabs {
				tab.controller?.discardPreviewSnapshot()
				for peek in tab.peeks {
					peek.controller.discardPreviewSnapshot()
				}
				if tab.id != browser.selectedTabID {
					browser.hibernateTab(tab.id, onlyIfBackground: true)
				}
			}
		}

		func disconnect(_ browser: Browser) {
			guard !disconnected else { return }
			disconnected = true
			BrowserWindowRegistry.shared.unregister(browser)
			guard browser.isPrivate else {
				browser.flushPersistence()
				return
			}
			for tab in browser.tabs {
				tab.stopForClose()
			}
			Task { @MainActor [session = browser.session] in
				await session.endPrivateSession()
			}
		}
	}
#endif
