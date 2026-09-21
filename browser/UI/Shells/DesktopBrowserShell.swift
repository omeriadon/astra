import Haze
import SwiftUI
import WebKit

let topBarItemWidth: CGFloat = 8
let topBarItemHeight: CGFloat = 14

let topHeight: CGFloat = 33

struct TopBarButton: Identifiable {
	let title: String
	let systemImage: String
	let accessibilityIdentifier: String
	let isDisabled: Bool
	let action: () -> Void
	let modifier: String

	var id: String {
		accessibilityIdentifier
	}
}

struct DesktopBrowserShell: View {
	let browser: Browser
	@Environment(\.colorScheme) private var colorScheme
	@State private var sidebarShown = true
	#if os(macOS)
		@AppStorage("tabSwitchingOrder") private var tabSwitchingOrder = TabSwitchingOrder.visibleTabList.rawValue
		@State private var controlTabSwitcher: ControlTabSwitcher
	#endif

	init(browser: Browser) {
		self.browser = browser
		#if os(macOS)
			_controlTabSwitcher = State(initialValue: ControlTabSwitcher(browser: browser))
		#endif
	}

	private var navigationButtons: [TopBarButton] {
		[
			TopBarButton(
				title: "Back",
				systemImage: "chevron.backward",
				accessibilityIdentifier: "browser-back",
				isDisabled: !(browser.selectedTab?.controller.canGoBack ?? false),
				action: { browser.selectedTab?.controller.goBack() },
				modifier: "["
			),
			TopBarButton(
				title: "Forward",
				systemImage: "chevron.forward",
				accessibilityIdentifier: "browser-forward",
				isDisabled: !(browser.selectedTab?.controller.canGoForward ?? false),
				action: { browser.selectedTab?.controller.goForward() },
				modifier: "]"
			),
			TopBarButton(
				title: "Refresh",
				systemImage: "arrow.clockwise",
				accessibilityIdentifier: "browser-reload",
				isDisabled: false,
				action: { browser.selectedTab?.controller.reload() },
				modifier: "R"
			),
		]
	}

	private var topBar: some View {
		HStack {
			HStack(spacing: 0) {
				Spacer()
					.frame(width: 85)

				Button {
					sidebarShown.toggle()
				} label: {
					Label("Toggle Sidebar", systemImage: "sidebar.leading")
						.labelStyle(.iconOnly)
						.frame(width: topBarItemWidth, height: topBarItemHeight)
				}
				.controlSize(.regular)
				.buttonSizing(.fitted)
				.keyboardShortcut("S", modifiers: .command)
				.buttonStyle(.bordered)
				.clipShape(RoundedRectangle(cornerRadius: 8))
				.accessibilityIdentifier("sidebar-toggle")
			}
			.frame(width: sidebarShown ? 224 : 125, alignment: .leading)

			HStack(spacing: 6) {
				ForEach(navigationButtons) { item in
					Button(action: item.action) {
						Label(item.title, systemImage: item.systemImage)
							.labelStyle(.iconOnly)
							.frame(width: topBarItemWidth, height: topBarItemHeight)
					}
					.keyboardShortcut(KeyEquivalent(item.modifier.first!), modifiers: .command)
					.disabled(item.isDisabled)
					.controlSize(.regular)
					.buttonSizing(.fitted)
					.clipShape(RoundedRectangle(cornerRadius: 8))
					.buttonStyle(.bordered)
					.accessibilityIdentifier(item.accessibilityIdentifier)
				}

				BrowserAddressField(browser: browser)

				Spacer()
			}
			.padding(.leading, sidebarShown ? 1.5 : 20)
			.padding(.top, sidebarShown ? 8 : 0)
		}
		.frame(width: nil, height: topHeight, alignment: .center)
		.animation(.smooth(duration: 0.3), value: sidebarShown)
	}

	private var topBarColorScheme: ColorScheme {
		guard let themeColorIsLight = browser.selectedTab?.controller.themeColorIsLight else { return colorScheme }
		return themeColorIsLight ? .light : .dark
	}

	var body: some View {
		BrowserSplitView(sidebarShown: $sidebarShown) {
			ZStack(alignment: .top) {
				ScrollView {
					LazyVStack(spacing: 5) {
						ForEach(browser.tabs) { tab in
							BrowserTabRow(
								tab: tab,
								isSelected: browser.selectedTabID == tab.id,
								onSelect: browser.selectTab,
								onClose: browser.closeTab
							)
						}

						Spacer(minLength: 0)

						Button("New Tab", systemImage: "plus") {
							browser.addTab()
						}
						.keyboardShortcut("T", modifiers: .command)
						.padding(.leading, 8)
						.buttonStyle(.plain)
						.frame(maxWidth: .infinity, alignment: .leading)
						.accessibilityIdentifier("new-tab")
					}
					.padding(.horizontal, 7)
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
				.frame(height: topHeight)
				.frame(maxWidth: .infinity)
			}

		} content: {
			ZStack(alignment: .top) {
				BrowserContentView(
					browser: browser,
					insets: BrowserViewportInsets(
						obscured: EdgeInsets(top: topHeight, leading: 0, bottom: 0, trailing: 0),
						minimum: EdgeInsets(top: topHeight, leading: 0, bottom: 0, trailing: 0),
						maximum: EdgeInsets(top: topHeight, leading: 0, bottom: 0, trailing: 0)
					)
				)

				HazeEffect(
					maskProvider: LinearGradientMaskProvider(
						startPoint: .top,
						endPoint: .bottom,
						startOpacity: 1.0,
						endOpacity: 1.0,
						isSmooth: false
					),
					maxBlurRadius: 6
				)
				.frame(height: topHeight)
				.frame(maxWidth: .infinity)
				.overlay {
					if let themeColor = browser.selectedTab?.controller.themeColor {
						themeColor.opacity(0.6)
					}
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: sidebarShown ? 13 : 16))
			.animation(.smooth(duration: 0.3)) { view in
				view
					.padding(sidebarShown ? 4 : 0)
			}
			.shadow(color: browser.selectedTab?.controller.themeColor?.opacity(0.8) ?? .black.opacity(0.8), radius: 11)
		}
		.background(.blue)
		.overlay(alignment: .top) {
			topBar
				.environment(\.colorScheme, topBarColorScheme)
		}
		#if os(macOS)
		.overlay {
			ControlTabSwitcherPreview(browser: browser, switcher: controlTabSwitcher)
				.animation(.easeInOut(duration: 0.05), value: controlTabSwitcher.isPreviewVisible)
		}
		.onAppear {
			controlTabSwitcher.start(order: TabSwitchingOrder(rawValue: tabSwitchingOrder) ?? .visibleTabList)
		}
		.onChange(of: tabSwitchingOrder) { _, value in
			controlTabSwitcher.start(order: TabSwitchingOrder(rawValue: value) ?? .visibleTabList)
		}
		.onChange(of: browser.tabs.map(\.id)) { _, _ in
			controlTabSwitcher.tabsDidChange()
		}
		.onDisappear {
			controlTabSwitcher.stop()
		}
		#endif
		.ignoresSafeArea()
	}
}

#Preview {
	DesktopBrowserShell(browser: Browser())
}
