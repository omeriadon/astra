#if os(macOS)
	import AppKit
	import Defaults
	import QuartzCore
	import SwiftUI

	@MainActor
	final class MiniAstraWindowController: NSObject, NSWindowDelegate {
		let browser = Browser(isMini: true)
		let window: NSPanel
		var onClose: (() -> Void)?
		var onPromote: ((BrowserTab) -> Void)?
		private let openingOrigin: NSPoint

		init(url: URL? = nil) {
			let cursor = NSEvent.mouseLocation
			openingOrigin = cursor
			let visibleFrame = NSScreen.screens.first { $0.frame.contains(cursor) }?.visibleFrame
				?? NSScreen.main?.visibleFrame
				?? NSRect(x: 0, y: 0, width: 1280, height: 800)
			let size = NSSize(width: min(760, visibleFrame.width), height: min(620, visibleFrame.height))
			window = MiniAstraWindow(
				contentRect: NSRect(
					x: visibleFrame.midX - size.width / 2,
					y: visibleFrame.midY - size.height / 2,
					width: size.width,
					height: size.height
				),
				styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
				backing: .buffered,
				defer: false
			)
			super.init()
			window.delegate = self
			window.title = "Mini Astra"
			window.titleVisibility = .hidden
			window.titlebarAppearsTransparent = true
			window.titlebarSeparatorStyle = .none
			window.contentMinSize = NSSize(width: 480, height: 320)
			window.tabbingMode = .disallowed
			window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
			window.isReleasedWhenClosed = false
			window.hidesOnDeactivate = false
			window.becomesKeyOnlyIfNeeded = false
			(window as? MiniAstraWindow)?.onPromote = { [weak self] in self?.promote() }
			let zoomButton = window.standardWindowButton(.zoomButton)
			zoomButton?.target = self
			zoomButton?.action = #selector(promote)
			zoomButton?.toolTip = "Move to Workspace"
			zoomButton?.setAccessibilityLabel("Move to Workspace")
			zoomButton?.setAccessibilityIdentifier("mini-astra-window-promote")
			let root = MiniAstraView(browser: browser)
			window.contentView = BrowserContentHostView(hostingView: NSHostingView(rootView: root))
			if let url {
				browser.selectedTab?.controller?.load(url)
			}
			#if DEBUG
				assert(BrowserWindowRegistry.shared.activeBrowser !== browser)
			#endif
		}

		func showWindow() {
			if window.isMiniaturized {
				window.deminiaturize(nil)
			}
			guard !window.isVisible,
			      Defaults[.miniAstraWindowAnimation],
			      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
			else {
				window.makeKeyAndOrderFront(nil)
				return
			}
			let destination = window.frame
			let minimumSize = window.contentMinSize
			window.contentMinSize = .zero
			window.setFrame(
				NSRect(x: openingOrigin.x, y: openingOrigin.y, width: 1, height: 1),
				display: false
			)
			window.alphaValue = 0
			window.makeKeyAndOrderFront(nil)
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.28
				context.timingFunction = CAMediaTimingFunction(name: .easeOut)
				window.animator().setFrame(destination, display: true)
				window.animator().alphaValue = 1
			} completionHandler: { [weak self] in
				self?.window.contentMinSize = minimumSize
			}
		}

		@objc func promote() {
			guard let tab = browser.selectedTab, let onPromote else { return }
			// Detach the hosted web view before the main window mounts the same controller.
			window.contentView = nil
			onPromote(tab)
			window.close()
		}

		func windowWillClose(_: Notification) {
			onClose?()
		}
	}

	private final class MiniAstraWindow: NSPanel {
		var onPromote: (() -> Void)?

		override var canBecomeKey: Bool {
			true
		}

		override var canBecomeMain: Bool {
			false
		}

		override func toggleFullScreen(_: Any?) {
			onPromote?()
		}

		override func zoom(_: Any?) {
			onPromote?()
		}
	}
#endif
