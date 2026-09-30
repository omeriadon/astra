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
					topBarColorScheme: browser.selectedTab?.activeController?.themeColorIsLight.map { $0 ? .light : .dark } ?? colorScheme,
					transitionFromTheme: nil,
					transitionToTheme: nil,
					themeBlend: 0
				)
				.background {
					WindowDragBackground()
				}
				.accessibilityIdentifier("mini-astra-top-bar")
				BrowserContentView(browser: browser)
			}
			.background {
				BrowserThemeBackground(theme: browser.theme)
			}
			.ignoresSafeArea()
			.accessibilityIdentifier("mini-astra-window")
		}
	}
#endif
