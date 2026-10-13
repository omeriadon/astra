#if os(macOS)
	import AppKit
	import SwiftUI

	struct EaselTextEditor: NSViewRepresentable {
		@Binding var text: String
		let fontName: String
		let fontSize: CGFloat
		let color: NSColor
		let onSelect: () -> Void

		func makeNSView(context: Context) -> TextView {
			let view = TextView()
			view.delegate = context.coordinator
			view.isRichText = false
			view.allowsUndo = true
			view.drawsBackground = false
			view.isHorizontallyResizable = false
			view.isVerticallyResizable = true
			view.textContainerInset = .zero
			view.textContainer?.lineFragmentPadding = 0
			view.textContainer?.widthTracksTextView = true
			view.setAccessibilityLabel("Easel text")
			return view
		}

		func updateNSView(_ view: TextView, context: Context) {
			view.onSelect = onSelect
			context.coordinator.parent = self
			if view.string != text {
				view.string = text
			}
			view.font = NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
			view.textColor = color
			let paragraph = NSMutableParagraphStyle()
			paragraph.lineHeightMultiple = 1.5
			view.defaultParagraphStyle = paragraph
			view.typingAttributes = [.font: view.font!, .foregroundColor: color, .paragraphStyle: paragraph]
			if let storage = view.textStorage, storage.length > 0 {
				storage.addAttributes(view.typingAttributes, range: NSRange(location: 0, length: storage.length))
			}
		}

		func sizeThatFits(_ proposal: ProposedViewSize, nsView view: TextView, context _: Context) -> CGSize? {
			let width = proposal.width ?? 224
			view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
			guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
			layout.ensureLayout(for: container)
			let height = layout.usedRect(for: container).height
			return CGSize(width: width, height: max(height + 4, fontSize * 1.5 + 4))
		}

		func makeCoordinator() -> Coordinator {
			Coordinator(parent: self)
		}

		final class TextView: NSTextView {
			var onSelect: (() -> Void)?

			override func becomeFirstResponder() -> Bool {
				let accepted = super.becomeFirstResponder()
				if accepted {
					onSelect?()
				}
				return accepted
			}

			override func mouseDown(with event: NSEvent) {
				onSelect?()
				super.mouseDown(with: event)
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
