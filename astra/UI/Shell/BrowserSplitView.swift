import SwiftUI
#if os(macOS)
	import AppKit
#endif

struct BrowserSplitView<Sidebar: View, Content: View>: View {
	let sidebarWidth: CGFloat
	let sidebarWidthRange: ClosedRange<CGFloat>
	let minimumContentWidth: CGFloat
	let edge: HorizontalEdge

	@Binding var sidebarShown: Bool
	@State private var resizedWidth: CGFloat?
	@GestureState private var resizeStartWidth: CGFloat?
	@State private var isResizeHovered = false
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
				preferred: resizedWidth ?? sidebarWidth,
				limits: sidebarWidthRange,
				availableWidth: geometry.size.width,
				minimumContentWidth: minimumContentWidth
			)
			let visibleWidth = sidebarShown ? width : 0
			ZStack(alignment: .topLeading) {
				sidebar
					.frame(width: width, height: geometry.size.height)
					.clipped()
					.mask(alignment: edge == .leading ? .leading : .trailing) {
						Rectangle().frame(width: visibleWidth)
					}
					.offset(x: edge == .leading ? 0 : geometry.size.width - width)
					.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: sidebarShown)
					.allowsHitTesting(sidebarShown)
					.accessibilityHidden(!sidebarShown)

				content
					.frame(width: max(0, geometry.size.width - visibleWidth), height: geometry.size.height)
					.clipped()
					.padding(edge == .leading ? .leading : .trailing, visibleWidth)
					.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: sidebarShown)

				if sidebarShown {
					Rectangle()
						.fill(.primary.opacity(isResizeHovered || resizeStartWidth != nil ? 0.2 : 0))
						.frame(width: 1, height: geometry.size.height)
						.frame(width: 8)
						.contentShape(Rectangle())
					#if os(macOS)
						.background { NonDraggableTitlebarRegion() }
						.onHover { hovered in
							isResizeHovered = hovered
							if hovered {
								NSCursor.resizeLeftRight.push()
							} else {
								NSCursor.pop()
							}
						}
						.onDisappear {
							if isResizeHovered {
								NSCursor.pop()
								isResizeHovered = false
							}
						}
					#endif
						.gesture(
							DragGesture(minimumDistance: 0, coordinateSpace: .global)
								.updating($resizeStartWidth) { _, startWidth, _ in
									if startWidth == nil {
										startWidth = width
									}
								}
								.onChanged { value in
									let translation = edge == .leading ? value.translation.width : -value.translation.width
									resizedWidth = BrowserChromeMetrics.sidebarWidth(
										preferred: (resizeStartWidth ?? width) + translation,
										limits: sidebarWidthRange,
										availableWidth: geometry.size.width,
										minimumContentWidth: minimumContentWidth
									)
								}
						)
						.accessibilityElement()
						.accessibilityLabel(edge == .leading ? "Left sidebar width" : "Right sidebar width")
						.accessibilityValue("\(Int(width)) points")
						.accessibilityIdentifier(edge == .leading ? "left-sidebar-resizer" : "right-sidebar-resizer")
						.accessibilityAdjustableAction { direction in
							let change: CGFloat = direction == .increment ? 20 : -20
							resizedWidth = BrowserChromeMetrics.sidebarWidth(
								preferred: width + change,
								limits: sidebarWidthRange,
								availableWidth: geometry.size.width,
								minimumContentWidth: minimumContentWidth
							)
						}
						.offset(x: (edge == .leading ? width : geometry.size.width - width) - 4)
				}
			}
			.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
			.clipped()
		}
	}
}
