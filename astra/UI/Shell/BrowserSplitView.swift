import SwiftUI
#if os(macOS)
	import AppKit
#endif

struct BrowserSplitView<Sidebar: View, Content: View>: View, Animatable {
	let sidebarWidth: CGFloat
	let sidebarWidthRange: ClosedRange<CGFloat>
	let minimumContentWidth: CGFloat
	let edge: HorizontalEdge
	let sidebarOverlaysContent: Bool
	private var sidebarVisibility: CGFloat
	private var sidebarReservation: CGFloat
	private var followingSidebarWidth: CGFloat

	var animatableData: AnimatableValues<CGFloat, CGFloat, CGFloat> {
		get { AnimatableValues(sidebarVisibility, sidebarReservation, followingSidebarWidth) }
		set {
			sidebarVisibility = min(max(newValue.value.0, 0), 1)
			sidebarReservation = min(max(newValue.value.1, 0), 1)
			followingSidebarWidth = max(newValue.value.2, 0)
		}
	}

	@Binding var sidebarShown: Bool
	@State private var resizedWidth: CGFloat?
	@GestureState private var resizeStartWidth: CGFloat?
	@State private var isResizeHovered = false
	@ViewBuilder let sidebar: Sidebar
	@ViewBuilder let content: Content

	init(
		sidebarShown: Binding<Bool>,
		sidebarWidth: CGFloat = BrowserChromeMetrics.expandedSidebarWidth,
		sidebarWidthRange: ClosedRange<CGFloat> = BrowserChromeMetrics.sidebarWidthRange,
		minimumContentWidth: CGFloat = BrowserChromeMetrics.minimumContentWidth,
		edge: HorizontalEdge = .leading,
		sidebarOverlaysContent: Bool = false,
		followingSidebarWidth: CGFloat = 0,
		@ViewBuilder sidebar: () -> Sidebar,
		@ViewBuilder content: () -> Content
	) {
		_sidebarShown = sidebarShown
		self.sidebarWidth = sidebarWidth
		self.sidebarWidthRange = sidebarWidthRange
		self.minimumContentWidth = minimumContentWidth
		self.edge = edge
		self.sidebarOverlaysContent = sidebarOverlaysContent
		sidebarVisibility = sidebarShown.wrappedValue ? 1 : 0
		sidebarReservation = sidebarOverlaysContent ? 0 : sidebarVisibility
		self.followingSidebarWidth = followingSidebarWidth
		self.sidebar = sidebar()
		self.content = content()
	}

	var body: some View {
		GeometryReader { geometry in
			let fitsInline = BrowserChromeMetrics.sidebarFits(
				availableWidth: geometry.size.width,
				minimumContentWidth: minimumContentWidth + followingSidebarWidth,
				limits: sidebarWidthRange
			)
			let overlaysContent = sidebarOverlaysContent || !fitsInline
			let width = min(geometry.size.width, BrowserChromeMetrics.sidebarWidth(
				preferred: resizedWidth ?? sidebarWidth,
				limits: sidebarWidthRange,
				availableWidth: geometry.size.width,
				minimumContentWidth: minimumContentWidth + followingSidebarWidth
			))
			let visibleWidth = width * sidebarVisibility
			let reservedWidth = fitsInline ? width * sidebarReservation : 0
			ZStack(alignment: .topLeading) {
				sidebar
					.frame(width: width, height: geometry.size.height, alignment: .topLeading)
					.clipped()
					.mask(alignment: edge == .leading ? .leading : .trailing) {
						Rectangle().frame(width: visibleWidth)
					}
					.offset(x: edge == .leading ? 0 : geometry.size.width - width)
					.zIndex(overlaysContent ? 1 : 0)
					.allowsHitTesting(sidebarShown)
					.accessibilityHidden(!sidebarShown)

				content
					.frame(width: geometry.size.width - reservedWidth, height: geometry.size.height, alignment: .topLeading)
					.clipped()
					.offset(x: edge == .leading ? reservedWidth : 0)

				if sidebarShown, sidebarVisibility == 1, !overlaysContent {
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
										minimumContentWidth: minimumContentWidth + followingSidebarWidth
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
								minimumContentWidth: minimumContentWidth + followingSidebarWidth
							)
						}
						.offset(x: (edge == .leading ? width : geometry.size.width - width) - 4)
				}
			}
			.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
			.clipped()
			// Visibility is interpolated once above; window and drag geometry must not animate again.
			.animation(nil, value: geometry.size)
			.animation(nil, value: visibleWidth)
			.animation(nil, value: reservedWidth)
		}
	}
}
