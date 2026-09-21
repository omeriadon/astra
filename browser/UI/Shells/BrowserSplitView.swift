import SwiftUI

struct BrowserSplitView<Sidebar: View, Content: View>: View {
	let sidebarWidth: CGFloat

	@ViewBuilder let sidebar: Sidebar
	@ViewBuilder let content: Content

	@Binding var sidebarShown: Bool

	init(
		sidebarShown: Binding<Bool>,
		sidebarWidth: CGFloat = 224,
		@ViewBuilder sidebar: () -> Sidebar,
		@ViewBuilder content: () -> Content
	) {
		_sidebarShown = sidebarShown
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
	}
}
