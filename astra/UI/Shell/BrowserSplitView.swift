import SwiftUI

/// SwiftUI supplies semantic content and the existing visibility animation. Native
/// views own pane frames and live resizing; dragging never writes SwiftUI state.
struct BrowserSplitView<Sidebar: View, Content: View>: View, @MainActor Animatable {
	let sidebarWidth: CGFloat
	let sidebarWidthRange: ClosedRange<CGFloat>
	let minimumContentWidth: CGFloat
	let edge: HorizontalEdge
	let sidebarOverlaysContent: Bool
	let onWidthChange: ((CGFloat) -> Void)?
	private var sidebarVisibility: CGFloat
	private var sidebarReservation: CGFloat
	private var followingSidebarWidth: CGFloat
	@Binding var sidebarShown: Bool
	@ViewBuilder let sidebar: Sidebar
	@ViewBuilder let content: Content

	var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
		get { .init(sidebarVisibility, .init(sidebarReservation, followingSidebarWidth)) }
		set {
			sidebarVisibility = min(max(newValue.first, 0), 1)
			sidebarReservation = min(max(newValue.second.first, 0), 1)
			followingSidebarWidth = max(newValue.second.second, 0)
		}
	}

	init(
		sidebarShown: Binding<Bool>,
		sidebarWidth: CGFloat = BrowserChromeMetrics.expandedSidebarWidth,
		sidebarWidthRange: ClosedRange<CGFloat> = BrowserChromeMetrics.sidebarWidthRange,
		minimumContentWidth: CGFloat = BrowserChromeMetrics.minimumContentWidth,
		edge: HorizontalEdge = .leading,
		sidebarOverlaysContent: Bool = false,
		followingSidebarWidth: CGFloat = 0,
		onWidthChange: ((CGFloat) -> Void)? = nil,
		@ViewBuilder sidebar: () -> Sidebar,
		@ViewBuilder content: () -> Content
	) {
		_sidebarShown = sidebarShown
		self.sidebarWidth = sidebarWidth
		self.sidebarWidthRange = sidebarWidthRange
		self.minimumContentWidth = minimumContentWidth
		self.edge = edge
		self.sidebarOverlaysContent = sidebarOverlaysContent
		self.onWidthChange = onWidthChange
		sidebarVisibility = sidebarShown.wrappedValue ? 1 : 0
		sidebarReservation = sidebarOverlaysContent ? 0 : sidebarVisibility
		self.followingSidebarWidth = followingSidebarWidth
		self.sidebar = sidebar()
		self.content = content()
	}

	var body: some View {
		BrowserNativeSplitView(
			configuration: BrowserNativeSplitConfiguration(
				preferredWidth: sidebarWidth, limits: sidebarWidthRange,
				minimumContentWidth: minimumContentWidth + followingSidebarWidth,
				leading: edge == .leading, overlaysContent: sidebarOverlaysContent,
				shown: sidebarShown, visibility: sidebarVisibility, reservation: sidebarReservation
			),
			onWidthChange: onWidthChange, sidebar: sidebar, content: content
		)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

struct BrowserNativeSplitConfiguration {
	var preferredWidth: CGFloat
	var limits: ClosedRange<CGFloat>
	var minimumContentWidth: CGFloat
	var leading: Bool
	var overlaysContent: Bool
	var shown: Bool
	var visibility: CGFloat
	var reservation: CGFloat
}

/// These are the original SwiftUI split's point coordinates, including the
/// trailing divider's two-point inset. No NSSplitView divider or system styling.
struct BrowserNativeSplitGeometry {
	let width: CGFloat
	let overlaysContent: Bool
	let sidebarClip: CGRect
	let sidebar: CGRect
	let content: CGRect
	let divider: CGRect
	let canResize: Bool

	init(size: CGSize, configuration: BrowserNativeSplitConfiguration, preferredWidth: CGFloat) {
		let available = max(0, size.width)
		let height = max(0, size.height)
		let fits = BrowserChromeMetrics.sidebarFits(availableWidth: available,
			minimumContentWidth: configuration.minimumContentWidth, limits: configuration.limits)
		overlaysContent = configuration.overlaysContent || !fits
		width = min(available, BrowserChromeMetrics.sidebarWidth(preferred: preferredWidth,
			limits: configuration.limits, availableWidth: available,
			minimumContentWidth: configuration.minimumContentWidth))
		let visible = width * configuration.visibility
		let reserved = fits ? width * configuration.reservation : 0
		sidebarClip = CGRect(x: configuration.leading ? 0 : available - visible, y: 0, width: visible, height: height)
		sidebar = CGRect(x: configuration.leading ? 0 : visible - width, y: 0, width: width, height: height)
		content = CGRect(x: configuration.leading ? reserved : 0, y: 0, width: max(0, available - reserved), height: height)
		divider = CGRect(x: configuration.leading ? width - 4 : available - width - BrowserChromeMetrics.shellEdgePadding / 2 - 4,
			y: 0, width: 8, height: height)
		canResize = configuration.shown && configuration.visibility == 1 && !overlaysContent
	}
}

/// Shared drag state. A width is published only after release (or an external
/// clamp), never for pointer motion. Keep the user's preferred width through a
/// temporary window clamp so widening the window restores it.
@MainActor
final class BrowserNativeSplitState {
	var configuration: BrowserNativeSplitConfiguration
	var onWidthChange: ((CGFloat) -> Void)?
	var resizedWidth: CGFloat?
	private(set) var dragStart: CGFloat?
	private var lastReportedWidth: CGFloat?
	private var pendingWidth: CGFloat?
	private var reportScheduled = false

	init(configuration: BrowserNativeSplitConfiguration) {
		self.configuration = configuration
	}

	func geometry(_ size: CGSize) -> BrowserNativeSplitGeometry {
		BrowserNativeSplitGeometry(size: size, configuration: configuration,
			preferredWidth: resizedWidth ?? configuration.preferredWidth)
	}

	func begin(_ size: CGSize) {
		guard geometry(size).canResize else { return }
		dragStart = geometry(size).width
		pendingWidth = nil
	}

	func drag(translation: CGFloat, size: CGSize) {
		guard let dragStart else { return }
		let delta = configuration.leading ? translation : -translation
		resizedWidth = min(max(0, size.width), BrowserChromeMetrics.sidebarWidth(preferred: dragStart + delta,
			limits: configuration.limits, availableWidth: size.width,
			minimumContentWidth: configuration.minimumContentWidth))
	}

	func end(_ size: CGSize) {
		guard dragStart != nil else { return }
		dragStart = nil
		reportWidth(geometry(size).width)
	}

	func adjust(by delta: CGFloat, size: CGSize) {
		guard geometry(size).canResize else { return }
		resizedWidth = BrowserChromeMetrics.sidebarWidth(preferred: geometry(size).width + delta,
			limits: configuration.limits, availableWidth: size.width,
			minimumContentWidth: configuration.minimumContentWidth)
		reportWidth(geometry(size).width)
	}

	func reportWidth(_ width: CGFloat) {
		guard width > 0, dragStart == nil else { return }
		pendingWidth = width
		guard !reportScheduled else { return }
		reportScheduled = true
		// Native layout also runs inside updateNSView/updateUIViewController.
		// Deliver outside that transaction and coalesce window-layout passes.
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			reportScheduled = false
			guard dragStart == nil, let width = pendingWidth else { return }
			pendingWidth = nil
			guard lastReportedWidth != width else { return }
			lastReportedWidth = width
			onWidthChange?(width)
		}
	}

	func invalidate() {
		onWidthChange = nil
		pendingWidth = nil
		dragStart = nil
	}
}

#if os(macOS)
import AppKit

private struct BrowserNativeSplitView<Sidebar: View, Content: View>: NSViewRepresentable {
	let configuration: BrowserNativeSplitConfiguration
	let onWidthChange: ((CGFloat) -> Void)?
	let sidebar: Sidebar
	let content: Content
	@Environment(\.self) private var environment

	func makeNSView(context: Context) -> BrowserNativeSplitContainer {
		BrowserNativeSplitContainer(configuration: configuration)
	}

	func updateNSView(_ view: BrowserNativeSplitContainer, context: Context) {
		view.state.configuration = configuration
		view.state.onWidthChange = onWidthChange
		view.setDividerAppearance(colorScheme: environment.colorScheme)
		// Frame-only drag updates never come through here. Roots retain identity,
		// focus, menus and local state; semantic changes still propagate normally.
		withTransaction(context.transaction) {
			view.sidebarHost.rootView = AnyView(sidebar.environment(\.self, environment)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped())
			view.contentHost.rootView = AnyView(content.environment(\.self, environment)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped())
		}
		view.layoutPanes()
	}

	static func dismantleNSView(_ view: BrowserNativeSplitContainer, coordinator: ()) {
		view.state.invalidate()
	}
}

/// Flipped coordinates match SwiftUI's top-leading layout. A separate clipping
/// view exposes the same anchored slice during show/hide, without shrinking the
/// hosted sidebar itself or disabling its exit animation.
private final class BrowserNativeSidebarClip: NSView {
	var acceptsEvents = true
	override var isFlipped: Bool { true }
	override var wantsDefaultClipping: Bool { true }
	override func hitTest(_ point: NSPoint) -> NSView? {
		acceptsEvents ? super.hitTest(point) : nil
	}
}

final class BrowserNativeSplitContainer: NSView {
	let state: BrowserNativeSplitState
	let sidebarHost = NSHostingView(rootView: AnyView(EmptyView()))
	let contentHost = NSHostingView(rootView: AnyView(EmptyView()))
	private let sidebarClip = BrowserNativeSidebarClip()
	private let divider = BrowserNativeSidebarDivider()
	private var sidebarOnTop: Bool?

	override var isFlipped: Bool { true }
	override var wantsDefaultClipping: Bool { true }

	init(configuration: BrowserNativeSplitConfiguration) {
		state = BrowserNativeSplitState(configuration: configuration)
		super.init(frame: .zero)
		clipsToBounds = true
		sidebarClip.clipsToBounds = true
		for host in [sidebarHost, contentHost] {
			host.sizingOptions = []
			host.safeAreaRegions = []
		}
		addSubview(contentHost)
		addSubview(sidebarClip)
		sidebarClip.addSubview(sidebarHost)
		addSubview(divider)
		divider.owner = self
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func layout() {
		super.layout()
		layoutPanes()
	}

	func setDividerAppearance(colorScheme: ColorScheme) {
		divider.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
	}

	func layoutPanes() {
		let geometry = state.geometry(bounds.size)
		if !geometry.canResize, state.dragStart != nil { state.end(bounds.size) }
		// Native frame mutations deliberately do not use animator() or SwiftUI
		// transactions. Visibility interpolation already arrives from Animatable.
		if sidebarClip.frame != geometry.sidebarClip { sidebarClip.frame = geometry.sidebarClip }
		if sidebarHost.frame != geometry.sidebar { sidebarHost.frame = geometry.sidebar }
		if contentHost.frame != geometry.content { contentHost.frame = geometry.content }
		sidebarClip.isHidden = state.configuration.visibility == 0
		sidebarClip.acceptsEvents = state.configuration.shown
		sidebarClip.setAccessibilityHidden(!state.configuration.shown)
		if sidebarOnTop != geometry.overlaysContent {
			addSubview(sidebarClip, positioned: geometry.overlaysContent ? .above : .below, relativeTo: contentHost)
			sidebarOnTop = geometry.overlaysContent
		}
		divider.frame = geometry.divider
		divider.isHidden = !geometry.canResize
		divider.updateAccessibility(width: geometry.width, leading: state.configuration.leading)
		state.reportWidth(geometry.width)
	}

	override func viewWillMove(toWindow newWindow: NSWindow?) {
		if newWindow == nil { state.end(bounds.size) }
		super.viewWillMove(toWindow: newWindow)
	}
}

private final class BrowserNativeSidebarDivider: NSView {
	weak var owner: BrowserNativeSplitContainer?
	private var tracking: NSTrackingArea?
	private var startX: CGFloat?
	private var hovered = false { didSet { needsDisplay = true } }

	override var mouseDownCanMoveWindow: Bool { false }
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
	override func updateTrackingAreas() {
		if let tracking { removeTrackingArea(tracking) }
		let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
		addTrackingArea(area)
		tracking = area
		super.updateTrackingAreas()
	}
	override func mouseEntered(with event: NSEvent) { hovered = true }
	override func mouseExited(with event: NSEvent) { hovered = false }
	override func draw(_ dirtyRect: NSRect) {
		guard hovered || owner?.state.dragStart != nil else { return }
		NSColor.labelColor.withAlphaComponent(0.2).setFill()
		NSRect(x: (bounds.width - 1) / 2, y: 0, width: 1, height: bounds.height).fill()
	}
	override func mouseDown(with event: NSEvent) {
		guard let owner else { return }
		owner.state.begin(owner.bounds.size)
		startX = event.locationInWindow.x
		needsDisplay = true
	}
	override func mouseDragged(with event: NSEvent) {
		guard let owner, let startX else { return }
		owner.state.drag(translation: event.locationInWindow.x - startX, size: owner.bounds.size)
		owner.layoutPanes()
	}
	override func mouseUp(with event: NSEvent) { finish() }
	override func cancelOperation(_ sender: Any?) { finish() }
	private func finish() {
		guard let owner else { return }
		owner.state.end(owner.bounds.size)
		startX = nil
		needsDisplay = true
	}
	func updateAccessibility(width: CGFloat, leading: Bool) {
		setAccessibilityElement(true)
		setAccessibilityRole(.splitter)
		setAccessibilityLabel(leading ? "Left sidebar width" : "Right sidebar width")
		setAccessibilityValue("\(Int(width)) points")
		setAccessibilityIdentifier(leading ? "left-sidebar-resizer" : "right-sidebar-resizer")
	}
	override func accessibilityPerformIncrement() -> Bool { adjust(20) }
	override func accessibilityPerformDecrement() -> Bool { adjust(-20) }
	private func adjust(_ amount: CGFloat) -> Bool {
		guard let owner else { return false }
		owner.state.adjust(by: amount, size: owner.bounds.size)
		owner.layoutPanes()
		return true
	}
}
#elseif os(iOS)
import UIKit

private struct BrowserNativeSplitView<Sidebar: View, Content: View>: UIViewControllerRepresentable {
	let configuration: BrowserNativeSplitConfiguration
	let onWidthChange: ((CGFloat) -> Void)?
	let sidebar: Sidebar
	let content: Content
	@Environment(\.self) private var environment

	func makeUIViewController(context: Context) -> BrowserNativeSplitController {
		BrowserNativeSplitController(configuration: configuration)
	}
	func updateUIViewController(_ controller: BrowserNativeSplitController, context: Context) {
		controller.state.configuration = configuration
		controller.state.onWidthChange = onWidthChange
		withTransaction(context.transaction) {
			controller.sidebarHost.rootView = AnyView(sidebar.environment(\.self, environment)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped())
			controller.contentHost.rootView = AnyView(content.environment(\.self, environment)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped())
		}
		controller.layoutPanes()
	}
	static func dismantleUIViewController(_ controller: BrowserNativeSplitController, coordinator: ()) {
		controller.state.invalidate()
	}
}

final class BrowserNativeSplitController: UIViewController {
	let state: BrowserNativeSplitState
	let sidebarHost = UIHostingController(rootView: AnyView(EmptyView()))
	let contentHost = UIHostingController(rootView: AnyView(EmptyView()))
	private let sidebarClip = UIView()
	private let divider = BrowserNativeSidebarDivider()

	init(configuration: BrowserNativeSplitConfiguration) {
		state = BrowserNativeSplitState(configuration: configuration)
		super.init(nibName: nil, bundle: nil)
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	override func viewDidLoad() {
		super.viewDidLoad()
		view.clipsToBounds = true
		sidebarClip.clipsToBounds = true
		view.addSubview(sidebarClip)
		for (host, parent) in [(contentHost, view!), (sidebarHost, sidebarClip)] {
			host.sizingOptions = []
			host.safeAreaRegions = []
			addChild(host)
			parent.addSubview(host.view)
			host.view.backgroundColor = .clear
			host.didMove(toParent: self)
		}
		view.addSubview(divider)
		divider.owner = self
	}
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		layoutPanes()
	}
	func layoutPanes() {
		loadViewIfNeeded()
		let geometry = state.geometry(view.bounds.size)
		if !geometry.canResize, state.dragStart != nil { state.end(view.bounds.size) }
		UIView.performWithoutAnimation {
			sidebarClip.frame = geometry.sidebarClip
			sidebarHost.view.frame = geometry.sidebar
			contentHost.view.frame = geometry.content
			sidebarClip.isHidden = state.configuration.visibility == 0
			sidebarClip.isUserInteractionEnabled = state.configuration.shown
			sidebarClip.accessibilityElementsHidden = !state.configuration.shown
			if geometry.overlaysContent { view.bringSubviewToFront(sidebarClip) }
			else { view.bringSubviewToFront(contentHost.view) }
			view.bringSubviewToFront(divider)
			divider.frame = geometry.divider
			divider.isHidden = !geometry.canResize
			divider.accessibilityLabel = state.configuration.leading ? "Left sidebar width" : "Right sidebar width"
			divider.accessibilityValue = "\(Int(geometry.width)) points"
			divider.accessibilityIdentifier = state.configuration.leading ? "left-sidebar-resizer" : "right-sidebar-resizer"
		}
		state.reportWidth(geometry.width)
	}
	override func viewWillDisappear(_ animated: Bool) {
		state.end(view.bounds.size)
		super.viewWillDisappear(animated)
	}
}

private final class BrowserNativeSidebarDivider: UIView {
	weak var owner: BrowserNativeSplitController?
	private let line = UIView()
	private var hovered = false
	private var dragging = false
	private var startX: CGFloat = 0

	override init(frame: CGRect) {
		super.init(frame: frame)
		isAccessibilityElement = true
		accessibilityTraits = .adjustable
		line.backgroundColor = UIColor.label.withAlphaComponent(0.2)
		line.isUserInteractionEnabled = false
		addSubview(line)
		let drag = UILongPressGestureRecognizer(target: self, action: #selector(pan(_:)))
		drag.minimumPressDuration = 0
		drag.allowableMovement = .greatestFiniteMagnitude
		addGestureRecognizer(drag)
		addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	override func layoutSubviews() {
		super.layoutSubviews()
		line.frame = CGRect(x: (bounds.width - 1) / 2, y: 0, width: 1, height: bounds.height)
		line.isHidden = !hovered && !dragging
	}
	@objc private func hover(_ gesture: UIHoverGestureRecognizer) {
		hovered = gesture.state == .began || gesture.state == .changed
		setNeedsLayout()
	}
	@objc private func pan(_ gesture: UILongPressGestureRecognizer) {
		guard let owner else { return }
		switch gesture.state {
		case .began:
			owner.state.begin(owner.view.bounds.size)
			startX = gesture.location(in: owner.view).x
			dragging = true
			fallthrough
		case .changed:
			owner.state.drag(translation: gesture.location(in: owner.view).x - startX, size: owner.view.bounds.size)
			owner.layoutPanes()
		case .ended, .cancelled, .failed:
			owner.state.end(owner.view.bounds.size)
			dragging = false
		default: break
		}
		setNeedsLayout()
	}
	override func accessibilityIncrement() { adjust(20) }
	override func accessibilityDecrement() { adjust(-20) }
	private func adjust(_ amount: CGFloat) {
		guard let owner else { return }
		owner.state.adjust(by: amount, size: owner.view.bounds.size)
		owner.layoutPanes()
	}
}
#endif
