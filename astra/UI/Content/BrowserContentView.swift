import Defaults
import Observation
import SwiftUI
import WebKit

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
				BrowserWebStackContent(browser: browser, insets: insets, displayedTabID: selectedTab?.id)
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
		.task(id: browser.tabCollectionRevision) { browser.tabResources.reconcileProtectedControllers() }
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
			NewTabView(browser: browser)
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
					#if os(macOS)
						// Older sessions can still contain a Settings tab. Reopen its
						// destination without embedding another settings hierarchy.
						ContentUnavailableView {
							Label("Settings", systemImage: "gearshape")
						} description: {
							Text("Settings are available in their own window.")
						} actions: {
							Button("Open Settings") { browser.openInternalPage(.settings) }
						}
						.task { browser.openInternalPage(.settings) }
					#else
						BrowserSettingsView(
							browser: browser,
							searchText: $settingsSearchText,
							selectedPage: $browser.settingsPage
						)
					#endif
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

/// SwiftUI resolves the active tab and failure overlay; AppKit/UIKit owns
/// the long-lived WebKit view hierarchy and updates it without a ForEach of
/// representables on every tab, sidebar or viewport-inset change.
private struct BrowserWebStackContent: View {
	let browser: Browser
	let insets: BrowserViewportInsets
	let displayedTabID: UUID?

	var body: some View {
		let selectedTab = displayedTabID.flatMap { browser.tab(withID: $0) } ?? browser.selectedTab
		// Each WKWebView has exactly one native parent. Split panes must
		// never retain competing hosts for the other pane's controller.
		let controllers = browser.isShowingTabSplit
			? browser.tabResources.controllersForDisplay().filter { $0 === selectedTab?.controller }
			: browser.tabResources.controllersForDisplay()
		let entries = controllers.map { controller in
			let isVisible = controller === selectedTab?.controller && selectedTab?.internalPage == nil
			let hasPage = isVisible && controller.committedURL != nil && controller.navigationFailure == nil
			return BrowserNativeWebStack.Entry(
				controller: controller,
				isVisible: isVisible,
				showsPage: hasPage,
				allowsInteraction: hasPage && selectedTab?.activeController === controller
			)
		}
		ZStack {
			BrowserNativeWebStack(entries: entries, windowID: browser.windowID, insets: insets)

			if let failure = selectedTab?.controller?.navigationFailure, selectedTab?.internalPage == nil {
				BrowserNavigationErrorView(kind: failure.kind, failedURL: failure.url) {
					selectedTab?.controller?.reload()
				}
			}
		}
		.task(id: selectedTab?.id) {
			// Both panes prepare their own controller, even when the
			// globally selected tab belongs to the opposite pane.
			if let controller = selectedTab?.controller, !controller.isWebViewReady {
				controller.prepareWebView()
			}
		}
	}
}

/// Only the visible/interactive state is resolved by SwiftUI. Native hosts
/// persist by controller identity and only change their children on membership
/// changes, preserving WebKit state through tab switches and split transitions.
private struct BrowserNativeWebStack {
	struct Entry: Identifiable {
		let controller: BrowserController
		let isVisible: Bool
		let showsPage: Bool
		let allowsInteraction: Bool

		var id: UUID {
			controller.id
		}
	}

	let entries: [Entry]
	let windowID: UUID?
	let insets: BrowserViewportInsets

	func specification(for entry: Entry) -> BrowserWebView {
		BrowserWebView(
			controller: entry.controller,
			windowID: windowID,
			isVisible: entry.isVisible,
			obscuredInsets: entry.isVisible ? insets.obscured : EdgeInsets(),
			minimumViewportInsets: insets.minimum,
			maximumViewportInsets: insets.maximum
		)
	}
}

#if os(macOS)

	extension BrowserNativeWebStack: NSViewRepresentable {
		func makeNSView(context _: Context) -> BrowserNativeWebStackNSView {
			BrowserNativeWebStackNSView()
		}

		func updateNSView(_ view: BrowserNativeWebStackNSView, context _: Context) {
			view.update(stack: self)
		}

		static func dismantleNSView(_ view: BrowserNativeWebStackNSView, coordinator _: ()) {
			view.removeAllHosts()
		}
	}

	@MainActor
	private final class BrowserNativeWebStackNSView: NSView {
		private var hosts: [UUID: BrowserWebViewHost] = [:]
		private var allowsWebInteraction = false

		override func hitTest(_ point: NSPoint) -> NSView? {
			guard allowsWebInteraction else { return nil }
			return super.hitTest(point)
		}

		func update(stack: BrowserNativeWebStack) {
			let requestedIDs = Set(stack.entries.map(\.id))
			for id in hosts.keys.filter({ !requestedIDs.contains($0) }) {
				guard let host = hosts.removeValue(forKey: id) else { continue }
				host.unmountWebView()
				host.removeFromSuperview()
			}

			allowsWebInteraction = stack.entries.contains(where: \.allowsInteraction)
			for entry in stack.entries {
				let specification = stack.specification(for: entry)
				let host: BrowserWebViewHost
				if let existing = hosts[entry.id], existing.specification.controller === entry.controller {
					host = existing
				} else {
					if let previous = hosts.removeValue(forKey: entry.id) {
						previous.unmountWebView()
						previous.removeFromSuperview()
					}
					host = BrowserWebViewHost(specification: specification)
					host.frame = bounds
					host.autoresizingMask = [.width, .height]
					host.isHidden = !entry.showsPage
					addSubview(host)
					hosts[entry.id] = host
				}
				// Reuse BrowserWebViewHost's native handoff, snapshot curtain,
				// inspector and trackpad-gesture lifecycle, without SwiftUI hosts.
				host.isHidden = !entry.showsPage
				host.setAccessibilityHidden(!entry.allowsInteraction)
				host.update(specification: specification)
			}
		}

		func removeAllHosts() {
			allowsWebInteraction = false
			for host in hosts.values {
				host.unmountWebView()
				host.removeFromSuperview()
			}
			hosts.removeAll()
		}
	}

#elseif os(iOS)

	extension BrowserNativeWebStack: UIViewRepresentable {
		func makeUIView(context _: Context) -> BrowserNativeWebStackUIView {
			BrowserNativeWebStackUIView()
		}

		func updateUIView(_ view: BrowserNativeWebStackUIView, context _: Context) {
			view.update(stack: self)
		}

		static func dismantleUIView(_ view: BrowserNativeWebStackUIView, coordinator _: ()) {
			view.removeAllHosts()
		}
	}

	@MainActor
	private final class BrowserNativeWebStackUIView: UIView {
		private struct MountedPage {
			let controller: BrowserController
			let coordinator: BrowserWebView.Coordinator
		}

		private var pages: [UUID: MountedPage] = [:]
		private var appliedInsets: [UUID: [EdgeInsets]] = [:]
		private var allowsWebInteraction = false

		override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
			guard allowsWebInteraction else { return nil }
			return super.hitTest(point, with: event)
		}

		override func layoutSubviews() {
			super.layoutSubviews()
			for page in pages.values where page.controller.webViewIfLoaded?.superview === self {
				page.controller.webViewIfLoaded?.frame = bounds
			}
		}

		func update(stack: BrowserNativeWebStack) {
			let requestedIDs = Set(stack.entries.map(\.id))
			for id in pages.keys.filter({ !requestedIDs.contains($0) }) {
				removePage(id)
			}
			allowsWebInteraction = stack.entries.contains(where: \.allowsInteraction)
			for entry in stack.entries {
				let controller = entry.controller
				if let old = pages[entry.id], old.controller !== controller {
					removePage(entry.id)
				}
				let webView = controller.webView
				if pages[entry.id] == nil {
					let coordinator = BrowserWebView.Coordinator()
					coordinator.attach(to: controller)
					pages[entry.id] = MountedPage(controller: controller, coordinator: coordinator)
				}
				if webView.superview !== self {
					webView.removeFromSuperview()
					webView.frame = bounds
					webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
					addSubview(webView)
				}
				webView.isHidden = !entry.showsPage
				webView.isUserInteractionEnabled = entry.allowsInteraction
				webView.accessibilityElementsHidden = !entry.allowsInteraction

				// Keep the existing edge-swipe and pull-to-refresh coordinator.
				// Avoid setting WebKit viewport insets on unrelated UI updates.
				let obscured = entry.isVisible ? stack.insets.obscured : EdgeInsets()
				let nextInsets = [obscured, stack.insets.minimum, stack.insets.maximum]
				if appliedInsets[entry.id] != nextInsets {
					webView.obscuredContentInsets = UIEdgeInsets(
						top: obscured.top, left: obscured.leading,
						bottom: obscured.bottom, right: obscured.trailing
					)
					let minimum = stack.insets.minimum
					let maximum = stack.insets.maximum
					webView.setMinimumViewportInset(
						UIEdgeInsets(top: minimum.top, left: minimum.leading, bottom: minimum.bottom, right: minimum.trailing),
						maximumViewportInset: UIEdgeInsets(top: maximum.top, left: maximum.leading, bottom: maximum.bottom, right: maximum.trailing)
					)
					appliedInsets[entry.id] = nextInsets
				}
			}
		}

		private func removePage(_ id: UUID) {
			guard let page = pages.removeValue(forKey: id) else { return }
			page.coordinator.detach()
			if let webView = page.controller.webViewIfLoaded, webView.superview === self {
				webView.removeFromSuperview()
				webView.isHidden = true
			}
			appliedInsets[id] = nil
		}

		func removeAllHosts() {
			allowsWebInteraction = false
			for id in Array(pages.keys) {
				removePage(id)
			}
		}
	}

#endif

/// Per-browser WebKit attachment policy. The normal warm budget is four
/// controllers; pressure reduces idle retention without overriding media,
/// capture, unsaved-form or active lifecycle protection from WebKit.
@MainActor
@Observable
final class BrowserTabResourceManager {
	@ObservationIgnored private weak var browser: Browser?
	private(set) var warmControllerLimit = 4
	private var protectedControllers: [UUID: [BrowserController]] = [:]
	@ObservationIgnored private var observationTokens: [UUID: UUID] = [:]
	@ObservationIgnored private var observedTabIdentities: [UUID: ObjectIdentifier] = [:]

	/// Install dependency tracking once per tab membership change. Each activity
	/// change then refreshes only its tab; rendering never scans every WebView.
	func reconcileProtectedControllers() {
		guard let browser else { return }
		let ids = Set(browser.tabs.map(\.id))
		protectedControllers = protectedControllers.filter { ids.contains($0.key) }
		observationTokens = observationTokens.filter { ids.contains($0.key) }
		observedTabIdentities = observedTabIdentities.filter { ids.contains($0.key) }
		for tab in browser.tabs where observedTabIdentities[tab.id] != ObjectIdentifier(tab) {
			observeProtection(of: tab)
		}
	}

	func refreshProtection(of tab: BrowserTab) {
		observeProtection(of: tab)
	}

	private func observeProtection(of tab: BrowserTab) {
		let token = UUID()
		observationTokens[tab.id] = token
		observedTabIdentities[tab.id] = ObjectIdentifier(tab)
		let controllers = withObservationTracking {
			([tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)).filter(\.shouldKeepWebViewAttached)
		} onChange: { [weak self, weak tab] in
			Task { @MainActor in
				guard let self, let tab, self.observationTokens[tab.id] == token,
				      self.browser?.tab(withID: tab.id) === tab else { return }
				self.observeProtection(of: tab)
			}
		}
		let previous = protectedControllers[tab.id] ?? []
		if previous.map(\.id) != controllers.map(\.id) {
			protectedControllers[tab.id] = controllers.isEmpty ? nil : controllers
		}
	}

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
		for (tabID, controllers) in protectedControllers where isOwned(tabID) {
			for controller in controllers {
				if tabID != selectedTab?.id || controller === selectedTab?.controller {
					append(controller)
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
