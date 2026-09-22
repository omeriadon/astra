import Defaults
import Haze
import SwiftUI
import WebKit

let topBarItemWidth: CGFloat = 8
let topBarItemHeight: CGFloat = 14

let topHeight: CGFloat = 33

struct DesktopBrowserShell: View {
	let browser: Browser
	@Environment(\.colorScheme) private var colorScheme
	@Default(.topBarBackgroundStyle) private var topBarBackgroundStyle
	@State private var sidebarShown = true
	@State private var toastManager = ToastManager.shared
	#if os(macOS)
		@Default(.tabSwitchingOrder) private var tabSwitchingOrder
		@State private var controlTabSwitcher: ControlTabSwitcher
	#endif

	init(browser: Browser) {
		self.browser = browser
		#if os(macOS)
			_controlTabSwitcher = State(initialValue: ControlTabSwitcher(browser: browser))
		#endif
	}

	var isLocalhost: Bool {
		browser.selectedTab?.activeController.url?.host.map { host in
			host == "localhost"
				|| host.hasSuffix(".localhost")
				|| host == "127.0.0.1"
				|| host == "::1"
		} ?? false
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

				#if os(macOS)
					Spacer()
						.contentShape(Rectangle())
						.gesture(WindowDragGesture())
				#endif
			}
			.frame(width: sidebarShown ? 224 : 125, alignment: .leading)
			.environment(
				\.colorScheme,
				sidebarShown ? colorScheme : topBarColorScheme
			)

			HStack(spacing: 6) {
				BrowserNavigationControls(controller: browser.selectedTab?.activeController)

				BrowserAddressField(browser: browser)

				Spacer()
			}
			.padding(.leading, sidebarShown ? 1.5 : 20)
			.padding(.top, sidebarShown ? 8 : 0)
			#if os(macOS)
				.overlay(alignment: .top) {
					Color.clear
						.frame(height: sidebarShown ? 8 : 0)
						.contentShape(Rectangle())
						.gesture(WindowDragGesture())
				}
			#endif
		}
		.frame(width: nil, height: topHeight, alignment: .center)
		.animation(.smooth(duration: 0.3), value: sidebarShown)
	}

	private var topBarColorScheme: ColorScheme {
		guard let themeColorIsLight = browser.selectedTab?.activeController.themeColorIsLight else { return colorScheme }
		return themeColorIsLight ? .light : .dark
	}

	private var topBarBackgroundShape: UnevenRoundedRectangle {
		UnevenRoundedRectangle(
			topLeadingRadius: sidebarShown ? 10 : 16,
			bottomLeadingRadius: sidebarShown ? 12 : 6,
			bottomTrailingRadius: sidebarShown ? 12 : 6,
			topTrailingRadius: sidebarShown ? 10 : 16
		)
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
						.foregroundStyle(.secondary)
						.accessibilityIdentifier("new-tab")

						#if os(macOS)
							Color.clear
								.containerRelativeFrame(.vertical)
								.contentShape(Rectangle())
								.gesture(WindowDragGesture())
								.accessibilityHidden(true)
						#endif
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

				Group {
					if topBarBackgroundStyle == .glass {
						VStack {}
							.frame(height: topHeight)
							.frame(maxWidth: .infinity)
							.glassEffect(.clear, in: topBarBackgroundShape)
					} else {
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
						.frame(maxWidth: .infinity)
						.clipShape(topBarBackgroundShape)
					}
				}
				.overlay {
					if let themeColor = browser.selectedTab?.activeController.themeColor {
						themeColor.opacity(0.6)
							.clipShape(topBarBackgroundShape)
					}
				}
				.overlay(alignment: .bottom) {
					if let controller = browser.selectedTab?.activeController {
						VStack {
							Spacer()

							BrowserLoadingBar(
								isLoading: controller.isLoading,
								estimatedProgress: controller.estimatedProgress
							)
							.frame(height: 1.5)
							.frame(maxWidth: .infinity)
						}
						.frame(height: topHeight)
						.clipShape(topBarBackgroundShape)
						.id(browser.selectedTabID)
					}
				}

				VStack(spacing: 0) {
					Color.clear
						.frame(height: topHeight)
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
						.padding(.top, topHeight + 12)
						.padding(.trailing, 14)
						.transition(.move(edge: .trailing))
				}
			}
			.animation(.easeOut(duration: 0.1), value: toastManager.toast != nil)
			.clipShape(RoundedRectangle(cornerRadius: sidebarShown ? 13 : 16))
			.overlay {
				if isLocalhost {
					RoundedRectangle(cornerRadius: sidebarShown ? 13 : 16)
						.inset(by: -2)
						.strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 5]))
						.foregroundStyle(.yellow)
				}
			}
			.animation(.smooth(duration: 0.3)) { view in
				view
					.padding(sidebarShown ? 4 : 0)
			}
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
		#endif
		.ignoresSafeArea()
		.focusedValue(\.browser, browser)
	}
}

#Preview {
	DesktopBrowserShell(browser: Browser())
}
