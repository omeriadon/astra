#if os(macOS)
	import AppKit
	import Defaults
	import SwiftUI

	@MainActor
	final class BrowserWindowController: NSObject, NSWindowDelegate {
		let browser: Browser
		let window: NSWindow
		var onClose: (() -> Void)?
		/// Fires after AppKit first updates a visible window, not merely after orderFront.
		var onFirstVisibleUpdate: (() -> Void)?
		private var didReportFirstVisibleUpdate = false
		private var allowsClosing = false
		private var closeApprovalInFlight = false

		override convenience init() {
			self.init(browser: Browser())
		}

		init(browser: Browser) {
			self.browser = browser

			let savedScreenFrame = browser.savedWindowFrame.map {
				NSRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
			}
			let targetScreen = savedScreenFrame.flatMap { saved in
				NSScreen.screens.first { $0.frame.intersects(saved) }
			} ?? NSScreen.main
			let visibleFrame = targetScreen?.visibleFrame
				?? NSRect(x: 0, y: 0, width: 1280, height: 800)
			let initialSize = NSSize(
				width: min(1280, visibleFrame.width * 0.86),
				height: min(820, visibleFrame.height * 0.86)
			)
			let styleMask: NSWindow.StyleMask = [
				.titled,
				.closable,
				.miniaturizable,
				.resizable,
				.fullSizeContentView,
			]
			let initialFrame: NSRect
			if let savedFrame = browser.savedWindowFrame {
				let clamped = savedFrame.clamped(to: visibleFrame)
				let frame = NSRect(x: clamped.x, y: clamped.y, width: clamped.width, height: clamped.height)
				initialFrame = NSWindow.contentRect(forFrameRect: frame, styleMask: styleMask)
			} else {
				initialFrame = NSRect(
					x: visibleFrame.midX - initialSize.width / 2,
					y: visibleFrame.midY - initialSize.height / 2,
					width: initialSize.width,
					height: initialSize.height
				)
			}

			let window = NSWindow(
				contentRect: initialFrame,
				styleMask: styleMask,
				backing: .buffered,
				defer: false
			)
			self.window = window

			let hostedRoot = MacBrowserHostedRoot(browser: browser)
			let hostingView = NSHostingView(rootView: hostedRoot)
			// Pane visibility controls the window minimum; intrinsic hosting constraints must not compete with it.
			hostingView.sizingOptions = []
			let contentHost = BrowserContentHostView(hostingView: hostingView)

			super.init()
			if !browser.isPrivate {
				BrowserExtensionManager.shared.extensionWindow(for: browser).nativeWindow = window
			}

			window.delegate = self
			window.contentView = contentHost
			window.contentMinSize = NSSize(width: BrowserChromeMetrics.minimumContentWidth, height: min(480, visibleFrame.height))
			window.setBrowserMinimumContentWidth(BrowserChromeMetrics.minimumWindowWidth(
				sidebarShown: browser.sidebarShown,
				aiSidebarShown: browser.showsAISidebar && browser.canShowAISidebar
					&& Defaults[.aiFeaturesEnabled] && Defaults[.aiSidebar],
				minimumContentWidth: BrowserChromeMetrics.minimumPageWidth(isSettings: browser.selectedTab?.internalPage == .settings)
			))
			window.title = browser.isPrivate ? "astra — Private Browsing" : "astra"
			window.isOpaque = false
			window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
			window.titleVisibility = .hidden
			window.titlebarAppearsTransparent = true
			window.titlebarSeparatorStyle = .none
			window.toolbar = nil
			window.isMovableByWindowBackground = false
			window.tabbingMode = .disallowed
			window.collectionBehavior.insert(.fullScreenPrimary)
			window.isReleasedWhenClosed = false
			if browser.savedWindowFrame == nil {
				let frame = window.frame
				browser.updateWindowFrame(BrowserWindowFrame(
					x: frame.origin.x,
					y: frame.origin.y,
					width: frame.width,
					height: frame.height
				))
			}
		}

		func showWindow() {
			BrowserWindowRegistry.shared.activate(browser)
			// AppKit performs layout and display during its normal update pass.
			// Forcing both synchronously here blocks the startup main thread.
			window.makeKeyAndOrderFront(nil)
		}

		func windowDidUpdate(_: Notification) {
			guard !didReportFirstVisibleUpdate, window.isVisible else { return }
			didReportFirstVisibleUpdate = true
			BrowserLog.notice(.lifecycle, "startup.window-first-appkit-update", metadata: [
				"window": BrowserLog.id(browser.windowID),
			])
			let callback = onFirstVisibleUpdate
			onFirstVisibleUpdate = nil
			callback?()
		}

		func windowDidBecomeKey(_: Notification) {
			BrowserWindowRegistry.shared.activate(browser)
		}

		func windowDidMove(_: Notification) {
			saveWindowFrame()
		}

		func windowDidEndLiveResize(_: Notification) {
			saveWindowFrame()
		}

		func windowDidExitFullScreen(_: Notification) {
			saveWindowFrame()
		}

		func saveWindowFrame() {
			guard !window.styleMask.contains(.fullScreen) else { return }
			let frame = window.frame
			browser.updateWindowFrame(BrowserWindowFrame(
				x: frame.origin.x,
				y: frame.origin.y,
				width: frame.width,
				height: frame.height
			))
		}

		func windowShouldClose(_ sender: NSWindow) -> Bool {
			guard !allowsClosing else { return true }
			guard !closeApprovalInFlight else { return false }
			closeApprovalInFlight = true
			Task { @MainActor in
				defer { closeApprovalInFlight = false }
				let hasUnsavedChanges = browser.tabs.contains(where: { tab in
					tab.controller?.hasUnsavedChanges == true || tab.peeks.contains { $0.controller.hasUnsavedChanges }
				})
				let hasProtectedMedia = browser.tabs.contains(where: { tab in
					tab.controller?.requiresMediaTeardownConfirmation == true
						|| tab.peeks.contains { $0.controller.requiresMediaTeardownConfirmation }
				})
				if hasUnsavedChanges || hasProtectedMedia {
					let message = hasUnsavedChanges && hasProtectedMedia
						? "Some tabs contain unsaved changes or media playback that will stop."
						: hasUnsavedChanges ? "Some tabs contain changes that may not be saved." : "Closing this window will stop media playback."
					let alert = BrowserWebsiteUI.alert(title: "Close this window?", message: message, confirm: "Close Window")
					guard await BrowserWebsiteUI.present(alert, in: sender) == .alertFirstButtonReturn else { return }
				}
				saveWindowFrame()
				await browser.flushAndWaitForPersistence()
				if let error = browser.persistenceErrorDescription {
					let alert = BrowserWebsiteUI.alert(title: "Close without saving?", message: error, confirm: "Close Without Saving")
					guard await BrowserWebsiteUI.present(alert, in: sender) == .alertFirstButtonReturn else { return }
				}
				allowsClosing = true
				sender.performClose(nil)
			}
			return false
		}

		func windowWillClose(_: Notification) {
			BrowserExtensionManager.shared.closeWindow(for: browser)
			BrowserWindowRegistry.shared.unregister(browser)
			browser.flushPersistence()
			for tab in browser.tabs {
				tab.stopForClose()
			}
			if browser.isPrivate {
				let session = browser.session
				Task { await session.endPrivateSession() }
			}
			window.contentView = nil
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
