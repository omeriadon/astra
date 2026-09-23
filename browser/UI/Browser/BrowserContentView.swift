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
		if let tab = browser.selectedTab,
		   let controller = tab.controller,
		   controller.url != nil
		{
			BrowserWebView(
				controller: controller,
				obscuredInsets: insets.obscured,
				minimumViewportInsets: insets.minimum,
				maximumViewportInsets: insets.maximum
			)
			.id(tab.id)
		} else if let tab = browser.selectedTab, tab.isHibernated {
			ContentUnavailableView {
				Label("Tab Hibernated", systemImage: "moon.zzz")
			} description: {
				Text("Reopen the tab to restore its page and scroll position.")
			} actions: {
				Button("Reopen Tab", systemImage: "arrow.clockwise") {
					browser.selectTab(tab.id)
				}
				.buttonStyle(.glassProminent)
				.accessibilityIdentifier("reopen-hibernated-tab")
			}
		} else if browser.selectedTab != nil {
			NewTabView(browser: browser)
				.padding(.top, insets.obscured.top)
				.background(.black)
		} else {
			ContentUnavailableView("Tab Unavailable", systemImage: "exclamationmark.triangle")
		}
	}
}
