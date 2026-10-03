#if os(macOS)
	import AppKit
	import SwiftUI

	struct NonDraggableTitlebarRegion: NSViewRepresentable {
		func makeNSView(context _: Context) -> RegionView {
			RegionView(frame: .zero)
		}

		func updateNSView(_ view: RegionView, context _: Context) {
			view.invalidateWindowDragRegion()
		}

		final class RegionView: NSView {
			override var mouseDownCanMoveWindow: Bool {
				false
			}

			override func hitTest(_: NSPoint) -> NSView? {
				nil
			}

			@objc(_opaqueRectForWindowMoveWhenInTitlebar)
			func opaqueRectForWindowMoveWhenInTitlebar() -> NSRect {
				bounds
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				invalidateWindowDragRegion()
			}

			override func setFrameSize(_ newSize: NSSize) {
				super.setFrameSize(newSize)
				invalidateWindowDragRegion()
			}

			func invalidateWindowDragRegion() {
				guard let window else { return }

				// AppKit caches the draggable area assembled from visible views.
				// Reassigning this property to false causes that area to be rebuilt.
				window.isMovableByWindowBackground = false
			}
		}
	}
#endif
