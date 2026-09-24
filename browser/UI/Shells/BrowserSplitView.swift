import SwiftUI

struct BrowserSplitView<Sidebar: View, Content: View>: View {
	let sidebarWidth: CGFloat

	@Binding var sidebarShown: Bool
	@Binding var isAboutToQuit: Bool

	@ViewBuilder let sidebar: Sidebar
	@ViewBuilder let content: Content

	init(
		sidebarShown: Binding<Bool>,
		isAboutToQuit: Binding<Bool>,
		sidebarWidth: CGFloat = 224,
		@ViewBuilder sidebar: () -> Sidebar,
		@ViewBuilder content: () -> Content
	) {
		_sidebarShown = sidebarShown
		_isAboutToQuit = isAboutToQuit
		self.sidebarWidth = sidebarWidth
		self.sidebar = sidebar()
		self.content = content()
	}

	var body: some View {
		HStack(spacing: 0) {
			ZStack(alignment: .leading) {
				sidebar
					.frame(width: sidebarWidth)
					.offset(x: sidebarShown ? 0 : sidebarWidth)
			}
			.frame(width: sidebarShown ? sidebarWidth : 0, alignment: .trailing)
			.clipped()

			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.animation(.smooth(duration: 0.3), value: sidebarShown)
		.overlay(alignment: .center) {
			if isAboutToQuit {
				GlassEffectContainer {
					Label("Press ⌘Q again to Quit", systemImage: "rectangle.portrait.and.arrow.right")
						.font(.title3)
						.padding(.horizontal, 10)
						.padding(.vertical, 8)
						.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
						.glassEffectTransition(.materialize)
				}
			}
		}
		.onChange(of: isAboutToQuit) {
			Task {
				try? await Task.sleep(for: .seconds(1))
				isAboutToQuit = false
			}
		}
	}
}
