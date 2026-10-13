#if os(macOS)
	import AppKit
	import SwiftUI

	struct EaselTextEditor: NSViewRepresentable {
		@Binding var text: String
		let fontName: String
		let fontSize: CGFloat
		let color: NSColor
		let onSelect: () -> Void
		let onFinish: () -> Void

		func makeNSView(context: Context) -> TextView {
			let view = TextView()
			view.delegate = context.coordinator
			view.onFinish = onFinish
			view.isRichText = false
			view.allowsUndo = true
			view.drawsBackground = false
			view.isHorizontallyResizable = false
			view.isVerticallyResizable = false
			view.textContainerInset = .zero
			view.textContainer?.lineFragmentPadding = 0
			view.textContainer?.widthTracksTextView = true
			view.setAccessibilityLabel("Easel text")
			return view
		}

		func updateNSView(_ view: TextView, context: Context) {
			context.coordinator.parent = self
			view.onSelect = onSelect
			view.onFinish = onFinish
			if view.string != text {
				view.string = text
			}
			let desiredFont = NSFont(name: fontName, size: fontSize)
				?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
			if view.font != desiredFont {
				view.font = desiredFont
			}
			if view.textColor != color {
				view.textColor = color
			}
			// NSTextView manages its own wrapping within the fixed item frame.
			// Do not call ensureLayout or mutate the text container from sizeThatFits:
			// doing so during SwiftUI measurement can recurse into AppKit constraints.
		}

		func makeCoordinator() -> Coordinator {
			Coordinator(parent: self)
		}

		final class TextView: NSTextView {
			var onSelect: (() -> Void)?
			var onFinish: (() -> Void)?

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				guard window != nil else { return }
				DispatchQueue.main.async { [weak self] in
					guard let self, let window = self.window else { return }
					window.makeFirstResponder(self)
				}
			}

			override func becomeFirstResponder() -> Bool {
				let accepted = super.becomeFirstResponder()
				if accepted { onSelect?() }
				return accepted
			}

			override func cancelOperation(_ sender: Any?) {
				onFinish?()
			}
		}

		final class Coordinator: NSObject, NSTextViewDelegate {
			var parent: EaselTextEditor

			init(parent: EaselTextEditor) {
				self.parent = parent
			}

			func textDidChange(_ notification: Notification) {
				guard let view = notification.object as? NSTextView else { return }
				parent.text = view.string
			}
		}
	}
#endif