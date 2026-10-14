import Defaults
import Haze
import Observation
import SwiftUI

struct BrowserContentView: View, Animatable {
	let browser: Browser
	var insets = BrowserViewportInsets()
	/// Keeps the outgoing page visible for the first half of a space crossfade.
	var displayedTabID: UUID?
	@Environment(\.colorScheme) private var colorScheme

	var animatableData: CGFloat {
		get { insets.obscured.top }
		set { insets.obscured.top = newValue }
	}

	var body: some View {
		GeometryReader { proxy in
			let selectedTab = displayedTabID.flatMap { browser.tab(withID: $0) } ?? browser.selectedTab
			let hasActiveDuplicate = BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser)
			ZStack {
				KeepAliveWebStack(browser: browser, insets: insets, displayedTabID: selectedTab?.id)
					.zIndex(0)
				content(hasActiveDuplicate: hasActiveDuplicate, tab: selectedTab)
					.zIndex(1)
			}
			.animation(nil, value: browser.selectedTabID)
			.animation(nil, value: hasActiveDuplicate)
			#if os(macOS)
				.overlay(alignment: .bottomLeading) {
					if !hasActiveDuplicate,
					   let controller = selectedTab?.activeController,
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
	private func content(hasActiveDuplicate: Bool, tab: BrowserTab?) -> some View {
		#if os(macOS)
			if let controller = tab?.activeController, controller.url != nil,
			   hasActiveDuplicate
			{
				BrowserTabMirrorView(controller: controller)
			} else {
				selectedContent(tab: tab)
			}
		#else
			selectedContent(tab: tab)
		#endif
	}

	@ViewBuilder
	private func selectedContent(tab: BrowserTab?) -> some View {
		if let tab, tab.internalPage != nil {
			InternalPageHost(browser: browser, tab: tab)
		} else if let tab, tab.controller?.url != nil {
			Color.clear
				.allowsHitTesting(false)
		} else if let tab, tab.isHibernated {
			HibernatedPlaceholder(browser: browser, tab: tab)
		} else if tab != nil {
			// Empty window anchors have no dedicated New Tab page; Cmd-T uses Spotlight.
			Color.clear
				.allowsHitTesting(false)
		} else {
			ContentUnavailableView("Tab Unavailable", systemImage: "exclamationmark.triangle")
		}
	}
}

private struct InternalPageHost: View {
	@Bindable var browser: Browser
	let tab: BrowserTab
	@State private var settingsSearchText = ""
	#if DEBUG
		@State private var failedStateRefreshID = 0
	#endif

	var body: some View {
		if let page = tab.internalPage {
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
				case .easel:
					BrowserEaselView(browser: browser, tab: tab)
						.id(tab.id)
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
	let displayedTabID: UUID?

	var body: some View {
		let selectedTab = displayedTabID.flatMap { browser.tab(withID: $0) } ?? browser.selectedTab
		// Each WebKit view can have exactly one AppKit parent. A split contains
		// two BrowserPageViews, so only attach the current pane's web view.
		let controllers = browser.isShowingTabSplit
			? browser.tabResources.controllersForDisplay().filter { $0 === selectedTab?.controller }
			: browser.tabResources.controllersForDisplay()
		ZStack {
			ForEach(controllers) { controller in
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
		.task(id: selectedTab?.id) {
			// Each side prepares its own WebKit controller, even when the
			// globally selected tab is the other split pane.
			if let controller = selectedTab?.controller, !controller.isWebViewReady {
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
		let started = BrowserLog.clock()
		let selectedTab = browser.selectedTab
		let registry = BrowserWindowRegistry.shared
		// All tabs belong to this window when there is no competing normal
		// window. Skip materializing the otherwise redundant UUID ownership set.
		let ownedTabIDs = registry.hasCompetingNormalWindow(for: browser)
			? registry.ownedTabIDs(in: browser) : nil
		func isOwned(_ id: UUID) -> Bool {
			ownedTabIDs?.contains(id) ?? true
		}
		let tabsByID = browser.tabsByID
		var result: [BrowserController] = []
		var seen = Set<UUID>()
		func append(_ controller: BrowserController?) {
			guard let controller, controller.url != nil, seen.insert(controller.id).inserted else { return }
			result.append(controller)
		}
		if browser.isShowingTabSplit {
			for splitID in [browser.splitLeftTabID, browser.splitRightTabID].compactMap(\.self)
				where isOwned(splitID)
			{
				append(tabsByID[splitID]?.controller)
			}
		}
		if let selectedTab, isOwned(selectedTab.id) {
			append(selectedTab.controller)
		}
		// Pressure applies only to idle recency retention. Independently
		// protected controllers are always included below regardless of budget.
		for id in browser.recentlyUsedTabIDs where result.count < warmControllerLimit {
			guard isOwned(id),
			      let tab = tabsByID[id], tab.internalPage == nil else { continue }
			append(tab.controller)
		}
		for tab in browser.tabs where isOwned(tab.id) {
			append(tab.controller?.shouldKeepWebViewAttached == true ? tab.controller : nil)
			for peek in tab.id == selectedTab?.id ? [] : tab.peeks {
				if peek.controller.shouldKeepWebViewAttached {
					append(peek.controller)
				}
			}
		}
		BrowserLog.duration(.performance, "workflow.webview-hosts.resolve",
		                    since: started, warnAboveMilliseconds: 8,
		                    metadata: [
		                    	"tab_count": String(browser.tabs.count),
		                    	"host_count": String(result.count),
		                    	"warm_budget": String(warmControllerLimit),
		                    ])
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
