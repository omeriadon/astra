import Foundation
import WebKit
#if os(macOS)
	import AppKit
#endif

@MainActor
final class BrowserExtensionWindow: NSObject, WKWebExtensionWindow {
	weak var browser: Browser?
	#if os(macOS)
		weak var nativeWindow: NSWindow?
	#endif

	init(browser: Browser) {
		self.browser = browser
	}

	func tabs(for _: WKWebExtensionContext) -> [any WKWebExtensionTab] {
		guard let browser else { return [] }
		return browser.tabs.filter { $0.internalPage == nil && BrowserWindowRegistry.shared.ownsTab($0.id, in: browser) }.compactMap {
			BrowserExtensionManager.shared.extensionTab(for: $0.id, in: browser)
		}
	}

	func activeTab(for _: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
		guard let browser, browser.selectedTab?.internalPage == nil else { return nil }
		return BrowserExtensionManager.shared.extensionTab(for: browser.selectedTabID, in: browser)
	}

	func isPrivate(for _: WKWebExtensionContext) -> Bool {
		false
	}

	#if os(macOS)
		func frame(for _: WKWebExtensionContext) -> CGRect {
			nativeWindow?.frame ?? .zero
		}

		func screenFrame(for _: WKWebExtensionContext) -> CGRect {
			nativeWindow?.screen?.frame ?? .zero
		}

		func focus(for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
			nativeWindow?.makeKeyAndOrderFront(nil)
			completionHandler(nil)
		}

		func close(for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
			nativeWindow?.performClose(nil)
			completionHandler(nil)
		}
	#endif
}

@MainActor
final class BrowserExtensionTab: NSObject, WKWebExtensionTab {
	weak var browser: Browser?
	let id: UUID

	init(id: UUID, browser: Browser) {
		self.id = id
		self.browser = browser
	}

	private var tab: BrowserTab? {
		browser?.tab(withID: id)
	}

	func window(for _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
		guard let browser else { return nil }
		return BrowserExtensionManager.shared.extensionWindow(for: browser)
	}

	func indexInWindow(for _: WKWebExtensionContext) -> Int {
		browser?.tabs.filter { $0.internalPage == nil }.firstIndex(where: { $0.id == id }) ?? 0
	}

	func webView(for _: WKWebExtensionContext) -> WKWebView? {
		tab?.controller?.webViewIfLoaded
	}

	func title(for _: WKWebExtensionContext) -> String? {
		tab?.title
	}

	func url(for _: WKWebExtensionContext) -> URL? {
		tab?.currentURL
	}

	func isPinned(for _: WKWebExtensionContext) -> Bool {
		isPinnedForBrowser
	}

	func isSelected(for _: WKWebExtensionContext) -> Bool {
		browser?.selectedTabID == id
	}

	func isLoadingComplete(for _: WKWebExtensionContext) -> Bool {
		tab?.controller?.isLoading != true
	}

	func zoomFactor(for _: WKWebExtensionContext) -> Double {
		tab?.controller?.pageZoom ?? 1
	}

	func activate(for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
		guard tab != nil else {
			completionHandler(NSError(domain: "astra.extensions", code: 7))
			return
		}
		browser?.selectTab(id)
		completionHandler(nil)
	}

	func loadURL(_ url: URL, for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
		if tab?.isHibernated == true {
			browser?.selectTab(id)
		}
		guard let controller = tab?.controller else {
			completionHandler(NSError(domain: "astra.extensions", code: 7))
			return
		}
		controller.load(url)
		completionHandler(nil)
	}

	func reload(fromOrigin: Bool, for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
		if fromOrigin {
			tab?.controller?.reloadFromOrigin()
		} else {
			tab?.controller?.reload()
		}
		completionHandler(nil)
	}

	func goBack(for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
		tab?.controller?.goBack()
		completionHandler(nil)
	}

	func goForward(for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
		tab?.controller?.goForward()
		completionHandler(nil)
	}

	func close(for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
		guard let browser, tab != nil else {
			completionHandler(NSError(domain: "astra.extensions", code: 7))
			return
		}
		if isPinnedForBrowser {
			let ownerID = browser.workspace.spaces.first { $0.tabIDs.contains(id) }?.id
			browser.moveTab(id, to: .normal, in: ownerID)
		}
		browser.closeTab(id)
		completionHandler(nil)
	}

	private var isPinnedForBrowser: Bool {
		guard let browser else { return false }
		return browser.workspace.favouriteTabIDs.contains(id)
			|| browser.workspace.spaces.contains { $0.pinnedTabIDs.contains(id) }
	}

	func setPinned(_ pinned: Bool, for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
		browser?.moveTab(id, to: pinned ? .pinned : .normal)
		completionHandler(nil)
	}

	func duplicate(
		using configuration: WKWebExtension.TabConfiguration,
		for _: WKWebExtensionContext,
		completionHandler: ((any WKWebExtensionTab)?, Error?) -> Void
	) {
		guard let browser, let duplicated = browser.duplicateTab(id) else {
			completionHandler(nil, NSError(domain: "astra.extensions", code: 7))
			return
		}
		if configuration.shouldBePinned {
			browser.moveTab(duplicated.id, to: .pinned)
		}
		completionHandler(BrowserExtensionManager.shared.extensionTab(for: duplicated.id, in: browser), nil)
	}

	func setZoomFactor(_ factor: Double, for _: WKWebExtensionContext, completionHandler: (Error?) -> Void) {
		tab?.controller?.pageZoom = factor
		completionHandler(nil)
	}
}
