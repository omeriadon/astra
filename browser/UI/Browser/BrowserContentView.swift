import SwiftUI

struct BrowserContentView: View {
	let browser: Browser
	var insets = BrowserViewportInsets()

	var body: some View {
		GeometryReader { proxy in
			content
				.frame(width: proxy.size.width, height: proxy.size.height)
				.allowsHitTesting(browser.selectedTab?.peeks.isEmpty ?? true)
				.accessibilityHidden(!(browser.selectedTab?.peeks.isEmpty ?? true))
		}
	}

	@ViewBuilder
	private var content: some View {
		if let tab = browser.selectedTab, tab.controller.url != nil {
			BrowserWebView(
				controller: tab.controller,
				obscuredInsets: insets.obscured,
				minimumViewportInsets: insets.minimum,
				maximumViewportInsets: insets.maximum
			)
			.id(tab.id)
		} else if browser.selectedTab != nil {
			NewTabView(browser: browser)
				.padding(.top, insets.obscured.top)
				.background(.black)
		} else {
			ContentUnavailableView("Tab Unavailable", systemImage: "exclamationmark.triangle")
		}
	}
}
