#if os(macOS)
	import SwiftUI

	struct MiniAstraView: View {
		let browser: Browser
		@Environment(\.colorScheme) private var colorScheme

		var body: some View {
			VStack(spacing: 0) {
				ShellTopBarView(
					browser: browser,
					theme: browser.theme,
					sidebarShown: false,
					topBarColorScheme: browser.selectedTab?.activeController?.themeColorIsLight.map { $0 ? .light : .dark } ?? colorScheme
				)
				.background {
					WindowDragBackground()
				}
				.accessibilityIdentifier("mini-astra-top-bar")
				BrowserPageView(browser: browser, cornerRadius: 0)
			}
			.background {
				BrowserThemeBackground(theme: browser.theme)
			}
			.modifier(BrowserQuitFeedback(browser: browser))
			.ignoresSafeArea()
			.accessibilityIdentifier("mini-astra-window")
		}
	}
#endif
