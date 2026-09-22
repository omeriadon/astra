import SwiftUI

struct PeekStackView: View {
	let tab: BrowserTab

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				ForEach(tab.peeks) { peek in
					Button("Dismiss Peek", systemImage: "xmark") {
						dismiss(peek)
					}
					.labelStyle(.iconOnly)
					.buttonStyle(.plain)
					.foregroundStyle(.clear)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(.black.opacity(0.35))
					.contentShape(Rectangle())
					.accessibilityLabel("Dismiss Peek")

					PeekCardView(
						peek: peek,
						viewportSize: proxy.size,
						isTopmost: peek.id == tab.peeks.last?.id,
						onDismiss: {
							tab.dismissPeek(peek.id)
						}
					)
					.id(peek.id)
					.transition(.opacity)
				}
			}
			.animation(.easeOut(duration: 0.2), value: tab.peeks.count)
		}
		.allowsHitTesting(!tab.peeks.isEmpty)
		.accessibilityIdentifier("peek-stack")
		#if os(macOS)
			.onExitCommand(perform: dismissTopPeek)
		#endif
	}

	private func dismiss(_ peek: BrowserPeek) {
		withAnimation(.easeOut(duration: 0.18)) {
			tab.dismissPeek(peek.id)
		}
	}

	private func dismissTopPeek() {
		guard let peek = tab.peeks.last else { return }
		dismiss(peek)
	}
}
