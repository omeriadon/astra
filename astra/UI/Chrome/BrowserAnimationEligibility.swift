import SwiftUI
#if os(macOS)
	import AppKit
#endif

/// Decorative animations share the owning window's actual render eligibility.
/// This changes no layout and does not treat a visible inactive window as hidden.
struct BrowserAnimationEligibility: ViewModifier {
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var windowVisible = false
	let update: (Bool) -> Void
	private var eligible: Bool {
		#if os(macOS)
			return windowVisible && !reduceMotion
		#else
			return scenePhase == .active && !reduceMotion
		#endif
	}

	func body(content: Content) -> some View {
		content
			.background {
				#if os(macOS)
					BrowserAnimationWindowReader { windowVisible = $0 }
				#endif
			}
			.onAppear { update(eligible) }
			.onChange(of: eligible) { _, value in update(value) }
			.onDisappear { update(false) }
	}
}

#if os(macOS)
	private struct BrowserAnimationWindowReader: NSViewRepresentable {
		let update: (Bool) -> Void
		func makeNSView(context _: Context) -> VisibilityView {
			VisibilityView()
		}

		func updateNSView(_ view: VisibilityView, context _: Context) {
			view.update = update; view.publishSoon()
		}

		static func dismantleNSView(_ view: VisibilityView, coordinator _: ()) {
			NotificationCenter.default.removeObserver(view)
			view.update = nil
		}

		final class VisibilityView: NSView {
			var update: ((Bool) -> Void)?
			private var pending = false
			private var lastValue: Bool?
			override func hitTest(_: NSPoint) -> NSView? {
				nil
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				NotificationCenter.default.removeObserver(self)
				for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
					NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: nil)
				}
				publishSoon()
			}

			@objc private func changed(_: Notification) {
				publishSoon()
			}

			func publishSoon() {
				guard !pending else { return }; pending = true
				DispatchQueue.main.async { [weak self] in
					guard let self else { return }; pending = false
					let window = unsafe window
					let value = !NSApp.isHidden && window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
					guard value != lastValue else { return }; lastValue = value; update?(value)
				}
			}
		}
	}
#endif
