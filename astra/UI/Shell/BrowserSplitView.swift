import SwiftUI

struct BrowserSplitView<Sidebar: View, Content: View>: View {
	let sidebarWidth: CGFloat
	let edge: HorizontalEdge
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	@Binding var sidebarShown: Bool
	@ViewBuilder let sidebar: Sidebar
	@ViewBuilder let content: Content

	init(
		sidebarShown: Binding<Bool>,
		sidebarWidth: CGFloat = BrowserChromeMetrics.expandedSidebarWidth,
		edge: HorizontalEdge = .leading,
		@ViewBuilder sidebar: () -> Sidebar,
		@ViewBuilder content: () -> Content
	) {
		_sidebarShown = sidebarShown
		self.sidebarWidth = sidebarWidth
		self.edge = edge
		self.sidebar = sidebar()
		self.content = content()
	}

	var body: some View {
		ZStack(alignment: edge == .leading ? .topLeading : .topTrailing) {
			sidebar
				.frame(width: sidebarWidth)
				.frame(maxHeight: .infinity)
				.allowsHitTesting(sidebarShown)
				.accessibilityHidden(!sidebarShown)

			HStack(spacing: 0) {
				if edge == .leading {
					Spacer(minLength: 0)
						.frame(width: sidebarShown ? sidebarWidth : 0)
				}
				content
					.frame(maxWidth: .infinity, maxHeight: .infinity)
				if edge == .trailing {
					Spacer(minLength: 0)
						.frame(width: sidebarShown ? sidebarWidth : 0)
				}
			}
		}
		.clipped()
		.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: sidebarShown)
	}
}
