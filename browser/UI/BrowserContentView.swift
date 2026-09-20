import SwiftUI

struct BrowserContentView: View {
	let browser: Browser
	var insets = BrowserViewportInsets()

	var body: some View {
		if let tab = browser.selectedTab {
			BrowserWebView(
				controller: tab.controller,
				obscuredInsets: insets.obscured,
				minimumViewportInsets: insets.minimum,
				maximumViewportInsets: insets.maximum
			)
		} else {
			Color.clear
		}
	}
}
