import Haze
import SwiftUI
import WebKit

struct DesktopBrowserShell: View {
	let browser: Browser
	@State private var sidebarShown = true

	var body: some View {
		ZStack(alignment: .topLeading) {
			BrowserSplitView(sidebarShown: $sidebarShown) {
				ScrollView {
					VStack(spacing: 18) {
						ForEach(0 ..< 40) { _ in
							RoundedRectangle(cornerRadius: 24)
								.fill(.green)
								.frame(height: 28)
						}
						Spacer(minLength: 0)
					}
					.padding(12)
					.padding(.top, 22)
					.frame(maxHeight: .infinity)
				}

			} content: {
				BrowserContentView(
					browser: browser,
					insets: BrowserViewportInsets(
						obscured: EdgeInsets(top: 35, leading: 0, bottom: 0, trailing: 0),
						minimum: EdgeInsets(top: 35, leading: 0, bottom: 0, trailing: 0),
						maximum: EdgeInsets(top: 35, leading: 0, bottom: 0, trailing: 0)
					)
				)
				.clipShape(RoundedRectangle(cornerRadius: sidebarShown ? 13 : 15))
				.animation(.smooth(duration: 0.3)) { view in
					view
						.padding(sidebarShown ? 4 : 0)
				}
			}
			.background(.blue)

			HazeEffect(
				maskProvider: LinearGradientMaskProvider(
					startPoint: .bottom,
					endPoint: .top,
					startOpacity: 0,
					endOpacity: 1
				),
				maxBlurRadius: 10
			)
			.frame(height: 35)
			.frame(maxWidth: .infinity)

			HStack {
				Spacer()
					.frame(width: 85)

				let sidebarToggle = Button {
					sidebarShown.toggle()
				} label: {
					Label("Toggle Sidebar", systemImage: "sidebar.leading")
						.labelStyle(.iconOnly)
				}
				.controlSize(.regular)
				.buttonSizing(.fitted)
				.buttonBorderShape(.roundedRectangle(radius: 6))
				.frame(width: 14, height: 12)

				ZStack {
					if sidebarShown {
						sidebarToggle
							.buttonStyle(.glass)
							.glassEffectTransition(.materialize)

					} else {
						sidebarToggle
							.buttonStyle(.plain)
							.transition(.blurReplace)
					}
				}
				.animation(.smooth(duration: 0.3), value: sidebarShown)

				Button {
					browser.selectedTab?.controller.goBack()
				} label: {
					Label("Back", systemImage: "chevron.backward")
						.labelStyle(.iconOnly)
				}
				.buttonStyle(.plain)
				.disabled(!(browser.selectedTab?.controller.canGoBack ?? false))
				.accessibilityIdentifier("browser-back")

				Button {
					browser.selectedTab?.controller.goForward()
				} label: {
					Label("Forward", systemImage: "chevron.forward")
						.labelStyle(.iconOnly)
				}
				.buttonStyle(.plain)
				.disabled(!(browser.selectedTab?.controller.canGoForward ?? false))
				.accessibilityIdentifier("browser-forward")

				Spacer()
			}
			.padding(.top, 10)
		}
		.ignoresSafeArea()
	}
}

#Preview {
	DesktopBrowserShell(browser: Browser())
}
