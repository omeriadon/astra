#if os(macOS)
	import AppKit
	import SwiftUI

	struct SpaceWheelReader: NSViewRepresentable {
		let sidebarShown: Bool
		let hasPreviousSpace: Bool
		let hasNextSpace: Bool
		let onSwipe: (CGFloat, Bool) -> Void

		func makeNSView(context _: Context) -> WheelView {
			WheelView(onSwipe: onSwipe)
		}

		func updateNSView(_ view: WheelView, context _: Context) {
			view.sidebarShown = sidebarShown
			view.hasPreviousSpace = hasPreviousSpace
			view.hasNextSpace = hasNextSpace
			view.onSwipe = onSwipe
		}

		final class WheelView: NSView {
			var sidebarShown = true
			var hasPreviousSpace = false
			var hasNextSpace = false
			var onSwipe: (CGFloat, Bool) -> Void
			private var monitor: Any?
			private var gestureX: CGFloat = 0
			private var gestureY: CGFloat = 0
			private var lockedVertically = false
			private var trackingSwipe = false

			init(onSwipe: @escaping (CGFloat, Bool) -> Void) {
				self.onSwipe = onSwipe
				super.init(frame: .zero)
			}

			@available(*, unavailable)
			required init?(coder _: NSCoder) {
				fatalError("init(coder:) is unavailable")
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				gestureX = 0
				gestureY = 0
				lockedVertically = false
				trackingSwipe = false
				if let monitor {
					NSEvent.removeMonitor(monitor)
					self.monitor = nil
				}
				guard window != nil else { return }
				monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
					guard let self,
					      event.window === window,
					      sidebarShown,
					      NSEvent.isSwipeTrackingFromScrollEventsEnabled,
					      event.hasPreciseScrollingDeltas,
					      event.momentumPhase.isEmpty
					else { return event }
					if trackingSwipe {
						return nil
					}
					if event.phase.contains(.began) {
						gestureX = 0
						gestureY = 0
						lockedVertically = false
					}
					if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
						return event
					}
					guard !lockedVertically,
					      (0 ... BrowserChromeMetrics.expandedSidebarWidth).contains(event.locationInWindow.x),
					      event.phase.contains(.began) || event.phase.contains(.changed)
					else { return event }
					gestureX += event.scrollingDeltaX
					gestureY += event.scrollingDeltaY
					guard max(abs(gestureX), abs(gestureY)) >= 8 else { return event }
					guard abs(gestureX) > abs(gestureY) * 1.5 else {
						lockedVertically = true
						return event
					}
					trackingSwipe = true
					event.trackSwipeEvent(
						options: .clampGestureAmount,
						dampenAmountThresholdMin: hasPreviousSpace ? -1 : 0,
						max: hasNextSpace ? 1 : 0
					) { [weak self] amount, _, isComplete, _ in
						guard let self else { return }
						onSwipe(amount, isComplete)
						if isComplete {
							trackingSwipe = false
							gestureX = 0
							gestureY = 0
						}
					}
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
