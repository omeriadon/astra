#if os(macOS)
	import AppKit
	import SwiftUI

	struct WindowFocusReader: NSViewRepresentable {
		let onWindow: (NSWindow?) -> Void

		func makeNSView(context _: Context) -> FocusView {
			FocusView(onWindow: onWindow)
		}

		func updateNSView(_ view: FocusView, context _: Context) {
			view.onWindow = onWindow
		}

		final class FocusView: NSView {
			var onWindow: (NSWindow?) -> Void

			init(onWindow: @escaping (NSWindow?) -> Void) {
				self.onWindow = onWindow
				super.init(frame: .zero)
			}

			@available(*, unavailable)
			required init?(coder _: NSCoder) {
				fatalError("init(coder:) is unavailable")
			}

			override func hitTest(_: NSPoint) -> NSView? {
				nil
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				window?.isMovable = false
				onWindow(window)
			}
		}
	}
#endif
