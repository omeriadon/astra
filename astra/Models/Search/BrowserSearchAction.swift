import Defaults
import Foundation

struct BrowserSearchAction: Identifiable {
	let id: String
	let title: String
	let symbol: String
	let terms: [String]
	let detail: String
	let perform: @MainActor () -> Void

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
				perform: { browser.addTab() }
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
