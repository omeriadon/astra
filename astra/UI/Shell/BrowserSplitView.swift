import SwiftUI

struct BrowserSplitView<Sidebar: View, Content: View>: View {
	let sidebarWidth: CGFloat
	let edge: HorizontalEdge

	@Binding var sidebarShown: Bool
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
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
		GeometryReader { geometry in
			let width = min(sidebarWidth, geometry.size.width)
			let visibleWidth = sidebarShown ? width : 0
			ZStack(alignment: .topLeading) {
				sidebar
					.frame(width: width, height: geometry.size.height)
					.clipped()
					.animation(reduceMotion ? nil : .smooth(duration: 0.3)) { view in
						view
							.mask(alignment: edge == .leading ? .leading : .trailing) {
								Rectangle().frame(width: visibleWidth)
							}
					}
					.offset(x: edge == .leading ? 0 : geometry.size.width - width)
					.allowsHitTesting(sidebarShown)
					.accessibilityHidden(!sidebarShown)

				content
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.clipped()
					.animation(reduceMotion ? nil : .smooth(duration: 0.3)) { view in
						view
							.padding(edge == .leading ? .leading : .trailing, visibleWidth)
					}
			}
			.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
			.clipped()
		}
	}
}
