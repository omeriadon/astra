import Defaults
import Haze
import SwiftUI

struct BrowserContentView: View {
	let browser: Browser
	var insets = BrowserViewportInsets()
	@State private var settingsSearchText = ""
	@State private var settingsPage: BrowserSettingsView.Page = .ui
	#if DEBUG
		@State private var failedStateRefreshID = 0
	#endif
	@Default(.browserTheme) private var theme
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		GeometryReader { proxy in
			content
				.frame(width: proxy.size.width, height: proxy.size.height)
				.background(theme.contentShade(for: colorScheme))
				.background {
					HazeEffect(
						maskProvider: LinearGradientMaskProvider(
							startPoint: .top,
							endPoint: .bottom,
							startOpacity: 1.0,
							endOpacity: 1.0,
							isSmooth: false
						),
						maxBlurRadius: 1
					)
				}
				.allowsHitTesting(browser.selectedTab?.peeks.isEmpty ?? true)
				.accessibilityHidden(!(browser.selectedTab?.peeks.isEmpty ?? true))
		}
	}

	@ViewBuilder
	private var content: some View {
		if let tab = browser.selectedTab, let page = tab.internalPage {
			switch page {
				case .themeEditor:
					BrowserThemeEditorView()
				case .settings:
					BrowserSettingsView(
						browser: browser,
						searchText: $settingsSearchText,
						selectedPage: $settingsPage
					)
				#if DEBUG
					case let .failedWebsiteState(kind):
						BrowserNavigationErrorView(kind: kind) {
							failedStateRefreshID += 1
						}
						.id(failedStateRefreshID)
				#endif
			}
		} else if let tab = browser.selectedTab,
		          let controller = tab.controller,
		          controller.url != nil
		{
			if controller.isWebViewReady {
				ZStack {
					BrowserWebView(
						controller: controller,
						obscuredInsets: insets.obscured,
						minimumViewportInsets: insets.minimum,
						maximumViewportInsets: insets.maximum
					)
					.id(tab.id)
					.opacity(controller.navigationFailure == nil ? 1 : 0)
					.allowsHitTesting(controller.navigationFailure == nil)
					.accessibilityHidden(controller.navigationFailure != nil)

					if let failure = controller.navigationFailure {
						BrowserNavigationErrorView(kind: failure.kind) {
							controller.reload()
						}
					}
				}
			} else {
				Color.clear
					.task {
						await Task.yield()
						guard !Task.isCancelled else { return }
						controller.prepareWebView()
					}
			}
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
		} else {
			ContentUnavailableView("Tab Unavailable", systemImage: "exclamationmark.triangle")
		}
	}
}
