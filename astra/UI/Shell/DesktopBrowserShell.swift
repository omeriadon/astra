import Defaults
import SwiftUI
import WebKit
#if os(macOS)
	import UniformTypeIdentifiers
#endif

extension Notification.Name {
	static let showBrowserDownloads = Notification.Name("ShowBrowserDownloads")
	static let toggleBrowserTopBar = Notification.Name("ToggleBrowserTopBar")
}

struct DesktopBrowserShell: View {
	@Bindable var browser: Browser
	@Environment(\.colorScheme) private var colorScheme
	private var theme: BrowserTheme {
		browser.theme
	}

	@Default(.sidebarShown) private var sidebarShown
	@Default(.aiFeaturesEnabled) private var allAIFeatures
	@Default(.aiSidebar) private var aiSidebarEnabled
	private var downloads: BrowserDownloadManager {
		browser.session.downloads
	}

	@State private var showsDownloads = false
	@State private var flight: DownloadFlight?
	@State private var flightProgress = 0.0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var isFullScreen = false
	@State private var spaceScrollState = BrowserSpaceScrollState()
	@State private var showsTopBar = true
	@State private var isTopBarRevealed = false
	@State private var isSidebarRevealed = false
	@State private var presentedSidebarShown = false
	@State private var presentedAISidebarShown = false
	@State private var reservedMinimumWidth: CGFloat = 0
	@State private var paneTransitionGeneration = 0
	#if os(macOS)
		@State private var hostWindow: NSWindow?
		@State private var windowButtonAnimationGeneration = 0
	#endif

	private var topBarColorScheme: ColorScheme {
		guard let themeColorIsLight = browser.selectedTab?.activeController?.themeColorIsLight else { return colorScheme }
		return themeColorIsLight ? .light : .dark
	}

	private var showsAISidebar: Bool {
		allAIFeatures && browser.showsAISidebar && browser.canShowAISidebar && aiSidebarEnabled
	}

	private var minimumWindowWidth: CGFloat {
		BrowserChromeMetrics.minimumWindowWidth(
			sidebarShown: sidebarShown,
			aiSidebarShown: showsAISidebar,
			minimumContentWidth: minimumPageWidth
		)
	}

	private var minimumPageWidth: CGFloat {
		BrowserChromeMetrics.minimumPageWidth(isSettings: browser.selectedTab?.internalPage == .settings)
	}

	private var isSidebarPinned: Bool {
		#if os(macOS)
			presentedSidebarShown
		#else
			sidebarShown
		#endif
	}

	private var isSidebarVisible: Bool {
		isSidebarPinned || isSidebarRevealed
	}

	private var isAISidebarVisible: Bool {
		#if os(macOS)
			presentedAISidebarShown
		#else
			showsAISidebar
		#endif
	}

	private var showsTopBarOnPage: Bool {
		!browser.isShowingNewTab && browser.selectedTab?.internalPage == nil
	}

	private var hasVisibleChrome: Bool {
		isSidebarVisible || isAISidebarVisible || (showsTopBarOnPage && (showsTopBar || isTopBarRevealed))
	}

	private var contentCornerRadius: CGFloat {
		hasVisibleChrome
			? BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar
			: BrowserChromeMetrics.tabWindowCornerRadiusWithoutSidebar
	}

	#if os(macOS)
		private func updateWindowMinimumSize() {
			guard let window = hostWindow else { return }
			paneTransitionGeneration += 1
			let generation = paneTransitionGeneration
			reservedMinimumWidth = max(reservedMinimumWidth, minimumWindowWidth)
			window.setBrowserMinimumContentWidth(reservedMinimumWidth)
			let animation: Animation? = window.isVisible && !reduceMotion ? .smooth(duration: 0.3) : nil
			withAnimation(animation, completionCriteria: .removed) {
				presentedSidebarShown = sidebarShown
				presentedAISidebarShown = showsAISidebar
			} completion: {
				guard generation == paneTransitionGeneration else { return }
				reservedMinimumWidth = minimumWindowWidth
				window.setBrowserMinimumContentWidth(reservedMinimumWidth)
			}
		}

		private func updateWindowButtons(in window: NSWindow?, animated: Bool = true) {
			guard let window else { return }
			let hidden = !isSidebarVisible && !(showsTopBarOnPage && (showsTopBar || isTopBarRevealed))
			let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
				.compactMap { window.standardWindowButton($0) }
			windowButtonAnimationGeneration += 1
			let generation = windowButtonAnimationGeneration

			guard animated, !reduceMotion else {
				for button in buttons {
					button.alphaValue = hidden ? 0 : 1
					button.isHidden = hidden
					button.isEnabled = !hidden
				}
				return
			}

			for button in buttons {
				button.isHidden = false
				button.isEnabled = !hidden
			}
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.2
				for button in buttons {
					button.animator().alphaValue = hidden ? 0 : 1
				}
			} completionHandler: {
				guard generation == windowButtonAnimationGeneration, hidden else { return }
				for button in buttons {
					button.isHidden = true
				}
			}
		}
	#endif

	private var windowLayout: some View {
		GeometryReader { geometry in
			let showsAI = isAISidebarVisible
			BrowserSplitView(
				sidebarShown: .constant(isSidebarVisible),
				minimumContentWidth: minimumPageWidth,
				sidebarOverlaysContent: !isSidebarPinned,
				followingSidebarWidth: showsAI ? BrowserChromeMetrics.aiSidebarWidthRange.lowerBound : 0
			) {
				ShellSidebarColumn(
					browser: browser,
					theme: theme,
					sidebarShown: isSidebarVisible,
					isFullScreen: isFullScreen,
					colorScheme: colorScheme,
					topBarColorScheme: topBarColorScheme,
					showsDownloads: $showsDownloads,
					downloads: downloads,
					spaceScrollState: spaceScrollState
				)

			} content: {
				BrowserSplitView(
					sidebarShown: .constant(showsAI),
					sidebarWidth: min(360, geometry.size.width * 0.45) + BrowserChromeMetrics.shellEdgePadding,
					sidebarWidthRange: BrowserChromeMetrics.aiSidebarWidthRange,
					minimumContentWidth: minimumPageWidth,
					edge: .trailing
				) {
					BrowserAIChatSidebar(browser: browser, chat: browser.aiChat, isVisible: showsAI)
						.padding(.vertical, BrowserChromeMetrics.shellEdgePadding)
						.padding(.trailing, BrowserChromeMetrics.shellEdgePadding)
						.allowsHitTesting(showsAI)
						.accessibilityHidden(!showsAI)
				} content: {
					ShellContentColumn(
						browser: browser,
						theme: theme,
						sidebarShown: isSidebarVisible,
						isFullScreen: isFullScreen,
						colorScheme: colorScheme,
						topBarColorScheme: topBarColorScheme,
						contentCornerRadius: contentCornerRadius,
						hasVisibleChrome: hasVisibleChrome,
						showsTopBar: showsTopBar,
						isTopBarRevealed: $isTopBarRevealed
					)
				}
				.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showsAI)
			}
			#if !os(macOS)
			.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isSidebarVisible)
			.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showsAI)
			#endif
			.onContinuousHover { phase in
				switch phase {
					case let .active(location):
						let revealWidth = isSidebarRevealed
							? BrowserChromeMetrics.sidebarWidth(
								preferred: BrowserChromeMetrics.expandedSidebarWidth,
								limits: BrowserChromeMetrics.sidebarWidthRange,
								availableWidth: geometry.size.width,
								minimumContentWidth: minimumPageWidth
									+ (showsAI ? BrowserChromeMetrics.aiSidebarWidthRange.lowerBound : 0)
							)
							: 6
						let shouldReveal = !sidebarShown && location.x < revealWidth
						guard shouldReveal != isSidebarRevealed else { return }
						withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
							isSidebarRevealed = shouldReveal
						}
					case .ended:
						guard isSidebarRevealed else { return }
						withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
							isSidebarRevealed = false
						}
				}
			}
		}
		.background {
			BrowserThemeBackground(theme: theme, spaces: browser.workspace.spaces, scrollState: spaceScrollState)
		}
		.onChange(of: sidebarShown) { _, _ in
			isSidebarRevealed = false
		}
		#if os(macOS)
		.onReceive(NotificationCenter.default.publisher(for: .toggleBrowserTopBar)) { notification in
			guard notification.object as? UUID == browser.windowID,
			      hostWindow?.isKeyWindow == true else { return }
			withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
				showsTopBar.toggle()
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: .showBrowserDownloads)) { notification in
			guard notification.object as? UUID == browser.windowID,
			      hostWindow?.isKeyWindow == true else { return }
			showsDownloads = true
		}
		.background {
			WindowFocusReader { window in
				hostWindow = window
				updateWindowButtons(in: window, animated: false)
			}
			.allowsHitTesting(false)
		}
		.onChange(of: minimumWindowWidth, initial: true) { _, _ in
			updateWindowMinimumSize()
		}
		.onChange(of: hostWindow) { _, _ in
			isFullScreen = hostWindow?.styleMask.contains(.fullScreen) == true
			updateWindowMinimumSize()
		}
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { notification in
			guard notification.object as? NSWindow === hostWindow else { return }
			updateWindowMinimumSize()
		}
		.onChange(of: isSidebarVisible) { _, shown in
			updateWindowButtons(in: hostWindow)
			if !shown {
				BrowserTabHoverPreviewCoordinator.shared.dismiss(for: browser.windowID)
			}
		}
		.onChange(of: showsTopBar) { _, _ in
			updateWindowButtons(in: hostWindow)
		}
		.onChange(of: isTopBarRevealed) { _, _ in
			updateWindowButtons(in: hostWindow)
		}
		.onChange(of: showsTopBarOnPage) { _, _ in
			isTopBarRevealed = false
			updateWindowButtons(in: hostWindow)
		}
		#endif
	}

	var body: some View {
		windowLayout
			.overlay {
				DownloadFlightOverlay(
					flight: flight,
					flightProgress: flightProgress,
					sidebarShown: isSidebarVisible,
					theme: theme
				)
				.allowsHitTesting(false)
			}
		#if os(macOS)
			.overlay {
				TabDragOverlay(browser: browser, hostWindow: hostWindow)
					.allowsHitTesting(false)
			}
			.overlay {
				BrowserTabHoverPreviewOverlay(browser: browser)
			}
		#endif
			.onChange(of: showsDownloads) { _, shown in
				if shown {
					BrowserTabHoverPreviewCoordinator.shared.dismiss(for: browser.windowID)
				}
			}
			.onChange(of: downloads.latestStart?.id) { _, _ in
				guard let start = downloads.latestStart,
				      let item = downloads.items.first(where: { $0.id == start.id })
				else { return }
				flightProgress = 0
				flight = DownloadFlight(id: start.id, source: start.source, symbol: item.symbol)
				withAnimation(reduceMotion ? .none : .smooth(duration: 0.7)) {
					flightProgress = 1
				}
			}
			.task(id: flight?.id) {
				guard flight != nil else { return }
				try? await Task.sleep(for: .milliseconds(750))
				if !Task.isCancelled {
					flight = nil
				}
			}
		#if os(macOS)
			.onAppear {
				isFullScreen = hostWindow?.styleMask.contains(.fullScreen) == true
			}
			.onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
				guard notification.object as? NSWindow === hostWindow else { return }
				isFullScreen = true
			}
			.onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
				guard notification.object as? NSWindow === hostWindow else { return }
				isFullScreen = false
				updateWindowMinimumSize()
			}
		#endif
			.ignoresSafeArea()
	}
}

private struct DownloadFlight: Identifiable {
	let id: UUID
	let source: UnitPoint
	let symbol: String
}

private struct ShellNavigationBarControls: View {
	let browser: Browser
	let theme: BrowserTheme
	let isFullScreen: Bool
	let sidebarShown: Bool
	let colorScheme: ColorScheme
	let topBarColorScheme: ColorScheme

	var body: some View {
		HStack(spacing: 5) {
			Spacer()
				.frame(width: isFullScreen ? 0 : 80)
		}
		.frame(height: BrowserChromeMetrics.topBarRegionHeight)
		.frame(maxWidth: BrowserChromeMetrics.persistentControlsAreaWidth, alignment: .leading)
		.environment(
			\.colorScheme,
			sidebarShown ? colorScheme : topBarColorScheme
		)
	}
}

private struct ShellSidebarColumn: View {
	let browser: Browser
	let theme: BrowserTheme
	let sidebarShown: Bool
	let isFullScreen: Bool
	let colorScheme: ColorScheme
	let topBarColorScheme: ColorScheme
	@Binding var showsDownloads: Bool
	let downloads: BrowserDownloadManager
	let spaceScrollState: BrowserSpaceScrollState
	@State private var sidebarMediaHeight: CGFloat = 0

	private var bottomOpacityHeight: CGFloat {
		sidebarMediaHeight > 0 ? sidebarMediaHeight + 8 + 33 : 34
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			sidebarContent

			ShellNavigationBarControls(
				browser: browser,
				theme: theme,
				isFullScreen: isFullScreen,
				sidebarShown: sidebarShown,
				colorScheme: colorScheme,
				topBarColorScheme: topBarColorScheme
			)
			.frame(maxWidth: .infinity, alignment: .leading)
			.allowsHitTesting(false)
		}
	}

	private var sidebarContent: some View {
		ZStack(alignment: .top) {
			Group {
				if browser.isPrivate {
					PrivateBrowserSidebar(browser: browser)
						.sidebarScrollContentMargins()
				} else {
					BrowserSpacePager(
						spaces: browser.workspace.spaces,
						selectedSpaceID: browser.workspace.selectedSpaceID,
						favouriteTabIDs: browser.workspace.favouriteTabIDs,
						scrollState: spaceScrollState,
						onSelectSpace: { id in
							guard id != browser.workspace.selectedSpaceID else { return }
							browser.selectSpace(id)
						}
					) { space, isActiveSpace, favouriteTabIDs in
						ShellSidebarListView(
							browser: browser,
							space: space,
							theme: space.theme,
							isActiveSpace: isActiveSpace,
							favouriteTabIDs: favouriteTabIDs
						)
						.foregroundStyle(space.theme.foregroundColor)
						.sidebarScrollContentMargins()
					}
					.accessibilityIdentifier("sidebar-space-pages")
				}
			}
			.foregroundStyle(theme.foregroundColor)
			.visualEffect { content, geometry in
				content.offset(x: showsDownloads ? geometry.size.width : 0)
			}

			DownloadsSidebarView(
				manager: downloads,
				theme: theme
			)
			.foregroundStyle(theme.foregroundColor)
			.sidebarScrollContentMargins()
			.visualEffect { content, geometry in
				content.offset(x: showsDownloads ? 0 : -geometry.size.width)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.ignoresSafeArea(.container, edges: .vertical)
		.sidebarScrollOpacityFade(
			top: 38,
			bottom: bottomOpacityHeight + 11,
			bottomOpacityHeight: bottomOpacityHeight
		)
		.overlay(alignment: .bottom) {
			if sidebarShown {
				sidebarBottomBar
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	private var sidebarBottomBar: some View {
		VStack(spacing: 8) {
			BrowserMediaActivityView(browser: browser)
				.padding(.horizontal, 8)
				.foregroundStyle(theme.foregroundColor)
				.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
					sidebarMediaHeight = height
				}

			ShellDownloadsBarView(
				browser: browser,
				theme: theme,
				downloads: downloads,
				showsDownloads: $showsDownloads
			)
			.foregroundStyle(theme.foregroundColor)
		}
	}
}

private struct ShellContentColumn: View {
	let browser: Browser
	let theme: BrowserTheme
	let sidebarShown: Bool
	let isFullScreen: Bool
	let colorScheme: ColorScheme
	let topBarColorScheme: ColorScheme
	let contentCornerRadius: CGFloat
	let hasVisibleChrome: Bool
	let showsTopBar: Bool
	@Binding var isTopBarRevealed: Bool
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	#if os(macOS)
		@State private var isAddressDropTargeted = false
	#endif

	private var topBar: some View {
		ShellTopBarView(
			browser: browser,
			theme: theme,
			sidebarShown: true,
			topBarColorScheme: topBarColorScheme,
			reservesWindowControls: !sidebarShown && !isFullScreen
		)
		#if os(macOS)
		.onDrop(of: [UTType.url, UTType.plainText], isTargeted: $isAddressDropTargeted, perform: acceptAddressDrop)
		.overlay {
			if isAddressDropTargeted {
				RoundedRectangle(cornerRadius: 10)
					.stroke(theme.foregroundColor.opacity(0.7), lineWidth: 2)
					.padding(.horizontal, 10)
					.allowsHitTesting(false)
			}
		}
		#endif
	}

	private var topBarHeight: CGFloat {
		guard browser.selectedTab?.internalPage == nil, !browser.isShowingNewTab else { return 0 }
		guard showsTopBar || isTopBarRevealed else { return 0 }
		return BrowserChromeMetrics.topBarRegionHeight
			+ BrowserChromeMetrics.shellEdgePadding
	}

	var body: some View {
		ZStack(alignment: .top) {
			topBar
				.frame(height: BrowserChromeMetrics.topBarRegionHeight + BrowserChromeMetrics.shellEdgePadding, alignment: .top)
				.frame(maxWidth: .infinity, alignment: .trailing)
				.mask(alignment: .top) {
					Rectangle().frame(height: topBarHeight)
				}
				.allowsHitTesting(topBarHeight > 0)
				.accessibilityHidden(topBarHeight == 0)
			VStack(spacing: 0) {
				Spacer(minLength: 0)
					.frame(height: topBarHeight)
				BrowserPageView(browser: browser, cornerRadius: contentCornerRadius)
					.padding(.top, hasVisibleChrome ? BrowserChromeMetrics.shellEdgePadding : 0)
					.padding([.bottom, .horizontal], hasVisibleChrome ? BrowserChromeMetrics.shellEdgePadding : 0)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.animation(nil, value: browser.selectedTabID)
		.onContinuousHover { phase in
			switch phase {
				case let .active(location):
					let revealHeight = isTopBarRevealed
						? BrowserChromeMetrics.topBarRegionHeight + BrowserChromeMetrics.shellEdgePadding
						: 6
					withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
						isTopBarRevealed = browser.selectedTab?.internalPage == nil
							&& !browser.isShowingNewTab
							&& !showsTopBar && location.y < revealHeight
					}
				case .ended:
					withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
						isTopBarRevealed = false
					}
			}
		}
		.onChange(of: sidebarShown) { _, _ in
			isTopBarRevealed = false
		}
	}

	#if os(macOS)
		private func acceptAddressDrop(_ providers: [NSItemProvider]) -> Bool {
			guard let provider = providers.first,
			      let controller = browser.selectedTab?.activeController
			else { return false }
			let tabID = browser.selectedTabID
			let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
				? UTType.url.identifier
				: UTType.plainText.identifier
			guard provider.hasItemConformingToTypeIdentifier(type) else { return false }
			provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
				let text: String? = if let url = item as? URL {
					url.absoluteString
				} else if let data = item as? Data {
					String(data: data, encoding: .utf8)
				} else if let string = item as? String {
					string
				} else if let string = item as? NSString {
					string as String
				} else if let url = item as? NSURL {
					url.absoluteString
				} else {
					nil
				}
				Task { @MainActor in
					guard browser.selectedTabID == tabID,
					      browser.selectedTab?.activeController === controller,
					      let text,
					      text.utf8.count <= 8192,
					      let destination = BrowserAddress.destination(
					      	for: text,
					      	configuration: browser.browserSearchConfiguration,
					      	isPrivate: browser.isPrivate
					      ),
					      ["http", "https"].contains(destination.scheme?.lowercased() ?? "")
					else { return }
					controller.loadFromAddressBar(destination)
				}
			}
			return true
		}
	#endif
}

private struct DownloadFlightOverlay: View {
	let flight: DownloadFlight?
	let flightProgress: Double
	let sidebarShown: Bool
	let theme: BrowserTheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		GeometryReader { geometry in
			if let flight, !reduceMotion {
				let startX = (sidebarShown ? BrowserChromeMetrics.expandedSidebarWidth : 0)
					+ (geometry.size.width - (sidebarShown ? BrowserChromeMetrics.expandedSidebarWidth : 0)) * flight.source.x
				let topBarHeight = sidebarShown ? BrowserChromeMetrics.topBarRegionHeight : 0
				let startY = topBarHeight
					+ (geometry.size.height - topBarHeight) * flight.source.y
				let endX: CGFloat = 25
				let endY = geometry.size.height - 24
				Image(systemName: flight.symbol)
					.font(.system(size: 24, weight: .semibold))
					.foregroundStyle(theme.progressColor)
					.scaleEffect(1 - flightProgress * 0.65)
					.opacity(1 - flightProgress * 0.2)
					.position(
						x: startX + (endX - startX) * flightProgress,
						y: startY + (endY - startY) * flightProgress - sin(flightProgress * .pi) * 60
					)
					.accessibilityHidden(true)
			}
		}
	}
}

#if os(macOS)
	private struct TabDragOverlay: View {
		let browser: Browser
		let hostWindow: NSWindow?
		@State private var tabDrag = BrowserTabDragCoordinator.shared

		var body: some View {
			GeometryReader { geometry in
				if let tabID = tabDrag.activeTabID,
				   let tab = browser.tab(withID: tabID),
				   let hostWindow
				{
					let point = hostWindow.convertPoint(fromScreen: tabDrag.screenPoint)
					Label(tab.title, systemImage: tab.internalPage?.symbol ?? "globe")
						.padding(.horizontal, 12)
						.padding(.vertical, 8)
						.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
						.position(x: point.x, y: geometry.size.height - point.y)
						.accessibilityHidden(true)
				}
			}
		}
	}
#endif

#Preview {
	DesktopBrowserShell(browser: Browser())
}
