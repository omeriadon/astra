#if os(macOS)
	import AppKit
	import SwiftUI

	struct SpaceWheelReader: NSViewRepresentable {
		let onScroll: (NSEvent) -> Void

		func makeNSView(context _: Context) -> WheelView {
			WheelView(onScroll: onScroll)
		}

		func updateNSView(_ view: WheelView, context _: Context) {
			view.onScroll = onScroll
		}

		final class WheelView: NSView {
			var onScroll: (NSEvent) -> Void
			private var monitor: Any?

			init(onScroll: @escaping (NSEvent) -> Void) {
				self.onScroll = onScroll
				super.init(frame: .zero)
			}

			@available(*, unavailable)
			required init?(coder _: NSCoder) {
				fatalError("init(coder:) is unavailable")
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				if let monitor {
					NSEvent.removeMonitor(monitor)
					self.monitor = nil
				}
				guard window != nil else { return }
				monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
					guard let self,
					      event.window === window,
					      bounds.contains(convert(event.locationInWindow, from: nil)),
					      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
					      event.momentumPhase.isEmpty
					else { return event }
					onScroll(event)
					return nil
				}
			}

			deinit {
				if let monitor {
					NSEvent.removeMonitor(monitor)
				}
			}
		}
	}
#endif
