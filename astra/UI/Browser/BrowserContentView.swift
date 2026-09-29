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
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		GeometryReader { proxy in
			content
				.frame(width: proxy.size.width, height: proxy.size.height)
				.background(browser.theme.contentShade(for: colorScheme))
				.allowsHitTesting(browser.selectedTab?.peeks.isEmpty ?? true)
				.accessibilityHidden(!(browser.selectedTab?.peeks.isEmpty ?? true))
		}
	}

	@ViewBuilder
	private var content: some View {
		if let tab = browser.selectedTab, let page = tab.internalPage {
			switch page {
				case .themeEditor:
					BrowserThemeEditorView(browser: browser)
				case .settings:
					BrowserSettingsView(
						browser: browser,
						searchText: $settingsSearchText,
						selectedPage: $settingsPage
					)
				case .history:
					BrowserHistoryView(browser: browser)
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
			// Keep the selected + 3 most-recent web tabs mounted so switching
			// back doesn't tear down/rebuild the NSViewRepresentable each time.
			// Hidden ones are hit-test-invisible and accessibility-hidden.
			ZStack {
				ForEach(keepAliveTabs(in: browser, selected: tab)) { keepTab in
					if let keepController = keepTab.controller, keepController.url != nil {
						BrowserWebView(
							controller: keepController,
							obscuredInsets: keepTab.id == tab.id ? insets.obscured : EdgeInsets(),
							minimumViewportInsets: insets.minimum,
							maximumViewportInsets: insets.maximum
						)
						.id(keepTab.id)
						.opacity(keepTab.id == tab.id && keepController.navigationFailure == nil ? 1 : 0)
						.allowsHitTesting(keepTab.id == tab.id && keepController.navigationFailure == nil)
						.accessibilityHidden(keepTab.id != tab.id || keepController.navigationFailure != nil)
					}
				}

				if let failure = controller.navigationFailure {
					BrowserNavigationErrorView(kind: failure.kind) {
						controller.reload()
					}
				}
			}
			.task(id: tab.id) {
				// Controller is usually already prepared by openHistory/addTab;
				// this is just the fallback for restored/hibernated tabs.
				if !controller.isWebViewReady {
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

	/// Selected tab plus up to 3 recently-used web tabs with live controllers.
	/// Bounded so hidden webviews don't grow memory without limit.
	private func keepAliveTabs(in browser: Browser, selected: BrowserTab) -> [BrowserTab] {
		var seen = Set<UUID>()
		var result: [BrowserTab] = []
		result.append(selected)
		seen.insert(selected.id)
		for id in browser.recentlyUsedTabIDs where result.count < 4 {
			guard !seen.contains(id),
			      let tab = browser.tab(withID: id),
			      tab.internalPage == nil,
			      tab.controller?.url != nil
			else { continue }
			seen.insert(id)
			result.append(tab)
		}
		return result
	}
}
