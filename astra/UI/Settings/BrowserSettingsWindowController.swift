#if os(macOS)
	import AppKit
	import SwiftUI

	/// A single Settings window, separate from browser tabs and their restoration.
	/// Astra owns its AppKit lifecycle, so this hosts SwiftUI without adding a
	/// second App/NSApplication entry point just for a Settings scene.
	@MainActor
	final class BrowserSettingsWindowController: NSObject, NSWindowDelegate {
		static let shared = BrowserSettingsWindowController()
		private(set) var browser: Browser?
		private var window: NSWindow?

		var isKeyWindow: Bool { window?.isKeyWindow == true }

		func show(for browser: Browser) {
			if self.browser === browser, let window {
				window.makeKeyAndOrderFront(nil)
				return
			}

			let window: NSWindow
			if let existing = self.window {
				window = existing
			} else {
				window = NSWindow(
					contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
					styleMask: [.titled, .closable, .miniaturizable, .resizable],
					backing: .buffered,
					defer: false
				)
				window.title = "Settings"
				window.isOpaque = false
				window.backgroundColor = .clear
				window.identifier = NSUserInterfaceItemIdentifier("astra-settings")
				window.contentMinSize = NSSize(
					width: BrowserChromeMetrics.minimumPageWidth(isSettings: true),
					height: 480
				)
				window.tabbingMode = .disallowed
				window.isReleasedWhenClosed = false
				window.delegate = self
				window.setFrameAutosaveName("AstraSettings")
				if !window.setFrameUsingName("AstraSettings") {
					window.center()
				}
				self.window = window
			}

			self.browser = browser
			window.contentViewController = NSHostingController(rootView: BrowserSettingsWindowRoot(browser: browser))
			window.makeKeyAndOrderFront(nil)
		}

		func close(for browser: Browser) {
			guard self.browser === browser else { return }
			window?.close()
		}

		func windowWillClose(_: Notification) {
			// Release the view hierarchy and its session, especially private website
			// data. The owning browser window can now tear down independently.
			window?.contentViewController = nil
			window?.contentView = nil
			browser = nil
			window = nil
		}
	}

	private struct BrowserSettingsWindowRoot: View {
		@Bindable var browser: Browser
		@State private var searchText = ""
		@Environment(\.colorScheme) private var colorScheme

		var body: some View {
			BrowserSettingsView(
				browser: browser,
				searchText: $searchText,
				selectedPage: $browser.settingsPage
			)
			.background {
				BrowserThemeBackground(theme: browser.theme)
					.overlay(browser.theme.contentShade(for: colorScheme))
			}
		}
	}
#endif
