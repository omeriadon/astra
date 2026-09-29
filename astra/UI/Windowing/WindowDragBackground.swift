#if os(macOS)
	import AppKit
	import SwiftUI

	struct WindowDragBackground: NSViewRepresentable {
		func makeNSView(context _: Context) -> DragView {
			DragView(frame: .zero)
		}

		func updateNSView(_: DragView, context _: Context) {}

		final class DragView: NSView {
			override var mouseDownCanMoveWindow: Bool {
				false
			}

			override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
				true
			}

			override func mouseDown(with event: NSEvent) {
				window?.performDrag(with: event)
			}
		}
	}
#endif
