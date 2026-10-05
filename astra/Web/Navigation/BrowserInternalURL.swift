import Foundation

nonisolated enum BrowserInternalURL {
	enum Source {
		case userInterface
		case operatingSystem
		case webContent
		case extensionContent
		case importedData

		var isTrusted: Bool {
			switch self {
				case .userInterface, .operatingSystem: true
				case .webContent, .extensionContent, .importedData: false
			}
		}
	}

	enum Destination: Equatable {
		case newTab
		case settings(BrowserSettingsView.Page?)
		case history
		case bookmarks
		case themeEditor
	}

	static func destination(for url: URL, source: Source) -> Destination? {
		guard source.isTrusted,
		      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      components.scheme?.lowercased() == "astra",
		      components.user == nil,
		      components.password == nil,
		      components.port == nil,
		      components.fragment == nil,
		      components.path.isEmpty || components.path == "/",
		      let host = components.host?.lowercased(),
		      !host.isEmpty
		else { return nil }

		let items = components.queryItems ?? []
		guard Set(items.map(\.name)).count == items.count else { return nil }

		switch host {
			case "new-tab":
				guard items.isEmpty else { return nil }
				return .newTab
			case "history":
				guard items.isEmpty else { return nil }
				return .history
			case "bookmarks":
				guard items.isEmpty else { return nil }
				return .bookmarks
			case "theme":
				guard items.isEmpty else { return nil }
				return .themeEditor
			case "extensions":
				guard items.isEmpty else { return nil }
				return .settings(.extensions)
			case "version":
				guard items.isEmpty else { return nil }
				return .settings(.about)
			case "settings":
				guard items.allSatisfy({ $0.name == "page" }), items.count <= 1 else { return nil }
				guard let item = items.first else { return .settings(nil) }
				guard let value = item.value, let page = settingsPage(named: value) else { return nil }
				return .settings(page)
			default:
				return nil
		}
	}

	@MainActor
	@discardableResult
	static func open(_ url: URL, source: Source, in browser: Browser) -> Bool {
		guard let destination = destination(for: url, source: source) else { return false }
		switch destination {
			case .newTab:
				browser.addTab()
			case let .settings(page):
				if let page {
					browser.settingsPage = browser.isPrivate ? .privacyAndSecurity : page
				}
				browser.openInternalPage(.settings)
			case .history:
				browser.openInternalPage(.history)
			case .bookmarks:
				browser.openInternalPage(.bookmarks)
			case .themeEditor:
				guard !browser.isPrivate else { return false }
				browser.openInternalPage(.themeEditor)
		}
		return true
	}

	private static func settingsPage(named value: String) -> BrowserSettingsView.Page? {
		switch value.lowercased() {
			case "general", "ui": .ui
			case "account", "sync": .account
			case "privacy", "security": .privacyAndSecurity
			case "extensions": .extensions
			case "developer": .developer
			#if os(macOS)
				case "website-apps": .websiteApps
			#endif
			case "advanced": .advanced
			case "about", "version": .about
			#if DEBUG
				case "failed-websites", "failures": .failedWebsiteStates
			#endif
			default: nil
		}
	}
}
