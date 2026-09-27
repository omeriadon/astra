import Defaults
import Haze
import SwiftUI
import WebKit

struct DesktopBrowserShell: View {
	@Bindable var browser: Browser
	@Environment(\.colorScheme) private var colorScheme
	private var theme: BrowserTheme {
		browser.theme
	}

	@Default(.sidebarShown) private var sidebarShown
	@State private var toastManager = ToastManager.shared
	@State private var downloads = BrowserDownloadManager.shared
	@State private var showsDownloads = false
	@State private var flight: DownloadFlight?
	@State private var flightProgress = 0.0
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var isFullScreen = false
	@State private var transitionFromTheme: BrowserTheme?
	@State private var transitionToTheme: BrowserTheme?
	@State private var themeBlend = 0.0
	@State private var themeTransitionGeneration = 0
	#if os(macOS)
		@State private var controlTabSwitcher: ControlTabSwitcher
		@State private var windowRegistry = BrowserWindowRegistry.shared
		@State private var tabDrag = BrowserTabDragCoordinator.shared
		@State private var hostWindow: NSWindow?
	#endif

	@State private var quitExpiry: Date = .distantPast

	init(browser: Browser) {
		self.browser = browser
		#if os(macOS)
			_controlTabSwitcher = State(initialValue: ControlTabSwitcher(browser: browser))
		#endif
	}

	var isLocalhost: Bool {
		browser.selectedTab?.activeController?.url?.host.map { host in
			host == "localhost"
				|| host.hasSuffix(".localhost")
				|| host == "127.0.0.1"
				|| host == "::1"
		} ?? false
	}

	private var websiteControls: some View {
		HStack(spacing: 10) {
			if let controller = browser.selectedTab?.activeController {
				BrowserNavigationControls(controller: controller)
					.id(ObjectIdentifier(controller))
			}

			BrowserAddressField(browser: browser)
		}
		.padding(
			.leading,
			sidebarShown
				? (isFullScreen ? 0 : 10)
				: (isFullScreen ? 80 : BrowserChromeMetrics.persistentControlsAreaWidth)
		)
		.padding(.trailing, 10)
		.frame(height: BrowserChromeMetrics.topBarRegionHeight)
		.frame(maxWidth: .infinity, alignment: .leading)
		.environment(\.colorScheme, topBarColorScheme)
	}

	private var navigationBarControls: some View {
		HStack(spacing: 5) {
			Spacer()
				.frame(width: isFullScreen ? 0 : 80)

			Button {
				browser.sidebarShown.toggle()
			} label: {
				Label("Toggle Sidebar", systemImage: "sidebar.leading")
					.labelStyle(.iconOnly)
					.frame(
						width: BrowserChromeMetrics.topBarButtonLabelWidth,
						height: BrowserChromeMetrics.topBarButtonLabelHeight
					)
					.font(.body.scaled(by: 0.9))
			}
			.controlSize(.regular)
			.labelStyle(.iconOnly)
			.buttonSizing(.fitted)
			.keyboardShortcut("S", modifiers: .command)
			.buttonStyle(.bordered)
			.foregroundStyle(theme.foregroundColor)
			.buttonBorderShape(.roundedRectangle(radius: BrowserChromeMetrics.topBarButtonCornerRadius))
			.accessibilityIdentifier("sidebar-toggle")

			Button {
				browser.openInternalPage(.themeEditor)

			} label: {
				Label("Edit Theme", systemImage: "paintpalette")
					.labelStyle(.iconOnly)
					.frame(
						width: BrowserChromeMetrics.topBarButtonLabelWidth,
						height: BrowserChromeMetrics.topBarButtonLabelHeight
					)
					.font(.body.scaled(by: 0.9))
			}
			.controlSize(.regular)
			.buttonSizing(.fitted)
			.buttonStyle(.bordered)
			.foregroundStyle(theme.foregroundColor)
			.buttonBorderShape(.roundedRectangle(radius: BrowserChromeMetrics.topBarButtonCornerRadius))
			.accessibilityIdentifier("edit-browser-theme")
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

	private var topBarColorScheme: ColorScheme {
		guard let themeColorIsLight = browser.selectedTab?.activeController?.themeColorIsLight else { return colorScheme }
		return themeColorIsLight ? .light : .dark
	}

	private var topBarBackgroundShape: RoundedRectangle {
		RoundedRectangle(cornerRadius: contentCornerRadius)
	}

	private var contentCornerRadius: CGFloat {
		sidebarShown
			? BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar
			: BrowserChromeMetrics.tabWindowCornerRadiusWithoutSidebar
	}

	@State private var newTabHovered = false

	private struct DownloadFlight: Identifiable {
		let id: UUID
		let source: UnitPoint
		let symbol: String
	}

	@State private var downloadsHover = false
	@State private var addSpaceHover = false

	private var downloadsBottomBar: some View {
		HStack {
			Button {
				withAnimation(reduceMotion ? .none : .smooth(duration: 0.32)) {
					showsDownloads.toggle()
				}
			} label: {
				HStack(spacing: 9) {
					ZStack {
						Image(systemName: downloads.buttonSymbol)
						if let progress = downloads.activeProgress {
							Circle()
								.trim(from: 0, to: progress)
								.stroke(theme.progressColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
								.rotationEffect(.degrees(-90))
						}
					}
				}
				.frame(width: 25, height: 25)
				.background {
					if downloadsHover {
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.primary.gradient)
							.opacity(0.3)
					}
					if showsDownloads {
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.primary.gradient)
							.opacity(0.4)
					}
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.keyboardShortcut("J", modifiers: .command)
			.accessibilityLabel(showsDownloads ? "Show Tabs" : "Show Downloads")
			.accessibilityValue(downloads.activeProgress.map { "\(Int($0 * 100)) percent" } ?? "No active downloads")
			.accessibilityIdentifier("downloads-button")
			.onHover { i in
				withAnimation(.smooth(duration: 0.1)) {
					downloadsHover = i
				}
			}

			BrowserSpacesBar(browser: browser, onSwipeProgress: previewSpaceTheme)
				.frame(maxWidth: .infinity)

			Button {
				browser.createSpace()
			} label: {
				Image(systemName: "plus")
					.frame(width: 25, height: 25)
					.background {
						if addSpaceHover {
							RoundedRectangle(cornerRadius: 8)
								.fill(Color.primary.gradient)
								.opacity(0.3)
						}
					}
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Add Space")
			.accessibilityIdentifier("add-space")
			.onHover { addSpaceHover = $0 }
		}
		.padding([.horizontal, .bottom], 8)
	}

	private var newTabButton: some View {
		Button {
			browser.addTab()
		} label: {
			Label("New Tab", systemImage: "plus")
				.frame(maxWidth: .infinity, alignment: .leading)
				.contentShape(Rectangle())
		}
		.keyboardShortcut("T", modifiers: .command)
		.buttonStyle(.plain)
		.padding(.horizontal, 8)
		.foregroundStyle(theme.foregroundColor.opacity(0.65))
		.onHover { newTabHovered = $0 }
		.frame(height: 28)
		.background {
			if newTabHovered {
				Color.clear.glassEffect(
					.regular,
					in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
				)
			}
		}
		.accessibilityIdentifier("new-tab")
	}

	private var tabSidebar: some View {
		ScrollView {
			LazyVStack(spacing: 2) {
				LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
					ForEach(browser.favouriteTabs) { tab in
						BrowserFavouriteTile(tab: tab, browser: browser)
					}
				}
				.frame(minHeight: browser.favouriteTabs.isEmpty ? 34 : 42)
				.padding(.bottom, 12)
				#if os(macOS)
					.background {
						BrowserDropZone(browser: browser, area: .favourite, spaceID: nil, beforeTabID: nil)
					}
				#endif

				VStack(spacing: 2) {
					ForEach(browser.pinnedTabs) { tab in
						BrowserTabRow(tab: tab, browser: browser, isSelected: browser.selectedTabID == tab.id)
					}
				}
				.frame(minHeight: 28)
				#if os(macOS)
					.background {
						BrowserDropZone(browser: browser, area: .pinned, spaceID: browser.workspace.selectedSpaceID, beforeTabID: nil)
					}
				#endif
				if !browser.pinnedTabs.isEmpty {
					Divider()
						.padding(.vertical, 8)
				}
				VStack(spacing: 2) {
					ForEach(browser.normalTabs) { tab in
						BrowserTabRow(tab: tab, browser: browser, isSelected: browser.selectedTabID == tab.id)
					}
					newTabButton
				}
				#if os(macOS)
				.background {
					BrowserDropZone(browser: browser, area: .normal, spaceID: browser.workspace.selectedSpaceID, beforeTabID: nil)
				}
				#endif
			}
			.padding(.horizontal, BrowserChromeMetrics.shellEdgePadding)
			.padding(.top, 35)
		}
	}

	private var animatedThemeBackground: some View {
		ZStack {
			if let transitionFromTheme, let transitionToTheme {
				BrowserThemeBackground(theme: transitionFromTheme)
				BrowserThemeBackground(theme: transitionToTheme)
					.opacity(themeBlend)
			} else {
				BrowserThemeBackground(theme: theme)
			}
		}
	}

	private func previewSpaceTheme(_ targetID: UUID?, progress: Double) {
		guard let targetID,
		      let target = browser.workspace.spaces.first(where: { $0.id == targetID })
		else {
			if transitionToTheme != nil, transitionToTheme != theme {
				withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
					themeBlend = 0
				}
			}
			return
		}
		if transitionToTheme != target.theme {
			transitionFromTheme = theme
			transitionToTheme = target.theme
			themeBlend = 0
		}
		withAnimation(reduceMotion ? nil : .smooth(duration: 0.12)) {
			themeBlend = progress
		}
	}

	private func completeSpaceThemeTransition(from oldID: UUID, to newID: UUID) {
		let oldTheme = browser.workspace.spaces.first(where: { $0.id == oldID })?.theme ?? theme
		transitionFromTheme = transitionFromTheme ?? oldTheme
		transitionToTheme = theme
		themeTransitionGeneration += 1
		let generation = themeTransitionGeneration
		withAnimation(reduceMotion ? nil : .smooth(duration: 0.3), completionCriteria: .logicallyComplete) {
			themeBlend = 1
		} completion: {
			guard generation == themeTransitionGeneration,
			      browser.workspace.selectedSpaceID == newID
			else { return }
			transitionFromTheme = nil
			transitionToTheme = nil
			themeBlend = 0
		}
	}

	var body: some View {
		BrowserSplitView(sidebarShown: $browser.sidebarShown) {
			VStack(spacing: 0) {
				ZStack(alignment: .top) {
					tabSidebar
						.foregroundStyle(theme.foregroundColor)
						.offset(x: showsDownloads ? BrowserChromeMetrics.expandedSidebarWidth : 0)

					DownloadsSidebarView(manager: downloads, theme: theme)
						.foregroundStyle(theme.foregroundColor)
						.offset(x: showsDownloads ? 0 : -BrowserChromeMetrics.expandedSidebarWidth)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.safeAreaBar(edge: .bottom) {
					downloadsBottomBar
						.foregroundStyle(theme.foregroundColor)
				}
			}

		} content: {
			ZStack(alignment: .top) {
				BrowserContentView(
					browser: browser,
					insets: BrowserViewportInsets(
						obscured: EdgeInsets(top: browser.selectedTab?.internalPage == nil ? BrowserChromeMetrics.topBarRegionHeight : 0, leading: 0, bottom: 0, trailing: 0),
						minimum: EdgeInsets(top: browser.selectedTab?.internalPage == nil ? BrowserChromeMetrics.topBarRegionHeight : 0, leading: 0, bottom: 0, trailing: 0),
						maximum: EdgeInsets(top: browser.selectedTab?.internalPage == nil ? BrowserChromeMetrics.topBarRegionHeight : 0, leading: 0, bottom: 0, trailing: 0)
					)
				)
				#if os(macOS)
				.blur(radius: windowRegistry.hasActiveDuplicate(of: browser) ? 10 : 0)
				#endif

				Group {
					if browser.selectedTab?.internalPage == nil {
						HazeEffect(
							maskProvider: LinearGradientMaskProvider(
								startPoint: .top,
								endPoint: .bottom,
								startOpacity: 1.0,
								endOpacity: browser.selectedTab?.activeController?.hasTopEdgeContent == true ? 1.0 : 0.0,
								isSmooth: browser.selectedTab?.activeController?.hasTopEdgeContent == true
							),
							maxBlurRadius: browser.selectedTab?.activeController?.hasTopEdgeContent == true ? 8 : 4
						)
						.frame(height: BrowserChromeMetrics.topBarRegionHeight)
						.frame(maxWidth: .infinity)
					}
				}
				.background {
					if browser.selectedTab?.internalPage == nil,
					   let themeColor = browser.selectedTab?.activeController?.themeColor
					{
						themeColor.opacity(0.6)
							.mask {
								if browser.selectedTab?.activeController?.hasTopEdgeContent == true {
									Color.white
								} else {
									LinearGradient(colors: [.clear, .white], startPoint: .bottom, endPoint: .top)
								}
							}
					}
				}
				.overlay(alignment: .bottom) {
					if browser.selectedTab?.internalPage == nil,
					   let controller = browser.selectedTab?.activeController
					{
						VStack {
							Spacer()

							BrowserLoadingBar(
								isLoading: controller.isLoading,
								estimatedProgress: controller.estimatedProgress,
								theme: theme
							)
							.frame(height: 1.5)
							.frame(maxWidth: .infinity)
						}
						.frame(height: BrowserChromeMetrics.topBarRegionHeight)
						.clipShape(topBarBackgroundShape)
						.id(browser.selectedTabID)
					}
				}

				VStack(spacing: 0) {
					Color.clear
						.frame(height: browser.selectedTab?.internalPage == nil ? BrowserChromeMetrics.topBarRegionHeight : 0)
						.allowsHitTesting(false)

					if let tab = browser.selectedTab {
						PeekStackView(tab: tab, browser: browser)
							.id(tab.id)
					}
				}
			}
			.overlay(alignment: .topTrailing) {
				if let toast = toastManager.toast {
					BrowserToastView(toast: toast)
						.padding(.top, BrowserChromeMetrics.topBarRegionHeight + 12)
						.padding(.trailing, 14)
						.transition(.move(edge: .trailing))
				}
			}
			.animation(.easeOut(duration: 0.1), value: toastManager.toast != nil)
			.clipShape(RoundedRectangle(cornerRadius: contentCornerRadius))
			.overlay {
				if isLocalhost {
					RoundedRectangle(cornerRadius: contentCornerRadius)
						.inset(by: -2)
						.strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 5]))
						.foregroundStyle(.yellow)
				}
			}
			.animation(.smooth(duration: 0.3)) { view in
				view
					.padding(sidebarShown ? BrowserChromeMetrics.shellEdgePadding : 0)
			}
		}
		.background { animatedThemeBackground }
		.onChange(of: browser.workspace.selectedSpaceID) { oldID, newID in
			completeSpaceThemeTransition(from: oldID, to: newID)
		}
		#if os(macOS)
		.background {
			BrowserDropZone(
				browser: browser,
				area: .normal,
				spaceID: browser.workspace.selectedSpaceID,
				beforeTabID: nil,
				isWindowFallback: true
			)
		}
		.background {
			WindowFocusReader { window in
				hostWindow = window
				if window?.isKeyWindow == true {
					windowRegistry.activate(browser)
				}
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
			if let window = notification.object as? NSWindow, window === hostWindow {
				windowRegistry.activate(browser)
			}
		}
		.overlay(alignment: .top) {
			Color.clear
				.frame(height: BrowserChromeMetrics.windowDragStripHeight)
				.frame(maxWidth: .infinity)
				.contentShape(Rectangle())
				.gesture(WindowDragGesture())
				.accessibilityHidden(true)
		}
		#endif
		.overlay(alignment: .top) {
			if browser.selectedTab?.internalPage == nil {
				websiteControls
					.padding(
						.leading,
						sidebarShown
							? BrowserChromeMetrics.expandedSidebarWidth + BrowserChromeMetrics.shellEdgePadding
							: 0
					)
			}
		}
		.overlay(alignment: .topLeading) {
			navigationBarControls
		}
		.overlay {
			GeometryReader { geometry in
				if let flight, !reduceMotion {
					let startX = (sidebarShown ? BrowserChromeMetrics.expandedSidebarWidth : 0)
						+ (geometry.size.width - (sidebarShown ? BrowserChromeMetrics.expandedSidebarWidth : 0)) * flight.source.x
					let startY = BrowserChromeMetrics.topBarRegionHeight
						+ (geometry.size.height - BrowserChromeMetrics.topBarRegionHeight) * flight.source.y
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
			.allowsHitTesting(false)
		}
		#if os(macOS)
		.overlay {
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
		.overlay {
			ControlTabSwitcherPreview(browser: browser, switcher: controlTabSwitcher)
				.animation(.easeInOut(duration: 0.05), value: controlTabSwitcher.isPreviewVisible)
		}
		.onAppear {
			controlTabSwitcher.start()
			isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
		}
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
			isFullScreen = true
		}
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
			isFullScreen = false
		}
		.onChange(of: browser.visibleTabs.map(\.id)) { _, _ in
			controlTabSwitcher.tabsDidChange()
		}
		.onDisappear {
			controlTabSwitcher.stop()
		}
		.blur(radius: browser.isAboutToQuit ? 5 : 0)
		.overlay(alignment: .center) {
			TimelineView(.animation) { timeline in
				let showQuitMessage = timeline.date < quitExpiry

				GlassEffectContainer {
					if showQuitMessage {
						ZStack {
							Rectangle()
								.fill(Color.black.gradient)
								.opacity(0.2)

							Label {
								Text("Press \(Image(systemName: "command"))Q again to quit")
							} icon: {
								Image(systemName: "rectangle.portrait.and.arrow.right")
							}
							.monospaced()
							.font(.title2)
							.padding(.horizontal, 20)
							.padding(.vertical, 16)
							.glassEffect(
								.regular,
								in: RoundedRectangle(cornerRadius: 20)
							)
							.glassEffectTransition(.materialize)
						}
					}
				}
				.animation(.snappy(duration: 0.2), value: showQuitMessage)
			}
		}
		.onChange(of: browser.isAboutToQuit) { _, newValue in
			if newValue {
				quitExpiry = .now.addingTimeInterval(1)
			}
		}
		.task(id: quitExpiry) {
			guard quitExpiry > .now else { return }

			try? await Task.sleep(until: .now + .seconds(quitExpiry.timeIntervalSinceNow))

			guard Date.now >= quitExpiry else { return }
			browser.isAboutToQuit = false
		}
		.animation(.snappy(duration: 0.2), value: Date.now < quitExpiry)
		#endif
		.ignoresSafeArea()
		#if os(macOS)
			.focusedValue(\.browser, browser)
		#endif
	}
}

#Preview {
	DesktopBrowserShell(browser: Browser())
}
