import SwiftUI

struct CompactBrowserShell: View {
	let browser: Browser
	@State private var toastManager = ToastManager.shared

	var body: some View {
		VStack(spacing: 0) {
			BrowserContentView(browser: browser)
				.overlay {
					if let tab = browser.selectedTab {
						PeekStackView(tab: tab, browser: browser)
							.id(tab.id)
					}
				}
				.overlay(alignment: .topTrailing) {
					if let toast = toastManager.toast {
						BrowserToastView(toast: toast)
							.padding(12)
							.transition(.move(edge: .trailing))
					}
				}
				.animation(.easeOut(duration: 0.1), value: toastManager.toast != nil)
				.clipShape(RoundedRectangle(cornerRadius: 28))
				.padding(10)
				.frame(maxWidth: .infinity, maxHeight: .infinity)

			HStack(spacing: 16) {
				Capsule()
					.fill(.gray.opacity(0.35))
					.frame(width: 40, height: 40)

				Capsule()
					.fill(.gray.opacity(0.35))
					.frame(maxWidth: .infinity)
					.frame(height: 40)

				Capsule()
					.fill(.gray.opacity(0.35))
					.frame(width: 40, height: 40)
			}
			.padding(.horizontal, 24)
			.padding(.vertical, 12)
			.background(.tint.opacity(0.9))
		}
		.background(.tint.opacity(0.9))
	}
}

#Preview {
	CompactBrowserShell(browser: Browser())
}
