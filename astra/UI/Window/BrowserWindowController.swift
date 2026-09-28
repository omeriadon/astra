#if os(macOS)
	import AppKit
	import SwiftUI

	@MainActor
	final class BrowserWindowController: NSObject, NSWindowDelegate {
		let browser: Browser
		let window: BrowserWindow
		var onClose: (() -> Void)?

		private let chromeView: BrowserWindowContentView

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

			let window = BrowserWindow(
				contentRect: initialFrame,
				styleMask: [.borderless, .resizable],
				backing: .buffered,
				defer: false
			)
			self.window = window

			let hostedRoot = MacBrowserHostedRoot(browser: browser)
			let hostingView = NSHostingView(rootView: hostedRoot)
			chromeView = BrowserWindowContentView(
				hostingView: hostingView,
				window: window
			)

			super.init()

			window.delegate = self
			window.contentView = chromeView
			window.contentMinSize = NSSize(width: 640, height: 480)
			window.backgroundColor = .clear
			window.isOpaque = false
			window.hasShadow = true
			window.isMovable = false
			window.isMovableByWindowBackground = false
			window.tabbingMode = .disallowed
			window.collectionBehavior.insert(.fullScreenPrimary)
			window.isReleasedWhenClosed = false
			window.acceptsMouseMovedEvents = true
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

		func windowWillEnterFullScreen(_: Notification) {
			chromeView.setFullScreen(true)
		}

		func windowDidExitFullScreen(_: Notification) {
			chromeView.setFullScreen(false)
		}

		func windowDidResize(_: Notification) {
			window.invalidateShadow()
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

	final class BrowserWindow: NSWindow {
		override var canBecomeKey: Bool {
			true
		}

		override var canBecomeMain: Bool {
			true
		}

		@objc
		func closeFromWindowControl(_ sender: Any?) {
			performClose(sender)
		}

		@objc
		func minimizeFromWindowControl(_ sender: Any?) {
			miniaturize(sender)
		}

		@objc
		func fullscreenFromWindowControl(_ sender: Any?) {
			toggleFullScreen(sender)
		}
	}

	private final class BrowserWindowContentView: NSView {
		private let windowControls: TrafficLightClusterView

		init(
			hostingView: NSView,
			window: BrowserWindow
		) {
			let close = NSWindow.standardWindowButton(
				.closeButton,
				for: [.titled, .closable, .miniaturizable, .resizable]
			)
			let minimize = NSWindow.standardWindowButton(
				.miniaturizeButton,
				for: [.titled, .closable, .miniaturizable, .resizable]
			)
			let fullscreen = NSWindow.standardWindowButton(
				.zoomButton,
				for: [.titled, .closable, .miniaturizable, .resizable]
			)

			let controls = [close, minimize, fullscreen].compactMap(\.self)
			windowControls = TrafficLightClusterView(buttons: controls)

			super.init(frame: .zero)

			wantsLayer = true
			layer?.masksToBounds = true
			layer?.cornerRadius = BrowserChromeMetrics.windowCornerRadius
			layer?.cornerCurve = .continuous

			hostingView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(hostingView)

			windowControls.orientation = .horizontal
			windowControls.alignment = .centerY
			windowControls.spacing = 8
			windowControls.translatesAutoresizingMaskIntoConstraints = false
			addSubview(windowControls)

			close?.target = window
			close?.action = #selector(BrowserWindow.closeFromWindowControl(_:))
			minimize?.target = window
			minimize?.action = #selector(BrowserWindow.minimizeFromWindowControl(_:))
			fullscreen?.target = window
			fullscreen?.action = #selector(BrowserWindow.fullscreenFromWindowControl(_:))

			for button in controls {
				button.refusesFirstResponder = true
			}

			NSLayoutConstraint.activate([
				hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
				hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
				hostingView.topAnchor.constraint(equalTo: topAnchor),
				hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),

				windowControls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
				windowControls.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			])
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		func setFullScreen(_ fullScreen: Bool) {
			windowControls.isHidden = fullScreen
			layer?.cornerRadius = fullScreen ? 0 : BrowserChromeMetrics.windowCornerRadius
			window?.invalidateShadow()
		}
	}

	private final class TrafficLightClusterView: NSStackView {
		private let trafficLightButtons: [NSButton]
		private var hoverTrackingArea: NSTrackingArea?

		init(buttons: [NSButton]) {
			trafficLightButtons = buttons
			super.init(views: buttons)

			orientation = .horizontal
			alignment = .centerY
			spacing = 8
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		override func updateTrackingAreas() {
			super.updateTrackingAreas()

			if let hoverTrackingArea {
				removeTrackingArea(hoverTrackingArea)
			}

			let area = NSTrackingArea(
				rect: bounds,
				options: [.mouseEnteredAndExited, .activeInKeyWindow],
				owner: self,
				userInfo: nil
			)
			addTrackingArea(area)
			hoverTrackingArea = area
		}

		override func mouseEntered(with event: NSEvent) {
			super.mouseEntered(with: event)
			for button in trafficLightButtons {
				button.mouseEntered(with: event)
			}
		}

		override func mouseExited(with event: NSEvent) {
			super.mouseExited(with: event)
			for button in trafficLightButtons {
				button.mouseExited(with: event)
			}
		}
	}
#endif
