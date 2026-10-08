import SwiftUI
import WebKit

struct BrowserWebView {
	let controller: BrowserController
	var windowID: UUID?
	var isVisible = true

	/// UI currently covering the webpage.
	var obscuredInsets = EdgeInsets()

	/// Insets when your browser UI is maximally collapsed.
	var minimumViewportInsets = EdgeInsets()

	/// Insets when your browser UI is maximally expanded.
	var maximumViewportInsets = EdgeInsets()
}

#if os(iOS)

	extension BrowserWebView: UIViewRepresentable {
		func makeUIView(context: Context) -> WKWebView {
			let webView = controller.webView
			context.coordinator.attach(to: controller)
			configure(webView)
			return webView
		}

		func updateUIView(_: WKWebView, context: Context) {
			context.coordinator.attach(to: controller)
			configure(controller.webView)
		}

		func makeCoordinator() -> Coordinator {
			Coordinator()
		}

		static func dismantleUIView(_: WKWebView, coordinator: Coordinator) {
			coordinator.detach()
		}

		private func configure(_ webView: WKWebView) {
			webView.obscuredContentInsets = obscuredInsets.uiInsets

			webView.setMinimumViewportInset(
				minimumViewportInsets.uiInsets,
				maximumViewportInset: maximumViewportInsets.uiInsets
			)
		}
	}

	extension BrowserWebView {
		@MainActor
		final class Coordinator: NSObject, UIGestureRecognizerDelegate {
			private var controller: BrowserController?
			private weak var webView: WKWebView?
			private var edgeGestures: [UIScreenEdgePanGestureRecognizer] = []
			private let refreshControl = UIRefreshControl()
			private var loadingObservation: NSKeyValueObservation?
			private var previousVerticalBounce = false
			private let feedback = UIImpactFeedbackGenerator(style: .medium)
			private let arrow = UIImageView()
			private let badge = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
			private var gaveFeedback = false
			private var threshold: CGFloat = 88

			func attach(to controller: BrowserController) {
				guard self.controller !== controller else { return }
				detach()
				self.controller = controller
				let webView = controller.webView
				self.webView = webView

				for edge: UIRectEdge in [.left, .right] {
					let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgeSwipe(_:)))
					gesture.edges = edge
					gesture.delegate = self
					gesture.maximumNumberOfTouches = 1
					gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
					webView.addGestureRecognizer(gesture)
					edgeGestures.append(gesture)
				}

				badge.isUserInteractionEnabled = false
				badge.accessibilityElementsHidden = true
				badge.accessibilityIdentifier = "browser.navigationSwipeIndicator"
				badge.clipsToBounds = true
				badge.layer.cornerRadius = 22
				badge.alpha = 0
				arrow.contentMode = .center
				arrow.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
				badge.contentView.addSubview(arrow)
				webView.addSubview(badge)

				previousVerticalBounce = webView.scrollView.alwaysBounceVertical
				webView.scrollView.alwaysBounceVertical = true
				refreshControl.accessibilityLabel = "Reload page"
				refreshControl.accessibilityIdentifier = "browser.pullToRefresh"
				refreshControl.addTarget(self, action: #selector(refreshPage), for: .valueChanged)
				webView.scrollView.refreshControl = refreshControl
				loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
					MainActor.assumeIsolated {
						if !webView.isLoading {
							self?.refreshControl.endRefreshing()
						}
					}
				}
			}

			func detach() {
				loadingObservation?.invalidate()
				loadingObservation = nil
				for gesture in edgeGestures {
					webView?.removeGestureRecognizer(gesture)
				}
				edgeGestures.removeAll()
				refreshControl.endRefreshing()
				refreshControl.removeTarget(self, action: #selector(refreshPage), for: .valueChanged)
				if let scrollView = webView?.scrollView, scrollView.refreshControl === refreshControl {
					scrollView.refreshControl = nil
					scrollView.alwaysBounceVertical = previousVerticalBounce
				}
				badge.layer.removeAllAnimations()
				badge.removeFromSuperview()
				badge.alpha = 0
				webView = nil
				controller = nil
			}

			func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
				guard let gesture = gestureRecognizer as? UIScreenEdgePanGestureRecognizer,
				      let webView else { return false }
				let velocity = gesture.velocity(in: webView)
				let isBack = gesture.edges == .left
				let inwardVelocity = isBack ? velocity.x : -velocity.x
				return inwardVelocity > abs(velocity.y) * 1.5
					&& (isBack ? webView.canGoBack : webView.canGoForward)
			}

			func gestureRecognizer(
				_: UIGestureRecognizer,
				shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
			) -> Bool {
				// Give deliberate edge swipes priority over page scrolling, including nested carousels.
				otherGestureRecognizer is UIPanGestureRecognizer
					&& !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer)
			}

			@objc private func refreshPage() {
				controller?.reload()
				if webView?.isLoading != true {
					refreshControl.endRefreshing()
				}
			}

			@objc private func handleEdgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
				guard let webView else { return }
				let isBack = gesture.edges == .left
				let direction: CGFloat = isBack ? 1 : -1
				let distance = max(0, gesture.translation(in: webView).x * direction)

				switch gesture.state {
					case .began:
						badge.layer.removeAllAnimations()
						badge.transform = .identity
						gaveFeedback = false
						threshold = min(88, webView.bounds.width * 0.25)
						feedback.prepare()
						arrow.image = UIImage(
							systemName: isBack ? "arrow.left" : "arrow.right",
							withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
						)
						fallthrough
					case .changed:
						let crossedThreshold = distance >= threshold
						if crossedThreshold, !gaveFeedback {
							feedback.impactOccurred()
							gaveFeedback = true
						}
						let progress = min(distance / max(threshold, 1), 1)
						let reveal = 56 * progress
						let centerX = isBack ? -22 + reveal : webView.bounds.width + 22 - reveal
						badge.frame = CGRect(x: centerX - 22, y: webView.bounds.midY - 22, width: 44, height: 44)
						badge.alpha = min(progress * 2, 1)
						arrow.tintColor = crossedThreshold ? .systemBlue : .label
						arrow.transform = CGAffineTransform(scaleX: crossedThreshold ? 1.15 : 1, y: crossedThreshold ? 1.15 : 1)
						webView.bringSubviewToFront(badge)
					case .ended, .cancelled, .failed:
						let shouldNavigate = gesture.state == .ended && distance >= threshold
						UIView.animate(
							withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2,
							delay: 0,
							options: [.beginFromCurrentState, .curveEaseOut]
						) {
							self.badge.alpha = 0
							if !UIAccessibility.isReduceMotionEnabled {
								self.badge.transform = CGAffineTransform(translationX: -direction * 56, y: 0)
							}
						}
						if shouldNavigate {
							if isBack {
								controller?.goBack()
							} else {
								controller?.goForward()
							}
						}
					default:
						break
				}
			}
		}
	}

	private extension EdgeInsets {
		var uiInsets: UIEdgeInsets {
			UIEdgeInsets(
				top: top,
				left: leading,
				bottom: bottom,
				right: trailing
			)
		}
	}

#elseif os(macOS)

	extension BrowserWebView: NSViewRepresentable {
		func makeNSView(context _: Context) -> BrowserWebViewHost {
			BrowserWebViewHost(specification: self)
		}

		func updateNSView(_ host: BrowserWebViewHost, context _: Context) {
			host.update(specification: self)
		}

		static func dismantleNSView(_ host: BrowserWebViewHost, coordinator _: ()) {
			host.handoffTask?.cancel()
			host.pageGestures.detach()
			host.unmountWebView()
		}
	}

	final class BrowserWebViewHost: NSView {
		var specification: BrowserWebView
		var handoffTask: Task<Void, Never>?
		let pageGestures = BrowserDesktopPageGestures()
		private let curtain = NSImageView()
		private var insets: [EdgeInsets]?
		private var appliedVisibility: Bool?
		private(set) var refreshPullOffset: CGFloat = 0

		init(specification: BrowserWebView) {
			self.specification = specification
			super.init(frame: .zero)
			clipsToBounds = true
			curtain.imageScaling = .scaleProportionallyUpOrDown
			curtain.autoresizingMask = [.width, .height]
			curtain.setAccessibilityHidden(true)
			addSubview(curtain)
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		override func layout() {
			super.layout()
			mountIfReady()
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			if window == nil {
				pageGestures.detach()
				unmountWebView()
			}
			mountIfReady()
		}

		func setRefreshPullOffset(_ offset: CGFloat, animated: Bool = false) {
			refreshPullOffset = offset
			let webView = specification.controller.webView
			guard webView.superview === self else { return }
			let origin = CGPoint(
				x: bounds.minX,
				y: bounds.minY + (isFlipped ? offset : -offset)
			)
			guard webView.frame.origin != origin else { return }
			if animated {
				NSAnimationContext.runAnimationGroup { context in
					context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
					webView.animator().setFrameOrigin(origin)
				}
			} else {
				webView.setFrameOrigin(origin)
			}
		}

		func update(specification: BrowserWebView) {
			if self.specification.controller !== specification.controller
				|| self.specification.windowID != specification.windowID
			{
				unmountWebView()
			}
			self.specification = specification
			mountIfReady()
		}

		func mountIfReady() {
			let controller = specification.controller
			let remainsAttached = specification.isVisible || controller.shouldKeepWebViewAttached

			guard specification.windowID == nil || controller.displayWindowID == specification.windowID else {
				unmountWebView()
				return
			}
			guard window != nil, !bounds.isEmpty else {
				if !remainsAttached {
					unmountWebView()
				}
				return
			}
			if !remainsAttached {
				unmountWebView()
				return
			}
			if !specification.isVisible, controller.webViewIfLoaded == nil {
				return
			}
			let webView = controller.webView
			if webView.superview !== self {
				// Reparenting an existing WKWebView can itself stall AppKit's
				// main thread independently of WebKit's initial creation.
				// Time the synchronous host handoff separately so switching
				// delays can be attributed to the correct lifecycle stage.
				let attachStarted = BrowserLog.clock()
				defer {
					BrowserLog.duration(
						.webKit, "webview.host.attach",
						since: attachStarted,
						warnAboveMilliseconds: 30,
						metadata: ["controller": BrowserLog.id(controller.id)]
					)
				}
				appliedVisibility = nil
				handoffTask?.cancel()
				curtain.frame = bounds
				curtain.image = controller.windowMirrorSnapshot ?? controller.previewSnapshot
				curtain.isHidden = !specification.isVisible || curtain.image == nil
				webView.removeFromSuperview()
				webView.frame = bounds
				webView.autoresizingMask = [.width, .height]
				addSubview(webView, positioned: .below, relativeTo: curtain)
				if webView.responds(to: NSSelectorFromString("_inspector")),
				   let inspector = webView.perform(NSSelectorFromString("_inspector"))?.takeUnretainedValue() as? NSObject,
				   inspector.value(forKey: "isVisible") as? Bool == true,
				   inspector.responds(to: NSSelectorFromString("attach"))
				{
					BrowserDesktopCommands.attachWebInspector(inspector)
				}
				handoffTask = Task { @MainActor [weak self, weak webView] in
					let deadline = ContinuousClock.now + .seconds(1)
					while !Task.isCancelled, ContinuousClock.now < deadline {
						if await controller.refreshWindowMirrorSnapshot() {
							break
						}
						do {
							// Failed snapshot attempts usually mean WebKit is still
							// attaching or another snapshot is in flight. Polling at
							// 20 ms only creates contention; 75 ms is still imperceptible.
							try await Task.sleep(for: .milliseconds(75))
						} catch {
							return
						}
					}
					guard !Task.isCancelled, let self, let webView, webView.superview === self,
					      specification.windowID == nil || specification.windowID == controller.displayWindowID else { return }
					curtain.isHidden = true
				}
			}
			// WebKit owns the page frame while its inspector is docked in this host.
			let hasDockedInspector = subviews.contains { $0 is WKWebView && $0 !== webView }
			if !hasDockedInspector {
				let targetFrame = bounds.offsetBy(dx: 0, dy: isFlipped ? refreshPullOffset : -refreshPullOffset)
				if webView.frame != targetFrame {
					webView.frame = targetFrame
				}
			}
			if appliedVisibility != specification.isVisible {
				webView.isHidden = !specification.isVisible
				webView.setAccessibilityHidden(!specification.isVisible)
				appliedVisibility = specification.isVisible
			}
			if specification.isVisible {
				pageGestures.attach(to: controller, in: self)
			} else {
				pageGestures.detach()
			}
			let nextInsets = [specification.obscuredInsets, specification.minimumViewportInsets, specification.maximumViewportInsets]
			if insets != nextInsets {
				webView.obscuredContentInsets = specification.obscuredInsets.nsInsets
				webView.setMinimumViewportInset(specification.minimumViewportInsets.nsInsets, maximumViewportInset: specification.maximumViewportInsets.nsInsets)
				insets = nextInsets
			}
		}

		func unmountWebView() {
			handoffTask?.cancel()
			handoffTask = nil
			pageGestures.detach()
			guard let webView = specification.controller.webViewIfLoaded,
			      webView.superview === self else { return }
			webView.removeFromSuperview()
			webView.isHidden = true
			webView.setAccessibilityHidden(true)
			appliedVisibility = nil
		}
	}

	@MainActor
	final class BrowserDesktopPageGestures {
		private weak var host: BrowserWebViewHost?
		private weak var controller: BrowserController?
		private var monitor: Any?
		private var loadingObservation: NSKeyValueObservation?
		private let indicator = BrowserDesktopGestureIndicator()
		private var gestureID = UUID()
		private var permissions: [Bool]?
		private var movement = CGPoint.zero
		private var action: Action?
		private var gaveFeedback = false
		private var suppressMomentum = false
		private var refreshing = false

		private enum Action {
			case back
			case forward
			case refresh
		}

		func attach(to controller: BrowserController, in host: BrowserWebViewHost) {
			guard self.controller !== controller || self.host !== host else { return }
			detach()
			self.controller = controller
			self.host = host
			host.addSubview(indicator)
			loadingObservation = controller.webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					guard let self, !webView.isLoading, self.refreshing else { return }
					self.refreshing = false
					self.host?.setRefreshPullOffset(0, animated: true)
					self.indicator.hide()
				}
			}
			monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
				let consumed = MainActor.assumeIsolated {
					guard let self else { return false }
					return self.handle(event) == nil
				}
				return consumed ? nil : event
			}
		}

		func detach() {
			if let monitor {
				NSEvent.removeMonitor(monitor)
			}
			monitor = nil
			loadingObservation?.invalidate()
			loadingObservation = nil
			gestureID = UUID()
			permissions = nil
			action = nil
			suppressMomentum = false
			refreshing = false
			host?.setRefreshPullOffset(0)
			indicator.hide()
			indicator.removeFromSuperview()
			host = nil
			controller = nil
		}

		private func handle(_ event: NSEvent) -> NSEvent? {
			guard let host, let controller,
			      event.window === host.window,
			      controller.webView.superview === host,
			      !host.isHiddenOrHasHiddenAncestor,
			      event.hasPreciseScrollingDeltas else { return event }

			if !event.momentumPhase.isEmpty {
				return suppressMomentum ? nil : event
			}
			if event.phase.contains(.began) {
				gestureID = UUID()
				permissions = nil
				movement = .zero
				action = nil
				gaveFeedback = false
				suppressMomentum = false
				guard !refreshing else { return event }
				let point = host.convert(event.locationInWindow, from: nil)
				guard host.bounds.contains(point),
				      let hitView = host.window?.contentView?.hitTest(event.locationInWindow),
				      hitView.isDescendant(of: controller.webView) else { return event }
				checkPage(at: point)
			}
			if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
				let consumed = action != nil
				if event.phase.contains(.ended), distance >= threshold, let action {
					switch action {
						case .back:
							controller.goBack()
						case .forward:
							controller.goForward()
						case .refresh:
							refreshing = true
							host.setRefreshPullOffset(60, animated: true)
							indicator.show(in: host, progress: 1, back: false, refresh: true, armed: true)
							indicator.spinner.isIndeterminate = true
							indicator.spinner.startAnimation(nil)
							controller.reload()
							refreshing = controller.webView.isLoading
					}
				}
				if !refreshing {
					host.setRefreshPullOffset(0, animated: true)
					indicator.hide()
				}
				gestureID = UUID()
				permissions = nil
				action = nil
				return consumed ? nil : event
			}
			guard event.phase.contains(.began) || event.phase.contains(.changed), !refreshing else { return event }
			movement.x += event.scrollingDeltaX
			movement.y += event.scrollingDeltaY
			guard let permissions else { return event }
			if action == nil, max(abs(movement.x), abs(movement.y)) >= 12 {
				if abs(movement.x) > abs(movement.y) * 1.5 {
					if movement.x > 0, permissions[0], controller.webView.canGoBack {
						action = .back
					} else if movement.x < 0, permissions[1], controller.webView.canGoForward {
						action = .forward
					}
				} else if movement.y > abs(movement.x) * 1.5, permissions[2] {
					action = .refresh
				}
				// Once the axis is clear, a page-owned gesture stays page-owned until release.
				if action == nil {
					self.permissions = nil
				}
			}
			guard let action else { return event }
			suppressMomentum = true
			let armed = distance >= threshold
			if armed, !gaveFeedback {
				NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
				gaveFeedback = true
			}
			if action == .refresh {
				host.setRefreshPullOffset(min(distance * 0.6, host.bounds.height * 0.3))
			}
			indicator.show(
				in: host,
				progress: min(distance / threshold, 1),
				back: action == .back,
				refresh: action == .refresh,
				armed: armed
			)
			return nil
		}

		private var threshold: CGFloat {
			action == .refresh ? 100 : 120
		}

		private var distance: CGFloat {
			switch action {
				case .back:
					max(0, movement.x)
				case .forward:
					max(0, -movement.x)
				case .refresh:
					max(0, movement.y)
				case nil:
					0
			}
		}

		private func checkPage(at point: CGPoint) {
			guard let host, let controller else { return }
			let webView = controller.webView
			let localPoint = webView.convert(point, from: host)
			let x = localPoint.x / webView.pageZoom
			let y = (webView.isFlipped ? localPoint.y : webView.bounds.height - localPoint.y) / webView.pageZoom
			let currentGestureID = gestureID
			// Read in an isolated world so page scripts cannot replace DOM APIs used for arbitration.
			let script = """
			(() => {
			    const root = document.scrollingElement;
			    if (!root) return [false, false, false];
			    let back = true, forward = true, refresh = root.scrollTop <= 1;
			    let node = document.elementFromPoint(\(x), \(y));
			    while (node) {
			        if (node.nodeType !== 1) break;
			        const style = getComputedStyle(node);
			        const nested = node !== root && node !== document.body;
			        const horizontal = /auto|scroll|overlay/.test(style.overflowX);
			        const vertical = /auto|scroll|overlay/.test(style.overflowY);
			        if (nested && ((horizontal && node.scrollWidth > node.clientWidth + 1)
			            || /^(CANVAS|IFRAME|VIDEO)$/.test(node.tagName)
			            || (node.tagName === 'INPUT' && node.type === 'range')
			            || /none|pan-y/.test(style.touchAction)
			            || /contain|none/.test(style.overscrollBehaviorX))) {
			            back = false; forward = false;
			        }
			        if (nested && ((vertical && node.scrollTop > 1)
			            || /^(IFRAME|CANVAS)$/.test(node.tagName)
			            || /contain|none/.test(style.overscrollBehaviorY))) refresh = false;
			        node = node.parentElement || node.getRootNode().host;
			    }
			    if (root.scrollWidth > root.clientWidth + 1
			        && !/hidden|clip/.test(getComputedStyle(root).overflowX)
			        && !/hidden|clip/.test(getComputedStyle(document.body).overflowX)) {
			        const rtl = getComputedStyle(root).direction === 'rtl';
			        const left = rtl ? root.scrollWidth - root.clientWidth + root.scrollLeft : root.scrollLeft;
			        back &&= left <= 1;
			        forward &&= left >= root.scrollWidth - root.clientWidth - 1;
			    }
			    return [back, forward, refresh];
			})()
			"""
			webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
				guard let self, gestureID == currentGestureID,
				      case let .success(value) = result,
				      let permissions = value as? [Bool], permissions.count == 3 else { return }
				self.permissions = permissions
			}
		}
	}

	private final class BrowserDesktopGestureIndicator: NSVisualEffectView {
		private let arrow = NSImageView()
		let spinner = NSProgressIndicator()

		init() {
			super.init(frame: .zero)
			material = .hudWindow
			blendingMode = .withinWindow
			state = .active
			wantsLayer = true
			layer?.cornerRadius = 22
			layer?.masksToBounds = true
			alphaValue = 0
			setAccessibilityHidden(true)
			setAccessibilityIdentifier("browser.pageGestureIndicator")
			arrow.imageScaling = .scaleProportionallyDown
			spinner.style = .spinning
			spinner.controlSize = .small
			spinner.isDisplayedWhenStopped = true
			addSubview(arrow)
			addSubview(spinner)
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		override func hitTest(_: NSPoint) -> NSView? {
			nil
		}

		func show(in host: BrowserWebViewHost, progress: CGFloat, back: Bool, refresh: Bool, armed: Bool) {
			layer?.removeAllAnimations()
			let reveal = 56 * progress
			let insets = host.specification.obscuredInsets
			let x = refresh ? host.bounds.midX - 22 : back ? -44 + reveal : host.bounds.width - reveal
			let refreshCenterY = host.isFlipped
				? insets.top + host.refreshPullOffset / 2
				: host.bounds.height - insets.top - host.refreshPullOffset / 2
			frame = CGRect(x: x, y: refresh ? refreshCenterY - 22 : host.bounds.midY - 22, width: 44, height: 44)
			alphaValue = min(progress * 2, 1)
			arrow.isHidden = refresh
			spinner.isHidden = !refresh
			arrow.frame = CGRect(x: 11, y: 11, width: 22, height: 22)
			arrow.image = NSImage(systemSymbolName: back ? "arrow.left" : "arrow.right", accessibilityDescription: nil)
			arrow.contentTintColor = armed ? .controlAccentColor : .labelColor
			spinner.frame = CGRect(x: 14, y: 14, width: 16, height: 16)
			if refresh {
				spinner.stopAnimation(nil)
				spinner.isIndeterminate = false
				spinner.doubleValue = progress * 100
			}
		}

		func hide() {
			spinner.stopAnimation(nil)
			NSAnimationContext.runAnimationGroup { context in
				context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
				animator().alphaValue = 0
			}
		}
	}

	private extension EdgeInsets {
		var nsInsets: NSEdgeInsets {
			NSEdgeInsets(
				top: top,
				left: leading,
				bottom: bottom,
				right: trailing
			)
		}
	}

#endif
