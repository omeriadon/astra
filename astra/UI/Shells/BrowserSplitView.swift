import SwiftUI

struct BrowserSplitView<Sidebar: View, Content: View>: View {
	let sidebarWidth: CGFloat

	@Binding var sidebarShown: Bool
	@ViewBuilder let sidebar: Sidebar
	@ViewBuilder let content: Content

	init(
		sidebarShown: Binding<Bool>,
		sidebarWidth: CGFloat = BrowserChromeMetrics.expandedSidebarWidth,
		@ViewBuilder sidebar: () -> Sidebar,
		@ViewBuilder content: () -> Content
	) {
		_sidebarShown = sidebarShown
		self.sidebarWidth = sidebarWidth
		self.sidebar = sidebar()
		self.content = content()
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			HStack(spacing: 0) {
				ZStack(alignment: .leading) {
					sidebar
						.frame(width: sidebarWidth)
						.offset(x: sidebarShown ? 0 : sidebarWidth)
				}
				.frame(width: sidebarShown ? sidebarWidth : 0, alignment: .trailing)
				.clipped()

				Spacer(minLength: 0)
			}

			HStack(spacing: 0) {
				Spacer(minLength: 0)
					.frame(width: sidebarShown ? sidebarWidth : 0)

				content
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.animation(.smooth(duration: 0.3), value: sidebarShown)
	}
}
