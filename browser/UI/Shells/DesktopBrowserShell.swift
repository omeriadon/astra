import Defaults
import Haze
import SwiftUI
import WebKit

struct DesktopBrowserShell: View {
	@Bindable var browser: Browser
	@Environment(\.colorScheme) private var colorScheme
	@Default(.browserTheme) private var theme
	@State private var sidebarShown = true
	@State private var toastManager = ToastManager.shared
	#if os(macOS)
		@Default(.tabSwitchingOrder) private var tabSwitchingOrder
		@State private var controlTabSwitcher: ControlTabSwitcher
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
		.padding(.leading, sidebarShown ? 10 : BrowserChromeMetrics.persistentControlsAreaWidth)
		.padding(.trailing, 10)
		.frame(height: BrowserChromeMetrics.topBarRegionHeight)
		.frame(maxWidth: .infinity, alignment: .leading)
		.environment(\.colorScheme, topBarColorScheme)
	}

	private var sidebarControls: some View {
		HStack(spacing: 5) {
			Spacer()
				.frame(width: 80)

			Button {
				sidebarShown.toggle()
			} label: {
				Label("Toggle Sidebar", systemImage: "sidebar.leading")
					.labelStyle(.iconOnly)
					.frame(
						width: BrowserChromeMetrics.topBarButtonLabelWidth,
						height: BrowserChromeMetrics.topBarButtonLabelHeight
					)
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

	var body: some View {
		BrowserSplitView(sidebarShown: $sidebarShown) {
			ZStack(alignment: .top) {
				ScrollView {
					LazyVStack(spacing: 2) {
						ForEach(browser.tabs) { tab in
							BrowserTabRow(
								tab: tab,
								browser: browser,
								isSelected: browser.selectedTabID == tab.id
							)
						}

						Spacer(minLength: 0)

						Button("New Tab", systemImage: "plus") {
							browser.addTab()
						}
						.keyboardShortcut("T", modifiers: .command)
						.padding(.leading, 8.5)
						.buttonStyle(.plain)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.top, 10)
						.foregroundStyle(theme.foregroundColor.opacity(0.65))
						.accessibilityIdentifier("new-tab")
					}
					.padding(.horizontal, BrowserChromeMetrics.shellEdgePadding)
					.padding(.top, 35)
				}

				HazeEffect(
					maskProvider: LinearGradientMaskProvider(
						startPoint: .top,
						endPoint: .bottom,
						startOpacity: 1,
						endOpacity: 0,
						isSmooth: true
					),
					maxBlurRadius: 2
				)
				.frame(height: BrowserChromeMetrics.topBarRegionHeight)
				.frame(maxWidth: .infinity)
			}
			.foregroundStyle(theme.foregroundColor)

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

				Group {
					if browser.selectedTab?.internalPage == nil {
						HazeEffect(
							maskProvider: LinearGradientMaskProvider(
								startPoint: .top,
								endPoint: .bottom,
								startOpacity: 1.0,
								endOpacity: browser.selectedTab?.activeController?.hasTopEdgeContent == true ? 1.0 : 0.0,
								isSmooth: false
							),
							maxBlurRadius: browser.selectedTab?.activeController?.hasTopEdgeContent == true ? 8 : 4
						)
						.frame(height: BrowserChromeMetrics.topBarRegionHeight)
						.frame(maxWidth: .infinity)
					}
				}
				.overlay {
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
								estimatedProgress: controller.estimatedProgress
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
		.background {
			BrowserThemeBackground(theme: theme)
		}
		#if os(macOS)
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
			sidebarControls
		}
		#if os(macOS)
		.overlay {
			ControlTabSwitcherPreview(browser: browser, switcher: controlTabSwitcher)
				.animation(.easeInOut(duration: 0.05), value: controlTabSwitcher.isPreviewVisible)
		}
		.onAppear {
			controlTabSwitcher.start(order: tabSwitchingOrder)
		}
		.onChange(of: tabSwitchingOrder) { _, value in
			controlTabSwitcher.start(order: value)
		}
		.onChange(of: browser.tabs.map(\.id)) { _, _ in
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
