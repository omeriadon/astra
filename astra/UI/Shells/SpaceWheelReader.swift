#if os(macOS)
	import AppKit
	import SwiftUI

	struct SpaceWheelReader: NSViewRepresentable {
		let sidebarShown: Bool
		let onScroll: (NSEvent) -> Void

		func makeNSView(context _: Context) -> WheelView {
			WheelView(onScroll: onScroll)
		}

		func updateNSView(_ view: WheelView, context _: Context) {
			view.sidebarShown = sidebarShown
			view.onScroll = onScroll
		}

		final class WheelView: NSView {
			var sidebarShown = true
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
				monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
					let horizontalDelta = event.type == .swipe ? event.deltaX : event.scrollingDeltaX
					let verticalDelta = event.type == .swipe ? event.deltaY : event.scrollingDeltaY
					guard let self,
					      event.window === window,
					      sidebarShown,
					      (0 ... BrowserChromeMetrics.expandedSidebarWidth).contains(event.locationInWindow.x),
					      abs(horizontalDelta) > max(0.5, abs(verticalDelta) * 0.75),
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
