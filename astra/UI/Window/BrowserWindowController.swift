#if os(macOS)
	import AppKit
	import SwiftUI

	@MainActor
	final class BrowserWindowController: NSObject, NSWindowDelegate {
		let browser: Browser
		let window: NSWindow
		var onClose: (() -> Void)?

		convenience init() {
			self.init(browser: Browser())
		}

		init(browser: Browser) {
			self.browser = browser

			let visibleFrame = NSScreen.main?.visibleFrame
				?? NSRect(x: 0, y: 0, width: 1280, height: 800)
			let initialSize = NSSize(
				width: min(1280, visibleFrame.width * 0.86),
				height: min(820, visibleFrame.height * 0.86)
			)
			let initialFrame = NSRect(
				x: visibleFrame.midX - initialSize.width / 2,
				y: visibleFrame.midY - initialSize.height / 2,
				width: initialSize.width,
				height: initialSize.height
			)

			let window = NSWindow(
				contentRect: initialFrame,
				styleMask: [
					.titled,
					.closable,
					.miniaturizable,
					.resizable,
					.fullSizeContentView,
				],
				backing: .buffered,
				defer: false
			)
			self.window = window

			let hostedRoot = MacBrowserHostedRoot(browser: browser)
			let hostingView = NSHostingView(rootView: hostedRoot)
			hostingView.autoresizingMask = [.width, .height]
			hostingView.frame = NSRect(origin: .zero, size: initialSize)

			super.init()

			window.delegate = self
			window.contentView = hostingView
			window.contentMinSize = NSSize(width: 640, height: 480)
			window.title = "astra"
			window.titleVisibility = .hidden
			window.titlebarAppearsTransparent = true
			window.titlebarSeparatorStyle = .none
			window.toolbar = nil
			window.isMovableByWindowBackground = false
			window.tabbingMode = .disallowed
			window.collectionBehavior.insert(.fullScreenPrimary)
			window.isReleasedWhenClosed = false
		}

		func showWindow() {
			window.makeKeyAndOrderFront(nil)
		}

		func windowDidBecomeKey(_: Notification) {
			BrowserWindowRegistry.shared.activate(browser)
		}

		func windowWillClose(_: Notification) {
			browser.flushPersistence()
			onClose?()
		}
	}

	private struct MacBrowserHostedRoot: View {
		let browser: Browser
		@State private var updates = UpdateManager.shared

		var body: some View {
			BrowserRootView(browser: .constant(browser))
				.sheet(isPresented: $updates.isPresented) {
					BrowserUpdateSheet(updates: updates)
				}
		}
	}
#endif
