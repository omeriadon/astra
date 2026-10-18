#if os(macOS)
import AppKit
import SwiftUI

/// Install only while a tab is hovered. SwiftUI's .global coordinates are local
/// to each hosting root; native reused cells need a common window coordinate
/// space. Clip movement updates the preview without invalidating every row.
struct BrowserWindowFrameReader: NSViewRepresentable {
	let onFrame: (CGRect) -> Void

	func makeNSView(context: Context) -> FrameView { FrameView() }
	func updateNSView(_ view: FrameView, context: Context) {
		view.onFrame = onFrame
		view.publishSoon()
	}
	static func dismantleNSView(_ view: FrameView, coordinator: ()) {
		NotificationCenter.default.removeObserver(view)
		view.onFrame = nil
	}

	final class FrameView: NSView {
		var onFrame: ((CGRect) -> Void)?
		private var publicationPending = false
		private var lastFrame: CGRect?

		override func hitTest(_ point: NSPoint) -> NSView? { nil }

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			NotificationCenter.default.removeObserver(self)
			if let scroll = enclosingScrollView {
				scroll.contentView.postsBoundsChangedNotifications = true
				NotificationCenter.default.addObserver(self, selector: #selector(geometryChanged), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
			}
			if let window = unsafe window {
				NotificationCenter.default.addObserver(self, selector: #selector(geometryChanged), name: NSWindow.didResizeNotification, object: window)
			}
			publishSoon()
		}

		override func layout() {
			super.layout()
			publishSoon()
		}

		@objc private func geometryChanged(_ notification: Notification) { publishSoon() }

		func publishSoon() {
			guard !publicationPending else { return }
			publicationPending = true
			DispatchQueue.main.async { [weak self] in
				guard let self else { return }
				publicationPending = false
				guard let content = unsafe window?.contentView, onFrame != nil else { return }
				var rect = convert(bounds, to: content)
				if !content.isFlipped { rect.origin.y = content.bounds.maxY - rect.maxY }
				guard rect != lastFrame else { return }
				lastFrame = rect
				onFrame?(rect)
			}
		}
	}
}
#endif
