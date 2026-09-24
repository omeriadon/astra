import CoreGraphics
import Observation
import SwiftUI
import WebKit
#if os(macOS)
	import AppKit
#endif

@MainActor
@Observable
final class BrowserController: NSObject {
	private static let scrollPositionMessageName = "scrollPositionChanged"
	private static let topEdgeMessageName = "topEdgeChanged"
	private static let scrollPositionScript = """
	(() => {
		let pending;
		const report = () => {
			clearTimeout(pending);
			pending = setTimeout(() => {
				window.webkit.messageHandlers.scrollPositionChanged.postMessage({
					x: window.scrollX,
					y: window.scrollY
				});
			}, 150);
		};
		window.addEventListener('scroll', report, { passive: true });
		window.addEventListener('pagehide', report);
	})();
	"""
	private static let topEdgeScript = """
	(() => {
		let scheduled = false;
		let previous;
		const check = () => {
			scheduled = false;
			if (window.scrollY < 0) return;
			const counts = new Map();
			const samples = 20;
			for (let index = 0; index < samples; index++) {
				const x = innerWidth * (index + 0.5) / samples;
				for (const element of document.elementsFromPoint(x, 2)) {
					if (element === document.body || element === document.documentElement) continue;
					const rect = element.getBoundingClientRect();
					const style = getComputedStyle(element);
					const isPageChrome = element.matches(
						'header, nav, [role="navigation"], [class*="header" i], [id*="header" i], ' +
						'[class*="nav" i], [id*="nav" i], [class*="toolbar" i], [id*="toolbar" i]'
					);
					if (!isPageChrome && style.position !== 'fixed' && style.position !== 'sticky') continue;
					if (rect.top > 3 || rect.bottom < 20 || rect.height > 160 ||
						rect.width < innerWidth * 0.5 || style.visibility === 'hidden' ||
						Number(style.opacity) < 0.05) continue;
					counts.set(element, (counts.get(element) || 0) + 1);
				}
			}
			const occupied = [...counts.values()].some(count => count >= samples * 0.7);
			if (occupied !== previous) {
				previous = occupied;
				window.webkit.messageHandlers.topEdgeChanged.postMessage(occupied);
			}
		};
		const schedule = () => {
			if (scheduled) return;
			scheduled = true;
			requestAnimationFrame(check);
		};
		addEventListener('scroll', schedule, { passive: true });
		addEventListener('resize', schedule);
		new MutationObserver(schedule).observe(document.documentElement, {
			subtree: true, childList: true, attributes: true
		});
		schedule();
	})();
	"""

	@ObservationIgnored
	private var createdWebView: WKWebView?

	var webViewIfLoaded: WKWebView? {
		createdWebView
	}

	var webView: WKWebView {
		if let createdWebView {
			return createdWebView
		}
		return makeWebView()
	}

	private(set) var isWebViewReady = false
	var pageZoom = 1.0 {
		didSet {
			if let createdWebView, Double(createdWebView.pageZoom) != pageZoom {
				createdWebView.pageZoom = CGFloat(pageZoom)
			}
		}
	}

	private var historyManager: BrowserHistory
	var history: [URL] {
		historyManager.entries
	}

	var historyIndex: Int {
		historyManager.index
	}

	var canGoBack: Bool {
		historyManager.canGoBack
	}

	var canGoForward: Bool {
		historyManager.canGoForward
	}

	var url: URL?
	private(set) var isLoading = false
	private(set) var estimatedProgress = 0.0
	private(set) var scrollPosition: BrowserScrollPosition
	private(set) var hasTopEdgeContent = false
	private(set) var themeColor: Color?
	private(set) var themeColorIsLight: Bool?
	#if os(macOS)
		private(set) var previewSnapshot: NSImage?
	#endif

	@ObservationIgnored
	var navigationDidChange: (@MainActor () -> Void)?
	@ObservationIgnored
	var titleDidChange: (@MainActor (String?) -> Void)?
	@ObservationIgnored
	var newWindowRequested: (@MainActor (URL, UnitPoint) -> Void)?
	@ObservationIgnored
	var escapeRequested: (@MainActor () -> Void)? {
		didSet { (createdWebView as? PeekSourceWebView)?.onEscape = escapeRequested }
	}

	@ObservationIgnored
	private var observations: [NSKeyValueObservation] = []
	@ObservationIgnored
	private var navigationGeneration = 0
	@ObservationIgnored
	private var hasDeclaredThemeColor = false
	@ObservationIgnored
	private var pendingRequest: URLRequest?
	@ObservationIgnored
	private var currentNavigation: WKNavigation?
	@ObservationIgnored
	private var awaitsNavigationCommit = false
	@ObservationIgnored
	private var restoredScrollPosition: BrowserScrollPosition?
	#if os(macOS)
		@ObservationIgnored
		private var previewSnapshotRefreshTask: Task<Void, Never>?
		@ObservationIgnored
		private var isRefreshingPreviewSnapshot = false
	#endif

	init(
		initialURL: URL? = nil,
		history: [URL] = [],
		historyIndex: Int = 0,
		scrollPosition: BrowserScrollPosition = .zero
	) {
		let restoredHistory = BrowserHistory(entries: history, index: historyIndex, initialURL: initialURL)
		historyManager = restoredHistory
		url = restoredHistory.currentURL
		self.scrollPosition = scrollPosition
		restoredScrollPosition = scrollPosition == .zero ? nil : scrollPosition
		super.init()
		updateThemeColor(url == nil ? .black : .white)
		#if os(macOS)
			startPreviewSnapshotRefresh()
		#endif

		if let url {
			load(URLRequest(url: url))
		}
	}

	func prepareWebView() {
		_ = webView
	}

	private func makeWebView() -> WKWebView {
		let configuration = WKWebViewConfiguration()
		FaviconStore.shared.configureFaviconObservation(in: configuration.userContentController)
		let webView = PeekSourceWebView(frame: .zero, configuration: configuration)
		createdWebView = webView
		let scrollHandler = WeakScriptMessageHandler(delegate: self)
		webView.configuration.userContentController.add(
			scrollHandler,
			contentWorld: .page,
			name: Self.scrollPositionMessageName
		)
		webView.configuration.userContentController.add(
			scrollHandler,
			contentWorld: .page,
			name: Self.topEdgeMessageName
		)
		webView.configuration.userContentController.addUserScript(
			WKUserScript(
				source: Self.scrollPositionScript,
				injectionTime: .atDocumentEnd,
				forMainFrameOnly: true,
				in: .page
			)
		)
		webView.configuration.userContentController.addUserScript(
			WKUserScript(
				source: Self.topEdgeScript,
				injectionTime: .atDocumentEnd,
				forMainFrameOnly: true,
				in: .page
			)
		)
		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.onEscape = escapeRequested
		webView.onLayout = { [weak self] in
			self?.loadPendingRequest()
		}
		webView.onZoomIn = { [weak self] in self?.zoomIn() }
		webView.onZoomOut = { [weak self] in self?.zoomOut() }
		webView.onResetZoom = { [weak self] in self?.resetZoom() }
		webView.pageZoom = CGFloat(pageZoom)
		updateThemeColor(url == nil ? .black : webView.underPageBackgroundColor ?? .white)

		observations = [
			webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.isLoading = webView.isLoading
				}
			},
			webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.estimatedProgress = webView.estimatedProgress
				}
			},
			webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					guard let self else { return }
					guard !self.awaitsNavigationCommit else { return }
					guard let url = change.newValue ?? webView.url else { return }
					self.url = url
					if !webView.isLoading {
						if (webView as? PeekSourceWebView)?.consumeRecentClick() == true {
							self.historyManager.beginVisit()
						}
						self.updateHistory()
					}
				}
			},
			webView.observe(\.themeColor, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					guard let self else { return }
					guard let color = change.newValue ?? webView.themeColor else {
						self.hasDeclaredThemeColor = false
						return
					}
					self.hasDeclaredThemeColor = true
					webView.underPageBackgroundColor = color.withAlphaComponent(1)
					self.updateThemeColor(color)
				}
			},
			webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					self?.titleDidChange?(change.newValue ?? webView.title)
				}
			},
			webView.observe(\.pageZoom, options: [.new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.pageZoom = Double(webView.pageZoom)
					self?.navigationDidChange?()
				}
			},
		]
		isWebViewReady = true
		return webView
	}

	deinit {
		#if os(macOS)
			previewSnapshotRefreshTask?.cancel()
		#endif
	}

	func load(_ url: URL) {
		createdWebView?.stopLoading()
		(createdWebView as? PeekSourceWebView)?.consumeRecentClick()
		historyManager.beginVisit()
		self.url = url
		scrollPosition = .zero
		restoredScrollPosition = nil
		load(URLRequest(url: url))
	}

	func goBack() {
		go(toHistoryIndex: historyIndex - 1)
	}

	func goForward() {
		go(toHistoryIndex: historyIndex + 1)
	}

	func go(toHistoryIndex index: Int) {
		guard let destination = historyManager.select(index) else { return }
		createdWebView?.stopLoading()
		(createdWebView as? PeekSourceWebView)?.consumeRecentClick()
		url = destination
		scrollPosition = .zero
		restoredScrollPosition = nil
		navigationDidChange?()
		load(URLRequest(url: destination))
	}

	func reload() {
		if let createdWebView {
			createdWebView.reload()
		} else if let url {
			load(URLRequest(url: url))
		}
	}

	func stopLoading() {
		createdWebView?.stopLoading()
		pendingRequest = nil
	}

	func resetZoom() {
		pageZoom = 1
		ToastManager.shared.show(symbol: "1.magnifyingglass", message: "Zoom 100%")
	}

	func reloadFromOrigin() {
		if let createdWebView {
			createdWebView.reloadFromOrigin()
		} else if let url {
			load(URLRequest(url: url))
		}
	}

	func zoomIn() {
		pageZoom = min(pageZoom + 0.1, 5)
		ToastManager.shared.show(
			symbol: "plus.magnifyingglass",
			message: "Zoom \(Int(pageZoom * 100))%"
		)
	}

	func zoomOut() {
		pageZoom = max(pageZoom - 0.1, 0.25)
		ToastManager.shared.show(
			symbol: "minus.magnifyingglass",
			message: "Zoom \(Int(pageZoom * 100))%"
		)
	}

	func loadFaviconIfMissing() {
		guard let url, let webView = createdWebView else { return }
		Task { @MainActor in
			await FaviconStore.shared.loadFavicon(
				for: url,
				from: webView,
				onlyIfMissing: true
			)
		}
	}

	#if os(macOS)
		func refreshPreviewSnapshot() async {
			guard let image = await takeSnapshot() else { return }
			previewSnapshot = image
		}
	#endif

	private func updateHistory() {
		guard let currentURL = createdWebView?.url else { return }
		url = currentURL
		historyManager.record(currentURL)
		navigationDidChange?()
	}

	private func load(_ request: URLRequest) {
		awaitsNavigationCommit = true
		guard let webView = createdWebView, !webView.bounds.isEmpty else {
			pendingRequest = request
			return
		}
		pendingRequest = nil
		currentNavigation = webView.load(request)
	}

	private func loadPendingRequest() {
		guard let pendingRequest else { return }
		load(pendingRequest)
	}

	private func updateThemeColor(_ color: PlatformColor) {
		#if os(macOS)
			guard let color = color.usingColorSpace(.deviceRGB) else {
				return
			}
		#endif
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		#if os(iOS)
			guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
				return
			}
		#elseif os(macOS)
			color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		#endif

		themeColor = Color(color)
		themeColorIsLight = red + green + blue > 1.5
	}

	private func takeSnapshot() async -> SnapshotImage? {
		guard url != nil, let webView = createdWebView, !webView.bounds.isEmpty else { return nil }
		#if os(macOS)
			guard !isRefreshingPreviewSnapshot else { return nil }
			isRefreshingPreviewSnapshot = true
			defer { isRefreshingPreviewSnapshot = false }
		#endif

		let configuration = WKSnapshotConfiguration()
		configuration.rect = webView.bounds
		configuration.snapshotWidth = 180
		return try? await webView.takeSnapshot(configuration: configuration)
	}

	private func capturePageSnapshot(generation: Int) async {
		guard let image = await takeSnapshot(),
		      generation == navigationGeneration
		else { return }

		#if os(macOS)
			previewSnapshot = image
		#endif
	}

	#if os(macOS)
		private func startPreviewSnapshotRefresh() {
			previewSnapshotRefreshTask = Task { @MainActor [weak self] in
				while !Task.isCancelled {
					do {
						try await Task.sleep(for: .seconds(Double.random(in: 50 ... 58)))
					} catch {
						return
					}

					guard let self else { return }
					await refreshPreviewSnapshot()
				}
			}
		}
	#endif
}

extension BrowserController: WKNavigationDelegate {
	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		if navigationAction.shouldPerformDownload {
			decisionHandler(.download)
			return
		}
		#if os(macOS)
			let shiftPressed = navigationAction.modifierFlags.contains(.shift)
		#else
			let shiftPressed = (webView as? PeekSourceWebView)?.hasShiftClick == true
		#endif
		guard navigationAction.navigationType == .linkActivated,
		      shiftPressed,
		      let url = navigationAction.request.url,
		      let newWindowRequested
		else {
			if navigationAction.targetFrame?.isMainFrame == true {
				switch navigationAction.navigationType {
					case .linkActivated, .formSubmitted, .formResubmitted:
						historyManager.beginVisit()
						(webView as? PeekSourceWebView)?.consumeRecentClick()
					default:
						break
				}
			}
			decisionHandler(.allow)
			return
		}
		let source = newWindowSource(in: webView)
		decisionHandler(.cancel)
		newWindowRequested(url, source)
	}

	func webView(
		_: WKWebView,
		decidePolicyFor navigationResponse: WKNavigationResponse,
		decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
	) {
		let disposition = (navigationResponse.response as? HTTPURLResponse)?
			.value(forHTTPHeaderField: "Content-Disposition")
		if !navigationResponse.canShowMIMEType || disposition?.lowercased().hasPrefix("attachment") == true {
			decisionHandler(.download)
		} else {
			decisionHandler(.allow)
		}
	}

	func webView(_: WKWebView, navigationAction _: WKNavigationAction, didBecome download: WKDownload) {
		BrowserDownloadManager.shared.start(download)
	}

	func webView(_: WKWebView, navigationResponse _: WKNavigationResponse, didBecome download: WKDownload) {
		BrowserDownloadManager.shared.start(download)
	}

	func webView(_: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		guard navigation === currentNavigation else { return }
		guard (error as NSError).code != NSURLErrorCancelled else { return }
		awaitsNavigationCommit = false
		historyManager.cancelVisit()
	}

	func webView(_: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		guard navigation === currentNavigation else { return }
		guard (error as NSError).code != NSURLErrorCancelled else { return }
		awaitsNavigationCommit = false
		historyManager.cancelVisit()
	}

	func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		currentNavigation = navigation
		awaitsNavigationCommit = true
		navigationGeneration += 1
		hasDeclaredThemeColor = false
		hasTopEdgeContent = false
		webView.underPageBackgroundColor = nil
	}

	func webView(_: WKWebView, didCommit navigation: WKNavigation!) {
		guard navigation === currentNavigation else { return }
		awaitsNavigationCommit = false
		updateHistory()
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard navigation === currentNavigation else { return }
		updateHistory()
		if !hasDeclaredThemeColor,
		   let pageBackgroundColor = webView.underPageBackgroundColor
		{
			updateThemeColor(pageBackgroundColor)
		}
		restoreScrollPositionIfNeeded(in: webView)
		let generation = navigationGeneration
		if let url {
			Task { @MainActor in
				await FaviconStore.shared.loadFavicon(for: url, from: webView)
			}
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			try? await Task.sleep(for: .milliseconds(200))
			await capturePageSnapshot(generation: generation)
		}
	}

	private func restoreScrollPositionIfNeeded(in webView: WKWebView) {
		guard let restoredScrollPosition else { return }
		self.restoredScrollPosition = nil
		let script = "window.scrollTo(\(restoredScrollPosition.x), \(restoredScrollPosition.y));"
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(150))
			_ = try? await webView.evaluateJavaScript(script)
		}
	}
}

extension BrowserController: WKScriptMessageHandler {
	func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.frameInfo.isMainFrame else { return }

		if message.name == Self.topEdgeMessageName {
			if let occupied = message.body as? Bool {
				hasTopEdgeContent = occupied
			}
			return
		}

		guard message.name == Self.scrollPositionMessageName,
		      let position = message.body as? [String: Double],
		      let x = position["x"],
		      let y = position["y"]
		else { return }

		let nextPosition = BrowserScrollPosition(x: x, y: y)
		guard scrollPosition != nextPosition else { return }
		scrollPosition = nextPosition
		navigationDidChange?()
	}
}

extension BrowserController: WKUIDelegate {
	func webView(
		_ webView: WKWebView,
		createWebViewWith _: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures _: WKWindowFeatures
	) -> WKWebView? {
		if navigationAction.shouldPerformDownload {
			webView.startDownload(using: navigationAction.request) { download in
				BrowserDownloadManager.shared.start(download)
			}
			return nil
		}
		guard navigationAction.targetFrame == nil,
		      let url = navigationAction.request.url
		else { return nil }

		newWindowRequested?(url, newWindowSource(in: webView))
		return nil
	}

	private func newWindowSource(in webView: WKWebView) -> UnitPoint {
		(webView as? PeekSourceWebView)?.consumeSource() ?? .center
	}
}

private final class PeekSourceWebView: WKWebView {
	var onEscape: (() -> Void)?
	var onLayout: (() -> Void)?
	var onZoomIn: (() -> Void)?
	var onZoomOut: (() -> Void)?
	var onResetZoom: (() -> Void)?
	private var clickSource: UnitPoint?
	private var clickTime: TimeInterval = 0
	var shiftClick = false
	var hasShiftClick: Bool {
		shiftClick && ProcessInfo.processInfo.systemUptime - clickTime < 2
	}

	@discardableResult
	func consumeRecentClick() -> Bool {
		guard clickTime > 0,
		      ProcessInfo.processInfo.systemUptime - clickTime < 2
		else { return false }
		clickTime = 0
		return true
	}

	func consumeSource() -> UnitPoint {
		defer {
			clickSource = nil
			clickTime = 0
			shiftClick = false
		}
		#if os(macOS)
			if NSApp.currentEvent?.type == .keyDown {
				return .center
			}
		#endif
		guard clickTime > 0,
		      ProcessInfo.processInfo.systemUptime - clickTime < 2
		else { return .center }
		return clickSource ?? .center
	}

	func recordSource(at point: CGPoint) {
		let insets = obscuredContentInsets
		let width = bounds.width - insets.left - insets.right
		let height = bounds.height - insets.top - insets.bottom
		guard width > 0, height > 0 else { return }
		#if os(macOS)
			let y = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
		#else
			let y = point.y - bounds.minY
		#endif
		clickSource = UnitPoint(
			x: min(max((point.x - bounds.minX - insets.left) / width, 0), 1),
			y: min(max((y - insets.top) / height, 0), 1)
		)
		clickTime = ProcessInfo.processInfo.systemUptime
	}

	#if os(macOS)
		override func layout() {
			super.layout()
			onLayout?()
		}

		override func hitTest(_ point: NSPoint) -> NSView? {
			let target = super.hitTest(point)
			if target != nil,
			   let event = NSApp.currentEvent,
			   event.window === window,
			   event.type == .leftMouseDown || event.type == .otherMouseDown
			{
				recordSource(at: convert(event.locationInWindow, from: nil))
			}
			return target
		}
	#elseif os(iOS)
		override func layoutSubviews() {
			super.layoutSubviews()
			onLayout?()
		}

		override var keyCommands: [UIKeyCommand]? {
			let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(dismissPeek))
			escape.wantsPriorityOverSystemBehavior = true
			let zoomIn = UIKeyCommand(input: "=", modifierFlags: .command, action: #selector(increaseZoom))
			let zoomOut = UIKeyCommand(input: "-", modifierFlags: .command, action: #selector(decreaseZoom))
			zoomIn.wantsPriorityOverSystemBehavior = true
			zoomOut.wantsPriorityOverSystemBehavior = true
			let resetZoom = UIKeyCommand(input: "0", modifierFlags: .command, action: #selector(resetPageZoom))
			resetZoom.wantsPriorityOverSystemBehavior = true
			return (super.keyCommands ?? []) + [zoomIn, zoomOut, resetZoom] + (onEscape == nil ? [] : [escape])
		}

		@objc private func resetPageZoom() {
			onResetZoom?()
		}

		@objc private func increaseZoom() {
			onZoomIn?()
		}

		@objc private func decreaseZoom() {
			onZoomOut?()
		}

		override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
			clickSource = nil
			super.pressesBegan(presses, with: event)
		}

		@objc private func dismissPeek() {
			onEscape?()
		}

		override init(frame: CGRect, configuration: WKWebViewConfiguration) {
			super.init(frame: frame, configuration: configuration)
			let recorder = PeekTouchRecorder(target: nil, action: nil)
			recorder.cancelsTouchesInView = false
			recorder.delaysTouchesBegan = false
			recorder.delaysTouchesEnded = false
			addGestureRecognizer(recorder)
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}
	#endif
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
	weak var delegate: (any WKScriptMessageHandler)?

	init(delegate: any WKScriptMessageHandler) {
		self.delegate = delegate
	}

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		delegate?.userContentController(userContentController, didReceive: message)
	}
}

#if os(iOS)
	private final class PeekTouchRecorder: UIGestureRecognizer {
		override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
			if let webView = view as? PeekSourceWebView, let touch = touches.first {
				webView.shiftClick = event.modifierFlags.contains(.shift)
				webView.recordSource(at: touch.location(in: webView))
			}
			state = .failed
		}
	}
#endif

#if os(iOS)
	private typealias PlatformColor = UIColor
#elseif os(macOS)
	private typealias PlatformColor = NSColor
	private typealias SnapshotImage = NSImage
#endif
#if os(iOS)
	private typealias SnapshotImage = UIImage
#endif
