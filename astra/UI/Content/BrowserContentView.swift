import Defaults
import Haze
import Observation
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
			let hasActiveDuplicate = BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser)
			ZStack {
				KeepAliveWebStack(browser: browser, insets: insets)
					.zIndex(0)
				content(hasActiveDuplicate: hasActiveDuplicate)
					.zIndex(1)
			}
			.animation(nil, value: browser.selectedTabID)
			.animation(nil, value: hasActiveDuplicate)
			#if os(macOS)
				.overlay(alignment: .bottomLeading) {
					if !hasActiveDuplicate,
					   let controller = browser.selectedTab?.activeController,
					   let url = controller.hoveredLinkURL
					{
						BrowserLinkPreview(url: url, isPrivate: browser.isPrivate)
							.frame(maxWidth: min(700, proxy.size.width * 0.75), alignment: .leading)
							.frame(maxWidth: .infinity, alignment: controller.hoveredLinkUsesTrailingCorner ? .trailing : .leading)
							.padding(8)
							.allowsHitTesting(false)
					}
				}
			#endif
				.frame(width: proxy.size.width, height: proxy.size.height)
				.background(browser.theme.contentShade(for: colorScheme))
				.allowsHitTesting(selectedTab?.peeks.isEmpty == true || selectedTab?.activeController === selectedTab?.controller)
				.accessibilityHidden(!(selectedTab?.peeks.isEmpty == true || selectedTab?.activeController === selectedTab?.controller))
		}
	}

	@ViewBuilder
	private func content(hasActiveDuplicate: Bool) -> some View {
		#if os(macOS)
			if let controller = browser.selectedTab?.activeController, controller.url != nil,
			   hasActiveDuplicate
			{
				BrowserTabMirrorView(controller: controller)
			} else {
				selectedContent
			}
		#else
			selectedContent
		#endif
	}

	@ViewBuilder
	private var selectedContent: some View {
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
			ForEach(browser.tabResources.controllersForDisplay()) { controller in
				BrowserWebView(
					controller: controller,
					windowID: browser.windowID,
					isVisible: controller === selectedTab?.controller && selectedTab?.internalPage == nil,
					obscuredInsets: controller === selectedTab?.controller ? insets.obscured : EdgeInsets(),
					minimumViewportInsets: insets.minimum,
					maximumViewportInsets: insets.maximum
				)
				.id(controller.id)
				.opacity(controller === selectedTab?.controller && selectedTab?.internalPage == nil && controller.committedURL != nil && controller.navigationFailure == nil ? 1 : 0)
				.allowsHitTesting(controller === selectedTab?.controller && selectedTab?.activeController === controller && controller.committedURL != nil && controller.navigationFailure == nil)
				.accessibilityHidden(controller !== selectedTab?.controller || selectedTab?.activeController !== controller || controller.committedURL == nil || controller.navigationFailure != nil)
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
}

/// Per-browser WebKit attachment policy. The normal warm budget is four
/// controllers; pressure reduces idle retention without overriding media,
/// capture, unsaved-form or active lifecycle protection from WebKit.
@MainActor
@Observable
final class BrowserTabResourceManager {
	@ObservationIgnored private weak var browser: Browser?
	private(set) var warmControllerLimit = 4

	init(browser: Browser) {
		self.browser = browser
	}

	func updateMemoryPressure(_ level: BrowserHibernationManager.PressureLevel) {
		let limit = switch level {
			case .normal: 4
			case .warning: 2
			case .critical: 1
		}
		guard warmControllerLimit != limit else { return }
		warmControllerLimit = limit
		BrowserLog.debug(.performance, "webkit.warm-controller-budget", metadata: ["count": String(limit)])
	}

	func controllersForDisplay() -> [BrowserController] {
		guard let browser else { return [] }
		let selectedTab = browser.selectedTab
		let ownedTabIDs = BrowserWindowRegistry.shared.ownedTabIDs(in: browser)
		let tabsByID = browser.tabsByID
		var result: [BrowserController] = []
		var seen = Set<UUID>()
		func append(_ controller: BrowserController?) {
			guard let controller, controller.url != nil, seen.insert(controller.id).inserted else { return }
			result.append(controller)
		}
		if let selectedTab, ownedTabIDs.contains(selectedTab.id) {
			append(selectedTab.controller)
		}
		// Pressure applies only to idle recency retention. Independently
		// protected controllers are always included below regardless of budget.
		for id in browser.recentlyUsedTabIDs where result.count < warmControllerLimit {
			guard ownedTabIDs.contains(id),
			      let tab = tabsByID[id], tab.internalPage == nil else { continue }
			append(tab.controller)
		}
		for tab in browser.tabs where ownedTabIDs.contains(tab.id) {
			append(tab.controller?.shouldKeepWebViewAttached == true ? tab.controller : nil)
			for peek in tab.id == selectedTab?.id ? [] : tab.peeks {
				if peek.controller.shouldKeepWebViewAttached {
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
