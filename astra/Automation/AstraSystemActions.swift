#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
	import AppIntents
	import AppKit
	import AstraAutomationCore
	import CoreSpotlight
	import Foundation
	import UniformTypeIdentifiers

	/// The only entry point used by App Intents, Services, and Spotlight navigation.
	/// Never infer a browser from a SwiftUI view or mutate a restoring session.
	@MainActor
	enum AstraSystemActions {
		enum Failure: LocalizedError {
			case unavailable
			case invalidURL
			case missingItem
			case unsupportedAction

			var errorDescription: String? {
				switch self {
					case .unavailable: "Astra is still opening. Try again once its windows are ready."
					case .invalidURL: "Only HTTP and HTTPS web addresses are supported."
					case .missingItem: "This item no longer exists in Astra."
					case .unsupportedAction: "This action is unavailable for the selected page."
				}
			}
		}

		private static var delegate: AppDelegate? {
			NSApp.delegate as? AppDelegate
		}

		static func normalBrowsers() -> [Browser] {
			BrowserWindowRegistry.shared.openBrowsers.filter {
				!$0.isPrivate && !$0.isMini && $0.isHydrationFinished
			}
		}

		/// Read-only entity queries must not create browser windows as a side effect.
		static func existingBrowser() async throws -> Browser {
			guard let delegate, await delegate.awaitSystemActionsReady() else {
				throw Failure.unavailable
			}
			if let preferred = BrowserWindowRegistry.shared.activeBrowser,
			   !preferred.isPrivate, !preferred.isMini, preferred.isHydrationFinished
			{
				return preferred
			}
			guard let existing = normalBrowsers().first else {
				throw Failure.unavailable
			}
			return existing
		}

		/// Commands acting on "the current page" must not silently operate on an
		/// unrelated normal window while the foreground window is private or Mini.
		static func currentBrowser() async throws -> Browser {
			guard let delegate, await delegate.awaitSystemActionsReady() else {
				throw Failure.unavailable
			}
			guard let active = BrowserWindowRegistry.shared.activeBrowser,
			      active.isHydrationFinished, !active.isPrivate, !active.isMini
			else {
				throw Failure.unsupportedAction
			}
			return active
		}

		/// Interactive commands may open a normal window if no normal window exists.
		static func browser() async throws -> Browser {
			if let existing = try? await existingBrowser() {
				return existing
			}
			guard let delegate, await delegate.awaitSystemActionsReady() else {
				throw Failure.unavailable
			}
			let created = delegate.openBrowserWindow().browser
			for _ in 0 ..< 200 {
				if created.isHydrationFinished {
					return created
				}
				try await Task.sleep(for: .milliseconds(50))
			}
			throw Failure.unavailable
		}

		static func validated(_ raw: URL) throws -> URL {
			let checked = try AstraWebAddress(raw)
			guard let url = BrowserHomepage.validURL(checked.url.absoluteString) else {
				throw Failure.invalidURL
			}
			return url
		}

		@discardableResult
		static func open(_ raw: URL, background: Bool = false) async throws -> BrowserTab {
			let url = try validated(raw)
			let browser = try await browser()
			let tab = browser.addTab(inBackground: background)
			tab.controller?.load(url)
			if !background {
				delegate?.focusSystemBrowser(browser)
			}
			return tab
		}

		static func newTab() async throws {
			let browser = try await browser()
			browser.addTab()
			delegate?.focusSystemBrowser(browser)
		}

		static func newWindow(isPrivate: Bool) async throws {
			guard let delegate, await delegate.awaitSystemActionsReady() else {
				throw Failure.unavailable
			}
			delegate.openBrowserWindow(isPrivate: isPrivate)
		}

		static func mini(_ url: URL?) async throws {
			guard let delegate, await delegate.awaitSystemActionsReady() else {
				throw Failure.unavailable
			}
			let checked = try url.map(validated)
			delegate.openMiniAstra(url: checked)
		}

		static func search(_ text: String) async throws {
			let browser = try await browser()
			let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !query.isEmpty, query.utf8.count <= 4096,
			      let url = browser.browserSearchConfiguration.searchURL(for: query, isPrivate: false)
			else {
				throw Failure.invalidURL
			}
			try await open(url)
		}

		static func bookmark(_ raw: URL, title: String? = nil) async throws {
			let url = try validated(raw)
			let browser = try await browser()
			if !browser.bookmarks.contains(where: { $0.url == url }) {
				browser.importBookmarks([Bookmark(name: title ?? url.host ?? url.absoluteString, url: url)])
			}
		}

		static func readLater(_ raw: URL, title: String? = nil) async throws {
			let url = try validated(raw)
			let browser = try await browser()
			if browser.canAddToReadingList(url) {
				browser.addToReadingList(url, title: title ?? url.host ?? url.absoluteString)
			}
		}

		static func selectedURL() async throws -> URL {
			let browser = try await currentBrowser()
			guard let url = browser.selectedTab?.copyableURL else { throw Failure.missingItem }
			return try validated(url)
		}

		static func openBookmark(id: String) async throws {
			let browser = try await browser()
			guard let uuid = UUID(uuidString: id),
			      let item = browser.bookmarks.first(where: { $0.id == uuid })
			else {
				throw Failure.missingItem
			}
			browser.openBookmark(item)
			delegate?.focusSystemBrowser(browser)
		}

		static func openReadingList(id: String) async throws {
			let browser = try await browser()
			guard let uuid = UUID(uuidString: id),
			      let item = browser.readingList.first(where: { $0.id == uuid })
			else {
				throw Failure.missingItem
			}
			browser.openReadingListItem(item, offline: false)
			delegate?.focusSystemBrowser(browser)
		}

		static func switchSpace(id: String) async throws {
			let browser = try await browser()
			guard let uuid = UUID(uuidString: id),
			      browser.workspace.spaces.contains(where: { $0.id == uuid })
			else {
				throw Failure.missingItem
			}
			browser.selectSpace(uuid)
			delegate?.focusSystemBrowser(browser)
		}

		static func resolveTab(id: String) async throws -> (Browser, BrowserTab) {
			guard let ref = AstraTabReference(rawValue: id) else {
				throw Failure.missingItem
			}
			let windowID = ref.windowID
			let tabID = ref.tabID
			guard let delegate, await delegate.awaitSystemActionsReady(),
			      let browser = normalBrowsers().first(where: { $0.windowID == windowID }),
			      BrowserWindowRegistry.shared.ownsTab(tabID, in: browser),
			      let tab = browser.tab(withID: tabID)
			else {
				throw Failure.missingItem
			}
			return (browser, tab)
		}

		static func switchTab(id: String) async throws {
			guard let ref = AstraTabReference(rawValue: id) else {
				throw Failure.missingItem
			}
			let windowID = ref.windowID
			let tabID = ref.tabID
			guard let delegate, await delegate.awaitSystemActionsReady(),
			      let browser = normalBrowsers().first(where: { $0.windowID == windowID }),
			      BrowserWindowRegistry.shared.ownsTab(tabID, in: browser),
			      browser.tab(withID: tabID) != nil
			else {
				throw Failure.missingItem
			}
			// Selecting a tab in another space already updates its space membership.
			browser.selectTab(tabID)
			delegate.focusSystemBrowser(browser)
		}

		static func createEasel(with selection: String? = nil, link: URL? = nil) async throws {
			let browser = try await browser()
			guard let tab = browser.createEasel() else { throw Failure.unsupportedAction }
			if let selection, !selection.isEmpty {
				var document = tab.easelDocument
				let text = String(selection.prefix(8000))
				document.items.append(.init(kind: .text, text: text))
				guard tab.updateEasel(document) else { throw Failure.unsupportedAction }
			} else if let link {
				var document = tab.easelDocument
				try document.items.append(.init(kind: .link, url: validated(link)))
				guard tab.updateEasel(document) else { throw Failure.unsupportedAction }
			}
			delegate?.focusSystemBrowser(browser)
		}

		static func openSpotlightURL(_ url: URL) async {
			guard let item = AstraLibraryItem(url: url) else { return }
			do {
				switch item {
					case let .bookmark(id): try await openBookmark(id: id.uuidString)
					case let .readingList(id): try await openReadingList(id: id.uuidString)
					case let .space(id): try await switchSpace(id: id.uuidString)
				}
			} catch {
				BrowserLog.error(.navigation, "system.spotlight-open-failed",
				                 metadata: ["error": BrowserLog.errorDescription(error)])
			}
		}
	}
#endif
