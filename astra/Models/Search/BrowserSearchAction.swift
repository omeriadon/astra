import Defaults
import Foundation
#if os(macOS)
	import AppKit
#endif

struct BrowserSearchAction: Identifiable {
	let id: String
	let title: String
	let symbol: String
	let terms: [String]
	let detail: String
	let perform: @MainActor () -> Void

	/// A local command list: never runs a web search or creates a tab on presentation.
	@MainActor
	static func paletteCatalogue(for browser: Browser) -> [Self] {
		var actions = catalogue(for: browser).filter { $0.detail == "Browser Action" }
		func add(_ id: String, _ title: String, _ symbol: String, _ terms: [String] = [], perform: @escaping @MainActor () -> Void) {
			actions.append(Self(id: id, title: title, symbol: symbol, terms: terms, detail: "Browser Action", perform: perform))
		}
		add("close-tab", "Close Tab", "xmark", ["close current tab"]) { browser.closeTab(browser.selectedTabID) }
		add("duplicate-tab", "Duplicate Tab", "plus.square.on.square") { _ = browser.duplicateTab(browser.selectedTabID) }
		#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME
			add("toggle-top-bar", "Toggle Top Bar", "rectangle.topthird.inset.filled", ["toolbar", "address bar"]) {
				NotificationCenter.default.post(name: .toggleBrowserTopBar, object: browser.windowID)
			}
			add("quit", "Quit Astra", "power") { NSApp.terminate(nil) }
		#endif
		if let controller = browser.selectedTab?.activeController {
			add("zoom-in", "Zoom In", "plus.magnifyingglass", ["increase zoom"]) { controller.zoomIn() }
			add("zoom-out", "Zoom Out", "minus.magnifyingglass", ["decrease zoom"]) { controller.zoomOut() }
			add("reset-zoom", "Reset Zoom", "arrow.counterclockwise", ["actual size", "100%"]) { controller.resetZoom() }
			add("reload", "Reload Page", "arrow.clockwise", ["refresh"]) { controller.reload() }
			if controller.canGoBack { add("back", "Go Back", "arrow.left") { controller.goBack() } }
			if controller.canGoForward { add("forward", "Go Forward", "arrow.right") { controller.goForward() } }
		}
		if !browser.isPrivate, !browser.isMini,
		   let current = browser.selectedTab, current.canAppearInEaselSplit,
		   let other = browser.visibleTabs.first(where: { $0.id != current.id && $0.canAppearInEaselSplit }) {
			actions.append(Self(id: "split-current-tab", title: "Add Current Tab to Split",
			                    symbol: "rectangle.split.2x1", terms: ["split view", "split screen"],
			                    detail: "Split with \(other.title)", perform: {
				                    browser.openSplit(current.id, beside: other.id, onLeft: false)
			                    }))
		}
		if browser.isShowingTabSplit {
			add("close-split", "Close Split", "rectangle") { browser.closeEaselSplit() }
		}
		#if !ASTRA_WEBSITE_APP_RUNTIME
		if Defaults[.aiFeaturesEnabled], Defaults[.aiSidebar], browser.canShowAISidebar,
		   !browser.isPrivate, !browser.aiChat.isResponding, !browser.aiChat.isImporting,
		   browser.aiChat.draft.isEmpty {
			add("summarise-page", "Summarise Page", "text.alignleft", ["summarize", "summary", "AI"]) {
				browser.showsAISidebar = true
				browser.pendingPageSummary = true
			}
		}
		#endif
		return actions.map { action in
			guard action.id == "toggle-sidebar" || action.id == "toggle-ai-sidebar" else { return action }
			let left = action.id == "toggle-sidebar"
			return Self(id: action.id, title: left ? "Toggle Left Sidebar" : "Toggle Right Sidebar",
			            symbol: left ? "sidebar.left" : "sidebar.right",
			            terms: action.terms + [left ? "left bar" : "right bar", action.title],
			            detail: action.detail, perform: action.perform)
		}
	}

	/// Add browser commands here. Settings destinations come from the settings catalogue.
	@MainActor
	static func catalogue(for browser: Browser) -> [Self] {
		var actions = BrowserInternalPage.allCases.filter { !browser.isPrivate || $0 == .settings }.map { page in
			Self(
				id: "page-\(page.persistenceID)",
				title: "Open \(page.title)",
				symbol: page.symbol,
				terms: [page.title],
				detail: "Browser Action",
				perform: { browser.openInternalPage(page) }
			)
		}
		for page in BrowserSettingsView.Page.allCases where !browser.isPrivate || page == .privacyAndSecurity {
			let definition = page.definition
			for term in [definition.title] + definition.terms {
				actions.append(Self(
					id: "\(definition.identifier)-\(term)",
					title: term,
					symbol: definition.symbol,
					terms: ["\(term) settings", "change \(term)", "configure \(term)"],
					detail: "Settings · \(definition.title)",
					perform: {
						browser.settingsPage = page
						browser.settingsScrollTarget = term
						browser.openInternalPage(.settings)
					}
				))
			}
		}
		actions += [
			Self(
				id: "new-tab", title: "New Tab", symbol: "plus",
				terms: ["create tab", "open tab"], detail: "Browser Action",
				perform: { browser.requestNewTab() }
			),
			Self(
				id: "reopen-tab", title: "Reopen Closed Tab", symbol: "arrow.uturn.backward",
				terms: ["restore tab", "undo close"], detail: "Browser Action",
				perform: { browser.reopenLastClosedTab() }
			),
			Self(
				id: "toggle-sidebar", title: "Toggle Sidebar", symbol: "sidebar.left",
				terms: ["show sidebar", "hide sidebar"], detail: "Browser Action",
				perform: { browser.sidebarShown.toggle() }
			),
			Self(
				id: "new-space", title: "New Space", symbol: "square.stack.3d.up.badge.plus",
				terms: ["create space", "workspace"], detail: "Browser Action",
				perform: { browser.createSpace() }
			),
		]
		if let controller = browser.selectedTab?.activeController,
		   controller.hasCurrentPageDocument,
		   !controller.isLoading,
		   controller.navigationFailure == nil,
		   let url = controller.committedURL,
		   BrowserTranslationPolicy.translationURL(for: url, language: "en", isPrivate: browser.isPrivate) != nil
		{
			actions.append(Self(
				id: "translate-page",
				title: "Translate Page",
				symbol: "translate",
				terms: ["translate website", "translation", "change page language"],
				detail: "Browser Action",
				perform: {
					NotificationCenter.default.post(name: .astraTranslatePage, object: browser)
				}
			))
		}
		if Defaults[.aiFeaturesEnabled], browser.canShowAISidebar, Defaults[.aiSidebar] {
			actions.append(Self(
				id: "toggle-ai-sidebar", title: "AI Sidebar", symbol: "bubble.left.and.text.bubble.right",
				terms: ["chat", "ask AI", "toggle AI"], detail: "Browser Action",
				perform: { browser.showsAISidebar.toggle() }
			))
		}
		if browser.isPrivate {
			actions.removeAll { $0.id == "new-space" || $0.id == "page-themeEditor" }
		}
		return actions
	}
}
