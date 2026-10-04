#if os(macOS)
	import AppKit

	@MainActor
	final class BrowserWebsiteAppMenuIntegration: NSObject, NSMenuItemValidation {
		static let shared = BrowserWebsiteAppMenuIntegration()
		private weak var addMenuItem: NSMenuItem?
		private var observer: NSObjectProtocol?

		func install() {
			guard observer == nil else { return }
			observer = NotificationCenter.default.addObserver(
				forName: NSApplication.didFinishLaunchingNotification,
				object: NSApp,
				queue: .main
			) { [weak self] _ in
				Task { @MainActor in self?.installMenuItem() }
			}
		}

		private func installMenuItem() {
			guard addMenuItem == nil,
			      let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }
			let item = NSMenuItem(title: "Add Website to Dock…", action: #selector(addWebsiteToDock(_:)), keyEquivalent: "")
			item.target = self
			item.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
			item.setAccessibilityLabel("Add Website to Dock")
			if let insertion = fileMenu.items.firstIndex(where: { $0.title == "Print…" }) {
				fileMenu.insertItem(item, at: insertion)
			} else {
				fileMenu.addItem(item)
			}
			addMenuItem = item
		}

		func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
			guard menuItem === addMenuItem else { return true }
			return currentCandidate() != nil
		}

		@objc private func addWebsiteToDock(_: Any?) {
			guard let candidate = currentCandidate(), let window = candidate.window else { return }
			let alert = NSAlert()
			alert.messageText = "Add Website to Dock"
			alert.informativeText = "Astra will create a local standalone app for this website. Website data is not exported from private browsing."
			alert.alertStyle = .informational
			alert.addButton(withTitle: "Add Website")
			alert.addButton(withTitle: "Cancel")
			let field = NSTextField(string: candidate.name)
			field.placeholderString = "App Name"
			field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
			field.setAccessibilityLabel("Website app name")
			alert.accessoryView = field
			alert.beginSheetModal(for: window) { response in
				guard response == .alertFirstButtonReturn else { return }
				Task { @MainActor in
					guard candidate.isStillCurrent() else {
						candidate.browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: "The page changed before the website app was created.")
						return
					}
					do {
						let registry = BrowserWebsiteAppRegistry.shared
						let installation = try registry.install(name: field.stringValue, url: candidate.url, icon: candidate.icon)
						try registry.beginKeepInDockFlow(installation.id)
						candidate.browser.session.toastManager.show(symbol: "checkmark", message: "Website app created. Use Options → Keep in Dock on its Dock icon to pin it.")
					} catch {
						candidate.browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: error.localizedDescription)
					}
				}
			}
		}

		private func currentCandidate() -> Candidate? {
			guard let browser = BrowserWindowRegistry.shared.activeBrowser,
			      !browser.isPrivate, !browser.isMini,
			      let tab = browser.selectedTab, tab.internalPage == nil,
			      let controller = tab.activeController,
			      let url = controller.committedURL,
			      controller.url == url,
			      !controller.isLoading,
			      BrowserWebsiteAppPolicy.validatedURL(url) != nil,
			      let webView = controller.webViewIfLoaded,
			      let window = webView.window
			else { return nil }
			let name = BrowserWebsiteAppPolicy.validatedName(tab.title)
				?? BrowserWebsiteAppPolicy.validatedName(url.host ?? "Website")
				?? "Website"
			let icon: NSImage? = FaviconKey.origin(for: url)
				.flatMap { browser.session.favicons.favicons[$0] }
				.flatMap(NSImage.init(data:))
			return Candidate(
				browser: browser,
				controller: controller,
				tabID: tab.id,
				documentID: controller.navigationIdentifier,
				url: url,
				name: name,
				icon: icon,
				window: window
			)
		}

		private struct Candidate {
			let browser: Browser
			weak var controller: BrowserController?
			let tabID: UUID
			let documentID: Int
			let url: URL
			let name: String
			let icon: NSImage?
			weak var window: NSWindow?

			@MainActor
			func isStillCurrent() -> Bool {
				guard let controller else { return false }
				return browser.selectedTabID == tabID
					&& browser.selectedTab?.activeController === controller
					&& controller.navigationIdentifier == documentID
					&& controller.committedURL == url
					&& controller.url == url
					&& !controller.isLoading
			}
		}
	}
#endif
