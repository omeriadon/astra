#if ASTRA_WEBSITE_APP_RUNTIME
	import AstraWebPushBridge
#endif
import AVFoundation
import CoreGraphics
import CoreLocation
import Defaults
import Observation
import SwiftUI
import WebKit
#if os(macOS)
	import AppKit
	import Darwin
#elseif os(iOS)
	import UIKit
#endif

#if os(macOS)
	@MainActor
	struct BrowserAddressPromptOwner {
		let browser: Browser
		let window: NSWindow
	}

	struct BrowserTabProcessMemorySnapshot: Equatable, Sendable {
		let webContentBytes: UInt64?
		let graphicsBytes: UInt64?
		let networkBytes: UInt64?
		let modelBytes: UInt64?

		var relatedProcessBytes: UInt64? {
			let values = [webContentBytes, graphicsBytes, networkBytes, modelBytes].compactMap(\.self)
			return values.isEmpty ? nil : values.reduce(0, +)
		}

		var hasSharedProcessMemory: Bool {
			graphicsBytes != nil || networkBytes != nil || modelBytes != nil
		}
	}
#endif

@MainActor
@Observable
final class BrowserController: NSObject, Identifiable {
	#if os(macOS)
		static var addressPromptOwner: ((BrowserController, WKWebView, Int) -> BrowserAddressPromptOwner?)?
	#endif
	let id = UUID()
	let session: BrowserWebSession
	private let suppliedConfiguration: WKWebViewConfiguration?
	private var pendingInteractionState: Data?
	@ObservationIgnored
	private var pendingEncryptedInteractionState: (data: Data, url: URL)?
	@ObservationIgnored
	private var securityScopedFile: URL?
	@ObservationIgnored
	private var uploadSecurityScopedFiles: [URL] = []
	private(set) var fileAccessBookmark: Data?
	private var pendingLocalFile: URL?
	private(set) var liveHistoryPrefix: [URL]
	@ObservationIgnored
	private var mediaObservationTask: Task<Void, Never>?
	@ObservationIgnored
	private var isRefreshingActivity = false
	@ObservationIgnored
	private var faviconTask: Task<Void, Never>?
	#if os(macOS)
		@ObservationIgnored
		private var webInspectorObserver: NSObjectProtocol?
		@ObservationIgnored
		private var observedWebInspectorEnabled = false
	#endif
	@ObservationIgnored
	var displayWindowID: UUID?
	/// The Browser/window whose callbacks are currently installed on this
	/// controller. Separate from displayWindowID because display ownership is
	/// updated before callback configuration during a tab switch.
	@ObservationIgnored
	var browserConfigurationWindowID: UUID?
	@ObservationIgnored
	private var isInvalidated = false
	@ObservationIgnored
	private var navigationLogStartedAt: TimeInterval?
	private(set) var isPlayingMedia = false
	private var hasActiveVideoPlayback = false
	private(set) var hasPausedMedia = false
	private(set) var mediaTitle: String?
	private(set) var mediaArtist: String?
	private(set) var pausedFromBrowser = false
	private(set) var areMediaElementsMuted = false
	private(set) var canEnterPictureInPicture = false
	private(set) var isPictureInPictureActive = false
	private(set) var isEnteringPictureInPicture = false
	private(set) var pictureInPictureControlUnavailable = false
	private(set) var committedURL: URL?
	private(set) var committedHasOnlySecureContent: Bool?
	private(set) var committedCertificateSummary: BrowserServerCertificateSummary?
	private(set) var committedSecurityNavigationID: Int?
	private(set) var hoveredLinkURL: URL?
	private(set) var hoveredLinkUsesTrailingCorner = false
	private(set) var hoveredLinkRect = CGRect.zero
	private(set) var hoveredLinkID = ""
	private(set) var hoveredLinkShiftPressed = false
	private(set) var aiPreviewDismissal = 0
	@ObservationIgnored var aiLinkPreviewCache: [URL: (summary: BrowserLinkSummaryFeature.Summary, page: BrowserAIPageText)] = [:]
	@ObservationIgnored private var aiLinkPreviewCacheOrder: [URL] = []

	/// Page text can be large. Keep a small FIFO cache rather than allowing
	/// previews of many links on one site to retain unbounded page snapshots.
	func cacheAILinkPreview(summary: BrowserLinkSummaryFeature.Summary, page: BrowserAIPageText, for url: URL) {
		if aiLinkPreviewCache[url] == nil {
			if aiLinkPreviewCacheOrder.count >= 12 {
				let oldest = aiLinkPreviewCacheOrder.removeFirst()
				aiLinkPreviewCache.removeValue(forKey: oldest)
			}
			aiLinkPreviewCacheOrder.append(url)
		}
		aiLinkPreviewCache[url] = (summary, page)
	}

	private func clearAILinkPreviewCache() {
		aiLinkPreviewCache.removeAll()
		aiLinkPreviewCacheOrder.removeAll()
	}
	private(set) var isReaderAvailable = false
	private(set) var readerHTML: String?
	private(set) var isPreparingReader = false
	private var readerGeneration = 0

	var showsFind = false
	var findText = "" {
		didSet {
			guard oldValue != findText else { return }
			findGeneration.advance()
			findHasMatch = nil
			findMatchCount = 0
			findMatchIndex = 0
		}
	}

	private(set) var findHasMatch: Bool?
	private(set) var findMatchCount = 0
	private(set) var findMatchIndex = 0
	var findFocusRequest = 0
	@ObservationIgnored
	private var findGeneration = BrowserFindGeneration()
	private(set) var hasUnsavedChanges = false
	private(set) var cameraCaptureState: WKMediaCaptureState = .none
	private(set) var microphoneCaptureState: WKMediaCaptureState = .none
	private(set) var mediaCaptureStateDocumentID: Int?
	var popupRequested: ((WKWebViewConfiguration, UnitPoint, Bool?) -> WKWebView?)?
	var newTabRequested: ((URLRequest, Bool) -> Void)?
	var closeRequested: (() -> Void)?
	@ObservationIgnored
	var promptOwnership: ((WKWebView) -> Bool)?
	@ObservationIgnored
	private var isOpeningExternalApplication = false
	@ObservationIgnored
	private var pendingLifecycleOperations = 0
	@ObservationIgnored
	// ponytail: controller-wide two-second throttle; per-origin limits if abuse becomes measurable.
	private var lastExternalApplicationRequestTime: TimeInterval?
	@ObservationIgnored
	var navigationIntercept: ((URL) -> Bool)?
	var pictureInPictureRestoreRequested: (() -> Void)?

	var isCapturing: Bool {
		cameraCaptureState != .none || microphoneCaptureState != .none
	}

	var connectionDescription: String {
		securityPresentation.connectionState.title
	}

	var connectionSymbol: String {
		securityPresentation.connectionState.symbol
	}

	var securityPresentation: BrowserSecurityPresentation {
		BrowserSecurityPresentation(
			committedURL: committedURL,
			hasOnlySecureContent: committedHasOnlySecureContent,
			isNavigating: awaitsNavigationCommit,
			isFailure: navigationFailure != nil,
			failedURL: navigationFailure?.url,
			certificate: committedCertificateSummary
		)
	}

	var canHibernate: Bool {
		!BrowserPictureInPicturePolicy.preventsDestructiveTeardown(
			isActive: isPictureInPictureActive,
			isEntering: isEnteringPictureInPicture,
			isPlayingMedia: isPlayingMedia || hasActiveVideoPlayback,
			hasPausedMedia: hasPausedMedia
		)
			&& !isCapturing && !hasUnsavedChanges && !isLoading
			&& (createdWebView == nil || (createdWebView?.cameraCaptureState == WKMediaCaptureState.none
						&& createdWebView?.microphoneCaptureState == WKMediaCaptureState.none))
	}

	/// Automatic hibernation must not detach a page that still has an operation
	/// whose completion handler or prompt can arrive after the view is detached.
	var canAutomaticallyHibernate: Bool {
		guard !isAuthenticationSessionBrowser,
			  suppliedConfiguration == nil,
			  !isOpeningExternalApplication,
			  !isDownloadHandoff,
			  pendingLifecycleOperations == 0,
			  pendingRequest == nil,
			  !awaitsNavigationCommit,
			  canHibernate
		else { return false }
		guard createdWebView == nil || displayCaptureState == false else { return false }
		#if os(macOS)
			guard createdWebView?.window?.attachedSheet == nil else { return false }
		#endif
		return true
	}

	fileprivate func beginLifecycleOperation() {
		pendingLifecycleOperations += 1
	}

	fileprivate func endLifecycleOperation() {
		pendingLifecycleOperations = max(0, pendingLifecycleOperations - 1)
	}

	private var displayCaptureState: Bool? {
		guard let webView = createdWebView,
			  webView.responds(to: NSSelectorFromString("_displayCaptureState"))
		else { return createdWebView == nil ? false : nil }
		guard let value = webView.value(forKey: "_displayCaptureState") as? NSNumber else { return nil }
		return value.intValue != 0
	}

	var requiresMediaTeardownConfirmation: Bool {
		BrowserPictureInPicturePolicy.preventsDestructiveTeardown(
			isActive: isPictureInPictureActive,
			isEntering: isEnteringPictureInPicture,
			isPlayingMedia: isPlayingMedia || hasActiveVideoPlayback,
			hasPausedMedia: hasPausedMedia
		)
	}

	private static var cachedSafariUserAgentSuffix: String?
	@ObservationIgnored
	private var isApplyingSiteZoom = false
	private var appliedContentRuleList: WKContentRuleList?

	private static func compatibilityUserAgentOverride(for url: URL?) -> String? {
		guard let url,
		      url.host == "chromewebstore.google.com"
		      || (url.host == "chrome.google.com" && url.path.hasPrefix("/webstore")) else { return nil }
		// Keep this existing exception while the Chrome Web Store expects a Chromium user agent.
		// Recheck it on each Chrome major and remove it if the store serves WebKit directly.
		return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36"
	}

	private func userAgentOverride(for url: URL?) -> String? {
		guard let url,
		      let origin = BrowserSitePermissions.origin(for: url)
		else {
			return nil
		}
		return session.sitePreferences.customUserAgent(for: origin)
			?? Self.compatibilityUserAgentOverride(for: url)
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
		BrowserLog.debug(.webKit, "webkit.prewarm")
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
		let mutationScheduled = false;
		let lastCheck = 0;
		let previous;
		const samples = 16;
		const threshold = Math.ceil(samples * 0.7);
		const minimumInterval = 100;
		const selector =
			'header, nav, [role="navigation"], [class*="header" i], [id*="header" i], ' +
			'[class*="nav" i], [id*="nav" i], [class*="toolbar" i], [id*="toolbar" i]';

		const check = () => {
			scheduled = false;
			lastCheck = performance.now();
			if (window.scrollY < 0 || innerWidth <= 0) return;

			// This probe does multiple hit-tests and layout/style reads. Top-edge
			// occupancy is browser chrome state, not animation state, so cap it
			// around 10 Hz instead of doing the work on every scroll frame.
			const counts = new Map();
			for (let index = 0; index < samples; index++) {
				const x = innerWidth * (index + 0.5) / samples;
				const seenAtPoint = new Set();
				for (const element of document.elementsFromPoint(x, 2)) {
					if (element === document.body || element === document.documentElement ||
						seenAtPoint.has(element)) continue;
					seenAtPoint.add(element);
					counts.set(element, (counts.get(element) || 0) + 1);
				}
			}

			let occupied = false;
			for (const [element, count] of counts) {
				if (count < threshold) continue;
				const rect = element.getBoundingClientRect();
				const style = getComputedStyle(element);
				const isPageChrome = element.matches(selector);
				if (!isPageChrome && style.position !== 'fixed' && style.position !== 'sticky') continue;
				if (rect.top > 3 || rect.bottom < 20 || rect.height > 160 ||
					rect.width < innerWidth * 0.5 || style.visibility === 'hidden' ||
					Number(style.opacity) < 0.05) continue;
				occupied = true;
				break;
			}

			if (occupied !== previous) {
				previous = occupied;
				window.webkit.messageHandlers.topEdgeChanged.postMessage(occupied);
			}
		};

		const schedule = (immediate = false) => {
			if (scheduled) return;
			scheduled = true;
			const delay = immediate ? 0 : Math.max(0, minimumInterval - (performance.now() - lastCheck));
			setTimeout(() => requestAnimationFrame(check), delay);
		};
		const scheduleMutation = () => {
			if (mutationScheduled) return;
			mutationScheduled = true;
			setTimeout(() => {
				mutationScheduled = false;
				schedule();
			}, 250);
		};

		addEventListener('scroll', () => schedule(), { passive: true });
		addEventListener('resize', () => schedule(true));
		new MutationObserver(scheduleMutation).observe(document.documentElement, {
			subtree: true,
			childList: true,
			attributes: true,
			attributeFilter: ['class', 'style', 'hidden', 'id', 'role']
		});
		schedule(true);
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
			let boundedZoom = BrowserZoomPolicy.clamp(pageZoom)
			if pageZoom != boundedZoom {
				pageZoom = boundedZoom
			}
			if let createdWebView, Double(createdWebView.pageZoom) != pageZoom {
				createdWebView.pageZoom = CGFloat(pageZoom)
			}
			if oldValue != pageZoom {
				zoomDidChange?()
				if !isApplyingSiteZoom,
				   canApplySitePreferencesToCurrentPage,
				   let origin = committedURL.flatMap(BrowserSitePermissions.origin(for:))
				{
					session.sitePreferences.setZoom(pageZoom, for: origin)
				}
			}
		}
	}

	func applySiteZoom(_ zoom: Double) {
		let boundedZoom = BrowserZoomPolicy.clamp(zoom)
		guard pageZoom != boundedZoom else { return }
		isApplyingSiteZoom = true
		pageZoom = boundedZoom
		isApplyingSiteZoom = false
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

	var url: URL? {
		didSet {
			if oldValue.flatMap(BrowserSitePermissions.origin(for:)) != url.flatMap(BrowserSitePermissions.origin(for:)) {
				clearAILinkPreviewCache()
			}
		}
	}

	private(set) var isLoading = false
	private(set) var estimatedProgress = 0.0
	private(set) var navigationFailure: BrowserNavigationFailure? {
		didSet {
			guard let failure = navigationFailure, !isAuthenticationSessionBrowser else { return }
			let category: BrowserDiagnosticReport.Event.Category = switch failure.kind {
				case .webContentTerminated, .repeatedWebContentTermination: .webContentTermination
				default: .navigationFailure
			}
			BrowserDiagnosticEventStore.shared.record(category, code: failure.kind.rawValue, isPrivate: session.isPrivate)
		}
	}

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
		@ObservationIgnored private var previewSnapshotGeneration: Int?
		var hasCurrentPreviewSnapshot: Bool {
			previewSnapshot != nil && previewSnapshotGeneration == navigationGeneration
		}
		private(set) var windowMirrorSnapshot: NSImage?
	#endif

	@ObservationIgnored
	var navigationDidChange: (@MainActor () -> Void)?
	@ObservationIgnored
	var zoomDidChange: (@MainActor () -> Void)?
	@ObservationIgnored
	var historyVisitDidCommit: (@MainActor (URL, String, Int) -> Void)?
	@ObservationIgnored
	var historyVisitTitleDidChange: (@MainActor (URL, String, Int) -> Void)?
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
	private var historyVisitPolicy: BrowserVisitPolicy
	@ObservationIgnored
	private var connectivityObserver: NSObjectProtocol?
	@ObservationIgnored
	private var currentRequest: URLRequest?
	@ObservationIgnored
	private var failedRequest: URLRequest?
	@ObservationIgnored
	var isAuthenticationSessionBrowser = false
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

	var hasCurrentPageDocument: Bool {
		!isInvalidated && !awaitsNavigationCommit && committedURL != nil
	}

	var canApplySitePreferencesToCurrentPage: Bool {
		hasCurrentPageDocument && navigationFailure == nil
	}

	@ObservationIgnored
	private var hasDeclaredThemeColor = false
	@ObservationIgnored
	private var pendingRequest: URLRequest?
	private var pendingWebArchive: (data: Data, baseURL: URL)?
	@ObservationIgnored
	private var currentNavigation: WKNavigation?
	@ObservationIgnored
	private var awaitsNavigationCommit = false
	@ObservationIgnored
	private var restoredPageZoomOrigin: String?
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
		fileAccessBookmark: Data? = nil,
		suppressInitialHistoryVisit: Bool = false
	) {
		let session = session ?? .shared
		let restoredHistory = BrowserHistory(entries: history, index: historyIndex, initialURL: initialURL)
		self.session = session
		restoredPageZoomOrigin = suppressInitialHistoryVisit
			? initialURL.flatMap(BrowserSitePermissions.origin(for:))
			: nil
		self.fileAccessBookmark = fileAccessBookmark
		historyVisitPolicy = BrowserVisitPolicy(suppressInitialVisit: suppressInitialHistoryVisit)
		if !session.isPrivate, let initialURL, let restorationState {
			// Unopened restored tabs shouldn't decrypt WebKit history at launch.
			pendingEncryptedInteractionState = (restorationState, initialURL)
		}
		suppliedConfiguration = configuration
		liveHistoryPrefix = Array(restoredHistory.entries.prefix(restoredHistory.index))
		historyManager = restoredHistory
		url = restoredHistory.currentURL
		self.scrollPosition = scrollPosition
		restoredScrollPosition = scrollPosition == .zero ? nil : scrollPosition
		super.init()
		updateThemeColor(url == nil ? .black : .white)

		if let url {
			#if os(macOS)
				if url.isFileURL, let fileAccessBookmark {
					var stale = false
					if let resolved = try? URL(resolvingBookmarkData: fileAccessBookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
						securityScopedFile = resolved.startAccessingSecurityScopedResource() ? resolved : nil
						pendingLocalFile = resolved
						if resolved != url {
							pendingEncryptedInteractionState = nil
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

	private static let linkHoverScript = """
	(() => {
		let previous = '', x = 0, y = 0, current = null, previewLink = null, sequence = 0, shift = false;
		let lastHref = '', lastTrailing = false, lastShift = false;
		let pointerFrame = 0, pendingLink = null, scrollFrame = 0;

		const report = (link, clientX, clientY, forceLayout = false) => {
			let href = '';
			try { if (link) href = new URL(link.getAttribute('href'), link.baseURI).href; } catch {}
			const linkChanged = link !== current;
			if (linkChanged) {
				if (current !== previewLink) current?.removeAttribute('data-astra-ai-preview-hover');
				current = link;
				sequence++;
			}
			if (current && /^https?:/.test(href)) {
				if (!document.getElementById('astra-ai-hover-style')) {
					const style = document.createElement('style');
					style.id = 'astra-ai-hover-style';
					style.textContent = '[data-astra-ai-preview-hover] { background-color: rgba(128,128,128,0.25); border-radius: 3px; } [data-astra-ai-preview-hover=thinking] { animation: astra-ai-thinking 1s ease-in-out infinite alternate; } @keyframes astra-ai-thinking { from { background-color: rgba(128,128,128,0.12); } to { background-color: rgba(128,128,128,0.4); } } @media (prefers-reduced-motion: reduce) { [data-astra-ai-preview-hover=thinking] { animation: none; } }';
					(document.head || document.documentElement).append(style);
				}
			}
			const trailing = clientX < innerWidth / 2 && clientY > innerHeight - 72;
			if (!forceLayout && !linkChanged && href === lastHref && trailing === lastTrailing && shift === lastShift) return;
			const rect = link?.getBoundingClientRect();
			const key = href + ':' + trailing + ':' + sequence + ':' + (rect?.top ?? 0) + ':' + (rect?.width ?? 0) + ':' + (rect?.height ?? 0) + ':' + shift;
			lastHref = href;
			lastTrailing = trailing;
			lastShift = shift;
			if (key === previous) return;
			previous = key;
			window.webkit.messageHandlers.linkHoverChanged.postMessage({ href, trailing, id: String(sequence), x: rect?.left ?? clientX, y: rect?.top ?? clientY, width: rect?.width ?? 0, height: rect?.height ?? 0, shift });
		};

		const schedulePointerReport = link => {
			pendingLink = link;
			if (pointerFrame) return;
			pointerFrame = requestAnimationFrame(() => {
				pointerFrame = 0;
				report(pendingLink, x, y);
			});
		};

		globalThis.astraSetAIHover = (enabled, thinking) => {
			const target = enabled ? (current || previewLink) : null;
			if (previewLink !== target) previewLink?.removeAttribute('data-astra-ai-preview-hover');
			previewLink = target;
			previewLink?.setAttribute('data-astra-ai-preview-hover', thinking ? 'thinking' : '');
		};
		document.addEventListener('keydown', event => { shift = event.shiftKey; report(current, x, y); }, true);
		document.addEventListener('keyup', event => { shift = event.shiftKey; report(current, x, y); }, true);
		document.addEventListener('pointermove', event => {
			shift = event.shiftKey;
			x = event.clientX;
			y = event.clientY;
			const link = event.composedPath().find(node => node.matches?.('a[href], area[href]'));
			schedulePointerReport(link);
		}, true);
		document.addEventListener('mouseleave', () => {
			pendingLink = null;
			report(null, 0, 0, true);
		});
		window.addEventListener('blur', () => report(null, 0, 0, true));
		window.addEventListener('pagehide', () => report(null, 0, 0, true));
		document.addEventListener('scroll', () => {
			if (scrollFrame) return;
			scrollFrame = requestAnimationFrame(() => {
				scrollFrame = 0;
				window.webkit.messageHandlers.linkHoverChanged.postMessage({ dismissPreview: true });
				const link = document.elementFromPoint(x, y)?.closest('a[href], area[href]');
				report(link, x, y, true);
			});
		}, true);
	})();
	"""

	func updateAIHoverHighlight(enabled: Bool = false, thinking: Bool = false) {
		createdWebView?.evaluateJavaScript(
			"globalThis.astraSetAIHover?.(\(enabled), \(thinking));",
			in: nil,
			in: .defaultClient
		) { _ in }
	}

	func clearHoveredLink() {
		hoveredLinkURL = nil
		hoveredLinkUsesTrailingCorner = false
		hoveredLinkID = ""
		hoveredLinkRect = .zero
		hoveredLinkShiftPressed = false
	}

	private static let activityScript = """
	(() => {
		const report = value => window.webkit.messageHandlers.pageActivityChanged.postMessage(value);
		document.addEventListener('input', event => {
			if (event.isTrusted && (event.target.matches('input:not([type="search"]), textarea, select') || event.target.closest('[contenteditable]'))) report('dirty');
		}, true);
		document.addEventListener('submit', () => report('submitted'), true);
		for (const event of ['playing', 'pause', 'ended', 'emptied', 'volumechange', 'loadeddata']) {
			document.addEventListener(event, () => report('media-changed'), true);
		}
	})();
	"""

	private static let pictureInPictureScript = """
	(() => {
		window.__astraSupportsPictureInPicture = video => !video.ended && video.readyState >= 2 &&
			video.videoWidth > 0 && video.videoHeight > 0 &&
			((typeof video.webkitSupportsPresentationMode === 'function' &&
				typeof video.webkitSetPresentationMode === 'function' && video.webkitSupportsPresentationMode('picture-in-picture')) ||
				(document.pictureInPictureEnabled && typeof video.requestPictureInPicture === 'function'));
		const report = () => {
			const videos = [...document.querySelectorAll('video')];
			window.webkit.messageHandlers.pictureInPictureChanged.postMessage({
				active: Boolean(document.pictureInPictureElement) || videos.some(video => video.webkitPresentationMode === 'picture-in-picture'),
				eligible: videos.some(window.__astraSupportsPictureInPicture)
			});
		};
		for (const name of ['enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged', 'loadedmetadata', 'loadeddata', 'canplay', 'resize', 'play', 'pause', 'ended']) {
			document.addEventListener(name, report, true);
		}
	report();
	})();
	"""

	private func startMediaObservation() {
		mediaObservationTask = Task { @MainActor [weak self] in
			while !Task.isCancelled {
				guard self?.createdWebView != nil else { return }
				await self?.refreshActivity()
				guard !Task.isCancelled else { return }
				do {
					// DOM media events perform immediate refreshes. Quiescent pages
					// need a much slower fallback; with many background tabs the
					// former 5-second poll woke WebKit processes unnecessarily.
					let hasActivity = self?.isPlayingMedia == true
						|| self?.hasPausedMedia == true
						|| self?.isCapturing == true
						|| self?.isPictureInPictureActive == true
						|| self?.isEnteringPictureInPicture == true
					try await Task.sleep(for: .seconds(hasActivity ? 5 : 20))
				} catch {
					return
				}
			}
		}
	}

	@discardableResult
	func refreshActivity() async -> Bool {
		guard !isInvalidated, !isRefreshingActivity, let webView = createdWebView else { return false }
		isRefreshingActivity = true
		defer { isRefreshingActivity = false }
		let documentID = navigationIdentifier
		let script = """
		(() => {
			const media = [...document.querySelectorAll('audio, video')];
			return {
				videoPlaying: media.some(element => element.tagName === 'VIDEO' && !element.paused && !element.ended && element.readyState >= 2 && element.videoWidth > 0 && element.videoHeight > 0),
				playing: media.some(element => !element.paused && !element.ended && element.readyState >= 2),
				paused: media.some(element => element.paused && !element.ended && element.currentTime > 0),
				title: navigator.mediaSession?.metadata?.title ?? '',
				artist: navigator.mediaSession?.metadata?.artist ?? ''
			};
		})()
		"""
		let value = try? await webView.evaluateJavaScript(script)
		guard owns(webView), documentID == navigationIdentifier,
		      let state = value as? [String: Any],
		      let videoPlaying = state["videoPlaying"] as? Bool,
		      let playing = state["playing"] as? Bool,
		      let paused = state["paused"] as? Bool,
		      let title = state["title"] as? String,
		      let artist = state["artist"] as? String
		else { return false }
		let playbackState = await webView.mediaPlaybackState()
		guard owns(webView), documentID == navigationIdentifier else { return false }
		isPlayingMedia = playing || playbackState == .playing
		hasActiveVideoPlayback = videoPlaying
		hasPausedMedia = paused || playbackState == .paused || playbackState == .suspended
		cameraCaptureState = webView.cameraCaptureState
		microphoneCaptureState = webView.microphoneCaptureState
		mediaCaptureStateDocumentID = committedSecurityNavigationID
		if isPlayingMedia || !hasPausedMedia {
			pausedFromBrowser = false
		}
		mediaTitle = title.isEmpty ? nil : String(title.prefix(500))
		mediaArtist = artist.isEmpty ? nil : String(artist.prefix(500))
		guard owns(webView), documentID == navigationIdentifier else { return }
		// pictureInPictureScript reports eligibility/active changes directly on
		// video lifecycle events; do not run a second DOM query on every poll.
		webView.configuration.preferences.inactiveSchedulingPolicy = isPictureInPictureActive || isEnteringPictureInPicture || isPlayingMedia || hasActiveVideoPlayback ? .none : .throttle
		return true
	}

	private func refreshPictureInPictureEligibility(in webView: WKWebView, documentID: Int) async {
		let script = """
		(() => {
			const videos = [...document.querySelectorAll('video')];
			const supports = video => !video.ended && video.readyState >= 2 &&
				video.videoWidth > 0 && video.videoHeight > 0 &&
				((typeof video.webkitSupportsPresentationMode === 'function' &&
				typeof video.webkitSetPresentationMode === 'function' && video.webkitSupportsPresentationMode('picture-in-picture')) ||
				(document.pictureInPictureEnabled && typeof video.requestPictureInPicture === 'function'));
			return {
				active: Boolean(document.pictureInPictureElement) || videos.some(video => video.webkitPresentationMode === 'picture-in-picture'),
			eligible: typeof supports === 'function' && videos.some(supports)
			};
		})()
		"""
		let value: [String: Bool]? = await withCheckedContinuation { continuation in
			webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
				continuation.resume(returning: (try? result.get()) as? [String: Bool])
			}
		}
		guard owns(webView), documentID == navigationIdentifier,
		      let result = value
		else { return }
		canEnterPictureInPicture = result["eligible"] == true
		if result["active"] == true {
			setPictureInPictureActive(true)
		} else if isPictureInPictureActive, !isEnteringPictureInPicture {
			setPictureInPictureActive(false)
		}
	}

	func enterPictureInPicture() {
		guard canEnterPictureInPicture,
		      !isPictureInPictureActive,
		      !isEnteringPictureInPicture,
		      let webView = createdWebView,
		      owns(webView)
		else { return }
		isEnteringPictureInPicture = true
		let documentID = navigationIdentifier
		webView.callAsyncJavaScript("""
		return (async () => {
			const supports = video => !video.ended && video.readyState >= 2 &&
				video.videoWidth > 0 && video.videoHeight > 0 &&
				((typeof video.webkitSupportsPresentationMode === 'function' &&
				typeof video.webkitSetPresentationMode === 'function' && video.webkitSupportsPresentationMode('picture-in-picture')) ||
				(document.pictureInPictureEnabled && typeof video.requestPictureInPicture === 'function'));
			const video = [...document.querySelectorAll('video')].find(supports);
			if (!video) return false;
			// The browser's explicit user action overrides the page's PiP hint for this request.
			const disabled = video.disablePictureInPicture;
			video.disablePictureInPicture = false;
			try {
				if (typeof video.webkitSetPresentationMode === 'function' && video.webkitSupportsPresentationMode?.('picture-in-picture')) {
					return await new Promise(resolve => {
						const finish = () => {
							video.removeEventListener('webkitpresentationmodechanged', finish);
							resolve(video.webkitPresentationMode === 'picture-in-picture');
						};
						video.addEventListener('webkitpresentationmodechanged', finish);
						video.webkitSetPresentationMode('picture-in-picture');
						setTimeout(finish, 2000);
					});
				}
				await video.requestPictureInPicture();
				return true;
			} catch {
				return false;
			} finally {
				video.disablePictureInPicture = disabled;
			}
		})();
		""", arguments: [:], in: nil, in: .defaultClient) { [weak self, weak webView] result in
			guard let self, let webView, owns(webView), documentID == navigationIdentifier else { return }
			isEnteringPictureInPicture = false
			if (try? result.get()) as? Bool == true {
				setPictureInPictureActive(true)
			} else {
				pictureInPictureControlUnavailable = true
				canEnterPictureInPicture = false
				session.toastManager.show(
					symbol: "pip",
					message: "Use the video's own Picture in Picture control; a page gesture or provider support may be required."
				)
			}
		}
	}

	func returnToPictureInPictureSource() {
		guard isPictureInPictureActive || isEnteringPictureInPicture else { return }
		pictureInPictureRestoreRequested?()
	}

	private func setPictureInPictureActive(_ active: Bool) {
		guard isPictureInPictureActive != active else { return }
		isPictureInPictureActive = active
		if active {
			pictureInPictureControlUnavailable = false
		}
		createdWebView?.configuration.preferences.inactiveSchedulingPolicy = active ? .none : .throttle
	}

	private static let findScript = #"""
	const selection = window.getSelection();
	if (!query) {
		window.__astraFindState = null;
		selection?.removeAllRanges();
		globalThis.CSS?.highlights?.delete('astra-find');
		return { count: 0, index: 0 };
	}
	const nodes = [], offsets = [];
	let text = '';
	const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
	for (let node; node = walker.nextNode();) {
		const parent = node.parentElement;
		if (!parent || parent.closest('script, style, noscript, input, textarea, select, [hidden]') || !parent.getClientRects().length) continue;
		nodes.push(node);
		offsets.push(text.length);
		text += node.textContent;
	}
	const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const matches = [];
	let first = 0, last = 0;
	for (const match of text.matchAll(new RegExp(escaped, 'giu'))) {
		const start = match.index, end = start + match[0].length;
		while (first + 1 < nodes.length && offsets[first + 1] <= start) first++;
		last = Math.max(last, first);
		while (last + 1 < nodes.length && offsets[last + 1] < end) last++;
		const range = document.createRange();
		range.setStart(nodes[first], start - offsets[first]);
		range.setEnd(nodes[last], end - offsets[last]);
		matches.push(range);
	}
	const previous = window.__astraFindState;
	const sameQuery = previous?.query === query;
	let index = sameQuery ? previous.index + (backwards ? -1 : 1) : (backwards ? matches.length - 1 : 0);
	index = matches.length ? (index + matches.length) % matches.length : -1;
	window.__astraFindState = { query, index };
	selection?.removeAllRanges();
	if (globalThis.CSS?.highlights && typeof Highlight === 'function') {
		CSS.highlights.set('astra-find', new Highlight(...matches));
		if (!document.getElementById('astra-find-style')) {
			const style = document.createElement('style');
			style.id = 'astra-find-style';
			style.textContent = '::highlight(astra-find) { background-color: #ffe066; color: #000; }';
			document.head.append(style);
		}
	}
	if (index >= 0) {
		selection?.addRange(matches[index]);
		const rect = matches[index].getBoundingClientRect();
		if (rect.top < 0 || rect.bottom > innerHeight) window.scrollBy(0, rect.top - innerHeight / 2);
	}
	return { count: matches.length, index: index + 1 };
	"""#

	func presentFind() {
		readerHTML = nil
		showsFind = true
		findFocusRequest += 1
	}

	func findNext(backwards: Bool = false) {
		guard !awaitsNavigationCommit,
		      navigationFailure == nil,
		      let webView = createdWebView,
		      owns(webView) else { return }
		let generation = findGeneration.advance()
		let query = findText
		webView.callAsyncJavaScript(Self.findScript, arguments: ["query": query, "backwards": backwards], in: nil, in: .defaultClient) { [weak self, weak webView] result in
			guard let self, let webView,
			      owns(webView), findGeneration.accepts(generation), query == findText else { return }
			guard let matches = (try? result.get()) as? [String: Int] else {
				// PDF and other non-HTML documents still use WebKit's native search.
				let configuration = WKFindConfiguration()
				configuration.backwards = backwards
				configuration.wraps = true
				webView.find(query, configuration: configuration) { [weak self] result in
					guard let self, findGeneration.accepts(generation) else { return }
					findHasMatch = query.isEmpty || result.matchFound
				}
				return
			}
			findMatchCount = matches["count"] ?? 0
			findMatchIndex = matches["index"] ?? 0
			findHasMatch = query.isEmpty || findMatchCount > 0
		}
	}

	func invalidateFindResults() {
		findGeneration.advance()
		findHasMatch = nil
		findMatchCount = 0
		findMatchIndex = 0
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
			pendingWebArchive = nil
			pendingRequest = nil
			pendingLocalFile = url
			pendingEncryptedInteractionState = nil
			pendingInteractionState = nil
			currentNavigation = nil
			_ = webView
			loadPendingRequest()
		}
	#endif

	func pauseMedia() {
		guard let webView = createdWebView, owns(webView) else { return }
		let documentID = navigationIdentifier
		pausedFromBrowser = true
		webView.pauseAllMediaPlayback(completionHandler: { [weak self, weak webView] in
			guard let self, let webView, owns(webView), documentID == navigationIdentifier else { return }
			isPlayingMedia = false
			pausedFromBrowser = true
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

	#if os(macOS)
		private func ownsExplicitAddressPrompt(
			in webView: WKWebView,
			documentID: Int,
			owner: BrowserAddressPromptOwner
		) -> Bool {
			let windowStillOwnsPrompt = owner.window.isKeyWindow || owner.window.attachedSheet?.isKeyWindow == true
			return BrowserKeyboardMenuPolicy.canPromptForAddressAction(
				isFocusedBrowser: windowStillOwnsPrompt,
				isSelectedController: owner.browser.selectedTab?.activeController === self,
				isSameSession: owner.browser.session === session,
				isCurrentWebView: webViewIfLoaded === webView && owns(webView),
				isSameNavigation: navigationIdentifier == documentID && !isInvalidated,
				webViewMatchesOwnerWindow: webView.window == nil || webView.window === owner.window
			)
		}
	#endif

	func toggleReader() {
		BrowserLog.info(.navigation, "reader.toggle", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url)])
		if readerHTML != nil {
			readerHTML = nil
			return
		}
		guard isReaderAvailable, !isPreparingReader, hasCurrentPageDocument,
		      navigationFailure == nil, let webView = createdWebView else { return }
		isPreparingReader = true
		let documentID = navigationIdentifier
		let generation = readerGeneration
		let pageURL = webView.url
		webView.evaluateJavaScript("globalThis.astraExtractReader?.()", in: nil, in: .defaultClient) { [weak self, weak webView] result in
			guard let self, let webView, owns(webView), hasCurrentPageDocument,
			      documentID == navigationIdentifier, generation == readerGeneration,
			      pageURL == webView.url else { return }
			isPreparingReader = false
			guard case let .success(value) = result,
			      let article = value as? [String: String],
			      let content = article["content"], !content.isEmpty,
			      content.utf8.count <= 5 * 1024 * 1024
			else {
				isReaderAvailable = false
				session.toastManager.show(symbol: "doc.text", message: "Reader mode could not extract an article from this page.")
				return
			}
			showsFind = false
			readerHTML = BrowserReaderScript.document(article: article)
		}
	}

	private func resetReader() {
		readerGeneration += 1
		isReaderAvailable = false
		isPreparingReader = false
		readerHTML = nil
	}

	func stopForClose() {
		BrowserLog.info(.webKit, "controller.stop-for-close", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url)])
		guard !isInvalidated else { return }
		clearAILinkPreviewCache()
		resetReader()
		clearHoveredLink()
		isInvalidated = true
		removeAppliedContentRuleList()
		promptOwnership = nil
		if let connectivityObserver {
			NotificationCenter.default.removeObserver(connectivityObserver)
			self.connectivityObserver = nil
		}
		#if os(macOS)
			if let webInspectorObserver {
				NotificationCenter.default.removeObserver(webInspectorObserver)
				self.webInspectorObserver = nil
			}
		#endif
		currentRequest = nil
		failedRequest = nil
		currentNavigation = nil
		pendingRequest = nil
		pendingWebArchive = nil
		navigationFailure = nil
		contentProcessTerminations = BrowserContentProcessTerminationTracker()
		session.permissions.removeTemporaryDecisions(controllerID: id)
		navigationGeneration += 1
		findGeneration.advance()
		observations.forEach { $0.invalidate() }
		observations.removeAll()
		securityScopedFile?.stopAccessingSecurityScopedResource()
		securityScopedFile = nil
		releaseUploadAccess()
		mediaObservationTask?.cancel()
		mediaObservationTask = nil
		pendingLifecycleOperations = 0
		pictureInPictureControlUnavailable = false
		faviconTask?.cancel()
		faviconTask = nil
		#if os(macOS)
			previewSnapshotRefreshTask?.cancel()
			previewSnapshotRefreshTask = nil
			previewSnapshot = nil
			previewSnapshotGeneration = nil
			windowMirrorSnapshot = nil
		#endif
		createdWebView?.navigationDelegate = nil
		createdWebView?.uiDelegate = nil
		createdWebView?.stopLoading()
		createdWebView?.closeAllMediaPresentations(completionHandler: nil)
		createdWebView?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
		stopCapture()
		(createdWebView as? PeekSourceWebView)?.onEscape = nil
		(createdWebView as? PeekSourceWebView)?.onLayout = nil
		(createdWebView as? PeekSourceWebView)?.onZoomIn = nil
		(createdWebView as? PeekSourceWebView)?.onZoomOut = nil
		(createdWebView as? PeekSourceWebView)?.onResetZoom = nil
		for name in [Self.scrollPositionMessageName, Self.topEdgeMessageName, Self.zapFinishedMessageName, "pageActivityChanged", "pictureInPictureChanged", "linkHoverChanged", "faviconChanged", "readerAvailabilityChanged"] {
			createdWebView?.configuration.userContentController.removeScriptMessageHandler(forName: name, contentWorld: .defaultClient)
		}
		createdWebView?.configuration.userContentController.removeAllUserScripts()
		createdWebView?.removeFromSuperview()
		createdWebView = nil
		isWebViewReady = false
		isRefreshingActivity = false
		#if os(macOS)
			screenshotReaderWebView = nil
			isRefreshingPreviewSnapshot = false
		#endif
		appliedContentRuleList = nil
		navigationDidChange = nil
		zoomDidChange = nil
		historyVisitDidCommit = nil
		historyVisitTitleDidChange = nil
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

	func retainPanelUploadAccess(for urls: [URL]) {
		uploadSecurityScopedFiles.append(contentsOf: urls)
	}

	private func releaseUploadAccess() {
		for url in uploadSecurityScopedFiles {
			url.stopAccessingSecurityScopedResource()
		}
		uploadSecurityScopedFiles.removeAll()
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
		BrowserLog.debug(.webKit, "webview.prepare", metadata: ["controller": BrowserLog.id(id), "has_webview": String(createdWebView != nil)])
		_ = webView
	}

	#if os(macOS)
		func updateWebInspectorAvailability(_ enabled: Bool) {
			if let createdWebView {
				BrowserDesktopCommands.configureWebInspector(createdWebView, enabled: enabled)
			}
		}
	#endif

	private func startWebViewEventObservations() {
		guard connectivityObserver == nil else { return }
		// Restored-but-unopened tabs don't need network notifications or
		// Web Inspector defaults observation until a WKWebView exists.
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
		#if os(macOS)
			observedWebInspectorEnabled = Defaults[.webInspectorEnabled]
			webInspectorObserver = NotificationCenter.default.addObserver(
				forName: UserDefaults.didChangeNotification,
				object: UserDefaults.standard,
				queue: .main
			) { [weak self] _ in
				MainActor.assumeIsolated {
					guard let self else { return }
					let enabled = Defaults[.webInspectorEnabled]
					guard enabled != self.observedWebInspectorEnabled else { return }
					self.observedWebInspectorEnabled = enabled
					self.updateWebInspectorAvailability(enabled)
				}
			}
		#endif
	}

	private func makeWebView() -> WKWebView {
		let webViewLogStarted = BrowserLog.clock()
		BrowserLog.info(.webKit, "webview.create.begin", metadata: ["controller": BrowserLog.id(id), "private": String(session.isPrivate)])
		var webViewStageStarted = BrowserLog.clock()
		let configuration = suppliedConfiguration ?? WKWebViewConfiguration()
		if suppliedConfiguration != nil {
			// Popup configurations inherit the opener's settings; give this page its own
			// controller before installing handlers that stopForClose will remove.
			configuration.userContentController = WKUserContentController()
		}
		configuration.websiteDataStore = session.dataStore
		configuration.webExtensionController = session.isPrivate ? nil : BrowserExtensionManager.shared.controller
		if suppliedConfiguration == nil {
			configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
		}
		configuration.preferences.isElementFullscreenEnabled = true
		configuration.preferences.isFraudulentWebsiteWarningEnabled = true
		configuration.preferences.inactiveSchedulingPolicy = .throttle
		configuration.mediaTypesRequiringUserActionForPlayback = .all
		configuration.allowsAirPlayForMediaPlayback = true
		#if os(iOS)
			configuration.allowsPictureInPictureMediaPlayback = true
		#endif
		#if os(macOS)
			// macOS WebKit defaults PiP playback off and exposes its opt-in only through SPI.
			if configuration.preferences.responds(to: NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")) {
				configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
			}
			_ = AstraConfigureWebPushPreferences(configuration.preferences, !session.isPrivate && BrowserWebPushManager.shared.hasNativeSupport)
		#endif
		if let suffix = Self.safariUserAgentSuffix() {
			configuration.applicationNameForUserAgent = suffix
		}
		session.favicons.configureFaviconObservation(in: configuration.userContentController)
		BrowserLog.duration(.webKit, "webview.create.configuration", since: webViewStageStarted, warnAboveMilliseconds: 40, metadata: ["controller": BrowserLog.id(id)])
		webViewStageStarted = BrowserLog.clock()
		let webView = PeekSourceWebView(frame: .zero, configuration: configuration)
		#if os(macOS)
			BrowserDesktopCommands.configureWebInspector(webView, enabled: Defaults[.webInspectorEnabled])
		#endif
		createdWebView = webView
		startWebViewEventObservations()
		#if os(macOS)
			startPreviewSnapshotRefresh()
		#endif
		BrowserLog.duration(.webKit, "webview.create.instance", since: webViewStageStarted, warnAboveMilliseconds: 50, metadata: ["controller": BrowserLog.id(id)])
		webViewStageStarted = BrowserLog.clock()
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
		#if os(macOS)
			webView.configuration.userContentController.add(scrollHandler, contentWorld: .defaultClient, name: "linkHoverChanged")
			webView.configuration.userContentController.addUserScript(
				WKUserScript(source: Self.linkHoverScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)
			)
		#endif
		webView.configuration.userContentController.add(scrollHandler, contentWorld: .defaultClient, name: "pageActivityChanged")
		if let script = BrowserReaderScript.source {
			webView.configuration.userContentController.add(scrollHandler, contentWorld: .defaultClient, name: "readerAvailabilityChanged")
			webView.configuration.userContentController.addUserScript(
				WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
			)
		}
		webView.configuration.userContentController.add(scrollHandler, contentWorld: .defaultClient, name: "pictureInPictureChanged")
		webView.configuration.userContentController.addUserScript(
			WKUserScript(source: Self.pictureInPictureScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient)
		)
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
		BrowserLog.duration(.webKit, "webview.create.handlers", since: webViewStageStarted, warnAboveMilliseconds: 40, metadata: ["controller": BrowserLog.id(id)])
		webViewStageStarted = BrowserLog.clock()

		observations = [
			webView.observe(\.hasOnlySecureContent, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated { [weak self, weak webView] in
					guard let self, let webView, owns(webView) else { return }
					refreshCommittedSecuritySnapshot()
				}
			},
			webView.observe(\.serverTrust, options: [.initial, .new]) { [weak self] webView, _ in
				MainActor.assumeIsolated { [weak self, weak webView] in
					guard let self, let webView, owns(webView) else { return }
					refreshCommittedSecuritySnapshot()
				}
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
					if self.url != url {
						self.aiPreviewDismissal += 1
					}
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
					guard let self else { return }
					let title = change.newValue ?? webView.title
					self.titleDidChange?(title)
					if let url = self.committedURL, self.canRecordVisit {
						self.historyVisitTitleDidChange?(url, title ?? url.host ?? url.absoluteString, self.navigationIdentifier)
					}
				}
			},
			webView.observe(\.pageZoom, options: [.new]) { [weak self] webView, _ in
				MainActor.assumeIsolated {
					self?.pageZoom = Double(webView.pageZoom)
				}
			},
		]
		BrowserLog.duration(.webKit, "webview.create.observers", since: webViewStageStarted, warnAboveMilliseconds: 30, metadata: ["controller": BrowserLog.id(id)])
		webViewStageStarted = BrowserLog.clock()
		startMediaObservation()
		isWebViewReady = true
		extensionWebViewDidChange?()
		// Start deferred navigation immediately once startup rule restoration is ready.
		contentBlockingDidBecomeReady()
		BrowserLog.duration(.webKit, "webview.create.finalize", since: webViewStageStarted, warnAboveMilliseconds: 30, metadata: ["controller": BrowserLog.id(id)])
		BrowserLog.duration(.webKit, "webview.create.end", since: webViewLogStarted, warnAboveMilliseconds: 150, metadata: ["controller": BrowserLog.id(id)])
		return webView
	}

	func contentBlockingDidBecomeReady() {
		guard session.contentBlocking.isReadyForNavigation,
		      let webView = createdWebView,
		      owns(webView) else { return }
		refreshContentBlocking()
		loadPendingRequest()
	}

	func refreshContentBlocking(for requestedURL: URL? = nil) {
		guard let webView = createdWebView, owns(webView) else { return }
		let currentURL = requestedURL ?? committedURL ?? webView.url ?? url
		let origin = currentURL.flatMap(BrowserSitePermissions.origin(for:))
		refreshContentBlocking(forOrigin: origin)
	}

	private func refreshContentBlocking(forOrigin origin: String?) {
		guard let webView = createdWebView, owns(webView) else { return }
		let nextRuleList = session.contentBlocking.ruleList(for: origin, sitePreferences: session.sitePreferences)
		guard appliedContentRuleList?.identifier != nextRuleList?.identifier else { return }
		removeAppliedContentRuleList()
		if let nextRuleList {
			webView.configuration.userContentController.add(nextRuleList)
			appliedContentRuleList = nextRuleList
		}
	}

	private func removeAppliedContentRuleList() {
		guard let appliedContentRuleList else { return }
		createdWebView?.configuration.userContentController.remove(appliedContentRuleList)
		self.appliedContentRuleList = nil
	}

	private func updateContentBlocking(
		forNavigationDisposition disposition: BrowserContentBlockingRuleSource.NavigationDisposition,
		isMainFrame: Bool,
		destinationURL: URL?,
		in webView: WKWebView
	) {
		let currentOrigin = (committedURL ?? webView.url).flatMap(BrowserSitePermissions.origin(for:))
		let destinationOrigin = destinationURL.flatMap(BrowserSitePermissions.origin(for:))
		let origin = BrowserContentBlockingRuleSource.originAfterNavigationDecision(
			isMainFrame: isMainFrame,
			disposition: disposition,
			currentOrigin: currentOrigin,
			destinationOrigin: destinationOrigin
		)
		refreshContentBlocking(forOrigin: origin)
	}

	deinit {
		if let connectivityObserver {
			NotificationCenter.default.removeObserver(connectivityObserver)
		}
		#if os(macOS)
			if let webInspectorObserver {
				NotificationCenter.default.removeObserver(webInspectorObserver)
			}
		#endif
		mediaObservationTask?.cancel()
		faviconTask?.cancel()
		observations.forEach { $0.invalidate() }
		#if os(macOS)
			previewSnapshotRefreshTask?.cancel()
		#endif
	}

	func load(_ url: URL) {
		BrowserLog.info(.navigation, "navigation.load-url", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url)])
		load(url, isExplicitAddressRequest: false)
	}

	func loadFromAddressBar(_ url: URL) {
		BrowserLog.info(.navigation, "navigation.address-submit", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url)])
		load(url, isExplicitAddressRequest: true)
	}

	private func load(_ url: URL, isExplicitAddressRequest: Bool) {
		guard !isInvalidated else { return }
		if BrowserAddress.externalApplicationScheme(for: url) != nil,
		   handleExternalLink(
		   	url,
		   	requestingOrigin: nil,
		   	requestingSite: isExplicitAddressRequest ? "Astra address bar" : nil,
		   	isExplicitAddressRequest: isExplicitAddressRequest,
		   	in: webView
		   )
		{
			return
		}
		navigate(URLRequest(url: url))
	}

	func loadWebArchive(_ data: Data, baseURL: URL) {
		guard !isInvalidated,
		      let safeURL = BrowserHomepage.validURL(baseURL.absoluteString) else { return }
		historyVisitPolicy.userInitiatedNavigation()
		createdWebView?.stopLoading()
		createdWebView?.closeAllMediaPresentations(completionHandler: nil)
		currentRequest = nil
		pendingRequest = nil
		pendingLocalFile = nil
		pendingEncryptedInteractionState = nil
		pendingInteractionState = nil
		failedRequest = nil
		retriedAfterConnectivityReturn = true
		navigationFailure = nil
		awaitsNavigationCommit = true
		invalidateFindResults()
		currentNavigation = nil
		historyManager.beginVisit()
		url = safeURL
		scrollPosition = .zero
		restoredScrollPosition = nil
		pendingWebArchive = (data, safeURL)
		_ = webView
		loadPendingRequest()
	}

	func navigate(_ request: URLRequest) {
		BrowserLog.info(.navigation, "navigation.request", metadata: ["controller": BrowserLog.id(id), "request": BrowserLog.request(request)])
		guard !isInvalidated else { return }
		guard let url = request.url else { return }
		historyVisitPolicy.userInitiatedNavigation()
		createdWebView?.stopLoading()
		createdWebView?.closeAllMediaPresentations(completionHandler: nil)
		(createdWebView as? PeekSourceWebView)?.consumeRecentClick()
		historyManager.beginVisit()
		self.url = url
		invalidateFindResults()
		scrollPosition = .zero
		restoredScrollPosition = nil
		load(request)
	}

	func goBack() {
		BrowserLog.debug(.navigation, "navigation.back", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url)])
		guard let webView = createdWebView, webView.canGoBack else { return }
		clearAILinkPreviewCache()
		aiPreviewDismissal += 1
		invalidateFindResults()
		historyVisitPolicy.userInitiatedNavigation()
		currentRequest = nil
		awaitsNavigationCommit = true
		currentNavigation = webView.goBack()
	}

	func goForward() {
		BrowserLog.debug(.navigation, "navigation.forward", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url)])
		guard let webView = createdWebView, webView.canGoForward else { return }
		clearAILinkPreviewCache()
		aiPreviewDismissal += 1
		invalidateFindResults()
		historyVisitPolicy.userInitiatedNavigation()
		currentRequest = nil
		awaitsNavigationCommit = true
		currentNavigation = webView.goForward()
	}

	func go(toHistoryIndex index: Int) {
		guard history.indices.contains(index), index != historyIndex else { return }
		clearAILinkPreviewCache()
		aiPreviewDismissal += 1
		historyVisitPolicy.userInitiatedNavigation()
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
		BrowserLog.info(.navigation, "navigation.reload", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url), "failure": String(navigationFailure != nil)])
		historyVisitPolicy.userInitiatedNavigation()
		if let navigationFailure {
			load(failedRequest ?? URLRequest(url: navigationFailure.url))
			return
		}
		reload(usingOrigin: false)
	}

	private func reload(usingOrigin: Bool) {
		if !hasCurrentPageDocument {
			if let pendingRequest {
				load(pendingRequest)
				return
			}
			if pendingWebArchive != nil || pendingLocalFile != nil || pendingInteractionState != nil || pendingEncryptedInteractionState != nil {
				loadPendingRequest()
				return
			}
		}
		if let createdWebView {
			if !hasCurrentPageDocument,
			   let request = currentRequest ?? url.map({ URLRequest(url: $0) }),
			   createdWebView.url == nil || createdWebView.url?.absoluteString == "about:blank"
			{
				load(request)
				return
			}
			awaitsNavigationCommit = true
			currentNavigation = usingOrigin ? createdWebView.reloadFromOrigin() : createdWebView.reload()
			if currentNavigation == nil, let request = currentRequest ?? url.map({ URLRequest(url: $0) }) {
				load(request)
			}
		} else if let url {
			load(URLRequest(url: url))
		}
	}

	func stopLoading() {
		BrowserLog.notice(.navigation, "navigation.stop", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url)])
		createdWebView?.stopLoading()
		pendingRequest = nil
		pendingLocalFile = nil
		pendingWebArchive = nil
	}

	func resetZoom() {
		pageZoom = BrowserZoomPolicy.defaultZoom
		session.toastManager.show(symbol: "1.magnifyingglass", message: "Zoom 100%")
	}

	func reloadFromOrigin() {
		historyVisitPolicy.userInitiatedNavigation()
		if navigationFailure != nil {
			reload()
			return
		}
		reload(usingOrigin: true)
	}

	func zoomIn() {
		pageZoom = BrowserZoomPolicy.clamp(pageZoom + 0.1)
		session.toastManager.show(
			symbol: "plus.magnifyingglass",
			message: "Zoom \(Int((pageZoom * 100).rounded()))%"
		)
	}

	func zoomOut() {
		pageZoom = BrowserZoomPolicy.clamp(pageZoom - 0.1)
		session.toastManager.show(
			symbol: "minus.magnifyingglass",
			message: "Zoom \(Int((pageZoom * 100).rounded()))%"
		)
	}

	func loadFaviconIfMissing() {
		guard let url, let webView = createdWebView,
		      !session.favicons.hasCachedFavicon(for: url) else { return }
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
			previewSnapshotGeneration = nil
			windowMirrorSnapshot = nil
		}

		@discardableResult
		func refreshWindowMirrorSnapshot() async -> Bool {
			guard let webView = createdWebView, owns(webView), !webView.isHidden else { return false }
			let generation = navigationGeneration
			guard let image = await takeSnapshot(snapshotWidth: min(1024, webView.bounds.width)),
			      owns(webView), generation == navigationGeneration else { return false }
			windowMirrorSnapshot = image
			return true
		}

		func refreshPreviewSnapshot() async {
			guard let webView = createdWebView, owns(webView) else { return }
			let generation = navigationGeneration
			guard let image = await takeSnapshot() else { return }
			guard owns(webView), generation == navigationGeneration else { return }
			previewSnapshot = image
			previewSnapshotGeneration = generation
		}

		func tabProcessMemorySnapshot() -> BrowserTabProcessMemorySnapshot? {
			guard let webView = createdWebView, owns(webView) else { return nil }

			let webContentPID = Self.privateProcessIdentifier("_webProcessIdentifier", on: webView)
			let graphicsPID = Self.privateProcessIdentifier("_gpuProcessIdentifier", on: webView)
			let modelPID = Self.privateProcessIdentifier("_modelProcessIdentifier", on: webView)
			let networkPID = Self.privateProcessIdentifier(
				"_networkProcessIdentifier",
				on: webView.configuration.websiteDataStore
			)

			let snapshot = BrowserTabProcessMemorySnapshot(
				webContentBytes: webContentPID.flatMap(Self.physicalFootprint),
				graphicsBytes: graphicsPID.flatMap(Self.physicalFootprint),
				networkBytes: networkPID.flatMap(Self.physicalFootprint),
				modelBytes: modelPID.flatMap(Self.physicalFootprint)
			)
			return snapshot.relatedProcessBytes == nil ? nil : snapshot
		}

		private static func privateProcessIdentifier(_ key: String, on object: NSObject) -> pid_t? {
			let selector = NSSelectorFromString(key)
			guard object.responds(to: selector),
			      let number = object.value(forKey: key) as? NSNumber
			else { return nil }
			let processIdentifier = number.int32Value
			return processIdentifier > 0 ? processIdentifier : nil
		}

		private static func physicalFootprint(_ processIdentifier: pid_t) -> UInt64? {
			var usage = rusage_info_v4()
			let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
				var info: rusage_info_t? = UnsafeMutableRawPointer(usagePointer)
				return withUnsafeMutablePointer(to: &info) { infoPointer in
					proc_pid_rusage(
						processIdentifier,
						Int32(RUSAGE_INFO_V4),
						infoPointer
					)
				}
			}
			guard result == 0 else { return nil }
			return usage.ri_phys_footprint
		}
	#endif

	private func updateHistory(reportSameDocumentVisit: Bool = true) {
		guard let currentURL = createdWebView?.url else { return }
		if committedURL != currentURL {
			resetReader()
			createdWebView?.evaluateJavaScript("globalThis.astraProbeReader?.(true)", in: nil, in: .defaultClient, completionHandler: nil)
		}
		url = currentURL
		if let list = createdWebView?.backForwardList, let current = list.currentItem {
			let entries = liveHistoryPrefix + list.backList.map(\.url) + [current.url] + list.forwardList.map(\.url)
			historyManager = BrowserHistory(entries: entries, index: liveHistoryPrefix.count + list.backList.count)
		} else {
			historyManager.record(currentURL)
		}
		if reportSameDocumentVisit {
			committedURL = currentURL
			committedSecurityNavigationID = navigationIdentifier
			refreshCommittedSecuritySnapshot()
			reportSameDocumentVisitIfNeeded(currentURL)
		}
		navigationDidChange?()
	}

	private func refreshCommittedSecuritySnapshot() {
		guard let webView = createdWebView,
		      owns(webView),
		      BrowserSecurityPresentation.canRefreshCommittedSnapshot(
		      	committedURL: committedURL,
		      	webViewURL: webView.url,
		      	committedDocumentID: committedSecurityNavigationID,
		      	currentDocumentID: navigationIdentifier,
		      	isNavigating: awaitsNavigationCommit,
		      	isFailure: navigationFailure != nil
		      )
		else { return }
		guard let committedURL else { return }

		committedHasOnlySecureContent = webView.hasOnlySecureContent
		committedCertificateSummary = webView.serverTrust.flatMap {
			BrowserServerCertificateSummary(trust: $0, committedURL: committedURL)
		}
	}

	private func reportHistoryVisit(_ url: URL, force: Bool) {
		let navigationID = navigationIdentifier
		guard canRecordVisit else { return }
		let shouldReport = force
			? historyVisitPolicy.didCommit(url, navigationID: navigationID)
			: historyVisitPolicy.didChangeSameDocument(to: url, navigationID: navigationID)
		guard shouldReport else { return }
		historyVisitDidCommit?(url, createdWebView?.title ?? url.host ?? url.absoluteString, navigationID)
	}

	private func reportSameDocumentVisitIfNeeded(_ url: URL) {
		reportHistoryVisit(url, force: false)
	}

	private func load(_ request: URLRequest, resetConnectivityRetry: Bool = true) {
		BrowserLog.debug(.navigation, "navigation.dispatch", metadata: ["controller": BrowserLog.id(id), "request": BrowserLog.request(request), "reset_retry": String(resetConnectivityRetry), "content_blocker_ready": String(session.contentBlocking.isReadyForNavigation)])
		guard !isInvalidated else { return }
		pendingWebArchive = nil
		pendingLocalFile = nil
		awaitsNavigationCommit = true
		currentRequest = isAuthenticationSessionBrowser ? nil : request
		failedRequest = nil
		if resetConnectivityRetry {
			retriedAfterConnectivityReturn = false
		}
		guard session.contentBlocking.isReadyForNavigation else {
			pendingRequest = request
			return
		}
		guard let webView = createdWebView else {
			pendingRequest = request
			return
		}
		pendingRequest = nil
		webView.customUserAgent = userAgentOverride(for: request.url)
		guard let navigation = webView.load(request) else {
			currentNavigation = nil
			awaitsNavigationCommit = false
			historyManager.cancelVisit()
			if let requestURL = request.url {
				navigationFailure = BrowserNavigationFailure(kind: .other, url: requestURL)
			}
			navigationDidChange?()
			return
		}
		currentNavigation = navigation
	}

	private func loadPendingRequest() {
		guard session.contentBlocking.isReadyForNavigation else { return }
		if let encrypted = pendingEncryptedInteractionState, createdWebView != nil {
			pendingEncryptedInteractionState = nil
			let startedAt = BrowserLog.clock()
			pendingInteractionState = BrowserRestorationStore.open(encrypted.data, for: encrypted.url)
			BrowserLog.duration(.webKit, "restoration.decrypt", since: startedAt, warnAboveMilliseconds: 30)
		}
		if let state = pendingInteractionState, let webView = createdWebView {
			pendingInteractionState = nil
			liveHistoryPrefix = []
			webView.interactionState = state
			if webView.backForwardList.currentItem != nil {
				pendingRequest = nil
				pendingLocalFile = nil
				updateHistory()
			}
		}
		if let archive = pendingWebArchive, let webView = createdWebView {
			pendingWebArchive = nil
			guard let navigation = webView.load(
				archive.data,
				mimeType: "application/x-webarchive",
				characterEncodingName: "UTF-8",
				baseURL: archive.baseURL
			) else {
				awaitsNavigationCommit = false
				historyManager.cancelVisit()
				navigationFailure = BrowserNavigationFailure(kind: .other, url: archive.baseURL)
				navigationDidChange?()
				return
			}
			currentNavigation = navigation
			navigationDidChange?()
			return
		}
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

	#if os(macOS)
		weak var screenshotReaderWebView: WKWebView?

		func captureScreenshot() async throws -> BrowserScreenshot {
			let view = readerHTML == nil ? createdWebView : screenshotReaderWebView
			guard hasCurrentPageDocument, let view, !view.bounds.isEmpty else {
				throw CocoaError(.coderInvalidValue)
			}
			let documentID = navigationIdentifier
			let wasReader = readerHTML != nil
			let configuration = WKSnapshotConfiguration()
			configuration.rect = view.bounds
			let scale = view.window?.backingScaleFactor ?? 2
			let image = try await view.takeSnapshot(configuration: configuration)
			guard hasCurrentPageDocument, navigationIdentifier == documentID,
			      wasReader == (readerHTML != nil)
			else {
				throw CocoaError(.userCancelled)
			}
			return BrowserScreenshot(image: image, scale: scale)
		}
	#endif

	private func takeSnapshot(snapshotWidth: CGFloat = 180) async -> SnapshotImage? {
		guard !isInvalidated, url != nil, let webView = createdWebView, !webView.bounds.isEmpty else { return nil }
		#if os(macOS)
			guard !isRefreshingPreviewSnapshot else { return nil }
			isRefreshingPreviewSnapshot = true
			defer { isRefreshingPreviewSnapshot = false }
		#endif

		let configuration = WKSnapshotConfiguration()
		configuration.rect = webView.bounds
		configuration.snapshotWidth = NSNumber(value: Double(snapshotWidth))
		return try? await webView.takeSnapshot(configuration: configuration)
	}

	private func capturePageSnapshot(generation: Int) async {
		guard let image = await takeSnapshot(),
		      generation == navigationGeneration,
		      !isInvalidated
		else { return }

		#if os(macOS)
			previewSnapshot = image
			previewSnapshotGeneration = generation
		#endif
	}

	#if os(macOS)
		private func startPreviewSnapshotRefresh() {
			guard previewSnapshotRefreshTask == nil else { return }
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
		if navigationAction.targetFrame?.isMainFrame == true, navigationAction.navigationType == .backForward {
			clearAILinkPreviewCache()
			aiPreviewDismissal += 1
		}
		if navigationAction.targetFrame?.isMainFrame == true,
		   let origin = navigationAction.request.url.flatMap(BrowserSitePermissions.origin(for:)),
		   let contentMode = session.sitePreferences.webKitContentMode(for: origin)
		{
			preferences.preferredContentMode = contentMode
		}
		#if os(macOS)
			preferences.globalPrivacyControlEnabled = Defaults[.globalPrivacyControl]
			let host = navigationAction.request.url?.host?.lowercased() ?? ""
			let isLocal = host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1"
			preferences.preferredHTTPSNavigationPolicy = Defaults[.tryHTTPSFirst] && !isLocal
				&& navigationAction.request.httpMethod == "GET" ? .automaticFallbackToHTTP : .keepAsRequested
		#endif
		if BrowserAuthenticationPolicy.canInterceptCallback(
			isSourceMainFrame: navigationAction.sourceFrame.isMainFrame,
			targetsMainFrame: navigationAction.targetFrame?.isMainFrame == true,
			isNewWindow: navigationAction.targetFrame == nil
		),
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
						historyVisitPolicy.userInitiatedNavigation()
					default:
						break
				}
				switch navigationAction.navigationType {
					case .linkActivated, .formSubmitted, .formResubmitted, .backForward, .reload:
						retriedAfterConnectivityReturn = false
					default:
						break
				}
				currentRequest = isAuthenticationSessionBrowser ? nil : navigationAction.request
				webView.customUserAgent = userAgentOverride(for: navigationAction.request.url)
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
			updateContentBlocking(
				forNavigationDisposition: .allow,
				isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
				destinationURL: navigationAction.request.url,
				in: webView
			)
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
						updateContentBlocking(
							forNavigationDisposition: .cancel,
							isMainFrame: navigationResponse.isForMainFrame,
							destinationURL: navigationResponse.response.url,
							in: webView
						)
						decisionHandler(.cancel)
						return
					}
					prepareDownloadHandoff(in: webView)
					updateContentBlocking(
						forNavigationDisposition: .download,
						isMainFrame: navigationResponse.isForMainFrame,
						destinationURL: navigationResponse.response.url,
						in: webView
					)
					decisionHandler(.download)
				}
				return
			}
			prepareDownloadHandoff(in: webView)
			updateContentBlocking(
				forNavigationDisposition: .download,
				isMainFrame: navigationResponse.isForMainFrame,
				destinationURL: navigationResponse.response.url,
				in: webView
			)
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

	func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
		guard owns(webView), navigation === currentNavigation, awaitsNavigationCommit else { return }
		updateContentBlocking(
			forNavigationDisposition: .redirect,
			isMainFrame: true,
			destinationURL: nil,
			in: webView
		)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		guard owns(webView) else { return }
		refreshContentBlocking(for: committedURL ?? webView.url)
		handleNavigationFailure(navigation, error: error)
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		guard owns(webView) else { return }
		refreshContentBlocking(for: committedURL ?? webView.url)
		handleNavigationFailure(navigation, error: error)
	}

	private func handleNavigationFailure(_ navigation: WKNavigation!, error: Error) {
		BrowserLog.error(.navigation, "navigation.failure.callback", metadata: ["controller": BrowserLog.id(id), "error": BrowserLog.errorDescription(error), "url": BrowserLog.url(url)])
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
		failedRequest = isAuthenticationSessionBrowser ? nil : currentRequest
		if let failedURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url {
			navigationFailure = BrowserNavigationFailure(error: error, url: failedURL)
		}
	}

	private func retryOfflineGETAfterConnectivityReturns() {
		guard !isInvalidated,
		      !isAuthenticationSessionBrowser,
		      createdWebView != nil,
		      !retriedAfterConnectivityReturn,
		      navigationFailure?.kind == .offline || navigationFailure?.kind == .connectionLost,
		      let request = failedRequest,
		      BrowserNavigationFailure.canRetryAutomatically(request)
		else { return }
		retriedAfterConnectivityReturn = true
		load(request, resetConnectivityRetry: false)
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		BrowserLog.fault(.webKit, "webcontent.terminated", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(webView.url ?? url)])
		guard owns(webView) else { return }
		resetReader()
		pictureInPictureControlUnavailable = false
		canEnterPictureInPicture = false
		isEnteringPictureInPicture = false
		setPictureInPictureActive(false)
		guard let url = webView.url ?? url else { return }
		let kind: BrowserNavigationFailure.Kind = contentProcessTerminations.record(url)
			? .repeatedWebContentTermination
			: .webContentTerminated
		navigationFailure = BrowserNavigationFailure(kind: kind, url: url)
	}

	func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		navigationLogStartedAt = BrowserLog.clock()
		BrowserLog.info(.navigation, "navigation.did-start", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(webView.url ?? url)])
		guard owns(webView) else { return }
		resetReader()
		clearHoveredLink()
		invalidateFindResults()
		if isPictureInPictureActive || isEnteringPictureInPicture {
			webView.closeAllMediaPresentations(completionHandler: nil)
		}
		setPictureInPictureActive(false)
		isEnteringPictureInPicture = false
		canEnterPictureInPicture = false
		isZapping = false
		isPlayingMedia = false
		hasActiveVideoPlayback = false
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
		refreshContentBlocking(for: committedURL ?? createdWebView?.url)
		navigationDidChange?()
	}

	func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
		BrowserLog.info(.navigation, "navigation.did-commit", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(webView.url)])
		guard owns(webView), navigation === currentNavigation else { return }
		// The document can change without changing origins (reloads and
		// same-site links). Preview text from the previous page must not
		// survive a successful main-frame navigation.
		clearAILinkPreviewCache()
		releaseUploadAccess()
		pictureInPictureControlUnavailable = false
		committedURL = webView.url
		refreshContentBlocking(for: committedURL)
		committedSecurityNavigationID = navigationIdentifier
		if let origin = committedURL.flatMap(BrowserSitePermissions.origin(for:)) {
			let isRestoredOrigin = restoredPageZoomOrigin == origin
			restoredPageZoomOrigin = nil
			if let zoom = session.sitePreferences.zoom(for: origin) {
				applySiteZoom(zoom)
			} else if !isRestoredOrigin {
				applySiteZoom(Defaults[.defaultPageZoom])
			}
		} else {
			restoredPageZoomOrigin = nil
		}
		automaticDownloadPolicy.didCommitDocument()
		contentProcessTerminations.navigationCommitted(at: webView.url)
		hasUnsavedChanges = false
		isDownloadHandoff = false
		pageURLBeforeDownload = nil
		navigationFailure = nil
		awaitsNavigationCommit = false
		refreshCommittedSecuritySnapshot()
		updateHistory(reportSameDocumentVisit: false)
		if let url = committedURL {
			reportHistoryVisit(url, force: true)
		}
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		if let navigationLogStartedAt {
			BrowserLog.duration(.navigation, "navigation.did-finish", since: navigationLogStartedAt, warnAboveMilliseconds: 1500, metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(webView.url)])
			self.navigationLogStartedAt = nil
		} else {
			BrowserLog.info(.navigation, "navigation.did-finish", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(webView.url)])
		}
		guard owns(webView), navigation === currentNavigation else { return }
		refreshContentBlocking(for: webView.url)
		webView.evaluateJavaScript("globalThis.astraProbeReader?.(true)", in: nil, in: .defaultClient, completionHandler: nil)
		updateHistory()
		if showsFind, !findText.isEmpty {
			findNext()
		}
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
		if message.name == "readerAvailabilityChanged" {
			guard message.frameInfo.isMainFrame, let webView = message.webView,
			      owns(webView), hasCurrentPageDocument, navigationFailure == nil,
			      let value = message.body as? [String: Any],
			      let pageURL = value["url"] as? String, pageURL == webView.url?.absoluteString,
			      let available = value["available"] as? Bool else { return }
			isReaderAvailable = available
			return
		}
		if message.name == "linkHoverChanged" {
			if let value = message.body as? [String: Any], value["dismissPreview"] as? Bool == true,
			   let webView = message.webView, owns(webView)
			{
				aiPreviewDismissal += 1
				return
			}
			guard !awaitsNavigationCommit, let webView = message.webView,
			      owns(webView), !webView.isHidden,
			      let value = message.body as? [String: Any],
			      let href = value["href"] as? String else { return }
			guard !href.isEmpty, href.utf8.count <= 16384, let url = URL(string: href) else {
				clearHoveredLink()
				return
			}
			hoveredLinkURL = BrowserAddress.withoutCredentials(url)
			hoveredLinkUsesTrailingCorner = value["trailing"] as? Bool == true
			if message.frameInfo.isMainFrame,
			   let x = value["x"] as? Double, let y = value["y"] as? Double,
			   let width = value["width"] as? Double, let height = value["height"] as? Double,
			   [x, y, width, height].allSatisfy(\.isFinite), width >= 0, height >= 0
			{
				hoveredLinkRect = CGRect(x: x, y: y, width: width, height: height)
				hoveredLinkID = value["id"] as? String ?? ""
				hoveredLinkShiftPressed = value["shift"] as? Bool == true
			} else {
				hoveredLinkID = ""
			}

			return
		}
		if message.name == "pageActivityChanged" {
			guard let activity = message.body as? String else { return }
			switch activity {
				case "dirty":
					hasUnsavedChanges = true
					scrollPositionDidChange?()
				case "submitted":
					scrollPositionDidChange?()
				case "media-changed":
					Task { @MainActor [weak self] in
						await self?.refreshActivity()
					}
				default: break
			}
			return
		}
		if message.name == "pictureInPictureChanged", message.frameInfo.isMainFrame,
		   let webView = createdWebView
		{
			let documentID = navigationIdentifier
			Task { @MainActor [weak self, weak webView] in
				guard let self, let webView, owns(webView), documentID == navigationIdentifier else { return }
				await refreshPictureInPictureEligibility(in: webView, documentID: documentID)
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
	#if os(macOS)
		@objc(_webViewFullscreenMayReturnToInline:)
		func webViewFullscreenMayReturnToInline(_ webView: WKWebView) {
			guard owns(webView) else { return }
			returnToPictureInPictureSource()
		}
	#endif

	#if os(iOS)
		func webView(
			_ webView: WKWebView,
			contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
			completionHandler: @escaping @MainActor @Sendable (UIContextMenuConfiguration?) -> Void
		) {
			guard owns(webView), hasCurrentPageDocument, !isLoading else {
				completionHandler(nil)
				return
			}
			let documentID = navigationIdentifier
			if let linkURL = safeContextLink(elementInfo.linkURL) {
				completionHandler(contextMenuConfiguration(
					for: webView,
					documentID: documentID,
					linkURL: linkURL,
					selectedText: nil
				))
				return
			}
			webView.evaluateJavaScript("window.getSelection().toString()") { [weak self, weak webView] result, _ in
				guard let self, let webView,
				      owns(webView),
				      hasCurrentPageDocument,
				      !isLoading,
				      navigationIdentifier == documentID
				else {
					completionHandler(nil)
					return
				}
				let selectedText = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
				completionHandler(contextMenuConfiguration(
					for: webView,
					documentID: documentID,
					linkURL: nil,
					selectedText: selectedText.flatMap { $0.utf8.count <= 8192 && !$0.isEmpty ? $0 : nil }
				))
			}
		}

		private func safeContextLink(_ url: URL?) -> URL? {
			guard let url,
			      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
			      let destination = BrowserAddress.destination(for: url.absoluteString),
			      destination.scheme?.lowercased() == url.scheme?.lowercased()
			else { return nil }
			return destination
		}

		private func contextMenuConfiguration(
			for webView: WKWebView,
			documentID: Int,
			linkURL: URL?,
			selectedText: String?
		) -> UIContextMenuConfiguration {
			UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self, weak webView] suggestedActions in
				guard let self, let webView else { return UIMenu(children: suggestedActions) }
				var actions = suggestedActions
				if let linkURL {
					actions += [
						UIAction(title: "Open Link", image: UIImage(systemName: "arrow.up.right.square")) { [weak self, weak webView] _ in
							guard let self, let webView, ownsPrompt(in: webView, documentID: documentID) else { return }
							load(linkURL)
						},
						UIAction(title: "Open Link in New Tab", image: UIImage(systemName: "plus.square.on.square")) { [weak self, weak webView] _ in
							guard let self, let webView, ownsPrompt(in: webView, documentID: documentID) else { return }
							newTabRequested?(URLRequest(url: linkURL), false)
						},
						UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { [weak self, weak webView] _ in
							guard let self, let webView, ownsPrompt(in: webView, documentID: documentID) else { return }
							UIPasteboard.general.url = BrowserAddress.withoutCredentials(linkURL)
						},
						UIAction(title: "Download Link", image: UIImage(systemName: "arrow.down.to.line")) { [weak self, weak webView] _ in
							guard let self, let webView else { return }
							Task { @MainActor [weak self, weak webView] in
								guard let self, let webView else { return }
								await downloadContextLink(linkURL, in: webView, documentID: documentID)
							}
						},
					]
				} else if let selectedText {
					actions.append(UIAction(title: "Search Selection", image: UIImage(systemName: "magnifyingglass")) { [weak self, weak webView] _ in
						guard let self, let webView else { return }
						Task { @MainActor [weak self, weak webView] in
							guard let self, let webView,
							      ownsPrompt(in: webView, documentID: documentID),
							      let url = BrowserSearchConfiguration.decode(Defaults[.browserSearchConfiguration])
							      .destination(for: selectedText, isPrivate: session.isPrivate)
							else { return }
							newTabRequested?(URLRequest(url: url), false)
						}
					})
				}
				return UIMenu(children: actions)
			}
		}

		private func downloadContextLink(_ url: URL, in webView: WKWebView, documentID: Int) async {
			guard ownsPrompt(in: webView, documentID: documentID) else { return }
			if automaticDownloadPolicy.reserveAttempt() {
				guard await requestMultipleDownloadPermission(in: webView) == .grant,
				      ownsPrompt(in: webView, documentID: documentID)
				else { return }
			}
			guard ownsPrompt(in: webView, documentID: documentID) else { return }
			let sourceURL = committedURL ?? webView.url
			webView.startDownload(using: URLRequest(url: url)) { [weak self, weak webView] download in
				guard let self, let webView,
				      ownsPrompt(in: webView, documentID: documentID)
				else {
					Task { @MainActor in
						_ = await download.cancel()
					}
					return
				}
				session.downloads.start(download, sourceURL: sourceURL)
			}
		}
	#endif

	func webView(
		_ webView: WKWebView,
		createWebViewWith configuration: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures _: WKWindowFeatures
	) -> WKWebView? {
		guard owns(webView) else { return nil }
		if BrowserAuthenticationPolicy.canInterceptCallback(
			isSourceMainFrame: navigationAction.sourceFrame.isMainFrame,
			targetsMainFrame: navigationAction.targetFrame?.isMainFrame == true,
			isNewWindow: navigationAction.targetFrame == nil
		),
			let destination = navigationAction.request.url,
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
			return createPopupWebView(configuration, source: source, inBackground: inBackground)
		}
		if permission == .allowAlways || permission == .allowOnce {
			return createPopupWebView(configuration, source: source, inBackground: inBackground)
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

	private func createPopupWebView(
		_ configuration: WKWebViewConfiguration,
		source: UnitPoint,
		inBackground: Bool?
	) -> WKWebView? {
		guard let popup = popupRequested?(configuration, source, inBackground) else { return nil }
		if isAuthenticationSessionBrowser,
		   let controller = popup.navigationDelegate as? BrowserController
		{
			controller.isAuthenticationSessionBrowser = true
		}
		return popup
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
		isExplicitAddressRequest: Bool = false,
		in webView: WKWebView
	) -> Bool {
		guard let scheme = BrowserAddress.externalApplicationScheme(for: url) else { return false }
		let documentID = navigationIdentifier
		#if os(macOS)
			let explicitOwner: BrowserAddressPromptOwner?
			if isExplicitAddressRequest {
				guard requestingOrigin == nil,
				      let owner = Self.addressPromptOwner?(self, webView, documentID),
				      ownsExplicitAddressPrompt(in: webView, documentID: documentID, owner: owner)
				else { return true }
				explicitOwner = owner
			} else {
				guard ownsPrompt(in: webView, documentID: documentID) else { return true }
				explicitOwner = nil
			}
		#else
			guard ownsPrompt(in: webView, documentID: documentID) else { return true }
		#endif
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
			isOpeningExternalApplication = true
			Task { @MainActor [weak self, weak webView] in
				guard let webView, self?.owns(webView) == true else { return }
				defer { self?.isOpeningExternalApplication = false }
				let promptWindow: NSWindow
				let promptOwnerIsCurrent: @MainActor () -> Bool
				if let explicitOwner {
					guard self?.ownsExplicitAddressPrompt(in: webView, documentID: documentID, owner: explicitOwner) == true else { return }
					promptWindow = explicitOwner.window
					promptOwnerIsCurrent = { [weak self, weak webView] in
						guard let self, let webView else { return false }
						return self.ownsExplicitAddressPrompt(in: webView, documentID: documentID, owner: explicitOwner)
					}
				} else {
					guard let window = webView.window else { return }
					promptWindow = window
					promptOwnerIsCurrent = { [weak self, weak webView] in
						guard let self, let webView else { return false }
						return self.ownsPrompt(in: webView, documentID: documentID)
					}
				}
				let alert = BrowserWebsiteUI.alert(
					title: "Open \(applicationName)?",
					message: "\(requestingSiteLabel) wants to open a \(scheme) link in \(applicationName).",
					confirm: "Open Application"
				)
				let response = await BrowserWebsiteUI.present(alert, in: promptWindow, isCurrent: promptOwnerIsCurrent)
				guard promptOwnerIsCurrent(),
				      response == .alertFirstButtonReturn else { return }
				self?.lastExternalApplicationRequestTime = ProcessInfo.processInfo.systemUptime
				let configuration = NSWorkspace.OpenConfiguration()
				configuration.addsToRecentItems = false
				do {
					_ = try await NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration)
				} catch {
					self?.session.toastManager.show(symbol: "exclamationmark.triangle", message: "\(applicationName) could not open this link")
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
