import SwiftUI

struct PeekStackView: View {
	let tab: BrowserTab
	let browser: Browser

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				ForEach(tab.peeks) { peek in
					PeekInputShield(
						isTopmost: peek.id == tab.peeks.last?.id,
						onDismiss: dismissTopPeek
					)
					.frame(width: proxy.size.width, height: proxy.size.height)
					.opacity(peek.isPresented ? 1 : 0)
					.accessibilityLabel("Dismiss Peek")
					.accessibilityIdentifier("dismiss-peek-\(peek.depth)")

					PeekCardView(
						peek: peek,
						viewportSize: proxy.size,
						isTopmost: peek.id == tab.peeks.last?.id,
						onDismiss: {
							guard tab.peeks.last?.id == peek.id else { return }
							dismissTopPeek()
						},
						onPromote: {
							browser.promotePeek(in: tab, id: peek.id)
						},
						onDismissCompleted: {
							tab.dismissPeek(peek.id)
						}
					)
					.id(peek.id)
				}
			}
			.frame(width: proxy.size.width, height: proxy.size.height)
		}
		.allowsHitTesting(!tab.peeks.isEmpty)
		.accessibilityIdentifier("peek-stack")
		#if os(iOS)
			.overlay {
				if !tab.peeks.isEmpty {
					Button("Dismiss Peek", systemImage: "xmark", action: dismissTopPeek)
						.keyboardShortcut(.cancelAction)
						.hidden()
				}
			}
		#endif
	}

	private func dismissTopPeek() {
		tab.requestPeekDismissal()
	}
}

#if os(macOS)
	import AppKit

	private struct PeekInputShield: NSViewRepresentable {
		let isTopmost: Bool
		let onDismiss: () -> Void

		func makeNSView(context _: Context) -> ShieldView {
			ShieldView()
		}

		func updateNSView(_ view: ShieldView, context _: Context) {
			view.isTopmost = isTopmost
			view.onDismiss = onDismiss
		}

		final class ShieldView: NSView {
			var isTopmost = false
			var onDismiss: (() -> Void)?
			private var escapeMonitor: Any?

			override init(frame: NSRect) {
				super.init(frame: frame)
				wantsLayer = true
				layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
				setAccessibilityRole(.button)
				setAccessibilityLabel("Dismiss Peek")
			}

			@available(*, unavailable)
			required init?(coder _: NSCoder) {
				fatalError("init(coder:) has not been implemented")
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				if let escapeMonitor {
					NSEvent.removeMonitor(escapeMonitor)
					self.escapeMonitor = nil
				}
				guard window != nil else { return }
				escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
					guard let self,
					      isTopmost,
					      let window,
					      event.window === window,
					      event.keyCode == 53
					else { return event }
					onDismiss?()
					return nil
				}
			}

			override func mouseDown(with _: NSEvent) {
				if isTopmost {
					onDismiss?()
				}
			}

			override func scrollWheel(with _: NSEvent) {}
			override func magnify(with _: NSEvent) {}
			override func rotate(with _: NSEvent) {}
			override func swipe(with _: NSEvent) {}

			override func accessibilityPerformPress() -> Bool {
				guard isTopmost else { return false }
				onDismiss?()
				return true
			}
		}
	}
#elseif os(iOS)
	import UIKit

	private struct PeekInputShield: UIViewRepresentable {
		let isTopmost: Bool
		let onDismiss: () -> Void

		func makeUIView(context _: Context) -> ShieldView {
			let view = ShieldView()
			view.backgroundColor = UIColor.black.withAlphaComponent(0.35)
			view.isAccessibilityElement = true
			view.accessibilityTraits = .button
			view.accessibilityLabel = "Dismiss Peek"
			view.addTarget(view, action: #selector(ShieldView.dismissPeek), for: .touchUpInside)
			return view
		}

		func updateUIView(_ view: ShieldView, context _: Context) {
			view.isTopmost = isTopmost
			view.onDismiss = onDismiss
		}

		final class ShieldView: UIControl {
			var isTopmost = false
			var onDismiss: (() -> Void)?

			@objc func dismissPeek() {
				if isTopmost {
					onDismiss?()
				}
			}

			override func accessibilityActivate() -> Bool {
				guard isTopmost else { return false }
				onDismiss?()
				return true
			}
		}
	}
#endif
