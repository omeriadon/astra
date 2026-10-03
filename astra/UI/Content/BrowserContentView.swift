import Defaults
import Haze
import SwiftUI

struct BrowserContentView: View, Animatable {
	let browser: Browser
	var insets = BrowserViewportInsets()
	@Environment(\.colorScheme) private var colorScheme

	var animatableData: CGFloat {
		get { insets.obscured.top }
		set { insets.obscured.top = newValue }
	}

	var body: some View {
		GeometryReader { proxy in
			let selectedTab = browser.selectedTab
			ZStack {
				KeepAliveWebStack(browser: browser, insets: insets)
					.zIndex(0)
				content
					.zIndex(1)
			}
			.frame(width: proxy.size.width, height: proxy.size.height)
			.background(browser.theme.contentShade(for: colorScheme))
			.allowsHitTesting(selectedTab?.peeks.isEmpty == true || selectedTab?.activeController === selectedTab?.controller)
			.accessibilityHidden(!(selectedTab?.peeks.isEmpty == true || selectedTab?.activeController === selectedTab?.controller))
		}
	}

	@ViewBuilder
	private var content: some View {
		if let tab = browser.selectedTab, tab.internalPage != nil {
			InternalPageHost(browser: browser)
		} else if let tab = browser.selectedTab, tab.controller?.url != nil {
			Color.clear
				.allowsHitTesting(false)
		} else if let tab = browser.selectedTab, tab.isHibernated {
			HibernatedPlaceholder(browser: browser, tab: tab)
		} else if browser.selectedTab != nil {
			NewTabView(browser: browser)
				.padding(.top, insets.obscured.top)
		} else {
			ContentUnavailableView("Tab Unavailable", systemImage: "exclamationmark.triangle")
		}
	}
}

private struct InternalPageHost: View {
	@Bindable var browser: Browser
	@State private var settingsSearchText = ""
	#if DEBUG
		@State private var failedStateRefreshID = 0
	#endif

	var body: some View {
		if let tab = browser.selectedTab, let page = tab.internalPage {
			switch page {
				case .themeEditor:
					BrowserThemeEditorView(browser: browser)
				case .settings:
					BrowserSettingsView(
						browser: browser,
						searchText: $settingsSearchText,
						selectedPage: $browser.settingsPage
					)
				case .history:
					BrowserHistoryView(browser: browser)
				case .bookmarks:
					BrowserBookmarksView(browser: browser)
				#if DEBUG
					case let .failedWebsiteState(kind):
						BrowserNavigationErrorView(kind: kind) {
							failedStateRefreshID += 1
						}
						.id(failedStateRefreshID)
				#endif
			}
		}
	}
}

private struct KeepAliveWebStack: View {
	let browser: Browser
	let insets: BrowserViewportInsets

	var body: some View {
		let selectedTab = browser.selectedTab
		ZStack {
			ForEach(keepAliveControllers()) { controller in
				BrowserWebView(
					controller: controller,
					obscuredInsets: controller === selectedTab?.controller ? insets.obscured : EdgeInsets(),
					minimumViewportInsets: insets.minimum,
					maximumViewportInsets: insets.maximum
				)
				.id(controller.id)
				.opacity(controller === selectedTab?.controller && selectedTab?.internalPage == nil && controller.navigationFailure == nil ? 1 : 0)
				.allowsHitTesting(controller === selectedTab?.controller && selectedTab?.activeController === controller && controller.navigationFailure == nil)
				.accessibilityHidden(controller !== selectedTab?.controller || selectedTab?.activeController !== controller || controller.navigationFailure != nil)
			}

			if let failure = selectedTab?.controller?.navigationFailure, selectedTab?.internalPage == nil {
				BrowserNavigationErrorView(kind: failure.kind, failedURL: failure.url) {
					selectedTab?.controller?.reload()
				}
			}
		}
		.task(id: browser.selectedTabID) {
			// Controller is usually already prepared by openHistory/addTab;
			// this is just the fallback for restored/hibernated tabs.
			if let controller = browser.selectedTab?.controller, !controller.isWebViewReady {
				controller.prepareWebView()
			}
		}
	}

	private func keepAliveControllers() -> [BrowserController] {
		let selectedTab = browser.selectedTab
		var result: [BrowserController] = []
		var seen = Set<UUID>()
		func append(_ controller: BrowserController?) {
			guard let controller, controller.url != nil, seen.insert(controller.id).inserted else { return }
			result.append(controller)
		}
		append(selectedTab?.controller)
		for id in browser.recentlyUsedTabIDs where result.count < 4 {
			guard let tab = browser.tab(withID: id), tab.internalPage == nil else { continue }
			append(tab.controller)
		}
		// ponytail: retain all playing or paused media while iframe PiP state is unobservable; narrow this when WebKit exposes a frame-aware callback.
		for tab in browser.tabs {
			append(tab.controller?.requiresMediaTeardownConfirmation == true ? tab.controller : nil)
			for peek in tab.id == selectedTab?.id ? [] : tab.peeks {
				if peek.controller.requiresMediaTeardownConfirmation {
					append(peek.controller)
				}
			}
		}
		return result
	}
}

private struct HibernatedPlaceholder: View {
	let browser: Browser
	let tab: BrowserTab

	var body: some View {
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
	}
}
