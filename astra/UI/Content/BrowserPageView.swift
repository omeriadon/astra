import SwiftUI

struct BrowserPageView: View {
	let browser: Browser
	let cornerRadius: CGFloat
	var insets = BrowserViewportInsets()
	private var toastManager: ToastManager {
		browser.session.toastManager
	}

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var isLocalhost: Bool {
		browser.selectedTab?.activeController?.url?.host.map { host in
			host == "localhost"
				|| host.hasSuffix(".localhost")
				|| host == "127.0.0.1"
				|| host == "::1"
		} ?? false
	}

	var body: some View {
		ZStack(alignment: .top) {
			BrowserContentView(browser: browser, insets: insets)
			#if os(macOS)
				.opacity(BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser) ? 0.35 : 1)
				.allowsHitTesting(!BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser))
				.accessibilityHidden(BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser))
			#endif

			if let tab = browser.selectedTab,
			   !BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser),
			   !tab.peeks.isEmpty,
			   tab.activeController !== tab.controller
			{
				PeekStackView(tab: tab, browser: browser)
					.id(tab.id)
			}
		}
		.allowsHitTesting(!BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser))
		.overlay(alignment: .topTrailing) {
			if let controller = browser.selectedTab?.activeController, controller.showsFind {
				BrowserFindBar(controller: controller)
					.id(controller.id)
			}
		}
		.overlay(alignment: .topTrailing) {
			if let toast = toastManager.toast {
				BrowserToastView(toast: toast)
					.padding(.top, 12)
					.padding(.trailing, 14)
					.transition(reduceMotion ? .opacity : .move(edge: .trailing))
			}
		}
		.animation(.easeOut(duration: 0.1), value: toastManager.toast != nil)
		.allowsHitTesting(!BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser))
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
		.overlay {
			if isLocalhost {
				RoundedRectangle(cornerRadius: cornerRadius)
					.inset(by: -2)
					.strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 5]))
					.foregroundStyle(.yellow)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			}
		}
	}
}
