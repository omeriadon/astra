#if os(macOS)
	import Observation
	import SwiftUI

	@MainActor
	@Observable
	final class BrowserWebsiteAppChromeState {
		var showsTopBar = true
	}

	struct BrowserWebsiteAppView: View {
		let browser: Browser
		@Bindable var chrome: BrowserWebsiteAppChromeState
		@Environment(\.colorScheme) private var colorScheme

		var body: some View {
			VStack(spacing: 0) {
				if chrome.showsTopBar {
					ShellTopBarView(
						browser: browser,
						theme: browser.theme,
						sidebarShown: false,
						topBarColorScheme: browser.selectedTab?.activeController?.themeColorIsLight.map { $0 ? .light : .dark } ?? colorScheme,
						transitionFromTheme: nil,
						transitionToTheme: nil,
						themeBlend: 0
					)
					.background { WindowDragBackground() }
					.accessibilityIdentifier("website-app-top-bar")
				}
				BrowserPageView(browser: browser, cornerRadius: 0)
			}
			.background { BrowserThemeBackground(theme: browser.theme) }
			.ignoresSafeArea()
			.accessibilityIdentifier("website-app-window")
		}
	}
#endif
