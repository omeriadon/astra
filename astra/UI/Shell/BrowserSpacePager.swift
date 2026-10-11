import SwiftUI
#if os(macOS)
	import AppKit
	import QuartzCore
#endif

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
		#if os(macOS)
			BrowserNativeSpacePager(
				spaces: spaces,
				selectedSpaceID: selectedSpaceID,
				favouriteTabIDs: favouriteTabIDs,
				scrollState: scrollState,
				reduceMotion: reduceMotion,
				onSelectSpace: onSelectSpace,
				content: content
			)
		#else
			swiftUIScroller
		#endif
	}

	private var swiftUIScroller: some View {
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

#if os(macOS)
	private enum BrowserSpacePagingPhysics {
		/// Recovered from Arc 1.167.1; see docs/arc-space-paging-research.md.
		static func resistedOffset(_ offset: Double, maximum: Double) -> Double {
			let clamped = min(max(offset, 0), maximum)
			let distance = abs(offset - clamped)
			let resistance = 255 * (1 - 1 / (distance * 0.15 / 255 + 1))
			return clamped + (offset < clamped ? -resistance : resistance)
		}

		static func adoptedOffset(_ offset: Double, maximum: Double) -> Double {
			let clamped = min(max(offset, 0), maximum)
			let distance = min(abs(offset - clamped), 254.999)
			let rawDistance = 255 * distance / (0.15 * (255 - distance))
			return clamped + (offset < clamped ? -rawDistance : rawDistance)
		}

		static func destination(
			offset: Double,
			width: Double,
			count: Int,
			velocity: Double,
			interrupted: Bool
		) -> Int {
			guard width > 0, count > 0 else { return 0 }
			let position = offset / width
			let floorIndex = min(max(Int(floor(position)), 0), count - 1)
			let index: Int = if abs(velocity) < 5 {
				Int(position.rounded())
			} else if interrupted {
				floorIndex + (velocity > 0 ? 1 : -1)
			} else {
				floorIndex + (velocity > 0 ? 1 : 0)
			}
			return min(max(index, 0), count - 1)
		}

		static func velocity(
			samples: [(time: TimeInterval, offset: Double)],
			at timestamp: TimeInterval
		) -> Double {
			let recent = samples.filter { timestamp - $0.time <= 0.1 }
			guard let first = recent.first, let last = recent.last,
			      last.time > first.time
			else { return 0 }
			return (last.offset - first.offset) / (last.time - first.time)
		}
	}

	private struct BrowserNativeSpacePager<Content: View>: NSViewRepresentable {
		let spaces: [BrowserSpace]
		let selectedSpaceID: UUID
		let favouriteTabIDs: [UUID]
		let scrollState: BrowserSpaceScrollState
		let reduceMotion: Bool
		let onSelectSpace: (UUID) -> Void
		let content: (BrowserSpace, Bool, [UUID]) -> Content

		func makeNSView(context _: Context) -> BrowserNativeSpacePagerView {
			BrowserNativeSpacePagerView()
		}

		func updateNSView(_ view: BrowserNativeSpacePagerView, context: Context) {
			view.update(
				spaces: spaces,
				selectedSpaceID: selectedSpaceID,
				scrollState: scrollState,
				reduceMotion: reduceMotion,
				onSelectSpace: onSelectSpace
			) { space, isActive in
				AnyView(
					content(space, isActive, favouriteTabIDs)
						.environment(\.self, context.environment)
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
						.allowsHitTesting(isActive)
						.accessibilityHidden(!isActive)
				)
			}
		}

		static func dismantleNSView(_ view: BrowserNativeSpacePagerView, coordinator _: ()) {
			view.teardown()
		}
	}

	private final class BrowserSpacePageHost: NSHostingView<AnyView> {
		var hitTestingEnabled = false

		override func hitTest(_ point: NSPoint) -> NSView? {
			hitTestingEnabled ? super.hitTest(point) : nil
		}
	}

	private final class BrowserSpacePagerDocumentView: NSView {
		override var isFlipped: Bool {
			true
		}
	}

	private final class BrowserNativeSpacePagerView: NSView {
		private enum Gesture {
			case none
			case pending
			case horizontal
			case vertical
		}

		private struct Settling {
			let start: Double
			let target: Double
			let velocity: Double
			let time: TimeInterval
			let spring: Spring
		}

		private let documentView = BrowserSpacePagerDocumentView()
		private var pageHosts: [UUID: BrowserSpacePageHost] = [:]
		private var spaceSnapshots: [UUID: BrowserSpace] = [:]
		private var pageFactory: ((BrowserSpace, Bool) -> AnyView)?
		private var pageIDs: [UUID] = []
		private var selectedSpaceID: UUID?
		private var pendingSelectionID: UUID?
		private var scrollState: BrowserSpaceScrollState?
		private var onSelectSpace: ((UUID) -> Void)?
		private var reduceMotion = false
		private var monitor: Any?
		private var frameLink: CADisplayLink?
		private var gesture = Gesture.none
		private var physicalGestureEnded = false
		private var interruptedSettling = false
		private var samples: [(time: TimeInterval, offset: Double)] = []
		private var offset = 0.0
		private var rawOffset = 0.0
		private var pageWidth = 0.0
		private var settling: Settling?
		private var positionPublicationPending = false

		override var isFlipped: Bool {
			true
		}

		private var maximumOffset: Double {
			Double(max(pageIDs.count - 1, 0)) * pageWidth
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		init() {
			super.init(frame: .zero)
			wantsLayer = true
			layer?.masksToBounds = true
			addSubview(documentView)
		}

		func update(
			spaces: [BrowserSpace],
			selectedSpaceID: UUID,
			scrollState: BrowserSpaceScrollState,
			reduceMotion: Bool,
			onSelectSpace: @escaping (UUID) -> Void,
			content: (BrowserSpace, Bool) -> AnyView
		) {
			let newIDs = spaces.map(\.id)
			let membershipChanged = pageIDs != newIDs
			let selectionChanged = self.selectedSpaceID != selectedSpaceID
			let selectionAcknowledged = pendingSelectionID == selectedSpaceID
			self.scrollState = scrollState
			self.onSelectSpace = onSelectSpace
			self.reduceMotion = reduceMotion
			self.selectedSpaceID = selectedSpaceID
			if selectionAcknowledged {
				pendingSelectionID = nil
			}
			pageIDs = newIDs
			spaceSnapshots = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })
			pageFactory = content

			// Page ownership is keyed to stable UUIDs. Only *attached* pages
			// participate in SwiftUI layout/observation; a detached host retains
			// its vertical ScrollView and local SwiftUI state until it is revisited.
			for id in pageHosts.keys.filter({ !newIDs.contains($0) }) {
				pageHosts.removeValue(forKey: id)?.removeFromSuperview()
			}

			if membershipChanged {
				resetGesture()
				stopSettling()
				pendingSelectionID = nil
				offset = selectedOffset
				rawOffset = offset
			} else if selectionChanged, !selectionAcknowledged {
				pendingSelectionID = nil
				resetGesture()
				startSettling(to: selectedOffset, velocity: 0, response: 0.4)
			} else if reduceMotion, let settling {
				let target = settling.target
				stopSettling()
				render(target, deferred: true)
			}
			updateMountedPages(refreshContent: true)
			needsLayout = true
			publishPosition(deferred: true)
		}

		private var selectedOffset: Double {
			Double(pageIDs.firstIndex(where: { $0 == selectedSpaceID }) ?? 0) * pageWidth
		}

		override func layout() {
			super.layout()
			let width = Double(bounds.width)
			if width != pageWidth {
				if pageWidth > 0, width > 0 {
					let ratio = width / pageWidth
					let previousSettling = settling
					let velocity = previousSettling.map {
						$0.spring.velocity(
							fromValue: $0.start,
							toValue: $0.target,
							initialVelocity: $0.velocity,
							time: max(0, CACurrentMediaTime() - $0.time)
						) * ratio
					} ?? 0
					offset *= ratio
					rawOffset *= ratio
					pageWidth = width
					samples.removeAll(keepingCapacity: true)
					if let previousSettling {
						startSettling(
							to: previousSettling.target * ratio,
							velocity: velocity,
							response: previousSettling.spring.response
						)
					}
				} else {
					pageWidth = width
					offset = selectedOffset
					rawOffset = offset
				}
			}
			documentView.frame = NSRect(
				x: -offset,
				y: 0,
				width: bounds.width * CGFloat(pageIDs.count),
				height: bounds.height
			)
			updateMountedPages()
			publishPosition(deferred: true)
		}

		private func render(_ position: Double, deferred: Bool = false) {
			offset = position
			documentView.setFrameOrigin(NSPoint(x: -position, y: 0))
			updateMountedPages()
			publishPosition(deferred: deferred)
		}

		/// Keep only the current and adjacent pages in AppKit's visible tree.
		/// The one-page lookahead supports slow swipes, interruption and the
		/// custom spring without eagerly constructing unrelated SwiftUI lists.
		private func updateMountedPages(refreshContent: Bool = false) {
			guard let pageFactory, !pageIDs.isEmpty, bounds.width > 0 else { return }
			let reference = pageWidth > 0 ? offset / pageWidth :
				Double(pageIDs.firstIndex(where: { $0 == selectedSpaceID }) ?? 0)
			let lower = max(0, Int(floor(reference)) - 1)
			let upper = min(pageIDs.count - 1, Int(ceil(reference)) + 1)
			guard lower <= upper else { return }
			let mountedIDs = Set((lower ... upper).map { pageIDs[$0] })

			for (id, host) in pageHosts where !mountedIDs.contains(id) && host.superview != nil {
				host.removeFromSuperview()
			}
			for index in lower ... upper {
				let id = pageIDs[index]
				guard let space = spaceSnapshots[id] else { continue }
				let active = id == selectedSpaceID
				let host: BrowserSpacePageHost
				if let retained = pageHosts[id] {
					host = retained
					if refreshContent || retained.superview == nil {
						retained.rootView = pageFactory(space, active)
					}
				} else {
					host = BrowserSpacePageHost(rootView: pageFactory(space, active))
					host.sizingOptions = []
					pageHosts[id] = host
				}
				host.hitTestingEnabled = active
				host.setAccessibilityHidden(!active)
				host.frame = NSRect(
					x: CGFloat(index) * bounds.width,
					y: 0,
					width: bounds.width,
					height: bounds.height
				)
				if host.superview !== documentView {
					documentView.addSubview(host)
				}
			}
		}

		private func publishPosition(deferred: Bool) {
			if deferred {
				guard !positionPublicationPending else { return }
				positionPublicationPending = true
				DispatchQueue.main.async { [weak self] in
					guard let self else { return }
					positionPublicationPending = false
					publishPosition(deferred: false)
				}
				return
			}
			guard pageWidth > 0, let scrollState else { return }
			let position = min(max(offset / pageWidth, 0), Double(max(pageIDs.count - 1, 0)))
			guard scrollState.position != position else { return }
			var transaction = Transaction(animation: nil)
			transaction.disablesAnimations = true
			withTransaction(transaction) {
				scrollState.position = position
			}
		}

		private func startSettling(to target: Double, velocity: Double, response: Double) {
			// shortcut: uses Apple's spring and local stop tolerances; match captured Arc traces if the remaining feel differs.
			stopSettling()
			rawOffset = target
			guard !reduceMotion, window != nil, pageWidth > 0,
			      abs(offset - target) > 0.1 || abs(velocity) > 1
			else {
				render(target, deferred: true)
				return
			}
			settling = Settling(
				start: offset,
				target: target,
				velocity: velocity,
				time: CACurrentMediaTime(),
				spring: Spring(response: response, dampingRatio: 1)
			)
			let link = displayLink(target: self, selector: #selector(step(_:)))
			frameLink = link
			link.add(to: .main, forMode: .common)
		}

		@objc private func step(_ link: CADisplayLink) {
			guard let settling else { return }
			let elapsed = max(0, link.timestamp - settling.time)
			let value: Double = settling.spring.value(
				fromValue: settling.start,
				toValue: settling.target,
				initialVelocity: settling.velocity,
				time: elapsed
			)
			let velocity: Double = settling.spring.velocity(
				fromValue: settling.start,
				toValue: settling.target,
				initialVelocity: settling.velocity,
				time: elapsed
			)
			render(value)
			if abs(value - settling.target) < 0.1, abs(velocity) < 1 {
				render(settling.target)
				stopSettling()
			}
		}

		private func stopSettling() {
			settling = nil
			frameLink?.invalidate()
			frameLink = nil
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			if window == nil {
				teardown()
			} else if monitor == nil {
				needsLayout = true
				monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
					guard let self else { return event }
					let consumed = MainActor.assumeIsolated {
						self.handle(event) == nil
					}
					return consumed ? nil : event
				}
			}
		}

		func teardown() {
			if let monitor {
				NSEvent.removeMonitor(monitor)
				self.monitor = nil
			}
			if let settling {
				offset = settling.target
			}
			stopSettling()
			resetGesture()
		}

		private func resetGesture() {
			gesture = .none
			physicalGestureEnded = false
			interruptedSettling = false
			samples.removeAll(keepingCapacity: true)
		}

		private func eventIsInside(_ event: NSEvent) -> Bool {
			guard let window, event.window === window,
			      window.isVisible, !isHiddenOrHasHiddenAncestor,
			      bounds.contains(convert(event.locationInWindow, from: nil)),
			      let contentView = window.contentView,
			      let target = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil))
			else { return false }
			return target === self || target.isDescendant(of: self)
		}

		private func handle(_ event: NSEvent) -> NSEvent? {
			guard let window, event.window === window,
			      window.isVisible, !isHiddenOrHasHiddenAncestor
			else { return event }

			if event.phase.contains(.began) {
				resetGesture()
				guard eventIsInside(event), pageWidth > 0, !pageIDs.isEmpty else { return event }
				gesture = .pending
				interruptedSettling = settling != nil
			}
			if !event.momentumPhase.isEmpty {
				guard gesture == .horizontal else { return event }
				if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
					resetGesture()
				}
				return nil
			}
			if event.phase.isEmpty {
				guard eventIsInside(event), pageWidth > 0,
				      event.scrollingDeltaX != 0,
				      abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY),
				      !pageIDs.isEmpty
				else { return event }
				resetGesture()
				let current = pageIDs.firstIndex(where: { $0 == (pendingSelectionID ?? selectedSpaceID) }) ?? 0
				let target = min(max(current + (event.scrollingDeltaX < 0 ? 1 : -1), 0), pageIDs.count - 1)
				startSettling(to: Double(target) * pageWidth, velocity: 0, response: 0.4)
				selectPage(target)
				return nil
			}
			guard gesture != .none else { return event }

			if event.phase.contains(.began) || event.phase.contains(.changed) {
				guard !physicalGestureEnded else { return nil }
				if gesture == .pending, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
					if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
						gesture = .vertical
					} else {
						gesture = .horizontal
						stopSettling()
						rawOffset = BrowserSpacePagingPhysics.adoptedOffset(offset, maximum: maximumOffset)
						samples = [(event.timestamp, rawOffset)]
					}
				}
				guard gesture == .horizontal else { return event }
				rawOffset -= event.scrollingDeltaX * 0.5
				render(BrowserSpacePagingPhysics.resistedOffset(rawOffset, maximum: maximumOffset))
				samples.append((event.timestamp, rawOffset))
				samples.removeAll { event.timestamp - $0.time > 0.1 }
				return nil
			}
			if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
				guard gesture == .horizontal else {
					resetGesture()
					return event
				}
				physicalGestureEnded = true
				let velocity = event.phase.contains(.cancelled) ? 0 :
					BrowserSpacePagingPhysics.velocity(samples: samples, at: event.timestamp)
				let target = BrowserSpacePagingPhysics.destination(
					offset: offset,
					width: pageWidth,
					count: pageIDs.count,
					velocity: velocity,
					interrupted: interruptedSettling
				)
				let targetOffset = Double(target) * pageWidth
				let pointsTowardTarget = (offset > targetOffset) != (velocity >= 0)
				startSettling(
					to: targetOffset,
					velocity: pointsTowardTarget ? velocity : 0,
					response: 0.25
				)
				selectPage(target)
				return nil
			}
			return gesture == .horizontal ? nil : event
		}

		private func selectPage(_ index: Int) {
			guard pageIDs.indices.contains(index) else { return }
			let id = pageIDs[index]
			guard id != selectedSpaceID else { return }
			pendingSelectionID = id
			withTransaction(Transaction(animation: nil)) {
				onSelectSpace?(id)
			}
		}
	}
#endif
