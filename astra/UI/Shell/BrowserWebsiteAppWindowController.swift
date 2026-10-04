#if os(macOS)
	import AppKit
	import SwiftUI

	@MainActor
	final class BrowserWebsiteAppWindowController: NSObject, NSWindowDelegate {
		let browser = Browser(isMini: true)
		let chrome = BrowserWebsiteAppChromeState()
		let window: NSWindow
		private var closeApproved = false

		init(url: URL, name: String) {
			let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
			let size = NSSize(width: min(1000, visibleFrame.width), height: min(760, visibleFrame.height))
			window = NSWindow(
				contentRect: NSRect(
					x: visibleFrame.midX - size.width / 2,
					y: visibleFrame.midY - size.height / 2,
					width: size.width,
					height: size.height
				),
				styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
				backing: .buffered,
				defer: false
			)
			super.init()
			window.delegate = self
			window.title = name
			window.titleVisibility = .hidden
			window.titlebarAppearsTransparent = true
			window.titlebarSeparatorStyle = .none
			window.contentMinSize = NSSize(width: 480, height: 320)
			window.tabbingMode = .disallowed
			window.isReleasedWhenClosed = false
			window.contentView = BrowserContentHostView(
				hostingView: NSHostingView(rootView: BrowserWebsiteAppView(browser: browser, chrome: chrome))
			)
			browser.selectedTab?.controller?.load(url)
		}

		func showWindow() {
			window.makeKeyAndOrderFront(nil)
			NSApp.activate()
		}

		func toggleTopBar() {
			chrome.showsTopBar.toggle()
		}

		func windowShouldClose(_ sender: NSWindow) -> Bool {
			guard !closeApproved else { return true }
			let hasProtectedMedia = browser.tabs.contains { tab in
				tab.controller?.requiresMediaTeardownConfirmation == true
					|| tab.peeks.contains { $0.controller.requiresMediaTeardownConfirmation }
			}
			guard hasProtectedMedia else { return true }
			Task { @MainActor in
				let alert = BrowserWebsiteUI.alert(
					title: "Close Website App?",
					message: "Closing this window will stop media playback.",
					confirm: "Close Window"
				)
				guard await BrowserWebsiteUI.present(alert, in: sender) == .alertFirstButtonReturn else { return }
				closeApproved = true
				for tab in browser.tabs {
					tab.stopForClose()
				}
				sender.close()
			}
			return false
		}

		func windowWillClose(_: Notification) {
			for tab in browser.tabs {
				tab.stopForClose()
			}
		}
	}
#endif
