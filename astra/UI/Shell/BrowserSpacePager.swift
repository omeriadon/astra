import SwiftUI
#if os(macOS)
import AppKit
import QuartzCore

/// AppKit owns horizontal paging; each page remains the existing SwiftUI
/// vertical-scrolling sidebar. This isolates horizontal gesture handling from
/// the nested SwiftUI scroll views and avoids eagerly mounting every space.
struct BrowserSpacePager<Content: View>: NSViewRepresentable {
	let spaces: [BrowserSpace]
	let selectedSpaceID: UUID
	let favouriteTabIDs: [UUID]
	let scrollState: BrowserSpaceScrollState
	let onSelectSpace: (UUID) -> Void
	let content: (BrowserSpace, Bool, [UUID]) -> Content

	init(
		spaces: [BrowserSpace],
		selectedSpaceID: UUID,
		favouriteTabIDs: [UUID],
		scrollState: BrowserSpaceScrollState,
		onSelectSpace: @escaping (UUID) -> Void,
		@ViewBuilder content: @escaping (BrowserSpace, Bool, [UUID]) -> Content
	) {
		self.spaces = spaces
		self.selectedSpaceID = selectedSpaceID
		self.favouriteTabIDs = favouriteTabIDs
		self.scrollState = scrollState
		self.onSelectSpace = onSelectSpace
		self.content = content
	}

	func makeNSView(context _: Context) -> AppKitSpacePagerView<Content> {
		let view = AppKitSpacePagerView<Content>()
		view.configure(self)
		return view
	}

	func updateNSView(_ view: AppKitSpacePagerView<Content>, context _: Context) {
		view.configure(self)
	}

	static func dismantleNSView(_ view: AppKitSpacePagerView<Content>, coordinator _: ()) {
		view.stopObserving()
	}
}

/// A single native horizontal NSScrollView and a bounded set of mounted
/// NSHostingViews. Hosts are cached by space ID to retain SwiftUI state when
/// a space moves offscreen (including its vertical scroll position).
@MainActor
final class AppKitSpacePagerView<Content: View>: NSView {
	private let scroller = NSScrollView(frame: .zero)
	private let document = NSView(frame: .zero)
	private var cachedPages: [UUID: NSHostingView<Content>] = [:]
	private var spaces: [BrowserSpace] = []
	private var favouriteIDs: [UUID] = []
	private var selectedID: UUID?
	private var factory: ((BrowserSpace, Bool, [UUID]) -> Content)?
	private var onSelect: ((UUID) -> Void)?
	private var scrollState: BrowserSpaceScrollState?
	private var boundsObserver: NSObjectProtocol?
	private var wheelMonitor: Any?
	private var snapTask: Task<Void, Never>?
	private var pendingSelection: UUID?
	private var pageWidth: CGFloat = 0
	private var pageHeight: CGFloat = 0
	private var applyingGeometry = false
	private var isConfiguring = false
	private var deferredPositionPublish = false
	private var pageOrderNeedsLayout = false

	override init(frame: NSRect) {
		super.init(frame: frame)
		scroller.drawsBackground = false
		scroller.borderType = .noBorder
		scroller.hasVerticalScroller = false
		scroller.hasHorizontalScroller = false
		scroller.verticalScrollElasticity = .none
		scroller.horizontalScrollElasticity = .none
		scroller.automaticallyAdjustsContentInsets = false
		scroller.contentInsets = .zero
		scroller.documentView = document
		scroller.autoresizingMask = [.width, .height]
		scroller.frame = bounds
		scroller.setAccessibilityIdentifier("sidebar-space-pages")
		addSubview(scroller)
		scroller.contentView.postsBoundsChangedNotifications = true
		boundsObserver = NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: scroller.contentView,
			queue: nil
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.didScroll() }
		}
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) is unavailable")
	}

	override func layout() {
		super.layout()
		scroller.frame = bounds
		let width = max(scroller.contentSize.width, 1)
		let height = max(scroller.contentSize.height, 1)
		let contentWidth = width * CGFloat(max(1, spaces.count))
		guard width != pageWidth || height != pageHeight
			|| document.frame.width != contentWidth || pageOrderNeedsLayout else { return }
		let selectedIndex = CGFloat(spaces.firstIndex(where: { $0.id == selectedID }) ?? 0)
		let currentPosition = pageOrderNeedsLayout || pageWidth == 0
			? selectedIndex
			: scroller.contentView.bounds.origin.x / pageWidth
		pageOrderNeedsLayout = false
		pageWidth = width
		pageHeight = height
		document.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
		for (id, host) in cachedPages {
			guard let index = spaces.firstIndex(where: { $0.id == id }) else { continue }
			host.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: height)
		}
		let target = min(max(currentPosition * width, 0), max(0, document.frame.width - width))
		applyingGeometry = true
		scroller.contentView.scroll(to: NSPoint(x: target, y: 0))
		scroller.reflectScrolledClipView(scroller.contentView)
		applyingGeometry = false
		updateMountedPages()
		didScroll()
	}

	func configure(_ configuration: BrowserSpacePager<Content>) {
		isConfiguring = true
		defer { isConfiguring = false }
		let oldSpaces = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })
		let oldIDs = spaces.map(\.id)
		let previousSelected = selectedID
		let favouritesChanged = favouriteIDs != configuration.favouriteTabIDs
		spaces = configuration.spaces
		favouriteIDs = configuration.favouriteTabIDs
		selectedID = configuration.selectedSpaceID
		factory = configuration.content
		onSelect = configuration.onSelectSpace
		scrollState = configuration.scrollState

		let validIDs = Set(spaces.map(\.id))
		for (id, host) in cachedPages where !validIDs.contains(id) {
			host.removeFromSuperview()
			cachedPages.removeValue(forKey: id)
		}
		for (id, host) in cachedPages {
			guard let space = spaces.first(where: { $0.id == id }) else { continue }
			if oldSpaces[id] != space || favouritesChanged || previousSelected != selectedID {
				host.rootView = configuration.content(space, id == selectedID, favouriteIDs)
			}
		}
		if oldIDs != spaces.map(\.id) {
			pageOrderNeedsLayout = true
			needsLayout = true
			layoutSubtreeIfNeeded()
		}
		if pageWidth <= 0 {
			needsLayout = true
			layoutSubtreeIfNeeded()
		}
		if previousSelected != selectedID, let index = spaces.firstIndex(where: { $0.id == selectedID }) {
			if pendingSelection == selectedID {
				pendingSelection = nil
			} else {
				scrollTo(index: index, animated: previousSelected != nil)
			}
		}
		updateMountedPages()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		removeWheelMonitor()
		guard window != nil else { return }
		// One event monitor per mounted pager. Returning the unmodified event
		// preserves vertical scrolling and child view interaction.
		wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
			MainActor.assumeIsolated { self?.routeWheel(event) }
			return event
		}
	}

	private func routeWheel(_ event: NSEvent) {
		guard let window, event.window === window, !spaces.isEmpty, pageWidth > 0 else { return }
		let point = convert(event.locationInWindow, from: nil)
		guard bounds.contains(point), abs(event.scrollingDeltaX) >= 0.5 else { return }
		snapTask?.cancel()
		snapTask = nil
		// NSScrollView applies the system's scrolling direction, natural
		// scrolling, and momentum. The event also reaches the child vertical
		// SwiftUI scroll view via the regular responder path.
		scroller.scrollWheel(with: event)
		if event.momentumPhase == .ended {
			scheduleSnap(delay: .milliseconds(0))
		} else if event.phase == .ended || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
			// Defer slightly: a trackpad momentum sequence can start after
			// the final direct-touch event.
			scheduleSnap(delay: .milliseconds(130))
		}
	}

	private func scheduleSnap(delay: Duration) {
		snapTask?.cancel()
		snapTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: delay)
			guard !Task.isCancelled else { return }
			self?.finishGesture()
		}
	}

	private func finishGesture() {
		guard pageWidth > 0, !spaces.isEmpty else { return }
		let position = scroller.contentView.bounds.origin.x / pageWidth
		let index = min(max(Int(position.rounded()), 0), spaces.count - 1)
		let id = spaces[index].id
		scrollTo(index: index, animated: true)
		guard id != selectedID else { return }
		pendingSelection = id
		onSelect?(id)
	}

	private func scrollTo(index: Int, animated: Bool) {
		guard pageWidth > 0, spaces.indices.contains(index) else { return }
		let origin = NSPoint(x: CGFloat(index) * pageWidth, y: 0)
		let previousIndex = Int((scroller.contentView.bounds.origin.x / pageWidth).rounded())
		// Don't animate through unmounted intervening pages on a distant jump.
		let shouldAnimate = animated && window != nil
			&& abs(index - previousIndex) <= 1
			&& !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		updateMountedPages(around: index)
		if shouldAnimate {
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.3
				context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
				scroller.contentView.animator().setBoundsOrigin(origin)
			}
		} else {
			scroller.contentView.scroll(to: origin)
			scroller.reflectScrolledClipView(scroller.contentView)
			didScroll()
		}
	}

	private func didScroll() {
		guard !applyingGeometry, pageWidth > 0 else { return }
		let value = Double(scroller.contentView.bounds.origin.x / pageWidth)
		let bounded = min(max(value, 0), Double(max(spaces.count - 1, 0)))
		if isConfiguring {
			// Publishing Observation during updateNSView can cause SwiftUI
			// state-mutation warnings and re-entrant representable updates.
			if !deferredPositionPublish {
				deferredPositionPublish = true
				Task { @MainActor [weak self] in
					await Task.yield()
					guard let self else { return }
					self.deferredPositionPublish = false
					self.didScroll()
				}
			}
		} else if scrollState?.position != bounded {
			scrollState?.position = bounded
		}
		updateMountedPages()
	}

	private func updateMountedPages(around overrideIndex: Int? = nil) {
		guard pageWidth > 0, pageHeight > 0, let factory else { return }
		let position = scroller.contentView.bounds.origin.x / pageWidth
		let current = overrideIndex ?? Int(position.rounded())
		// Keep the current page and both neighbours mounted during gestures.
		let indices = Set((current - 1 ... current + 1).filter { spaces.indices.contains($0) })
		let required = Set(indices.map { spaces[$0].id })
		for (id, host) in cachedPages where !required.contains(id) && host.superview != nil {
			host.removeFromSuperview()
		}
		for index in indices.sorted() {
			let space = spaces[index]
			let host: NSHostingView<Content>
			if let existing = cachedPages[space.id] {
				host = existing
			} else {
				host = NSHostingView(rootView: factory(space, space.id == selectedID, favouriteIDs))
				host.sizingOptions = []
				cachedPages[space.id] = host
			}
			host.frame = NSRect(x: CGFloat(index) * pageWidth, y: 0, width: pageWidth, height: pageHeight)
			if host.superview !== document {
				document.addSubview(host)
			}
		}
	}

	private func removeWheelMonitor() {
		if let wheelMonitor {
			NSEvent.removeMonitor(wheelMonitor)
			self.wheelMonitor = nil
		}
	}

	func stopObserving() {
		snapTask?.cancel()
		snapTask = nil
		removeWheelMonitor()
		if let boundsObserver {
			NotificationCenter.default.removeObserver(boundsObserver)
			self.boundsObserver = nil
		}
	}

}
#else

struct BrowserSpacePager<Content: View>: View {
	let spaces: [BrowserSpace]
	let selectedSpaceID: UUID
	let favouriteTabIDs: [UUID]
	let scrollState: BrowserSpaceScrollState
	let onSelectSpace: (UUID) -> Void
	let content: (BrowserSpace, Bool, [UUID]) -> Content

	@State private var scrollPosition = ScrollPosition(idType: UUID.self)
	@State private var userScrollPending = false
	@State private var userSelectedSpaceID: UUID?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	init(
		spaces: [BrowserSpace],
		selectedSpaceID: UUID,
		favouriteTabIDs: [UUID],
		scrollState: BrowserSpaceScrollState,
		onSelectSpace: @escaping (UUID) -> Void,
		@ViewBuilder content: @escaping (BrowserSpace, Bool, [UUID]) -> Content
	) {
		self.spaces = spaces
		self.selectedSpaceID = selectedSpaceID
		self.favouriteTabIDs = favouriteTabIDs
		self.scrollState = scrollState
		self.onSelectSpace = onSelectSpace
		self.content = content
		_scrollPosition = State(initialValue: ScrollPosition(id: selectedSpaceID, anchor: .center))
	}

	var body: some View {
		ScrollView(.horizontal) {
			HStack(spacing: 0) {
				ForEach(spaces) { space in
					// The page container is the horizontal target around its native vertical scroll view.
					VStack(spacing: 0) {
						content(space, space.id == selectedSpaceID, favouriteTabIDs)
					}
					.containerRelativeFrame(.horizontal)
					.id(space.id)
					.allowsHitTesting(space.id == selectedSpaceID)
					.accessibilityHidden(space.id != selectedSpaceID)
				}
			}
			.scrollTargetLayout()
		}
		.scrollIndicators(.hidden)
		.scrollTargetBehavior(.paging)
		.scrollPosition($scrollPosition, anchor: .center)
		.onScrollGeometryChange(for: Double.self) { geometry in
			Self.pagePosition(in: geometry)
		} action: { _, position in
			var transaction = Transaction(animation: nil)
			transaction.disablesAnimations = true
			withTransaction(transaction) {
				scrollState.position = min(max(position, 0), Double(max(spaces.count - 1, 0)))
			}
		}
		.onScrollPhaseChange { _, phase, context in
			if phase == .interacting {
				userScrollPending = true
			} else if userScrollPending {
				selectSpace(at: Self.pagePosition(in: context.geometry))
			}
		}
		.onChange(of: selectedSpaceID, initial: true) { oldID, id in
			if userSelectedSpaceID == id {
				userSelectedSpaceID = nil
				return
			}
			if oldID != id, let index = spaces.firstIndex(where: { $0.id == id }),
			   let position = scrollState.position, abs(position - Double(index)) < 0.001
			{
				return
			}
			withAnimation(reduceMotion || oldID == id ? nil : .smooth(duration: 0.3)) {
				scrollPosition.scrollTo(id: id, anchor: .center)
			}
		}
		.onChange(of: spaces.map(\.id)) { _, _ in
			// Membership changes keep the selected space aligned without rebuilding its page.
			var transaction = Transaction(animation: nil)
			transaction.disablesAnimations = true
			withTransaction(transaction) {
				scrollPosition.scrollTo(id: selectedSpaceID, anchor: .center)
			}
		}
	}

	private func selectSpace(at position: Double) {
		guard userScrollPending, !spaces.isEmpty else { return }
		userScrollPending = false
		let index = min(max(Int(position.rounded()), 0), spaces.count - 1)
		let id = spaces[index].id
		guard id != selectedSpaceID else { return }
		userSelectedSpaceID = id
		withTransaction(Transaction(animation: nil)) {
			onSelectSpace(id)
		}
	}

	private static func pagePosition(in geometry: ScrollGeometry) -> Double {
		guard geometry.containerSize.width > 0 else { return 0 }
		return Double((geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width)
	}
}

#endif
