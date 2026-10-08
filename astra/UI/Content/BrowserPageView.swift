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
		let hasActiveDuplicate = BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser)
		let selectedTab = browser.selectedTab
		return ZStack(alignment: .top) {
			BrowserContentView(browser: browser, insets: insets)
			#if os(macOS)
				.blur(radius: hasActiveDuplicate ? 10 : 0)
				.allowsHitTesting(!hasActiveDuplicate)
				.accessibilityHidden(hasActiveDuplicate)
			#endif

			if let tab = selectedTab,
			   !hasActiveDuplicate,
			   !tab.peeks.isEmpty,
			   tab.activeController !== tab.controller
			{
				PeekStackView(tab: tab, browser: browser)
					.id(tab.id)
			}
		}
		.accessibilityHidden(selectedTab?.activeController?.readerHTML != nil)
		.overlay {
			if let controller = selectedTab?.activeController,
			   let html = controller.readerHTML,
			   !hasActiveDuplicate
			{
				BrowserReaderView(controller: controller, html: html)
					.id(controller.id)
					.padding(.top, insets.obscured.top)
					.padding(.bottom, insets.obscured.bottom)
			}
		}
		.animation(nil, value: hasActiveDuplicate)
		.allowsHitTesting(!hasActiveDuplicate)
		#if os(macOS)
			.overlay {
				if let controller = browser.selectedTab?.activeController,
				   controller.readerHTML == nil,
				   !hasActiveDuplicate
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
			.allowsHitTesting(!hasActiveDuplicate)
			.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
	}
}
