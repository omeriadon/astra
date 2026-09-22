import SwiftUI

struct PeekCardView: View {
	let peek: BrowserPeek
	let viewportSize: CGSize
	let isTopmost: Bool
	let onDismiss: () -> Void
	let onPromote: () -> Void
	let onDismissCompleted: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

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
		var rect = CGRect(origin: .zero, size: viewportSize)
		for _ in 0 ..< max(depth, 0) {
			let horizontalInset = min(max(rect.width * 0.07, 72), rect.width * 0.25)
			rect = rect.insetBy(dx: horizontalInset, dy: rect.height * 0.03)
		}
		return rect
	}

	var body: some View {
		BrowserWebView(controller: peek.controller)
			.frame(width: cardRect.width, height: cardRect.height)
			.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
			.overlay(alignment: .topLeading) {
				if isTopmost {
					VStack(spacing: 10) {
						peekButton("Close Peek", symbol: "xmark", identifier: "close-peek", action: dismiss)
						peekButton("Open Peek in New Tab", symbol: "arrow.up.left.and.arrow.down.right", identifier: "promote-peek", action: onPromote)
					}
					.offset(x: -controlSize - 15, y: 16)
				}
			}
//			.shadow(color: .black.opacity(0.38), radius: 32, y: 18)
			.offset(reduceMotion || peek.isPresented ? .zero : sourceOffset)
			.position(x: cardRect.midX, y: cardRect.midY)
			.opacity(reduceMotion && !peek.isPresented ? 0 : 1)
			.allowsHitTesting(isTopmost && !peek.isDismissing)
			.accessibilityHidden(!isTopmost)
			.task {
				guard !peek.hasPresented else { return }
				await Task.yield()
				guard !Task.isCancelled else { return }
				withAnimation(presentationAnimation) {
					peek.isPresented = true
				}
				peek.hasPresented = true
			}
			.onChange(of: peek.isDismissing) { _, dismissing in
				guard dismissing else { return }
				withAnimation(.easeOut(duration: reduceMotion ? 0.08 : 0.1), completionCriteria: .removed) {
					peek.isPresented = false
				} completion: {
					onDismissCompleted()
				}
			}
	}

	private var presentationAnimation: Animation {
		reduceMotion ? .easeOut(duration: 0.08) : .spring(duration: 0.2, bounce: 0.2)
	}

	private var controlSize: CGFloat {
		min(40, max(24, cardRect.minX - 12))
	}

	private func peekButton(_ title: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Label(title, systemImage: symbol)
				.labelStyle(.iconOnly)
				.font(.system(size: 20, weight: .medium))
				.frame(width: controlSize, height: controlSize)
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.glassEffect(.regular.interactive(), in: .circle)
		.accessibilityLabel(title)
		.accessibilityIdentifier("\(identifier)-\(peek.depth)")
	}

	private func dismiss() {
		onDismiss()
	}
}
