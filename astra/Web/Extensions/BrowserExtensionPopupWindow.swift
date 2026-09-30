#if os(macOS)
	import AppKit
	import WebKit

	@MainActor
	final class BrowserExtensionPopupWindow: NSWindowController, NSWindowDelegate {
		private let action: WKWebExtension.Action
		private let popover: NSPopover
		var onClose: (() -> Void)?

		init?(action: WKWebExtension.Action, title: String) {
			guard let popover = action.popupPopover, let content = popover.contentViewController else { return nil }
			self.action = action
			self.popover = popover
			let window = NSPanel(
				contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
				styleMask: [.titled, .closable, .utilityWindow],
				backing: .buffered,
				defer: false
			)
			super.init(window: window)
			window.title = title
			window.isReleasedWhenClosed = false
			window.delegate = self
			window.hidesOnDeactivate = false
			window.collectionBehavior = [.fullScreenAuxiliary]
			window.standardWindowButton(.zoomButton)?.isHidden = true
			window.contentViewController = content
			let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 800, height: 900)
			let size = popover.contentSize
			window.setContentSize(NSSize(width: min(max(size.width, 320), available.width - 80), height: min(max(size.height, 300), available.height - 100)))
			window.center()
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		func windowWillClose(_: Notification) {
			action.closePopup()
			onClose?()
		}
	}
#endif
