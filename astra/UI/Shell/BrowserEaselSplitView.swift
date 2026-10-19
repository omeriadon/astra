import SwiftUI
#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif

/// SwiftUI still owns each page's content and controls. AppKit/UIKit owns the
/// two page frames and divider, so live resizing does not invalidate either
/// SwiftUI page tree or reparent its WebKit view.
struct BrowserEaselSplitView: View {
	let browser: Browser
	let leftTab: BrowserTab
	let rightTab: BrowserTab
	let cornerRadius: CGFloat
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		BrowserNativeTabContentSplit(left: leftContent, right: rightContent)
			.overlay {
				if rightTab.internalPage == .easel, !rightTab.peeks.isEmpty {
					PeekStackView(tab: rightTab, browser: browser)
				} else if leftTab.internalPage == .easel, !leftTab.peeks.isEmpty {
					PeekStackView(tab: leftTab, browser: browser)
				}
			}
			.accessibilityIdentifier("browser-tab-split-view")
	}

	private var leftContent: some View {
		BrowserPageView(browser: browser, cornerRadius: cornerRadius, tabID: leftTab.id, showsPeeks: leftTab.internalPage != .easel)
		#if !ASTRA_WEBSITE_APP_RUNTIME
			.overlay { WebsiteAugmentEditingOverlay(browser: browser, tab: leftTab, cornerRadius: cornerRadius) }
		#endif
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.simultaneousGesture(TapGesture().onEnded { browser.selectTab(leftTab.id) })
	}

	private var rightContent: some View {
		VStack(spacing: 0) {
			HStack {
				Text(rightTab.title).font(.headline).lineLimit(1)
				Spacer(minLength: 0)
				Button("Open Tab Alone", systemImage: "arrow.up.left.and.arrow.down.right") {
					browser.closeEaselSplit()
					browser.selectTab(rightTab.id)
				}
				.labelStyle(.iconOnly)
				.accessibilityIdentifier("split-open-alone")
				Button("Close Split", systemImage: "xmark") {
					browser.closeEaselSplit()
					browser.selectTab(leftTab.id)
				}
				.labelStyle(.iconOnly)
				.accessibilityIdentifier("split-close")
			}
			.padding(8)
			if rightTab.internalPage == .easel {
				BrowserEaselView(browser: browser, tab: rightTab)
					.id(rightTab.id)
			} else {
				BrowserPageView(browser: browser, cornerRadius: cornerRadius, tabID: rightTab.id)
				#if !ASTRA_WEBSITE_APP_RUNTIME
					.overlay { WebsiteAugmentEditingOverlay(browser: browser, tab: rightTab, cornerRadius: cornerRadius) }
				#endif
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.simultaneousGesture(TapGesture().onEnded { browser.selectTab(rightTab.id) })
		.background(browser.theme.contentShade(for: colorScheme))
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
	}
}

/// Exactly matches the old GeometryReader/HStack: 8-point divider, a 1-point
/// center line, 50/50 initial split, and up to 300 points minimum per pane.
private struct BrowserTabContentSplitGeometry {
	static let dividerWidth: CGFloat = 8
	let leftFrame: CGRect
	let dividerFrame: CGRect
	let rightFrame: CGRect
	let usableWidth: CGFloat
	let minimumWidth: CGFloat

	init(size: CGSize, fraction: CGFloat) {
		let width = max(0, size.width)
		let height = max(0, size.height)
		usableWidth = max(0, width - Self.dividerWidth)
		minimumWidth = min(300, usableWidth / 2)
		let leftWidth = min(max(minimumWidth, usableWidth * fraction), usableWidth - minimumWidth)
		leftFrame = CGRect(x: 0, y: 0, width: leftWidth, height: height)
		dividerFrame = CGRect(x: leftWidth, y: 0, width: Self.dividerWidth, height: height)
		rightFrame = CGRect(x: leftWidth + Self.dividerWidth, y: 0,
		                    width: usableWidth - leftWidth, height: height)
	}
}

/// Transient drag state is native and never publishes through SwiftUI.
/// A newly opened split starts at 50/50, as it did with @State.
@MainActor
private final class BrowserTabContentSplitState {
	private(set) var fraction: CGFloat = 0.5
	private var startingFraction: CGFloat?

	func geometry(size: CGSize) -> BrowserTabContentSplitGeometry {
		BrowserTabContentSplitGeometry(size: size, fraction: fraction)
	}

	func beginDrag() {
		startingFraction = fraction
	}

	func drag(translation: CGFloat, size: CGSize) {
		guard let startingFraction else { return }
		let geometry = geometry(size: size)
		guard geometry.usableWidth > 0 else { return }
		let minimumFraction = geometry.minimumWidth / geometry.usableWidth
		fraction = min(max(startingFraction + translation / geometry.usableWidth, minimumFraction),
		               1 - minimumFraction)
	}

	func endDrag() {
		startingFraction = nil
	}

	func adjust(_ direction: CGFloat) {
		// Preserve the old accessibility step and its independent 25–75% clamp.
		fraction = min(max(fraction + direction * 0.05, 0.25), 0.75)
	}
}

#if os(macOS)
	private struct BrowserNativeTabContentSplit<Left: View, Right: View>: NSViewRepresentable {
		let left: Left
		let right: Right
		@Environment(\.self) private var environment

		func makeNSView(context _: Context) -> BrowserNativeTabContentSplitContainer {
			BrowserNativeTabContentSplitContainer()
		}

		func updateNSView(_ view: BrowserNativeTabContentSplitContainer, context: Context) {
			// Do not reconstruct the hosts: the pages contain live WKWebViews,
			// independent focus state and SwiftUI presentation state.
			withTransaction(context.transaction) {
				view.leftHost.rootView = AnyView(left.environment(\.self, environment)
					.frame(maxWidth: .infinity, maxHeight: .infinity).clipped())
				view.rightHost.rootView = AnyView(right.environment(\.self, environment)
					.frame(maxWidth: .infinity, maxHeight: .infinity).clipped())
			}
			view.layoutPanes()
		}

		static func dismantleNSView(_ view: BrowserNativeTabContentSplitContainer, coordinator _: ()) {
			view.endResize()
		}
	}

	private final class BrowserNativeTabContentSplitContainer: NSView {
		let state = BrowserTabContentSplitState()
		let leftHost = NSHostingView(rootView: AnyView(EmptyView()))
		let rightHost = NSHostingView(rootView: AnyView(EmptyView()))
		private let divider = BrowserNativeTabContentDivider()

		override var isFlipped: Bool {
			true
		}

		override var wantsDefaultClipping: Bool {
			true
		}

		override init(frame frameRect: NSRect) {
			super.init(frame: frameRect)
			clipsToBounds = true
			for host in [leftHost, rightHost] {
				host.sizingOptions = []
				host.safeAreaRegions = []
				addSubview(host)
			}
			addSubview(divider)
			divider.owner = self
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override func layout() {
			super.layout()
			layoutPanes()
		}

		func layoutPanes() {
			let geometry = state.geometry(size: bounds.size)
			if leftHost.frame != geometry.leftFrame {
				leftHost.frame = geometry.leftFrame
			}
			if divider.frame != geometry.dividerFrame {
				divider.frame = geometry.dividerFrame
			}
			if rightHost.frame != geometry.rightFrame {
				rightHost.frame = geometry.rightFrame
			}
			divider.updateAccessibility(fraction: state.fraction)
		}

		func endResize() {
			state.endDrag()
		}

		override func viewWillMove(toWindow window: NSWindow?) {
			if window == nil {
				endResize()
			}
			super.viewWillMove(toWindow: window)
		}
	}

	private final class BrowserNativeTabContentDivider: NSView {
		weak var owner: BrowserNativeTabContentSplitContainer?
		private var dragStartX: CGFloat?

		override var mouseDownCanMoveWindow: Bool {
			false
		}

		override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
			true
		}

		override func resetCursorRects() {
			addCursorRect(bounds, cursor: .resizeLeftRight)
		}

		override func draw(_: NSRect) {
			// Same single-point, 15%-primary divider as Rectangle in SwiftUI.
			NSColor.labelColor.withAlphaComponent(0.15).setFill()
			NSRect(x: (bounds.width - 1) / 2, y: 0, width: 1, height: bounds.height).fill()
		}

		override func mouseDown(with event: NSEvent) {
			guard let owner else { return }
			owner.state.beginDrag()
			dragStartX = event.locationInWindow.x
		}

		override func mouseDragged(with event: NSEvent) {
			guard let owner, let dragStartX else { return }
			owner.state.drag(translation: event.locationInWindow.x - dragStartX, size: owner.bounds.size)
			owner.layoutPanes()
		}

		override func mouseUp(with _: NSEvent) {
			finish()
		}

		override func cancelOperation(_: Any?) {
			finish()
		}

		private func finish() {
			owner?.endResize()
			dragStartX = nil
		}

		func updateAccessibility(fraction: CGFloat) {
			setAccessibilityElement(true)
			setAccessibilityRole(.splitter)
			setAccessibilityLabel("Split width")
			setAccessibilityValue("\(Int(fraction * 100)) percent")
			setAccessibilityIdentifier("browser-tab-split-resizer")
		}

		override func accessibilityPerformIncrement() -> Bool {
			adjust(1)
		}

		override func accessibilityPerformDecrement() -> Bool {
			adjust(-1)
		}

		private func adjust(_ amount: CGFloat) -> Bool {
			guard let owner else { return false }
			owner.state.adjust(amount)
			owner.layoutPanes()
			return true
		}
	}
#elseif os(iOS)
	private struct BrowserNativeTabContentSplit<Left: View, Right: View>: UIViewControllerRepresentable {
		let left: Left
		let right: Right
		@Environment(\.self) private var environment

		func makeUIViewController(context _: Context) -> BrowserNativeTabContentSplitController {
			BrowserNativeTabContentSplitController()
		}

		func updateUIViewController(_ controller: BrowserNativeTabContentSplitController, context: Context) {
			withTransaction(context.transaction) {
				controller.leftHost.rootView = AnyView(left.environment(\.self, environment)
					.frame(maxWidth: .infinity, maxHeight: .infinity).clipped())
				controller.rightHost.rootView = AnyView(right.environment(\.self, environment)
					.frame(maxWidth: .infinity, maxHeight: .infinity).clipped())
			}
			controller.layoutPanes()
		}

		static func dismantleUIViewController(_ controller: BrowserNativeTabContentSplitController, coordinator _: ()) {
			controller.endResize()
		}
	}

	private final class BrowserNativeTabContentSplitController: UIViewController {
		let state = BrowserTabContentSplitState()
		let leftHost = UIHostingController(rootView: AnyView(EmptyView()))
		let rightHost = UIHostingController(rootView: AnyView(EmptyView()))
		private let divider = BrowserNativeTabContentDivider()

		override func viewDidLoad() {
			super.viewDidLoad()
			view.clipsToBounds = true
			for host in [leftHost, rightHost] {
				host.sizingOptions = []
				host.safeAreaRegions = []
				addChild(host)
				view.addSubview(host.view)
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
			let geometry = state.geometry(size: view.bounds.size)
			UIView.performWithoutAnimation {
				if leftHost.view.frame != geometry.leftFrame {
					leftHost.view.frame = geometry.leftFrame
				}
				if divider.frame != geometry.dividerFrame {
					divider.frame = geometry.dividerFrame
				}
				if rightHost.view.frame != geometry.rightFrame {
					rightHost.view.frame = geometry.rightFrame
				}
				divider.accessibilityValue = "\(Int(state.fraction * 100)) percent"
			}
		}

		func endResize() {
			state.endDrag()
		}

		override func viewWillDisappear(_ animated: Bool) {
			endResize()
			super.viewWillDisappear(animated)
		}
	}

	private final class BrowserNativeTabContentDivider: UIView {
		weak var owner: BrowserNativeTabContentSplitController?
		private let line = UIView()

		override init(frame: CGRect) {
			super.init(frame: frame)
			isAccessibilityElement = true
			accessibilityTraits = .adjustable
			accessibilityLabel = "Split width"
			accessibilityIdentifier = "browser-tab-split-resizer"
			line.backgroundColor = UIColor.label.withAlphaComponent(0.15)
			line.isUserInteractionEnabled = false
			addSubview(line)
			addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resize(_:))))
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override func layoutSubviews() {
			super.layoutSubviews()
			line.frame = CGRect(x: (bounds.width - 1) / 2, y: 0, width: 1, height: bounds.height)
		}

		@objc private func resize(_ gesture: UIPanGestureRecognizer) {
			guard let owner else { return }
			switch gesture.state {
				case .began:
					owner.state.beginDrag()
					fallthrough
				case .changed:
					owner.state.drag(translation: gesture.translation(in: owner.view).x, size: owner.view.bounds.size)
					owner.layoutPanes()
				case .ended, .cancelled, .failed:
					owner.endResize()
				default:
					break
			}
		}

		override func accessibilityIncrement() {
			adjust(1)
		}

		override func accessibilityDecrement() {
			adjust(-1)
		}

		private func adjust(_ direction: CGFloat) {
			guard let owner else { return }
			owner.state.adjust(direction)
			owner.layoutPanes()
		}
	}
#endif
