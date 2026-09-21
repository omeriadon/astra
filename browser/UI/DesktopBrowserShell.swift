import Haze
import SwiftUI
import WebKit

let topBarItemWidth: CGFloat = 8
let topBarItemHeight: CGFloat = 14

let topHeight: CGFloat = 33

struct TopBarButton: Identifiable {
	let id = UUID()
	let title: String
	let systemImage: String
	let accessibilityIdentifier: String
	let isDisabled: Bool
	let action: () -> Void
}

struct DesktopBrowserShell: View {
	let browser: Browser
	@State private var sidebarShown = true

	private var navigationButtons: [TopBarButton] {
		[
			TopBarButton(
				title: "Back",
				systemImage: "chevron.backward",
				accessibilityIdentifier: "browser-back",
				isDisabled: !(browser.selectedTab?.controller.canGoBack ?? false),
				action: { browser.selectedTab?.controller.goBack() }
			),
			TopBarButton(
				title: "Forward",
				systemImage: "chevron.forward",
				accessibilityIdentifier: "browser-forward",
				isDisabled: !(browser.selectedTab?.controller.canGoForward ?? false),
				action: { browser.selectedTab?.controller.goForward() }
			),
			TopBarButton(
				title: "Refresh",
				systemImage: "arrow.clockwise",
				accessibilityIdentifier: "browser-reload",
				isDisabled: false,
				action: { browser.selectedTab?.controller.reload() }
			),
		]
	}

	private var topBar: some View {
		HStack {
			HStack(spacing: 0) {
				Spacer()
					.frame(width: 90)

				let sidebarToggle = Button {
					sidebarShown.toggle()
				} label: {
					Label("Toggle Sidebar", systemImage: "sidebar.leading")
						.labelStyle(.iconOnly)
				}
				.controlSize(.regular)
				.buttonSizing(.fitted)
				.buttonBorderShape(.roundedRectangle(radius: 6))
				.keyboardShortcut("S", modifiers: .command)

				ZStack {
					if !sidebarShown {
						sidebarToggle
							.buttonStyle(.bordered)
							.transition(.opacity)

					} else {
						sidebarToggle
							.buttonStyle(.plain)
							.transition(.opacity)
					}
				}
				.frame(width: topBarItemWidth, height: topBarItemHeight)
				.accessibilityIdentifier("sidebar-toggle")

				if sidebarShown {
					Spacer()
				}
			}
			.frame(width: sidebarShown ? 224 : nil)

			HStack(spacing: 6) {
				ForEach(navigationButtons) { item in
					Button(action: item.action) {
						Label(item.title, systemImage: item.systemImage)
							.labelStyle(.iconOnly)
							.frame(width: topBarItemWidth, height: topBarItemHeight)
					}
					.disabled(item.isDisabled)
					.controlSize(.regular)
					.buttonSizing(.fitted)
					.clipShape(RoundedRectangle(cornerRadius: (sidebarShown ? 13 : 15) - 5))
					.buttonStyle(.bordered)
					.accessibilityIdentifier(item.accessibilityIdentifier)
				}

				Text(browser.selectedTab?.controller.url?.absoluteString ?? "new tab")
					.lineLimit(1)

				Spacer()
			}
			.padding(.leading, sidebarShown ? 1.5 : 20)
		}
		.frame(width: nil, height: topHeight, alignment: .center)
		.animation(.smooth(duration: 0.3), value: sidebarShown)
	}

	var body: some View {
		BrowserSplitView(sidebarShown: $sidebarShown) {
			ScrollView {
				VStack(spacing: 18) {
					Button("New Tab", systemImage: "plus") {
						browser.addTab()
					}
					.buttonStyle(.plain)
					.accessibilityIdentifier("new-tab")

					ForEach(browser.tabs) { tab in
						BrowserTabRow(
							tab: tab,
							isSelected: browser.selectedTabID == tab.id,
							onSelect: browser.selectTab,
							onClose: browser.closeTab
						)
					}

					Spacer(minLength: 0)
				}
				.padding(12)
				.padding(.top, 22)
				.frame(maxHeight: .infinity)
			}

		} content: {
			ZStack(alignment: .top) {
				BrowserContentView(
					browser: browser,
					insets: BrowserViewportInsets(
						obscured: EdgeInsets(top: topHeight - 5, leading: 0, bottom: 0, trailing: 0),
						minimum: EdgeInsets(top: topHeight - 5, leading: 0, bottom: 0, trailing: 0),
						maximum: EdgeInsets(top: topHeight - 5, leading: 0, bottom: 0, trailing: 0)
					)
				)

				HazeEffect(
					maskProvider: LinearGradientMaskProvider(
						startPoint: .center,
						endPoint: .bottom,
						startOpacity: 1.0,
						endOpacity: 1,
						isSmooth: true
					),
					maxBlurRadius: 5
				)
				.frame(height: topHeight)
				.frame(maxWidth: .infinity)

//					LinearGradient(colors: [.blue, .clear], startPoint: .top, endPoint: .bottom)
//						.frame(height: topHeight)
//						.frame(maxWidth: .infinity)
			}
			.clipShape(RoundedRectangle(cornerRadius: sidebarShown ? 13 : 15))
			.animation(.smooth(duration: 0.3)) { view in
				view
					.padding(sidebarShown ? 4 : 0)
			}
		}
		.background(.blue)
		.overlay(alignment: .top) {
			topBar
				.padding(.top, sidebarShown ? 4 : 0)
		}
		.ignoresSafeArea()
	}
}

#Preview {
	DesktopBrowserShell(browser: Browser())
}
