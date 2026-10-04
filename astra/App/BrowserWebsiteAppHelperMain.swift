#if os(macOS) && ASTRA_WEBSITE_APP_HELPER
	import AppKit
	import Foundation

	@main
	enum BrowserWebsiteAppHelperMain {
		@MainActor
		static func main() {
			let application = NSApplication.shared
			let delegate = BrowserWebsiteAppHelperDelegate()
			application.setActivationPolicy(.regular)
			application.delegate = delegate
			application.run()
			_ = delegate
		}
	}

	@MainActor
	private final class BrowserWebsiteAppHelperDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
		private var windowController: BrowserWebsiteAppWindowController?
		private var launchURL: URL?

		func applicationDidFinishLaunching(_: Notification) {
			guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "AstraWebsiteAppLaunchURL") as? String,
			      let url = URL(string: rawURL),
			      BrowserWebsiteAppPolicy.validatedURL(url) != nil
			else {
				NSApp.terminate(nil)
				return
			}
			launchURL = url
			let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
				.flatMap(BrowserWebsiteAppPolicy.validatedName) ?? "Website"
			let controller = BrowserWebsiteAppWindowController(url: url, name: name)
			controller.browser.navigationIntercept = { [weak self] destination in
				guard let self, let launchURL else { return false }
				guard !BrowserWebsiteAppPolicy.shouldStayInWebsiteApp(destination, launchURL: launchURL) else { return false }
				guard BrowserWebsiteAppPolicy.validatedURL(destination) != nil else { return false }
				NSWorkspace.shared.open(destination)
				return true
			}
			windowController = controller
			installMenu()
			controller.showWindow()
		}

		func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
			true
		}

		func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
			if !flag {
				windowController?.showWindow()
			}
			return true
		}

		private func installMenu() {
			let main = NSMenu()
			let appMenu = NSMenu()
			let appRoot = NSMenuItem()
			appRoot.submenu = appMenu
			main.addItem(appRoot)
			appMenu.addItem(withTitle: "Quit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Website")", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

			let viewMenu = NSMenu(title: "View")
			let viewRoot = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
			viewRoot.submenu = viewMenu
			main.addItem(viewRoot)
			let toggle = NSMenuItem(title: "Toggle Top Bar", action: #selector(toggleTopBar(_:)), keyEquivalent: "s")
			toggle.keyEquivalentModifierMask = [.command]
			toggle.target = self
			viewMenu.addItem(toggle)
			NSApp.mainMenu = main
		}

		@objc private func toggleTopBar(_: Any?) {
			windowController?.toggleTopBar()
		}

		func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
			menuItem.action != #selector(toggleTopBar(_:)) || windowController != nil
		}
	}
#endif
