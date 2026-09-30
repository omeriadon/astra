#if os(macOS)
	import AppKit
	import Defaults
	import SwiftUI

	@MainActor
	final class MiniAstraWindowController: NSObject, NSWindowDelegate {
		let browser = Browser(isMini: true)
		let window: NSWindow
		var onClose: (() -> Void)?
		var onPromote: ((BrowserTab) -> Void)?
		private var cursorTask: Task<Void, Never>?

		init(url: URL? = nil) {
			let cursor = NSEvent.mouseLocation
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
				styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
			(window as? MiniAstraWindow)?.onPromote = { [weak self] in self?.promote() }
			let zoomButton = window.standardWindowButton(.zoomButton)
			zoomButton?.target = self
			zoomButton?.action = #selector(promote)
			zoomButton?.toolTip = "Move to Workspace"
			zoomButton?.setAccessibilityLabel("Move to Workspace")
			zoomButton?.setAccessibilityIdentifier("mini-astra-window-promote")
			let root = MiniAstraView(browser: browser) { [weak self] in self?.promote() }
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
			window.makeKeyAndOrderFront(nil)
			NSApp.activate()
			animateCursor()
		}

		@objc func promote() {
			guard let tab = browser.selectedTab, let onPromote else { return }
			cursorTask?.cancel()
			// Detach the hosted web view before the main window mounts the same controller.
			window.contentView = nil
			onPromote(tab)
			window.close()
		}

		func windowWillClose(_: Notification) {
			cursorTask?.cancel()
			onClose?()
		}

		private func animateCursor() {
			cursorTask?.cancel()
			guard Defaults[.miniAstraCursorAnimation],
			      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
			      let start = CGEvent(source: nil)?.location
			else { return }
			let target = CGPoint(
				x: window.frame.midX,
				y: CGDisplayBounds(CGMainDisplayID()).height - window.frame.midY
			)
			cursorTask = Task { @MainActor [weak self] in
				var previous = start
				for step in 1 ... 18 {
					guard let self, !Task.isCancelled, window.isKeyWindow,
					      Defaults[.miniAstraCursorAnimation],
					      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
					      let current = CGEvent(source: nil)?.location,
					      hypot(current.x - previous.x, current.y - previous.y) < 4
					else { return }
					let progress = Double(step) / 18
					let eased = progress * progress * (3 - 2 * progress)
					let point = CGPoint(
						x: start.x + (target.x - start.x) * eased,
						y: start.y + (target.y - start.y) * eased
					)
					guard CGWarpMouseCursorPosition(point) == .success else { return }
					previous = point
					try? await Task.sleep(for: .milliseconds(14))
				}
			}
		}
	}

	private final class MiniAstraWindow: NSWindow {
		var onPromote: (() -> Void)?

		override func toggleFullScreen(_: Any?) {
			onPromote?()
		}

		override func zoom(_: Any?) {
			onPromote?()
		}
	}
#endif
