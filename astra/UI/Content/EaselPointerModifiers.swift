#if os(macOS)
	import AppKit
	import SwiftUI

	struct EaselPointerModifiers: NSViewRepresentable {
		let onChange: (Bool) -> Void

		func makeNSView(context _: Context) -> PointerView {
			PointerView()
		}

		func updateNSView(_ view: PointerView, context _: Context) {
			view.onChange = onChange
		}

		final class PointerView: NSView {
			var onChange: ((Bool) -> Void)?
			private var monitor: Any?

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				if let monitor {
					NSEvent.removeMonitor(monitor)
					self.monitor = nil
				}
				guard window != nil else { return }
				monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
					if let self, let window, event.window === window {
						// Button actions can run after mouse-up, so retain the pointer event's modifiers.
						onChange?(event.modifierFlags.contains(.shift))
					}
					return event
				}
			}
		}
	}
#endif
