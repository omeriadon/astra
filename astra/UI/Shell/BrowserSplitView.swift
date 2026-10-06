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
		if edge == .trailing {
			ZStack(alignment: .topTrailing) {
				HStack(spacing: 0) {
					Spacer(minLength: 0)
					ZStack(alignment: .trailing) {
						sidebar
							.frame(width: sidebarWidth)
							.offset(x: sidebarShown ? 0 : -sidebarWidth)
					}
					.frame(width: sidebarShown ? sidebarWidth : 0, alignment: .leading)
					.clipped()
				}
				HStack(spacing: 0) {
					content.frame(maxWidth: .infinity, maxHeight: .infinity)
					Spacer(minLength: 0).frame(width: sidebarShown ? sidebarWidth : 0)
				}
			}
			.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: sidebarShown)
		} else {
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
			.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: sidebarShown)
		}
	}
}
