import Defaults
import Haze
import SwiftUI
import WebKit
#if os(macOS)
	import UniformTypeIdentifiers
#endif

extension Notification.Name {
	static let showBrowserDownloads = Notification.Name("ShowBrowserDownloads")
}

struct DesktopBrowserShell: View {
	@Bindable var browser: Browser
	@Environment(\.colorScheme) private var colorScheme
	private var theme: BrowserTheme {
		browser.theme
	}

	@Default(.sidebarShown) private var sidebarShown
	@Default(.aiFeaturesEnabled) private var allAIFeatures
	private var downloads: BrowserDownloadManager {
		browser.session.downloads
	}

	@State private var showsDownloads = false
	@State private var flight: DownloadFlight?
	@State private var flightProgress = 0.0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var isFullScreen = false
	@State private var transitionFromTheme: BrowserTheme?
	@State private var transitionToTheme: BrowserTheme?
	@State private var themeBlend = 0.0
	@State private var themeTransitionGeneration = 0
	@State private var swipeTargetID: UUID?
	@State private var swipeProgress = 0.0
	@State private var swipeDirection: CGFloat = 1
	@State private var isTopBarRevealed = false
	#if os(macOS)
		@State private var hostWindow: NSWindow?
		@State private var windowButtonAnimationGeneration = 0
	#endif

	private var topBarColorScheme: ColorScheme {
		guard let themeColorIsLight = browser.selectedTab?.activeController?.themeColorIsLight else { return colorScheme }
		return themeColorIsLight ? .light : .dark
	}

	private var contentCornerRadius: CGFloat {
		sidebarShown
			? BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar
			: BrowserChromeMetrics.tabWindowCornerRadiusWithoutSidebar
	}

	#if os(macOS)
		private func updateWindowButtons(in window: NSWindow?, animated: Bool = true) {
			guard let window else { return }
			let hidden = !sidebarShown && !isTopBarRevealed
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

	private func previewSpaceTheme(_ targetID: UUID?, progress: Double) {
		guard let targetID,
		      let targetIndex = browser.workspace.spaces.firstIndex(where: { $0.id == targetID }),
		      let currentIndex = browser.workspace.spaces.firstIndex(where: { $0.id == browser.workspace.selectedSpaceID })
		else {
			withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
				swipeTargetID = nil
				swipeProgress = 0
				if transitionToTheme != nil, transitionToTheme != theme {
					themeBlend = 0
				}
			}
			return
		}
		let target = browser.workspace.spaces[targetIndex]
		swipeDirection = targetIndex > currentIndex ? 1 : -1
		swipeTargetID = targetID
		swipeProgress = reduceMotion ? 0 : progress
		if transitionToTheme != target.theme {
			transitionFromTheme = theme
			transitionToTheme = target.theme
			themeBlend = 0
		}
		themeBlend = progress
	}

	private func completeSpaceThemeTransition(from oldID: UUID, to newID: UUID) {
		if swipeTargetID == newID, swipeProgress >= 0.99 {
			swipeTargetID = nil
			swipeProgress = 0
			transitionFromTheme = nil
			transitionToTheme = nil
			themeBlend = 0
			return
		}
		swipeTargetID = nil
		swipeProgress = 0
		let oldTheme = browser.workspace.spaces.first(where: { $0.id == oldID })?.theme ?? theme
		transitionFromTheme = oldTheme
		transitionToTheme = theme
		themeBlend = 0
		themeTransitionGeneration += 1
		let generation = themeTransitionGeneration
		withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24), completionCriteria: .logicallyComplete) {
			themeBlend = 1
		} completion: {
			guard generation == themeTransitionGeneration,
			      browser.workspace.selectedSpaceID == newID else { return }
			transitionFromTheme = nil
			transitionToTheme = nil
			themeBlend = 0
		}
	}

	var body: some View {
		GeometryReader { geometry in
			let showsAI = allAIFeatures && browser.showsAISidebar && browser.canShowAISidebar && Defaults[.aiSidebar]
			BrowserSplitView(sidebarShown: $browser.sidebarShown) {
				ShellSidebarColumn(
					browser: browser,
					theme: theme,
					sidebarShown: sidebarShown,
					isFullScreen: isFullScreen,
					colorScheme: colorScheme,
					topBarColorScheme: topBarColorScheme,
					showsDownloads: $showsDownloads,
					swipeTargetID: swipeTargetID,
					swipeProgress: swipeProgress,
					swipeDirection: swipeDirection,
					downloads: downloads,
					onSwipeProgress: previewSpaceTheme
				)

			} content: {
				BrowserSplitView(sidebarShown: .constant(showsAI), sidebarWidth: min(360, geometry.size.width * 0.45) + BrowserChromeMetrics.shellEdgePadding, edge: .trailing) {
					BrowserAIChatSidebar(browser: browser, chat: browser.aiChat, isVisible: showsAI)
						.padding(.vertical, BrowserChromeMetrics.shellEdgePadding)
						.padding(.trailing, BrowserChromeMetrics.shellEdgePadding)
						.allowsHitTesting(showsAI)
						.accessibilityHidden(!showsAI)
				} content: {
					ShellContentColumn(
						browser: browser,
						theme: theme,
						sidebarShown: sidebarShown,
						isFullScreen: isFullScreen,
						colorScheme: colorScheme,
						topBarColorScheme: topBarColorScheme,
						transitionFromTheme: transitionFromTheme,
						transitionToTheme: transitionToTheme,
						themeBlend: themeBlend,
						contentCornerRadius: contentCornerRadius,
						windowWidth: geometry.size.width - (showsAI ? min(360, geometry.size.width * 0.45) + BrowserChromeMetrics.shellEdgePadding : 0),
						isTopBarRevealed: $isTopBarRevealed
					)
				}
			}
		}
		.background {
			BrowserThemeBackground(
				theme: transitionToTheme ?? theme,
				transitionFromTheme: transitionFromTheme,
				transitionProgress: themeBlend
			)
		}
		.onChange(of: browser.workspace.selectedSpaceID) { oldID, newID in
			completeSpaceThemeTransition(from: oldID, to: newID)
		}
		#if os(macOS)
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
		.onChange(of: sidebarShown) { _, _ in
			updateWindowButtons(in: hostWindow)
		}
		.onChange(of: isTopBarRevealed) { _, _ in
			updateWindowButtons(in: hostWindow)
		}
		#endif
		.overlay {
			DownloadFlightOverlay(
				flight: flight,
				flightProgress: flightProgress,
				sidebarShown: sidebarShown,
				theme: theme
			)
			.allowsHitTesting(false)
		}
		#if os(macOS)
		.overlay {
			TabDragOverlay(browser: browser, hostWindow: hostWindow)
				.allowsHitTesting(false)
		}
		#endif
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
			isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
		}
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
			isFullScreen = true
		}
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
			isFullScreen = false
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
		.frame(
			width: BrowserChromeMetrics.persistentControlsAreaWidth,
			height: BrowserChromeMetrics.topBarRegionHeight,
			alignment: .leading
		)
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
	let swipeTargetID: UUID?
	let swipeProgress: Double
	let swipeDirection: CGFloat
	let downloads: BrowserDownloadManager
	let onSwipeProgress: (UUID?, Double) -> Void

	var body: some View {
		VStack(spacing: 0) {
			ShellNavigationBarControls(
				browser: browser,
				theme: theme,
				isFullScreen: isFullScreen,
				sidebarShown: sidebarShown,
				colorScheme: colorScheme,
				topBarColorScheme: topBarColorScheme
			)
			.frame(maxWidth: .infinity, alignment: .leading)
			ZStack(alignment: .top) {
				Group {
					if browser.isPrivate {
						PrivateBrowserSidebar(browser: browser)
					} else {
						ShellSidebarListView(browser: browser, space: browser.selectedSpace, theme: theme)
					}
				}
				.foregroundStyle(theme.foregroundColor)
				.offset(x: showsDownloads ? BrowserChromeMetrics.expandedSidebarWidth : -swipeDirection * BrowserChromeMetrics.expandedSidebarWidth * swipeProgress)

				if !browser.isPrivate, let swipeTargetID,
				   let target = browser.workspace.spaces.first(where: { $0.id == swipeTargetID }),
				   !showsDownloads
				{
					ShellSidebarListView(browser: browser, space: target, theme: theme)
						.foregroundStyle(target.theme.foregroundColor)
						.allowsHitTesting(false)
						.offset(x: swipeDirection * BrowserChromeMetrics.expandedSidebarWidth * (1 - swipeProgress))
				}

				DownloadsSidebarView(manager: downloads, theme: theme)
					.foregroundStyle(theme.foregroundColor)
					.offset(x: showsDownloads ? 0 : -BrowserChromeMetrics.expandedSidebarWidth)
			}
			.clipped()
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.safeAreaInset(edge: .bottom, spacing: 0) {
				BrowserMediaActivityView(browser: browser)
					.padding(.horizontal, 8)
					.padding(.bottom, 48)
			}
			.overlay(alignment: .bottom) {
				ZStack(alignment: .bottom) {
					HazeEffect(
						maskProvider: LinearGradientMaskProvider(
							startPoint: .bottom,
							endPoint: .top,
							startOpacity: 1,
							endOpacity: 0,
							isSmooth: true
						),
						maxBlurRadius: 2
					)
					.frame(height: 56)
					.allowsHitTesting(false)
					ShellDownloadsBarView(
						browser: browser,
						theme: theme,
						downloads: downloads,
						showsDownloads: $showsDownloads,
						onSwipeProgress: onSwipeProgress
					)
					.foregroundStyle(theme.foregroundColor)
				}
			}
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
	let transitionFromTheme: BrowserTheme?
	let transitionToTheme: BrowserTheme?
	let themeBlend: Double
	let contentCornerRadius: CGFloat
	let windowWidth: CGFloat
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
			transitionFromTheme: transitionFromTheme,
			transitionToTheme: transitionToTheme,
			themeBlend: themeBlend
		)
	}

	private var topBarHeight: CGFloat {
		guard browser.selectedTab?.internalPage == nil, !browser.isShowingNewTab else { return 0 }
		guard sidebarShown || isTopBarRevealed else { return 0 }
		return BrowserChromeMetrics.topBarRegionHeight
			+ BrowserChromeMetrics.shellEdgePadding
	}

	var body: some View {
		ZStack(alignment: .top) {
			topBar
				.frame(width: max(0, windowWidth - BrowserChromeMetrics.expandedSidebarWidth))
				.frame(height: BrowserChromeMetrics.topBarRegionHeight + BrowserChromeMetrics.shellEdgePadding, alignment: .top)
				.transaction { transaction in
					transaction.animation = nil
				}
				.frame(maxWidth: .infinity, alignment: .trailing)
				.animation(reduceMotion ? nil : .smooth(duration: 0.3)) { content in
					content
						.offset(y: topBarHeight > 0 ? 0 : -BrowserChromeMetrics.topBarRegionHeight - BrowserChromeMetrics.shellEdgePadding)
						.opacity(topBarHeight > 0 ? 1 : 0)
				}
				.clipped()
				.zIndex(1)
				.allowsHitTesting(topBarHeight > 0)
				.accessibilityHidden(topBarHeight == 0)
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

			VStack(spacing: 0) {
				Spacer(minLength: 0)
					.frame(height: topBarHeight)
				BrowserPageView(browser: browser, cornerRadius: contentCornerRadius)
					.padding(.top, sidebarShown ? BrowserChromeMetrics.shellEdgePadding : 0)
					.padding([.bottom, .horizontal], sidebarShown ? BrowserChromeMetrics.shellEdgePadding : 0)
					.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: sidebarShown)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			.transaction { transaction in
				transaction.animation = nil
			}
		}
		.animation(nil, value: browser.selectedTabID)
		.onContinuousHover { phase in
			switch phase {
				case let .active(location):
					let revealHeight = isTopBarRevealed
						? BrowserChromeMetrics.topBarRegionHeight + BrowserChromeMetrics.shellEdgePadding
						: 6
					isTopBarRevealed = !sidebarShown && location.y < revealHeight
				case .ended:
					isTopBarRevealed = false
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
				   let tab = browser.tabs.first(where: { $0.id == tabID }),
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
