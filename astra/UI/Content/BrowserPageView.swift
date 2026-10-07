import SwiftUI

struct BrowserPageView: View {
	let browser: Browser
	let cornerRadius: CGFloat
	var insets = BrowserViewportInsets()
	private var toastManager: ToastManager {
		browser.session.toastManager
	}

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack(alignment: .top) {
			BrowserContentView(browser: browser, insets: insets)
			#if os(macOS)
				.blur(radius: BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser) ? 10 : 0)
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
		.accessibilityHidden(browser.selectedTab?.activeController?.readerHTML != nil)
		.overlay {
			if let controller = browser.selectedTab?.activeController,
			   let html = controller.readerHTML,
			   !BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser)
			{
				BrowserReaderView(controller: controller, html: html)
					.id(controller.id)
					.padding(.top, insets.obscured.top)
					.padding(.bottom, insets.obscured.bottom)
			}
		}
		.animation(nil, value: BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser))
		.allowsHitTesting(!BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser))
		#if os(macOS)
			.overlay {
				if let controller = browser.selectedTab?.activeController,
				   controller.readerHTML == nil,
				   !BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser)
				{
					BrowserAIHoverPreview(browser: browser, controller: controller)
						.id(controller.id)
				}
			}
		#endif

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
	}
}
