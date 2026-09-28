#if os(macOS)
	import AppKit
	import SwiftUI

	@MainActor
	final class BrowserWindowController: NSObject, NSWindowDelegate {
		let browser: Browser
		let window: NSWindow
		var onClose: (() -> Void)?

		override convenience init() {
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
			let hostingView = BrowserHostingView(rootView: hostedRoot)
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

	private final class BrowserHostingView<Content: View>: NSHostingView<Content> {
		override var mouseDownCanMoveWindow: Bool {
			false
		}

		// AppKit gives the hidden titlebar region special drag handling for
		// full-size-content windows. Firefox, Chromium, and Zed override this
		// selector so interactive app content owns mouse handling in that region.
		//
		// This is an undocumented AppKit selector. Returning our entire bounds
		// makes the hosted SwiftUI hierarchy non-draggable by AppKit; Astra then
		// opts specific blank regions back into dragging via performDrag(with:).
		@objc(_opaqueRectForWindowMoveWhenInTitlebar)
		func astraOpaqueRectForWindowMoveWhenInTitlebar() -> NSRect {
			bounds
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
