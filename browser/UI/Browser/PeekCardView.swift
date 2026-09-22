import SwiftUI

struct PeekCardView: View {
	let peek: BrowserPeek
	let viewportSize: CGSize
	let isTopmost: Bool
	let onDismiss: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var isPresented: Bool

	init(
		peek: BrowserPeek,
		viewportSize: CGSize,
		isTopmost: Bool,
		onDismiss: @escaping () -> Void
	) {
		self.peek = peek
		self.viewportSize = viewportSize
		self.isTopmost = isTopmost
		self.onDismiss = onDismiss
		_isPresented = State(initialValue: peek.hasPresented)
	}

	private var sourcePoint: CGPoint {
		if peek.depth == 1 {
			return CGPoint(
				x: viewportSize.width * peek.source.x,
				y: viewportSize.height * peek.source.y
			)
		}

		let parentRect = cardRect(for: peek.depth - 1)
		return CGPoint(
			x: parentRect.minX + parentRect.width * peek.source.x,
			y: parentRect.minY + parentRect.height * peek.source.y
		)
	}

	private var sourceOffset: CGSize {
		CGSize(
			width: sourcePoint.x - cardRect.midX,
			height: sourcePoint.y - cardRect.midY
		)
	}

	private var cardRect: CGRect {
		cardRect(for: peek.depth)
	}

	private var cornerRadius: CGFloat {
		min(max(min(viewportSize.width, viewportSize.height) * 0.035, 20), 42)
	}

	private func cardRect(for depth: Int) -> CGRect {
		let horizontalInset = viewportSize.width * 0.07
		let topInset = viewportSize.height * 0.02
		let bottomInset = viewportSize.height * 0.04
		let firstPeekRect = CGRect(
			x: horizontalInset,
			y: topInset,
			width: max(0, viewportSize.width - horizontalInset * 2),
			height: max(0, viewportSize.height - topInset - bottomInset)
		)

		guard depth > 1 else { return firstPeekRect }
		let offset = min(max(min(viewportSize.width, viewportSize.height) * 0.025, 20), 32)
		return firstPeekRect.offsetBy(dx: offset, dy: offset)
	}

	var body: some View {
		BrowserWebView(controller: peek.controller)
			.frame(width: cardRect.width, height: cardRect.height)
			.clipShape(.rect(cornerRadius: cornerRadius))
			.overlay(alignment: .topLeading) {
				if isTopmost {
					Button("Close Peek", systemImage: "xmark", action: dismiss)
						.labelStyle(.iconOnly)
						.frame(width: 52, height: 52)
						.buttonStyle(.glass)
						.buttonBorderShape(.circle)
						.offset(x: -26, y: 16)
						.accessibilityIdentifier("close-peek-\(peek.depth)")
				}
			}
			.shadow(color: .black.opacity(0.38), radius: 32, y: 18)
			.position(x: cardRect.midX, y: cardRect.midY)
			.scaleEffect(reduceMotion || isPresented ? 1 : 0.04)
			.offset(reduceMotion || isPresented ? .zero : sourceOffset)
			.opacity(isPresented ? 1 : 0)
			.allowsHitTesting(isTopmost)
			.accessibilityHidden(!isTopmost)
			.task {
				guard !peek.hasPresented else { return }
				withAnimation(presentationAnimation) {
					isPresented = true
				}
				peek.hasPresented = true
			}
	}

	private var presentationAnimation: Animation {
		reduceMotion ? .easeOut(duration: 0.1) : .smooth(duration: 0.24)
	}

	private func dismiss() {
		withAnimation(presentationAnimation, completionCriteria: .logicallyComplete) {
			isPresented = false
		} completion: {
			onDismiss()
		}
	}
}
