import SwiftUI

struct BrowserQuickSearchOverlay: View {
	let browser: Browser

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .top) {
				Button {
					browser.dismissQuickSearch()
				} label: {
					Label("Dismiss New Tab Search", systemImage: "xmark")
						.hidden()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.contentShape(Rectangle())
						.background(Color.black.opacity(0.15))
				}
				.buttonStyle(.plain)
				.keyboardShortcut(.cancelAction)
				.accessibilityLabel("Dismiss New Tab Search")
				.accessibilityIdentifier("quick-search-dismiss")

				NewTabView(browser: browser, isQuickSearch: true)
					.frame(width: min(640, max(0, geometry.size.width - 32)), height: min(440, max(0, geometry.size.height - 48)))
					.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
					.padding(.top, min(80, geometry.size.height * 0.12))
					.accessibilityIdentifier("quick-search-overlay")
			}
			.onKeyPress(.escape) {
				browser.dismissQuickSearch()
				return .handled
			}
		}
	}
}
