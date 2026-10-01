import CoreGraphics
import AVFoundation
import CoreLocation
import Defaults
import Observation
import SwiftUI
import WebKit
#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif

@MainActor
@Observable
final class BrowserController: NSObject, Identifiable {
	let id = UUID()
	let session: BrowserWebSession
	private let suppliedConfiguration: WKWebViewConfiguration?
	private var pendingInteractionState: Data?
	@ObservationIgnored
	private var securityScopedFile: URL?
	private(set) var fileAccessBookmark: Data?
	private var pendingLocalFile: URL?
	private(set) var liveHistoryPrefix: [URL]
	@ObservationIgnored
	private var mediaObservationTask: Task<Void, Never>?
	@ObservationIgnored
	private var faviconTask: Task<Void, Never>?
	@ObservationIgnored
	private var isInvalidated = false
	private(set) var isPlayingMedia = false
	private(set) var hasPausedMedia = false
	private(set) var mediaTitle: String?
	private(set) var mediaArtist: String?
	private(set) var pausedFromBrowser = false
	private(set) var areMediaElementsMuted = false
	private(set) var committedURL: URL?
	private(set) var hasOnlySecureContent = false
	var showsFind = false
	var findText = ""
	private(set) var findHasMatch = true
	@ObservationIgnored
	private var findGeneration = 0
	private(set) var hasUnsavedChanges = false
	private(set) var cameraCaptureState: WKMediaCaptureState = .none
	private(set) var microphoneCaptureState: WKMediaCaptureState = .none
	var popupRequested: ((WKWebViewConfiguration, UnitPoint, Bool?) -> WKWebView?)?
	var newTabRequested: ((URLRequest, Bool) -> Void)?
	var closeRequested: (() -> Void)?
	@ObservationIgnored
	var promptOwnership: ((WKWebView) -> Bool)?
	@ObservationIgnored
	private var isOpeningExternalApplication = false
	@ObservationIgnored
	// ponytail: controller-wide two-second throttle; per-origin limits if abuse becomes measurable.
	private var lastExternalApplicationRequestTime: TimeInterval?
	@ObservationIgnored
	var navigationIntercept: ((URL) -> Bool)?

	var isCapturing: Bool {
		cameraCaptureState != .none || microphoneCaptureState != .none
	}

	var connectionDescription: String {
		guard navigationFailure == nil else { return "Connection Failed" }
		guard let committedURL else { return "No Page Loaded" }
		if committedURL.isFileURL {
			return "Local File"
		}
		if committedURL.scheme == "https" {
			return hasOnlySecureContent ? "Connection Encrypted" : "Mixed Content"
		}
		return committedURL.scheme == "http" ? "Not Secure" : "Local Content"
	}

	var connectionSymbol: String {
		guard navigationFailure == nil else { return "exclamationmark.shield" }
		if committedURL?.scheme == "https", hasOnlySecureContent {
			return "lock.shield"
		}
		return committedURL?.scheme == "http" ? "exclamationmark.triangle" : "info.circle"
	}

	var canHibernate: Bool {
		!isPlayingMedia && !isCapturing && !hasUnsavedChanges && !isLoading
			&& (createdWebView == nil || (createdWebView?.cameraCaptureState == WKMediaCaptureState.none
					&& createdWebView?.microphoneCaptureState == WKMediaCaptureState.none))
	}

	private static var cachedSafariUserAgentSuffix: String?

	private static func userAgentOverride(for url: URL?) -> String? {
		guard let url,
		      url.host == "chromewebstore.google.com"
		      || (url.host == "chrome.google.com" && url.path.hasPrefix("/webstore")) else { return nil }
		return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36"
	}

	/// Resolve once per launch, not once per tab (was NSWorkspace + Bundle plist per makeWebView).
	private static func safariUserAgentSuffix() -> String? {
		if let cachedSafariUserAgentSuffix {
			return cachedSafariUserAgentSuffix
		}
		#if os(macOS)
			let suffix: String? = if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
			                         let safariVersion = Bundle(url: safariURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
			{
				"Version/\(safariVersion) Safari/605.1.15"
			} else {
				nil
			}
		#else
			let suffix: String? = nil
		#endif
		cachedSafariUserAgentSuffix = suffix
		return suffix
	}

	/// Spawn the WebContent/Network processes + warm the UA lookup off the
	/// tab-creation critical path. Safe to call repeatedly.
	/// (Since macOS 12 all configurations share one process pool, so merely
	/// creating a throwaway WKWebView is enough to warm it.)
	static func prewarmSharedProcess() {
		_ = safariUserAgentSuffix()
		Task { @MainActor in
			// Thrown away; existence warms the shared WebKit processes.
			_ = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
		}
	}

	private static let scrollPositionMessageName = "scrollPositionChanged"
	private static let topEdgeMessageName = "topEdgeChanged"
	private static let zapFinishedMessageName = "zapFinished"
	private static let zapScript = """
	(() => {
		if (window.__astraZap) return;
		let target;
		const style = document.createElement('style');
		style.textContent = '[data-astra-zap] { outline: 3px solid #f35 !important; cursor: crosshair !important; }';
		document.documentElement.append(style);
		const move = event => {
			const next = event.target;
			if (target === next) return;
			target?.removeAttribute('data-astra-zap');
			target = next;
			target?.setAttribute('data-astra-zap', '');
		};
		const finish = () => {
			target?.removeAttribute('data-astra-zap');
			style.remove();
			document.removeEventListener('pointermove', move, true);
			document.removeEventListener('click', click, true);
			document.removeEventListener('keydown', key, true);
			delete window.__astraZap;
			window.webkit.messageHandlers.zapFinished.postMessage(true);
		};
		const click = event => {
			event.preventDefault();
			event.stopImmediatePropagation();
			if (target && target !== document.body && target !== document.documentElement) target.remove();
			finish();
		};
		const key = event => {
			if (event.key === 'Escape') { event.preventDefault(); finish(); }
		};
		window.__astraZap = finish;
		document.addEventListener('pointermove', move, true);
		document.addEventListener('click', click, true);
		document.addEventListener('keydown', key, true);
	})();
	"""
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
	private(set) var isZapping = false

	func toggleZap() {
		guard let webView = createdWebView, url != nil else { return }
		if isZapping {
			webView.evaluateJavaScript("window.__astraZap?.()", in: nil, in: .defaultClient, completionHandler: nil)
			isZapping = false
		} else {
			webView.evaluateJavaScript(Self.zapScript, in: nil, in: .defaultClient, completionHandler: nil)
			isZapping = true
		}
	}

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
		createdWebView?.canGoBack ?? false
	}

	var canGoForward: Bool {
		createdWebView?.canGoForward ?? false
	}

	var url: URL?
	private(set) var isLoading = false
	private(set) var estimatedProgress = 0.0
	private(set) var navigationFailure: BrowserNavigationFailure?
	private(set) var scrollPosition: BrowserScrollPosition
	private(set) var hasTopEdgeContent = false
	private(set) var themeColor: Color?
	private(set) var themeColorIsLight: Bool?
	private var pendingDownloadSource: UnitPoint?
	private var pendingDownloadSiteURL: URL?
	@ObservationIgnored
	private var automaticDownloadPolicy = BrowserSitePermissions.AutomaticDownloadPolicy()
	private var isDownloadHandoff = false
	private var pageURLBeforeDownload: URL?
	#if os(macOS)
		private(set) var previewSnapshot: NSImage?
	#endif

	@ObservationIgnored
	var navigationDidChange: (@MainActor () -> Void)?
	@ObservationIgnored
	var extensionStateDidChange: (@MainActor () -> Void)?
	@ObservationIgnored
	var extensionWebViewDidChange: (@MainActor () -> Void)?
	@ObservationIgnored
	var scrollPositionDidChange: (@MainActor () -> Void)?
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
	private var connectivityObserver: NSObjectProtocol?
	@ObservationIgnored
	private var currentRequest: URLRequest?
	@ObservationIgnored
	private var failedRequest: URLRequest?
	@ObservationIgnored
	private var retriedAfterConnectivityReturn = false
	@ObservationIgnored
	private var contentProcessTerminations = BrowserContentProcessTerminationTracker()

	var navigationIdentifier: Int {
		navigationGeneration
	}

	var canRecordVisit: Bool {
		!awaitsNavigationCommit
	}

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
		/// Set by Browser.selectTab: only the selected tab snapshots itself on
		/// the background loop. Explicit refreshes (Ctrl-Tab) bypass this.
		@ObservationIgnored
		var previewSnapshotRefreshSuspended = false
	#endif

	init(
		initialURL: URL? = nil,
		session: BrowserWebSession? = nil,
		configuration: WKWebViewConfiguration? = nil,
		history: [URL] = [],
		historyIndex: Int = 0,
		scrollPosition: BrowserScrollPosition = .zero,
		restorationState: Data? = nil,
		fileAccessBookmark: Data? = nil
	) {
		let session = session ?? .shared
		let restoredHistory = BrowserHistory(entries: history, index: historyIndex, initialURL: initialURL)
		self.session = session
		self.fileAccessBookmark = fileAccessBookmark
		if !session.isPrivate, let initialURL, let restorationState {
			pendingInteractionState = BrowserRestorationStore.open(restorationState, for: initialURL)
		}
		suppliedConfiguration = configuration
		liveHistoryPrefix = Array(restoredHistory.entries.prefix(restoredHistory.index))
		historyManager = restoredHistory
		url = restoredHistory.currentURL
		self.scrollPosition = scrollPosition
		restoredScrollPosition = scrollPosition == .zero ? nil : scrollPosition
		super.init()
		_ = BrowserNavigationConnectivity.shared
		connectivityObserver = NotificationCenter.default.addObserver(
			forName: BrowserNavigationConnectivity.didChangeNotification,
			object: nil,
			queue: .main
		) { [weak self] notification in
			guard notification.object as? Bool == true else { return }
			Task { @MainActor [weak self] in
				self?.retryOfflineGETAfterConnectivityReturns()
			}
		}
		updateThemeColor(url == nil ? .black : .white)
		#if os(macOS)
			startPreviewSnapshotRefresh()
		#endif

		if let url {
			#if os(macOS)
				if url.isFileURL, let fileAccessBookmark {
					var stale = false
					if let resolved = try? URL(resolvingBookmarkData: fileAccessBookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
						securityScopedFile = resolved.startAccessingSecurityScopedResource() ? resolved : nil
						pendingLocalFile = resolved
						if resolved != url {
							pendingInteractionState = nil
							self.url = resolved
							historyManager = BrowserHistory(initialURL: resolved)
						}
						if stale {
							self.fileAccessBookmark = try? resolved.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
						}
					}
				}
			#endif
			load(URLRequest(url: self.url ?? url))
		}
	}

	private static let activityScript = """
	(() => {
		const report = value => window.webkit.messageHandlers.pageActivityChanged.postMessage(value);
		document.addEventListener('input', event => {
			if (event.isTrusted && (event.target.matches('input:not([type="search"]), textarea, select') || event.target.closest('[contenteditable]'))) report('dirty');
		}, true);
		document.addEventListener('submit', () => report('submitted'), true);
		document.addEventListener('playing', () => report('playing'), true);
	})();
	"""

	private func startMediaObservation() {
		mediaObservationTask = Task { @MainActor [weak self] in
			while !Task.isCancelled {
				guard self?.createdWebView != nil else { return }
				await self?.refreshActivity()
				guard !Task.isCancelled else { return }
				do {
					try await Task.sleep(for: .seconds(1))
				} catch {
					return
				}
			}
		}
	}

	func refreshActivity() async {
		guard let webView = createdWebView else { return }
		let documentID = navigationIdentifier
		let state = await webView.requestMediaPlaybackState()
		guard owns(webView), documentID == navigationIdentifier else { return }
		isPlayingMedia = state == .playing
		hasPausedMedia = state == .paused
		cameraCaptureState = webView.cameraCaptureState
		microphoneCaptureState = webView.microphoneCaptureState
		if state == .playing || state == .none {
			pausedFromBrowser = false
		}
		if state == .none {
			mediaTitle = nil
			mediaArtist = nil
		}
		if state != .none {
			let script = "({ title: navigator.mediaSession?.metadata?.title ?? '', artist: navigator.mediaSession?.metadata?.artist ?? '' })"
			let metadata: [String: String]? = await withCheckedContinuation { continuation in
				webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
					continuation.resume(returning: (try? result.get()) as? [String: String])
				}
			}
			guard owns(webView), documentID == navigationIdentifier else { return }
			mediaTitle = metadata?["title"].flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }
			mediaArtist = metadata?["artist"].flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }
		}
	}

	func findNext(backwards: Bool = false) {
		guard let webView = createdWebView, owns(webView) else { return }
		findGeneration += 1
		let generation = findGeneration
		let configuration = WKFindConfiguration()
		configuration.backwards = backwards
		configuration.wraps = true
		webView.find(findText, configuration: configuration) { [weak self] result in
			guard let self, generation == findGeneration else { return }
			findHasMatch = findText.isEmpty || result.matchFound
		}
	}

	func dismissFind() {
		showsFind = false
		findText = ""
		findNext()
		#if os(macOS)
			createdWebView?.window?.makeFirstResponder(createdWebView)
		#endif
	}

	#if os(macOS)
		func loadLocalFile(_ url: URL) {
			guard url.isFileURL else { return }
			securityScopedFile?.stopAccessingSecurityScopedResource()
			securityScopedFile = url.startAccessingSecurityScopedResource() ? url : nil
			fileAccessBookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
			awaitsNavigationCommit = true
			currentNavigation = webView.loadFileURL(url, allowingReadAccessTo: url)
		}
	#endif

	func pauseMedia() {
		guard let webView = createdWebView, owns(webView) else { return }
		let documentID = navigationIdentifier
		pausedFromBrowser = true
		webView.pauseAllMediaPlayback(completionHandler: { [weak self, weak webView] in
			guard let self, let webView, owns(webView), documentID == navigationIdentifier else { return }
			self.isPlayingMedia = false
			self.pausedFromBrowser = true
		})
	}

	func resumeMedia() {
		guard let webView = createdWebView, owns(webView) else { return }
		let documentID = navigationIdentifier
		let script = """
		(() => {
			for (const media of document.querySelectorAll('audio, video')) {
				if (media.paused && !media.ended) media.play().catch(() => {});
			}
			return true;
		})()
		"""
		webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self, weak webView] _ in
			guard let self, let webView, owns(webView), documentID == navigationIdentifier else { return }
			Task { @MainActor [weak self] in
				try? await Task.sleep(for: .milliseconds(250))
				guard let self, owns(webView), documentID == navigationIdentifier else { return }
				await refreshActivity()
			}
		}
	}

	func toggleMediaElementsMuted() {
		guard let webView = createdWebView, owns(webView) else { return }
		let documentID = navigationIdentifier
		let shouldMute = !areMediaElementsMuted
		let script = """
		(() => {
			const current = window.__astraMediaMute;
			if (!\(shouldMute)) {
				if (current) {
					current.observer.disconnect();
					for (const media of current.elements) media.muted = current.original.get(media);
					delete window.__astraMediaMute;
				}
				return true;
			}
			if (current) return true;
			const original = new WeakMap();
			const elements = new Set();
			const mute = media => {
				if (!original.has(media)) original.set(media, media.muted);
				elements.add(media);
				media.muted = true;
			};
			for (const media of document.querySelectorAll('audio, video')) mute(media);
			const observer = new MutationObserver(records => {
				for (const record of records) {
					for (const node of record.removedNodes) {
						if (!(node instanceof Element)) continue;
						if (node.matches('audio, video') && (!node.isConnected || node.ownerDocument !== document)) elements.delete(node);
						for (const media of node.querySelectorAll('audio, video')) {
							if (!media.isConnected || media.ownerDocument !== document) elements.delete(media);
						}
					}
					for (const node of record.addedNodes) {
						if (!(node instanceof Element)) continue;
						if (node.matches('audio, video')) mute(node);
						for (const media of node.querySelectorAll('audio, video')) mute(media);
					}
				}
			});
			observer.observe(document.documentElement, { childList: true, subtree: true });
			window.__astraMediaMute = { original, elements, observer };
			return true;
		})()
		"""
		webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self, weak webView] result in
			guard let self, let webView, owns(webView), documentID == navigationIdentifier,
			      (try? result.get()) as? Bool == true
			else { return }
			areMediaElementsMuted = shouldMute
		}
	}

	func stopCapture(capability: BrowserSitePermissions.Capability? = nil) {
		if capability == nil || capability == .camera {
			createdWebView?.setCameraCaptureState(.none, completionHandler: nil)
			cameraCaptureState = .none
		}
		if capability == nil || capability == .microphone {
			createdWebView?.setMicrophoneCaptureState(.none, completionHandler: nil)
			microphoneCaptureState = .none
		}
	}

	func ownsPrompt(in webView: WKWebView, documentID: Int) -> Bool {
		guard owns(webView), navigationIdentifier == documentID,
		      promptOwnership?(webView) == true else { return false }
		#if os(macOS)
			guard let window = webView.window, window.isVisible else { return false }
			return window.isKeyWindow || window.attachedSheet?.isKeyWindow == true
		#else
			guard let window = webView.window, !window.isHidden,
			      window.windowScene?.activationState == .foregroundActive else { return false }
			return true
		#endif
	}

	func stopForClose() {
		guard !isInvalidated else { return }
		isInvalidated = true
		promptOwnership = nil
		if let connectivityObserver {
			NotificationCenter.default.removeObserver(connectivityObserver)
			self.connectivityObserver = nil
		}
		currentRequest = nil
		failedRequest = nil
		pendingRequest = nil
		navigationFailure = nil
		contentProcessTerminations = BrowserContentProcessTerminationTracker()
		session.permissions.removeTemporaryDecisions(controllerID: id)
		navigationGeneration += 1
		findGeneration += 1
		observations.forEach { $0.invalidate() }
		observations.removeAll()
		securityScopedFile?.stopAccessingSecurityScopedResource()
		securityScopedFile = nil
		mediaObservationTask?.cancel()
		mediaObservationTask = nil
		faviconTask?.cancel()
		faviconTask = nil
		#if os(macOS)
			previewSnapshotRefreshTask?.cancel()
			previewSnapshotRefreshTask = nil
			previewSnapshot = nil
		#endif
		createdWebView?.navigationDelegate = nil
		createdWebView?.uiDelegate = nil
		createdWebView?.stopLoading()
		createdWebView?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
		stopCapture()
		(createdWebView as? PeekSourceWebView)?.onEscape = nil
		(createdWebView as? PeekSourceWebView)?.onLayout = nil
		(createdWebView as? PeekSourceWebView)?.onZoomIn = nil
		(createdWebView as? PeekSourceWebView)?.onZoomOut = nil
		(createdWebView as? PeekSourceWebView)?.onResetZoom = nil
		for name in [Self.scrollPositionMessageName, Self.topEdgeMessageName, Self.zapFinishedMessageName, "pageActivityChanged", "faviconChanged"] {
			createdWebView?.configuration.userContentController.removeScriptMessageHandler(forName: name, contentWorld: .defaultClient)
		}
		createdWebView?.configuration.userContentController.removeAllUserScripts()
		navigationDidChange = nil
		extensionStateDidChange = nil
		extensionWebViewDidChange = nil
		scrollPositionDidChange = nil
		titleDidChange = nil
		popupRequested = nil
		newTabRequested = nil
		closeRequested = nil
		newWindowRequested = nil
		escapeRequested = nil
	}

	private func owns(_ webView: WKWebView) -> Bool {
		!isInvalidated && createdWebView === webView
	}

	var encryptedInteractionState: Data? {
		guard !session.isPrivate, canRecordVisit, let committedURL,
		      let data = createdWebView?.interactionState as? Data else { return nil }
		return BrowserRestorationStore.seal(data, for: BrowserAddress.withoutCredentials(committedURL))
	}

	func restoreInteractionState(_ state: Any, historyPrefix: [URL]) {
		guard !isInvalidated else { return }
		liveHistoryPrefix = historyPrefix
		webView.interactionState = state
		updateHistory()
	}

	func prepareWebView() {
		_ = webView
	}

	private func makeWebView() -> WKWebView {
		let configuration = suppliedConfiguration ?? WKWebViewConfiguration()
		if suppliedConfiguration != nil {
			configuration.userContentController = WKUserContentController()
		}
		configuration.websiteDataStore = session.dataStore
		configuration.webExtensionController = session.isPrivate ? nil : BrowserExtensionManager.shared.controller
		if suppliedConfiguration == nil {
			configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
		}
		configuration.preferences.isElementFullscreenEnabled = true
		configuration.preferences.isFraudulentWebsiteWarningEnabled = true
		configuration.preferences.inactiveSchedulingPolicy = .suspend
		configuration.mediaTypesRequiringUserActionForPlayback = .all
		configuration.allowsAirPlayForMediaPlayback = true
		#if os(macOS)
			_ = AstraConfigureWebPushPreferences(configuration.preferences, !session.isPrivate && BrowserWebPushManager.shared.hasNativeSupport)
			if configuration.preferences.responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:")) {
				configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
			}
		#endif
		if let suffix = Self.safariUserAgentSuffix() {
			configuration.applicationNameForUserAgent = suffix
		}
		session.favicons.configureFaviconObservation(in: configuration.userContentController)
		let webView = PeekSourceWebView(frame: .zero, configuration: configuration)
		#if os(macOS)
			webView.isInspectable = true
			// WebKit's docked inspector resizes the web view outside SwiftUI's layout.
			let inspectorAttachmentView = NSView(frame: .zero)
			inspectorAttachmentView.isHidden = true
			if webView.responds(to: NSSelectorFromString("_setInspectorAttachmentView:")) {
				webView.perform(NSSelectorFromString("_setInspectorAttachmentView:"), with: inspectorAttachmentView)
			}
		#endif
		createdWebView = webView
		let scrollHandler = WeakScriptMessageHandler(delegate: self)
		webView.configuration.userContentController.add(
			scrollHandler,
			contentWorld: .defaultClient,
			name: Self.scrollPositionMessageName
		)
		webView.configuration.userContentController.add(
			scrollHandler,
			contentWorld: .defaultClient,
			name: Self.topEdgeMessageName
		)
		webView.configuration.userContentController.add(
			scrollHandler,
			contentWorld: .defaultClient,
			name: Self.zapFinishedMessageName
		)
		webView.configuration.userContentController.add(scrollHandler, contentWorld: .defaultClient, name: "pageActivityChanged")
		webView.configuration.userContentController.addUserScript(
			WKUserScript(source: Self.activityScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)
		)
		webView.configuration.userContentController.addUserScript(
			WKUserScript(
				source: Self.scrollPositionScript,
				injectionTime: .atDocumentEnd,
				forMainFrameOnly: true,
				in: .defaultClient
			)
		)
		webView.configuration.userContentController.addUserScript(
			WKUserScript(
				source: Self.topEdgeScript,
				injectionTime: .atDocumentEnd,
				forMainFrameOnly: true,
				in: .defaultClient
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
			webView.observe(\.hasOnlySecureContent, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated { self?.hasOnlySecureContent = webView.hasOnlySecureContent }
			},
			webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.isLoading = webView.isLoading
					self?.extensionStateDidChange?()
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
					guard !self.isDownloadHandoff else { return }
					guard let url = change.newValue ?? webView.url else { return }
					self.url = url
					if !webView.isLoading {
						if webView.consumeRecentClick() == true {
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
		startMediaObservation()
		isWebViewReady = true
		extensionWebViewDidChange?()
		// Start any deferred navigation immediately; WKWebView loads fine
		// with a zero frame so we don't wait for first layout.
		if let state = pendingInteractionState {
			pendingInteractionState = nil
			liveHistoryPrefix = []
			webView.interactionState = state
			if webView.backForwardList.currentItem != nil {
				pendingRequest = nil
				pendingLocalFile = nil
				updateHistory()
			} else {
				loadPendingRequest()
			}
		} else {
			loadPendingRequest()
		}
		return webView
	}

	deinit {
		if let connectivityObserver {
			NotificationCenter.default.removeObserver(connectivityObserver)
		}
		mediaObservationTask?.cancel()
		faviconTask?.cancel()
		observations.forEach { $0.invalidate() }
		#if os(macOS)
			previewSnapshotRefreshTask?.cancel()
		#endif
	}

	func load(_ url: URL) {
		guard !isInvalidated else { return }
		if BrowserAddress.externalApplicationScheme(for: url) != nil,
		   handleExternalLink(url, requestingOrigin: nil, requestingSite: "Astra address bar", in: webView)
		{
			return
		}
		navigate(URLRequest(url: url))
	}

	func navigate(_ request: URLRequest) {
		guard !isInvalidated else { return }
		guard let url = request.url else { return }
		createdWebView?.stopLoading()
		(createdWebView as? PeekSourceWebView)?.consumeRecentClick()
		historyManager.beginVisit()
		self.url = url
		scrollPosition = .zero
		restoredScrollPosition = nil
		load(request)
	}

	func goBack() {
		guard let webView = createdWebView, webView.canGoBack else { return }
		currentRequest = nil
		awaitsNavigationCommit = true
		currentNavigation = webView.goBack()
	}

	func goForward() {
		guard let webView = createdWebView, webView.canGoForward else { return }
		currentRequest = nil
		awaitsNavigationCommit = true
		currentNavigation = webView.goForward()
	}

	func go(toHistoryIndex index: Int) {
		guard history.indices.contains(index), index != historyIndex else { return }
		if let webView = createdWebView,
		   let item = webView.backForwardList.item(at: index - historyIndex)
		{
			currentRequest = nil
			awaitsNavigationCommit = true
			currentNavigation = webView.go(to: item)
		} else {
			// URL records from an earlier launch can be revisited; live navigation
			// uses WebKit's entries so POST requests and page state stay intact.
			load(history[index])
		}
	}

	func reload() {
		if let navigationFailure {
			load(failedRequest ?? URLRequest(url: navigationFailure.url))
			return
		}
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
		session.toastManager.show(symbol: "1.magnifyingglass", message: "Zoom 100%")
	}

	func reloadFromOrigin() {
		if navigationFailure != nil {
			reload()
			return
		}
		if let createdWebView {
			createdWebView.reloadFromOrigin()
		} else if let url {
			load(URLRequest(url: url))
		}
	}

	func zoomIn() {
		pageZoom = min(pageZoom + 0.1, 5)
		session.toastManager.show(
			symbol: "plus.magnifyingglass",
			message: "Zoom \(Int(pageZoom * 100))%"
		)
	}

	func zoomOut() {
		pageZoom = max(pageZoom - 0.1, 0.25)
		session.toastManager.show(
			symbol: "minus.magnifyingglass",
			message: "Zoom \(Int(pageZoom * 100))%"
		)
	}

	func loadFaviconIfMissing() {
		guard let url, let webView = createdWebView else { return }
		loadFavicon(for: url, in: webView)
	}

	private func loadFavicon(for url: URL, in webView: WKWebView) {
		faviconTask?.cancel()
		faviconTask = Task { @MainActor [weak self, weak webView] in
			guard let self, let webView, owns(webView) else { return }
			await session.favicons.loadFavicon(for: url, from: webView, onlyIfMissing: true)
			guard owns(webView) else { return }
		}
	}

	#if os(macOS)
		func discardPreviewSnapshot() {
			previewSnapshot = nil
		}

		func refreshPreviewSnapshot() async {
			guard let webView = createdWebView, owns(webView) else { return }
			let generation = navigationGeneration
			guard let image = await takeSnapshot() else { return }
			guard owns(webView), generation == navigationGeneration else { return }
			previewSnapshot = image
		}
	#endif

	private func updateHistory() {
		guard let currentURL = createdWebView?.url else { return }
		url = currentURL
		if let list = createdWebView?.backForwardList, let current = list.currentItem {
			let entries = liveHistoryPrefix + list.backList.map(\.url) + [current.url] + list.forwardList.map(\.url)
			historyManager = BrowserHistory(entries: entries, index: liveHistoryPrefix.count + list.backList.count)
		} else {
			historyManager.record(currentURL)
		}
		navigationDidChange?()
	}

	private func load(_ request: URLRequest, resetConnectivityRetry: Bool = true) {
		guard !isInvalidated else { return }
		awaitsNavigationCommit = true
		currentRequest = request
		failedRequest = nil
		if resetConnectivityRetry {
			retriedAfterConnectivityReturn = false
		}
		guard let webView = createdWebView else {
			pendingRequest = request
			return
		}
		pendingRequest = nil
		webView.customUserAgent = Self.userAgentOverride(for: request.url)
		currentNavigation = webView.load(request)
	}

	private func loadPendingRequest() {
		#if os(macOS)
			if let file = pendingLocalFile, let webView = createdWebView {
				pendingLocalFile = nil
				pendingRequest = nil
				currentNavigation = webView.loadFileURL(file, allowingReadAccessTo: file)
				return
			}
		#endif
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
		guard !isInvalidated, url != nil, let webView = createdWebView, !webView.bounds.isEmpty else { return nil }
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
		      generation == navigationGeneration,
		      !isInvalidated
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
					guard !previewSnapshotRefreshSuspended else { continue }
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
		preferences: WKWebpagePreferences,
		decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
	) {
		guard owns(webView) else {
			decisionHandler(.cancel, preferences)
			return
		}
		#if os(macOS)
			preferences.globalPrivacyControlEnabled = Defaults[.globalPrivacyControl]
			let host = navigationAction.request.url?.host?.lowercased() ?? ""
			let isLocal = host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1"
			preferences.preferredHTTPSNavigationPolicy = Defaults[.tryHTTPSFirst] && !isLocal
				&& navigationAction.request.httpMethod == "GET" ? .automaticFallbackToHTTP : .keepAsRequested
		#endif
		if navigationAction.targetFrame?.isMainFrame == true,
		   let destination = navigationAction.request.url,
		   navigationIntercept?(destination) == true
		{
			decisionHandler(.cancel, preferences)
			return
		}
		if let url = navigationAction.request.url, handleExternalLink(url, requestingOrigin: navigationAction.sourceFrame.securityOrigin, in: webView) {
			decisionHandler(.cancel, preferences)
			return
		}
		if navigationAction.shouldPerformDownload {
			if automaticDownloadPolicy.reserveAttempt() {
				let documentID = navigationIdentifier
				Task { @MainActor [weak self, weak webView] in
					guard let self, let webView else {
						decisionHandler(.cancel, preferences)
						return
					}
					let permission = await requestMultipleDownloadPermission(in: webView)
					guard permission == .grant, ownsPrompt(in: webView, documentID: documentID) else {
						decisionHandler(.cancel, preferences)
						return
					}
					prepareDownloadHandoff(in: webView)
					decisionHandler(.download, preferences)
				}
				return
			}
			prepareDownloadHandoff(in: webView)
			decisionHandler(.download, preferences)
			return
		}
		isDownloadHandoff = false
		pageURLBeforeDownload = nil
		#if os(macOS)
			let tabInBackground = Self.linkTabInBackground(
				navigationType: navigationAction.navigationType,
				modifiers: navigationAction.modifierFlags,
				buttonNumber: navigationAction.buttonNumber
			)
			if navigationAction.targetFrame != nil,
			   navigationAction.sourceFrame.webView === webView,
			   let tabInBackground, let newTabRequested
			{
				decisionHandler(.cancel, preferences)
				(webView as? PeekSourceWebView)?.consumeRecentClick()
				newTabRequested(navigationAction.request, tabInBackground)
				return
			}
			let shiftPressed = navigationAction.modifierFlags.contains(.shift) && tabInBackground == nil
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
					case .linkActivated, .formSubmitted, .formResubmitted, .backForward, .reload:
						retriedAfterConnectivityReturn = false
					default:
						break
				}
				currentRequest = navigationAction.request
				webView.customUserAgent = Self.userAgentOverride(for: navigationAction.request.url)
				switch navigationAction.navigationType {
					case .linkActivated:
						pendingDownloadSource = (webView as? PeekSourceWebView)?.sourceIfRecent
						pendingDownloadSiteURL = webView.url
						historyManager.beginVisit()
						(webView as? PeekSourceWebView)?.consumeRecentClick()
					case .formSubmitted, .formResubmitted:
						pendingDownloadSource = (webView as? PeekSourceWebView)?.sourceIfRecent
						pendingDownloadSiteURL = committedURL ?? webView.url
						historyManager.beginVisit()
						(webView as? PeekSourceWebView)?.consumeRecentClick()
					default:
						break
				}
			}
			// WebKit's .allow path attempts eligible universal links and falls back to the website.
			decisionHandler(.allow, preferences)
			return
		}
		let source = newWindowSource(in: webView)
		decisionHandler(.cancel, preferences)
		newWindowRequested(url, source)
	}

	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationResponse: WKNavigationResponse,
		decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
	) {
		guard owns(webView) else {
			decisionHandler(.cancel)
			return
		}
		let disposition = (navigationResponse.response as? HTTPURLResponse)?
			.value(forHTTPHeaderField: "Content-Disposition")
		if !navigationResponse.canShowMIMEType || disposition?.lowercased().hasPrefix("attachment") == true {
			if automaticDownloadPolicy.reserveAttempt() {
				let documentID = navigationIdentifier
				Task { @MainActor [weak self, weak webView] in
					guard let self, let webView else {
						decisionHandler(.cancel)
						return
					}
					let permission = await requestMultipleDownloadPermission(in: webView)
					guard permission == .grant, ownsPrompt(in: webView, documentID: documentID) else {
						decisionHandler(.cancel)
						return
					}
					prepareDownloadHandoff(in: webView)
					decisionHandler(.download)
				}
				return
			}
			prepareDownloadHandoff(in: webView)
			decisionHandler(.download)
		} else {
			pendingDownloadSource = nil
			pendingDownloadSiteURL = nil
			decisionHandler(.allow)
		}
	}

	func webView(_ webView: WKWebView, navigationAction _: WKNavigationAction, didBecome download: WKDownload) {
		guard owns(webView) else { return }
		session.downloads.start(
			download,
			sourceURL: pageURLBeforeDownload ?? webView.url,
			source: newWindowSource(in: webView)
		)
		restorePageAfterDownloadHandoff()
	}

	func webView(_ webView: WKWebView, navigationResponse _: WKNavigationResponse, didBecome download: WKDownload) {
		guard owns(webView) else { return }
		let source = pendingDownloadSource ?? newWindowSource(in: webView)
		session.downloads.start(
			download,
			sourceURL: pendingDownloadSiteURL ?? pageURLBeforeDownload ?? webView.url,
			source: source
		)
		pendingDownloadSource = nil
		pendingDownloadSiteURL = nil
		restorePageAfterDownloadHandoff()
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		guard owns(webView) else { return }
		handleNavigationFailure(navigation, error: error)
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		guard owns(webView) else { return }
		handleNavigationFailure(navigation, error: error)
	}

	private func handleNavigationFailure(_ navigation: WKNavigation!, error: Error) {
		guard navigation === currentNavigation else { return }
		let error = error as NSError
		if isDownloadHandoff,
		   error.domain == "WebKitErrorDomain" && error.code == 102
		   || error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
		{
			restorePageAfterDownloadHandoff()
			return
		}
		guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
		isDownloadHandoff = false
		pageURLBeforeDownload = nil
		awaitsNavigationCommit = false
		historyManager.cancelVisit()
		failedRequest = currentRequest
		if let failedURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url {
			navigationFailure = BrowserNavigationFailure(error: error, url: failedURL)
		}
	}

	private func retryOfflineGETAfterConnectivityReturns() {
		guard !isInvalidated,
		      createdWebView != nil,
		      !retriedAfterConnectivityReturn,
		      (navigationFailure?.kind == .offline || navigationFailure?.kind == .connectionLost),
		      let request = failedRequest,
		      BrowserNavigationFailure.canRetryAutomatically(request)
		else { return }
		retriedAfterConnectivityReturn = true
		load(request, resetConnectivityRetry: false)
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		guard owns(webView) else { return }
		guard let url = webView.url ?? url else { return }
		let kind: BrowserNavigationFailure.Kind = contentProcessTerminations.record(url)
			? .repeatedWebContentTermination
			: .webContentTerminated
		navigationFailure = BrowserNavigationFailure(kind: kind, url: url)
	}

	func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		guard owns(webView) else { return }
		isZapping = false
		isPlayingMedia = false
		mediaTitle = nil
		mediaArtist = nil
		pausedFromBrowser = false
		hasPausedMedia = false
		areMediaElementsMuted = false
		currentNavigation = navigation
		failedRequest = nil
		navigationFailure = nil
		awaitsNavigationCommit = true
		session.permissions.removeTemporaryDecisions(controllerID: id)
		navigationGeneration += 1
		hasDeclaredThemeColor = false
		hasTopEdgeContent = false
		webView.underPageBackgroundColor = nil
	}

	private func prepareDownloadHandoff(in webView: WKWebView) {
		isDownloadHandoff = true
		pageURLBeforeDownload = historyManager.currentURL ?? webView.url
	}

	private func requestMultipleDownloadPermission(in webView: WKWebView) async -> WKPermissionDecision {
		guard let topSite = committedURL ?? webView.url else { return .deny }
		return await requestPermission([.automaticDownloads], originURL: topSite, topURL: topSite, in: webView)
	}

	private func restorePageAfterDownloadHandoff() {
		guard isDownloadHandoff else { return }
		historyManager.cancelVisit()
		awaitsNavigationCommit = false
		navigationFailure = nil
		url = pageURLBeforeDownload
		navigationDidChange?()
	}

	func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
		guard owns(webView), navigation === currentNavigation else { return }
		committedURL = webView.url
		automaticDownloadPolicy.didCommitDocument()
		contentProcessTerminations.navigationCommitted(at: webView.url)
		hasUnsavedChanges = false
		isDownloadHandoff = false
		pageURLBeforeDownload = nil
		navigationFailure = nil
		awaitsNavigationCommit = false
		updateHistory()
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard owns(webView), navigation === currentNavigation else { return }
		updateHistory()
		if !hasDeclaredThemeColor,
		   let pageBackgroundColor = webView.underPageBackgroundColor
		{
			updateThemeColor(pageBackgroundColor)
		}
		restoreScrollPositionIfNeeded(in: webView)
		let generation = navigationGeneration
		if let url {
			loadFavicon(for: url, in: webView)
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
		let generation = navigationGeneration
		let script = "window.scrollTo(\(restoredScrollPosition.x), \(restoredScrollPosition.y));"
		Task { @MainActor [weak self, weak webView] in
			try? await Task.sleep(for: .milliseconds(150))
			guard let self, let webView, owns(webView), generation == navigationGeneration else { return }
			_ = try? await webView.evaluateJavaScript(script)
		}
	}
}

extension BrowserController: WKScriptMessageHandler {
	func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
		guard !isInvalidated else { return }
		if message.name == "pageActivityChanged" {
			guard let activity = message.body as? String else { return }
			switch activity {
				case "dirty":
					hasUnsavedChanges = true
					scrollPositionDidChange?()
				case "submitted":
					scrollPositionDidChange?()
				case "playing": isPlayingMedia = true
				default: break
			}
			return
		}
		guard message.frameInfo.isMainFrame else { return }
		if message.name == Self.zapFinishedMessageName {
			isZapping = false
			return
		}

		if message.name == Self.topEdgeMessageName {
			if let occupied = message.body as? Bool {
				hasTopEdgeContent = occupied
			}
			return
		}

		guard message.name == Self.scrollPositionMessageName,
		      let position = message.body as? [String: Double],
		      let x = position["x"],
		      let y = position["y"],
		      x.isFinite, y.isFinite
		else { return }

		let nextPosition = BrowserScrollPosition(x: x, y: y)
		guard scrollPosition != nextPosition else { return }
		scrollPosition = nextPosition
		if let scrollPositionDidChange {
			scrollPositionDidChange()
		} else {
			navigationDidChange?()
		}
	}
}

extension BrowserController: WKUIDelegate {
	func webView(
		_ webView: WKWebView,
		createWebViewWith configuration: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures _: WKWindowFeatures
	) -> WKWebView? {
		guard owns(webView) else { return nil }
		if navigationAction.targetFrame == nil, let destination = navigationAction.request.url,
		   navigationIntercept?(destination) == true
		{
			return nil
		}
		if let url = navigationAction.request.url, handleExternalLink(url, requestingOrigin: navigationAction.sourceFrame.securityOrigin, in: webView) {
			return nil
		}
		if navigationAction.shouldPerformDownload {
			let requiresPermission = automaticDownloadPolicy.reserveAttempt()
			if requiresPermission {
				guard let topSite = committedURL ?? webView.url,
				      let topOrigin = BrowserSitePermissions.origin(for: topSite) else { return nil }
				let decision = session.permissions.effectiveDecision(
					origin: topOrigin,
					topOrigin: topOrigin,
					capability: .automaticDownloads,
					controllerID: id,
					documentID: navigationIdentifier
				)
				if decision == nil {
					let documentID = navigationIdentifier
					Task { @MainActor [weak self, weak webView] in
						guard let self, let webView,
						      await requestMultipleDownloadPermission(in: webView) == .grant,
						      ownsPrompt(in: webView, documentID: documentID) else { return }
						session.toastManager.show(symbol: "checkmark.circle", message: "Automatic downloads allowed. Retry the page action.")
					}
					return nil
				}
				guard decision == .allowAlways || decision == .allowOnce else { return nil }
			}
			let source = newWindowSource(in: webView)
			let sourceURL = webView.url
			webView.startDownload(using: navigationAction.request) { [weak self, weak webView] download in
				guard let self, let webView, owns(webView) else { return }
				session.downloads.start(download, sourceURL: sourceURL, source: source)
			}
			return nil
		}
		guard navigationAction.targetFrame == nil else { return nil }
		#if os(macOS)
			let inBackground = Self.linkTabInBackground(
				navigationType: navigationAction.navigationType,
				modifiers: navigationAction.modifierFlags,
				buttonNumber: navigationAction.buttonNumber
			)
		#else
			let inBackground: Bool? = nil
		#endif
		guard navigationAction.request.url != nil,
		      let originID = Self.securityOrigin(navigationAction.sourceFrame.securityOrigin),
		      let topOrigin = webView.url.flatMap(BrowserSitePermissions.origin(for:)) else { return nil }
		let documentID = navigationIdentifier
		let source = newWindowSource(in: webView)
		let permission = session.permissions.effectiveDecision(
			origin: originID,
			topOrigin: topOrigin,
			capability: .popups,
			controllerID: id,
			documentID: documentID
		)
		if permission == .deny || !ownsPrompt(in: webView, documentID: documentID) {
			return nil
		}
		if navigationAction.navigationType == .linkActivated,
		   permission == nil || permission == .allowOnce || permission == .allowAlways
		{
			return popupRequested?(configuration, source, inBackground)
		}
		if permission == .allowAlways || permission == .allowOnce {
			return popupRequested?(configuration, source, inBackground)
		}
		Task { @MainActor [weak self, weak webView] in
			guard let self, let webView,
			      await requestPermission([.popups], origin: navigationAction.sourceFrame.securityOrigin, in: webView) == .grant,
			      ownsPrompt(in: webView, documentID: documentID),
			      (committedURL ?? webView.url).flatMap(BrowserSitePermissions.origin(for:)) == topOrigin else { return }
			session.toastManager.show(symbol: "checkmark.circle", message: "Pop-ups allowed. Retry the page action.")
		}
		return nil
	}

	private static func securityOrigin(_ origin: WKSecurityOrigin) -> String? {
		var parts = URLComponents()
		parts.scheme = origin.protocol
		parts.host = origin.host
		parts.port = origin.port > 0 ? origin.port : nil
		return parts.url.flatMap(BrowserSitePermissions.origin(for:))
	}

	#if os(macOS)
		static func linkTabInBackground(
			navigationType: WKNavigationType,
			modifiers: NSEvent.ModifierFlags,
			buttonNumber: Int
		) -> Bool? {
			// WKNavigationAction uses WebKit's button mask: middle is 1 << 2.
			guard navigationType == .linkActivated,
			      modifiers.contains(.command) || buttonNumber == 1 << 2 else { return nil }
			return !modifiers.contains(.shift)
		}
	#endif

	private func newWindowSource(in webView: WKWebView) -> UnitPoint {
		(webView as? PeekSourceWebView)?.consumeSource() ?? .center
	}

	private func handleExternalLink(
		_ url: URL,
		requestingOrigin: WKSecurityOrigin?,
		requestingSite: String? = nil,
		in webView: WKWebView
	) -> Bool {
		guard let scheme = BrowserAddress.externalApplicationScheme(for: url) else { return false }
		guard ownsPrompt(in: webView, documentID: navigationIdentifier) else { return true }
		let addresses = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
		if scheme == "mailto", Defaults[.copyMailtoAddresses], !addresses.isEmpty {
			#if os(macOS)
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(addresses, forType: .string)
			#elseif os(iOS)
				UIPasteboard.general.string = addresses
			#endif
			session.toastManager.show(symbol: "doc.on.doc", message: "Email address copied")
			return true
		}
		#if os(macOS)
			guard !isOpeningExternalApplication else { return true }
			let now = ProcessInfo.processInfo.systemUptime
			if let lastExternalApplicationRequestTime, now - lastExternalApplicationRequestTime < 2 {
				return true
			}
			lastExternalApplicationRequestTime = now
			guard let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
				session.toastManager.show(symbol: "exclamationmark.triangle", message: "No application is installed to open \(scheme) links")
				return true
			}
			guard applicationURL.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else {
				session.toastManager.show(symbol: "exclamationmark.triangle", message: "This link points back to Astra")
				return true
			}
			let applicationName = FileManager.default.displayName(atPath: applicationURL.path)
			var origin = URLComponents()
			origin.scheme = requestingOrigin?.protocol
			origin.host = requestingOrigin?.host
			origin.port = (requestingOrigin?.port ?? 0) > 0 ? requestingOrigin?.port : nil
			let requestingSiteLabel = requestingSite
				?? origin.url.flatMap(BrowserSitePermissions.origin(for:))
				?? "This page"
			let documentID = navigationIdentifier
			isOpeningExternalApplication = true
			Task { @MainActor in
				defer { isOpeningExternalApplication = false }
				let alert = BrowserWebsiteUI.alert(
					title: "Open \(applicationName)?",
					message: "\(requestingSiteLabel) wants to open a \(scheme) link in \(applicationName).",
					confirm: "Open Application"
				)
				let response = await BrowserWebsiteUI.present(alert, in: webView.window) { [self, webView] in
					ownsPrompt(in: webView, documentID: documentID)
				}
				guard ownsPrompt(in: webView, documentID: documentID),
				      response == .alertFirstButtonReturn else { return }
				lastExternalApplicationRequestTime = ProcessInfo.processInfo.systemUptime
				let configuration = NSWorkspace.OpenConfiguration()
				configuration.addsToRecentItems = false
				do {
					_ = try await NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration)
				} catch {
					session.toastManager.show(symbol: "exclamationmark.triangle", message: "\(applicationName) could not open this link")
				}
			}
		#elseif os(iOS)
			guard !isOpeningExternalApplication else { return true }
			let now = ProcessInfo.processInfo.systemUptime
			if let lastExternalApplicationRequestTime, now - lastExternalApplicationRequestTime < 2 {
				return true
			}
			lastExternalApplicationRequestTime = now
			isOpeningExternalApplication = true
			UIApplication.shared.open(url) { [weak self] succeeded in
				Task { @MainActor in
					guard let self else { return }
					self.isOpeningExternalApplication = false
					if !succeeded {
						session.toastManager.show(symbol: "exclamationmark.triangle", message: "No application could open this link")
					}
				}
			}
		#endif
		return true
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

	var sourceIfRecent: UnitPoint? {
		guard clickTime > 0,
		      ProcessInfo.processInfo.systemUptime - clickTime < 2
		else { return nil }
		return clickSource
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
