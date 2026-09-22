import Defaults
import SwiftUI

struct PeekCardView: View {
	let peek: BrowserPeek
	let viewportSize: CGSize
	let isTopmost: Bool
	let onDismiss: () -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var isPresented = false

	private var cardSize: CGSize {
		cardSize(for: peek.depth)
	}

	private var sourcePoint: CGPoint {
		if peek.depth == 1 {
			return CGPoint(
				x: viewportSize.width * peek.source.x,
				y: viewportSize.height * peek.source.y
			)
		}

		let parentSize = cardSize(for: peek.depth - 1)
		return CGPoint(
			x: (viewportSize.width - parentSize.width) / 2 + parentSize.width * peek.source.x,
			y: (viewportSize.height - parentSize.height) / 2 + parentSize.height * peek.source.y
		)
	}

	private var sourceOffset: CGSize {
		CGSize(
			width: sourcePoint.x - viewportSize.width / 2,
			height: sourcePoint.y - viewportSize.height / 2
		)
	}

	private func cardSize(for depth: Int) -> CGSize {
		let baseScale = depth == 1 ? 0.78 : 0.70
		let zoomScale = if Defaults[.zoomOutInPeeks] {
			depth == 1 ? 0.95 : 0.85
		} else {
			1.0
		}

		return CGSize(
			width: min(980, viewportSize.width * baseScale * zoomScale),
			height: min(760, viewportSize.height * baseScale * zoomScale)
		)
	}

	var body: some View {
		BrowserWebView(controller: peek.controller)
			.frame(width: cardSize.width, height: cardSize.height)
			.clipShape(.rect(cornerRadius: 16))
			.overlay(alignment: .topTrailing) {
				Button("Close Peek", systemImage: "xmark", action: dismiss)
					.labelStyle(.iconOnly)
					.buttonStyle(.glass)
					.padding(12)
					.accessibilityIdentifier("close-peek-(peek.depth)")
			}
			.shadow(color: .black.opacity(0.38), radius: 32, y: 18)
			.scaleEffect(reduceMotion || isPresented ? 1 : 0.04)
			.offset(reduceMotion || isPresented ? .zero : sourceOffset)
			.opacity(isPresented ? 1 : 0)
			.allowsHitTesting(isTopmost)
			.accessibilityHidden(!isTopmost)
			.task {
				withAnimation(presentationAnimation) {
					isPresented = true
				}
			}
	}

	private var presentationAnimation: Animation {
		reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.42)
	}

	private func dismiss() {
		withAnimation(presentationAnimation, completionCriteria: .logicallyComplete) {
			isPresented = false
		} completion: {
			onDismiss()
		}
	}
}
