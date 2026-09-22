import SwiftUI

struct PeekStackView: View {
	let browser: Browser

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				ForEach(browser.peeks) { peek in
					Color.black
						.opacity(peek.depth == 1 ? 0.42 : 0.24)
						.allowsHitTesting(false)

					PeekCardView(
						peek: peek,
						viewportSize: proxy.size,
						isTopmost: peek.id == browser.peeks.last?.id,
						onDismiss: {
							browser.dismissPeek(peek.id)
						}
					)
					.id(peek.id)
				}
			}
			.animation(.easeOut(duration: 0.2), value: browser.peeks.count)
		}
		.allowsHitTesting(!browser.peeks.isEmpty)
		.accessibilityIdentifier("peek-stack")
	}
}
