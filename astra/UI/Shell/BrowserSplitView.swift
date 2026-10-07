import SwiftUI

struct BrowserSplitView<Sidebar: View, Content: View>: View {
	let sidebarWidth: CGFloat
	let sidebarWidthRange: ClosedRange<CGFloat>
	let minimumContentWidth: CGFloat
	let edge: HorizontalEdge

	@Binding var sidebarShown: Bool
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ViewBuilder let sidebar: Sidebar
	@ViewBuilder let content: Content

	init(
		sidebarShown: Binding<Bool>,
		sidebarWidth: CGFloat = BrowserChromeMetrics.expandedSidebarWidth,
		sidebarWidthRange: ClosedRange<CGFloat> = BrowserChromeMetrics.sidebarWidthRange,
		minimumContentWidth: CGFloat = BrowserChromeMetrics.minimumContentWidth,
		edge: HorizontalEdge = .leading,
		@ViewBuilder sidebar: () -> Sidebar,
		@ViewBuilder content: () -> Content
	) {
		_sidebarShown = sidebarShown
		self.sidebarWidth = sidebarWidth
		self.sidebarWidthRange = sidebarWidthRange
		self.minimumContentWidth = minimumContentWidth
		self.edge = edge
		self.sidebar = sidebar()
		self.content = content()
	}

	var body: some View {
		GeometryReader { geometry in
			let width = BrowserChromeMetrics.sidebarWidth(
				preferred: sidebarWidth,
				limits: sidebarWidthRange,
				availableWidth: geometry.size.width,
				minimumContentWidth: minimumContentWidth
			)
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
					.animation(reduceMotion ? nil : .smooth(duration: 0.3)) { view in
						view
							.frame(width: max(0, geometry.size.width - visibleWidth), height: geometry.size.height)
							.clipped()
							.padding(edge == .leading ? .leading : .trailing, visibleWidth)
					}
			}
			.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
			.clipped()
		}
	}
}
