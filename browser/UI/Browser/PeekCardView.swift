import SwiftUI

struct PeekCardView: View {
	let peek: BrowserPeek
	let viewportSize: CGSize
	let isTopmost: Bool
	let onDismiss: () -> Void
	let onPromote: () -> Void
	let onDismissCompleted: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Namespace private var controlsNamespace
	@State private var showsWebContent = false
	@State private var showsPlaceholder = true

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
		ZStack {
			BrowserWebView(controller: peek.controller)
				.clipShape(.rect(cornerRadius: cornerRadius))
				.opacity(showsWebContent ? 1 : 0)

			if showsPlaceholder {
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(peek.controller.themeColor ?? .black)
					.scaleEffect(reduceMotion || peek.isPresented ? 1 : 0.001)
					.offset(reduceMotion || peek.isPresented ? .zero : sourceOffset)
					.transition(.opacity)
			}
		}
		.frame(width: cardRect.width, height: cardRect.height)
		.overlay(alignment: .topLeading) {
			GlassEffectContainer(spacing: 10) {
				VStack(spacing: 10) {
					if isTopmost, !showsPlaceholder {
						peekButton("Close Peek", symbol: "xmark", identifier: "close-peek", action: dismiss)
						peekButton("Open Peek in New Tab", symbol: "arrow.up.left.and.arrow.down.right", identifier: "promote-peek", action: promote)
					}
				}
			}
			.animation(controlsAnimation, value: isTopmost)
			.offset(x: -controlSize - 15, y: 16)
		}
//			.shadow(color: .black.opacity(0.38), radius: 32, y: 18)
		.position(x: cardRect.midX, y: cardRect.midY)
		.allowsHitTesting(showsWebContent && isTopmost && !peek.isDismissing)
		.accessibilityHidden(!isTopmost)
		.task {
			guard !peek.hasPresented else {
				showsWebContent = true
				showsPlaceholder = false
				return
			}
			await Task.yield()
			guard !Task.isCancelled else { return }
			withAnimation(presentationAnimation, completionCriteria: .logicallyComplete) {
				peek.isPresented = true
			} completion: {
				withAnimation(nil) {
					showsWebContent = true
				}
				withAnimation(.easeIn(duration: reduceMotion ? 0.01 : 0.2)) {
					showsPlaceholder = false
				}
			}
			peek.hasPresented = true
		}
		.onChange(of: peek.isDismissing) { _, dismissing in
			guard dismissing else { return }
			withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.2), completionCriteria: .removed) {
				showsPlaceholder = true
			} completion: {
				withAnimation(nil) {
					showsWebContent = false
				}
				withAnimation(.easeOut(duration: reduceMotion ? 0.08 : 0.1), completionCriteria: .removed) {
					peek.isPresented = false
				} completion: {
					onDismissCompleted()
				}
			}
		}
	}

	private var presentationAnimation: Animation {
		reduceMotion ? .easeOut(duration: 0.08) : .spring(duration: 0.2, bounce: 0.2)
	}

	private var controlsAnimation: Animation {
		.easeOut(duration: reduceMotion ? 0.01 : 0.2)
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
		.glassEffectID(identifier, in: controlsNamespace)
		.glassEffectTransition(.materialize)
		.accessibilityLabel(title)
		.accessibilityIdentifier("\(identifier)-\(peek.depth)")
	}

	private func dismiss() {
		onDismiss()
	}

	private func promote() {
		withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.2), completionCriteria: .removed) {
			showsPlaceholder = true
		} completion: {
			withAnimation(nil) {
				showsWebContent = false
			}
			onPromote()
		}
	}
}
