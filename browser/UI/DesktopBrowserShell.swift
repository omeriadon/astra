import Haze
import SwiftUI
import WebKit

struct DesktopBrowserShell: View {
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
				Color.teal
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

				Spacer()
			}
			.padding(.top, 10)
		}
		.ignoresSafeArea()
	}
}

#Preview {
	DesktopBrowserShell()
}
