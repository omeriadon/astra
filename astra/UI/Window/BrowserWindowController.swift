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
			let hostingView = NSHostingView(rootView: hostedRoot)
			let contentHost = BrowserContentHostView(hostingView: hostingView)

			super.init()

			window.delegate = self
			window.contentView = contentHost
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

	private final class BrowserContentHostView: NSView {
		init(hostingView: NSView) {
			super.init(frame: .zero)

			hostingView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(hostingView)

			NSLayoutConstraint.activate([
				hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
				hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
				hostingView.topAnchor.constraint(equalTo: topAnchor),
				hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
			])

			#if DEBUG
				assert(
					responds(to: NSSelectorFromString("_opaqueRectForWindowMoveWhenInTitlebar")),
					"AppKit titlebar drag override is not visible to Objective-C"
				)
			#endif
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		override var mouseDownCanMoveWindow: Bool {
			false
		}

		/// NSWindowStyleMaskFullSizeContentView normally lets AppKit force
		/// titlebar-overlapping content into the native window-drag region even
		/// when mouseDownCanMoveWindow is false. Firefox, Chromium, and Zed use
		/// this private selector to mark app-owned titlebar content as opaque to
		/// that drag-region calculation.
		///
		/// Returning the entire host bounds disables AppKit's implicit titlebar
		/// dragging across Astra. Explicit WindowDragBackground views still move
		/// the window with NSWindow.performDrag(with:).
		@objc(_opaqueRectForWindowMoveWhenInTitlebar)
		func opaqueRectForWindowMoveWhenInTitlebar() -> NSRect {
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
