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

#endif

@MainActor
@Observable
final class BrowserController: NSObject, Identifiable {
	#if os(macOS)
		var hasDockedWebInspector = false
	#endif
	#if os(macOS)
		static func logReclamation(for before: BrowserTabProcessMemorySnapshot) async -> BrowserMemoryReclamationSnapshot {
			try? await Task.sleep(for: .seconds(2))
			let sampled = await BrowserTabProcessMemorySnapshot.resample(before.processes)
			func after(_ process: BrowserTabProcessMemorySnapshot.Process?) -> BrowserTabProcessMemorySnapshot.Process? {
				guard let process else { return nil }
				return sampled[process.identity]
			}
			let afterSnapshot: BrowserTabProcessMemorySnapshot? = {
				let webContent = after(before.webContent)
				let graphics = after(before.graphics)
				let network = after(before.network)
				let model = after(before.model)
				guard webContent != nil || graphics != nil || network != nil || model != nil else { return nil }
				return BrowserTabProcessMemorySnapshot(webContent: webContent, graphics: graphics, network: network, model: model)
			}()
			let result = BrowserMemoryReclamationSnapshot(before: before, after: afterSnapshot)
			BrowserLog.info(.diagnostics, "webkit.memory.reclamation", metadata: [
				"before_bytes": result.beforeObservedBytes.map(String.init) ?? "unavailable",
				"after_bytes": result.afterObservedBytes.map(String.init) ?? "unavailable",
				"identity_changed": String(result.processIdentityChanged),
				"unavailable_processes": String(result.unavailableProcessCount),
			])
			return result
		}

		static func tabProcessMemorySnapshots(for controllers: [BrowserController]) async -> [UUID: BrowserTabProcessMemorySnapshot] {
			struct Request {
				let controller: BrowserController
				let webView: WKWebView
				let generation: Int
				let webContentPID: pid_t?
				let graphicsPID: pid_t?
				let networkPID: pid_t?
				let modelPID: pid_t?
			}

			let requests = controllers.compactMap { controller -> Request? in
				guard let webView = controller.createdWebView, controller.owns(webView) else { return nil }
				return Request(
					controller: controller,
					webView: webView,
					generation: controller.navigationGeneration,
					webContentPID: privateProcessIdentifier("_webProcessIdentifier", on: webView),
					graphicsPID: privateProcessIdentifier("_gpuProcessIdentifier", on: webView),
					networkPID: privateProcessIdentifier("_networkProcessIdentifier", on: webView.configuration.websiteDataStore),
					modelPID: privateProcessIdentifier("_modelProcessIdentifier", on: webView)
				)
			}
			let processIDs = Set(requests.flatMap { [$0.webContentPID, $0.graphicsPID, $0.networkPID, $0.modelPID].compactMap(\.self) })
			guard !processIDs.isEmpty else { return [:] }
			let sampled = await Task.detached(priority: .utility) {
				Self.sampleProcessMemory(for: Array(processIDs))
			}.value
			var result: [UUID: BrowserTabProcessMemorySnapshot] = [:]
			for request in requests {
				guard request.controller.owns(request.webView), request.generation == request.controller.navigationGeneration,
				      privateProcessIdentifier("_webProcessIdentifier", on: request.webView) == request.webContentPID,
				      privateProcessIdentifier("_gpuProcessIdentifier", on: request.webView) == request.graphicsPID,
				      privateProcessIdentifier("_networkProcessIdentifier", on: request.webView.configuration.websiteDataStore) == request.networkPID,
				      privateProcessIdentifier("_modelProcessIdentifier", on: request.webView) == request.modelPID
				else { continue }
				let snapshot = BrowserTabProcessMemorySnapshot(
					webContent: request.webContentPID.flatMap { sampled[$0] },
					graphics: request.graphicsPID.flatMap { sampled[$0] },
					network: request.networkPID.flatMap { sampled[$0] },
					model: request.modelPID.flatMap { sampled[$0] }
				)
				guard snapshot.knownProcessBytes != nil else { continue }
				result[request.controller.id] = snapshot
			}
			return result
		}

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
	private(set) var isInvalidated = false
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
	@ObservationIgnored
	var easelQuoteDestinations: (() -> [BrowserEaselQuoteDestination])?
	@ObservationIgnored
	var addQuoteToEasel: ((UUID, BrowserEaselQuote) -> Void)?
	@ObservationIgnored
	var easelQuoteHighlight: BrowserEaselQuote?
	var closeRequested: (() -> Void)?
	@ObservationIgnored
	var promptOwnership: ((WKWebView) -> Bool)?
	@ObservationIgnored
	private var isOpeningExternalApplication = false
	@ObservationIgnored
	private var pendingLifecycleOperations = 0
	private let livePopupControllers = NSHashTable<BrowserController>.weakObjects()
	@ObservationIgnored
	// ponytail: controller-wide two-second throttle; per-origin limits if abuse becomes measurable.
	private var lastExternalApplicationRequestTime: TimeInterval?
	@ObservationIgnored
	var navigationIntercept: ((URL) -> Bool)?
	/// Saved website snapshots retain their local document and cannot open destinations.
	@ObservationIgnored
	var snapshotNavigationOnly = false
	@ObservationIgnored
	var snapshotSourceURL: URL?
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
		      !hasLivePopupDependency,
		      !isPreparingReader,
		      pendingRequest == nil,
		      !awaitsNavigationCommit,
		      canHibernate, createdWebView == nil || displayCaptureState == false else { return false }
		#if os(macOS)
			guard unsafe createdWebView?.window?.attachedSheet == nil else { return false }
		#endif
		return true
	}

	private var hasLivePopupDependency: Bool {
		livePopupControllers.allObjects.contains { $0.isWebViewReady && $0.webViewIfLoaded != nil }
	}

	func beginLifecycleOperation() {
		pendingLifecycleOperations += 1
	}

	func endLifecycleOperation() {
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

	/// An inactive page stays attached while WebKit reports activity that a
	/// detached host could interrupt. Ordinary retained pages can be detached
	/// by BrowserWebView without rebuilding their WebView.
	var shouldKeepWebViewAttached: Bool {
		requiresMediaTeardownConfirmation
			|| isCapturing
			|| isLoading
			|| hasUnsavedChanges
			|| pendingLifecycleOperations > 0
			|| hasLivePopupDependency
			|| isOpeningExternalApplication
			|| displayCaptureState == true
	}

	private static var cachedSafariUserAgentSuffix: String?
	@ObservationIgnored
	private var isApplyingSiteZoom = false
	private var appliedContentRuleLists: [WKContentRuleList] = []

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
	private static let pageTintMessageName = "pageTintChanged"
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
			if (document.hidden || window.scrollY < 0 || innerWidth <= 0) return;

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
			if (document.hidden || scheduled) return;
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
		const observer = new MutationObserver(scheduleMutation);
		const updateVisibility = () => {
			observer.disconnect();
			if (document.hidden) return;
			observer.observe(document.documentElement, {
				subtree: true,
				childList: true,
				attributes: true,
				attributeFilter: ['class', 'style', 'hidden', 'id', 'role']
			});
			schedule(true);
		};
		document.addEventListener('visibilitychange', updateVisibility);
		updateVisibility();
	})();
	"""

	/// Live, bounded page-surface sampling inspired by Safari 26's edge tinting.
	/// Runs in WebKit, not on the app's main actor. No network calls or image decoding.
	private static let pageTintScript = #"""
	(() => {
		if (globalThis.__astraPageTintInstalled) return;
		globalThis.__astraPageTintInstalled = true;
		const canvas = document.createElement('canvas');
		canvas.width = canvas.height = 1;
		const context = canvas.getContext('2d', { willReadFrequently: true });
		if (!context) return;
		const cache = new Map(), gradients = new Map();
		const header = 'header, nav, [role="banner"], [role="navigation"], ' +
			'[class*="header" i], [id*="header" i], [class*="navbar" i], [id*="navbar" i]';
		let queued = false, loaded = false, sampled = false;
		const pixels = css => {
			if (cache.has(css)) return cache.get(css);
			let rgba = null;
			if (css && css !== 'transparent') {
				try {
					if (globalThis.CSS?.supports && !CSS.supports('color', css)) return null;
					context.clearRect(0, 0, 1, 1);
					context.fillStyle = '#010203';
					context.fillStyle = css;
					// Canvas silently ignores unrecognised CSS colours.
					if (context.fillStyle === '#010203' && !/^(#010203|rgb\(1,\s*2,\s*3\))$/i.test(css.trim()))
						return null;
					context.fillRect(0, 0, 1, 1);
					rgba = Array.from(context.getImageData(0, 0, 1, 1).data);
				} catch (_) {}
			}
			// Animations can create arbitrarily many CSS values; bound both caches.
			if (cache.size >= 128) cache.clear();
			cache.set(css, rgba);
			return rgba;
		};
		// Inspired by Chromalift's gradient parsing, but only examines a hit-tested
		// surface. No document-wide palette crawl or screenshot readback.
		const split = value => {
			let depth = 0, start = 0;
			const parts = [];
			for (let i = 0; i < value.length; i++) {
				if (value[i] === '(') depth++;
				else if (value[i] === ')') depth--;
				else if (value[i] === ',' && depth === 0) {
					parts.push(value.slice(start, i).trim());
					start = i + 1;
				}
			}
			parts.push(value.slice(start).trim());
			return parts;
		};
		const gradient = css => {
			if (gradients.has(css)) return gradients.get(css);
			let result = null;
			const match = /^(?:repeating-)?linear-gradient\((.*)\)$/is.exec(css);
			if (match && !css.includes('url(')) {
				let stops = split(match[1]), angle = 180;
				if (/^to (top|bottom|left|right)/i.test(stops[0])) {
					const dir = stops.shift().toLowerCase();
					if (dir.includes('top') && dir.includes('right')) angle = 45;
					else if (dir.includes('bottom') && dir.includes('right')) angle = 135;
					else if (dir.includes('bottom') && dir.includes('left')) angle = 225;
					else if (dir.includes('top') && dir.includes('left')) angle = 315;
					else if (dir.includes('top')) angle = 0;
					else if (dir.includes('right')) angle = 90;
					else if (dir.includes('left')) angle = 270;
				} else if (/^-?[\d.]+deg$/i.test(stops[0])) {
					angle = Number(stops.shift().slice(0, -3));
				} else if (/^-?[\d.]+turn$/i.test(stops[0])) {
					angle = Number(stops.shift().slice(0, -4)) * 360;
				}
				const parsed = stops.map(stop => {
					const color = /^(#[\da-f]{3,8}|(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\([^)]*\)|[a-z-]+)/i.exec(stop);
					if (!color) return null;
					const rgba = pixels(color[1]);
					if (!rgba || rgba[3] === 0) return null;
					const position = /^\s*(\d+(?:\.\d+)?)%/.exec(stop.slice(color[0].length));
					return { rgba, position: position ? Number(position[1]) / 100 : null };
				});
				if (parsed.length >= 2 && parsed.length <= 8 && parsed.every(Boolean)) {
					parsed[0].position ??= 0;
					parsed[parsed.length - 1].position ??= 1;
					// Distribute implicit CSS stop positions between fixed positions.
					for (let i = 1; i < parsed.length - 1; i++) {
						if (parsed[i].position !== null) continue;
						let next = i + 1;
						while (next < parsed.length && parsed[next].position === null) next++;
						for (let n = i; n < next; n++)
							parsed[n].position = parsed[i - 1].position +
								(parsed[next].position - parsed[i - 1].position) * (n - i + 1) / (next - i + 1);
						i = next - 1;
					}
					result = { stops: parsed, radians: angle * Math.PI / 180 };
				}
			}
			if (gradients.size >= 32) gradients.clear();
			gradients.set(css, result);
			return result;
		};
		const gradientPixel = (css, rect, x, y) => {
			const parsed = gradient(css);
			if (!parsed || rect.width <= 0 || rect.height <= 0) return null;
			const dx = (x - rect.left) / rect.width - .5;
			const dy = (y - rect.top) / rect.height - .5;
			const t = Math.max(0, Math.min(1, .5 +
				dx * Math.sin(parsed.radians) - dy * Math.cos(parsed.radians)));
			let left = parsed.stops[0], right = parsed.stops[parsed.stops.length - 1];
			for (let i = 1; i < parsed.stops.length; i++) {
				if (t <= parsed.stops[i].position) {
					left = parsed.stops[i - 1]; right = parsed.stops[i]; break;
				}
			}
			const ratio = Math.max(0, Math.min(1,
				(t - left.position) / (right.position - left.position || 1)));
			return left.rgba.map((channel, i) => Math.round(channel +
				(right.rgba[i] - channel) * ratio));
		};
		const sample = (x, y, layoutCache) => {
			let element = document.elementFromPoint(x, y);
			let edge = false, gradientAnchor = null, covered = 0;
			const mixed = [0, 0, 0];
			for (let depth = 0; element && depth < 14; depth++, element = element.parentElement) {
				let layout = layoutCache.get(element);
				if (!layout) {
					// Defer layout reads until a genuinely painted ancestor is found.
					layout = { style: getComputedStyle(element), rect: null };
					layoutCache.set(element, layout);
				}
				const { style } = layout;
				if (style.visibility === 'hidden') return null;
				const opacity = Number(style.opacity);
				if (opacity < .01) continue;
				const image = style.backgroundImage;
				let rgba = pixels(style.backgroundColor);
				if (image && image !== 'none') {
					// A background image cannot be faithfully inferred from CSS.
					// A simple CSS linear gradient can be sampled analytically.
					layout.rect ??= element.getBoundingClientRect();
					rgba = gradientPixel(image, layout.rect, x, y);
					if (!rgba) return null;
					gradientAnchor ??= element;
				}
				if (!rgba || rgba[3] === 0) continue;
				layout.rect ??= element.getBoundingClientRect();
				const rect = layout.rect;
				if (element !== document.body && element !== document.documentElement &&
					rect.width >= innerWidth * .7 && rect.height >= 10 &&
					rect.height <= 260 && rect.top <= 8 && rect.bottom >= y &&
					(element.matches(header) || style.position === 'fixed' ||
					 style.position === 'sticky' || rect.width >= innerWidth * .9)) edge = true;
				// CSS opacity applies to the entire layer, not just its fill.
				// Exact compositing of nested opacity groups requires rendering;
				// this bounded estimate avoids treating a faded bar as opaque.
				const contribution = (rgba[3] / 255) * (Number.isFinite(opacity) ? opacity : 1) * (1 - covered);
				for (let channel = 0; channel < 3; channel++)
					mixed[channel] += rgba[channel] * contribution;
				covered += contribution;
				if (covered >= .98)
					return { color: mixed.map(v => Math.round(v / covered)), edge, gradientAnchor };
			}
			return null;
		};
		// Chromalift-style perceptual clustering: DeltaE groups adjacent shades
		// across RGB bucket boundaries without enumerating the page's palette.
		const lab = rgb => {
			const [r, g, b] = rgb.map(channel => {
				const c = channel / 255;
				return c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4;
			});
			const x = (.4124564 * r + .3575761 * g + .1804375 * b) / .95047;
			const y = .2126729 * r + .7151522 * g + .0721750 * b;
			const z = (.0193339 * r + .1191920 * g + .9503041 * b) / 1.08883;
			const f = v => v > .008856 ? Math.cbrt(v) : 7.787 * v + 16 / 116;
			const fx = f(x), fy = f(y), fz = f(z);
			return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
		};
		const add = (groups, item) => {
			const colourLab = item.gradientAnchor ? null : lab(item.color);
			let group = groups.find(candidate =>
				item.gradientAnchor
					? candidate.anchor === item.gradientAnchor
					: !candidate.anchor && candidate.lab.every((value, index) =>
						Math.abs(value - colourLab[index]) <= 12) &&
					  Math.hypot(...candidate.lab.map((value, index) =>
						  value - colourLab[index])) <= 12
			);
			if (!group) {
				group = { count: 0, sum: [0, 0, 0], anchor: item.gradientAnchor, lab: colourLab };
				groups.push(group);
			}
			group.count++;
			for (let i = 0; i < 3; i++) group.sum[i] += item.color[i];
			if (colourLab && group.count > 1)
				for (let i = 0; i < 3; i++)
					group.lab[i] += (colourLab[i] - group.lab[i]) / group.count;
		};
		const winner = groups => groups.reduce((best, candidate) =>
			!best || candidate.count > best.count ? candidate : best, null);
		// OpenBrand's secondary branding metadata and CSS brand tokens can help
		// when a page provides no reliable visible surface or WebKit theme.
		// Never let them override painted page chrome or native theme-color.
		const brand = () => {
			const meta = document.querySelector?.('meta[name="msapplication-TileColor" i]');
			let rgba = pixels(meta?.content);
			if (rgba && rgba[3] === 255) return rgba.slice(0, 3);
			for (const root of [document.documentElement, document.body]) {
				if (!root) continue;
				const style = getComputedStyle(root);
				if (!style) continue;
				for (const key of [
					'--theme-color', '--brand-color', '--color-brand', '--primary-color',
					'--color-primary', '--accent-color', '--color-accent'
				]) {
					rgba = pixels(style.getPropertyValue?.(key)?.trim());
					if (rgba && rgba[3] === 255) return rgba.slice(0, 3);
				}
			}
			return null;
		};
		const run = () => {
			// One colour extraction per document. Full navigations install
			// a new user script; scroll, SPA mutations and CSS changes do not.
			if (sampled || document.hidden) return;
			sampled = true;
			if (innerWidth < 80 || innerHeight < 20) return;
			const edges = [], surfaces = [], layoutCache = new Map();
			const rows = [3, 16, 34, 56].filter(y => y < innerHeight);
			const scan = columns => {
				for (const y of rows) for (const i of columns) {
					const item = sample(innerWidth * (i + .5) / 10, y, layoutCache);
					if (!item) continue;
					add(item.edge ? edges : surfaces, item);
				}
			};
			// Sample 16 uniformly distributed points first. Only take the
			// remaining 24 of the original grid when the result is uncertain.
			scan([1, 4, 5, 8]);
			let total = rows.length * 4;
			let chrome = winner(edges), body = winner(surfaces);
			if (Math.max(chrome?.count ?? 0, body?.count ?? 0) < total * .75) {
				scan([0, 2, 3, 6, 7, 9]);
				total = rows.length * 10;
				chrome = winner(edges);
				body = winner(surfaces);
			}
			const selected = chrome && chrome.count >= total * .45
				? { count: chrome, source: 'chrome' }
				: body && body.count >= total * .5
				? { count: body, source: 'surface' } : null;
			const fallback = selected ? null : brand();
			const rgb = selected
				? selected.count.sum.map(value => Math.round(value / selected.count.count))
				: fallback;
			const source = selected?.source || (fallback ? 'brand' : 'none');
			window.webkit.messageHandlers.pageTintChanged.postMessage({ url: location.href, source, rgb });
		};
		const schedule = () => {
			if (!loaded || queued || sampled || document.hidden) return;
			queued = true;
			// The single extraction yields to page paint and user input.
			const execute = () => {
				queued = false;
				run();
			};
			if (typeof requestIdleCallback === 'function')
				requestIdleCallback(execute, { timeout: 1200 });
			else
				setTimeout(execute, 0);
		};
		const onLoad = () => {
			loaded = true;
			schedule();
		};
		// At documentEnd, wait for stylesheet/image load completion.
		// Documents that already loaded (e.g. restored) execute once.
		if (document.readyState === 'complete')
			onLoad();
		else
			addEventListener('load', onLoad, { once: true });
		// A background tab loaded while hidden is sampled only when
		// first shown; it is never sampled again after that.
		document.addEventListener('visibilitychange', () => {
			if (!document.hidden) schedule();
		});
	})();
	"""#
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
	@ObservationIgnored
	private var encounteredProxyAuthentication = false
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
	@ObservationIgnored private var sampledChromeColor: PlatformColor?
	@ObservationIgnored private var sampledSurfaceColor: PlatformColor?
	@ObservationIgnored private var sampledBrandColor: PlatformColor?
	@ObservationIgnored private var sampledFaviconColor: PlatformColor?
	@ObservationIgnored private var pageTintHandledGeneration: Int?
	@ObservationIgnored private var faviconTintTask: Task<Void, Never>?
	@ObservationIgnored private var faviconTintAttemptedGeneration: Int?
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

	var hasRenderedWebView: Bool {
		!isInvalidated && createdWebView != nil
	}

	var canApplySitePreferencesToCurrentPage: Bool {
		hasCurrentPageDocument && navigationFailure == nil
	}

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
		document.addEventListener('drop', event => {
			if (event.isTrusted && event.dataTransfer?.files?.length) report('dirty');
		}, true);
		document.addEventListener('pointerdown', event => {
			if (event.isTrusted && event.target.closest?.('canvas')) report('dirty');
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
				let hasActivity = self?.isPlayingMedia == true
					|| self?.isCapturing == true
					|| self?.isPictureInPictureActive == true
					|| self?.isEnteringPictureInPicture == true
				let isDetached = unsafe self?.createdWebView?.window == nil
				#if os(macOS)
					let isBackground = isDetached || self?.previewSnapshotRefreshSuspended == true
				#else
					let isBackground = isDetached
				#endif
				// Do not wake an idle background page merely to rediscover inactivity.
				if !isBackground || hasActivity {
					await self?.refreshActivity()
				}
				guard !Task.isCancelled else { return }
				let fallbackInterval: TimeInterval = if hasActivity {
					5
				} else if isBackground {
					90
				} else {
					20
				}
				do {
					try await Task.sleep(for: .seconds(fallbackInterval))
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
				audible: media.some(element => !element.paused && !element.ended && element.readyState >= 2 && !element.muted && element.volume > 0),
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
		      let audible = state["audible"] as? Bool,
		      let paused = state["paused"] as? Bool,
		      let title = state["title"] as? String,
		      let artist = state["artist"] as? String
		else { return false }
		let playbackState = await webView.requestMediaPlaybackState()
		guard owns(webView), documentID == navigationIdentifier else { return false }
		// A muted looping background video is not a Now Playing session. WebKit's
		// aggregate playback state also includes silent page decoration; use the
		// element state to disambiguate, while retaining cross-origin iframe audio.
		isPlayingMedia = audible || (!playing && playbackState == .playing)
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
		guard owns(webView), documentID == navigationIdentifier else { return false }
		// pictureInPictureScript reports eligibility/active changes directly on
		// video lifecycle events; do not run a second DOM query on every poll.
		updateInactiveSchedulingPolicy()
		return true
	}

	func refreshHibernationSafety() async -> Bool {
		guard await refreshActivity(), canAutomaticallyHibernate,
		      let webView = createdWebView else { return false }
		let documentID = navigationIdentifier
		let script = """
		(() => {
			return [...document.querySelectorAll('input:not([type="hidden"]), textarea, select')].some(element => {
				if (element.tagName === 'SELECT') {
					const options = [...element.options];
					if (!element.multiple && !options.some(option => option.defaultSelected)) {
						const initialIndex = element.size > 1 ? -1 : options.findIndex(option => !option.disabled);
						return element.selectedIndex !== initialIndex;
					}
					return options.some(option => option.selected !== option.defaultSelected);
				}
				if (element.type === 'checkbox' || element.type === 'radio') return element.checked !== element.defaultChecked;
				return element.value !== element.defaultValue;
			});
		})()
		"""
		let value: Bool? = await withCheckedContinuation { continuation in
			webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
				continuation.resume(returning: (try? result.get()) as? Bool)
			}
		}
		guard owns(webView), documentID == navigationIdentifier,
		      value == false else { return false }
		return canAutomaticallyHibernate
	}

	private func updateInactiveSchedulingPolicy() {
		guard let webView = createdWebView else { return }
		let requiresContinuousScheduling = isPictureInPictureActive
			|| isEnteringPictureInPicture
			|| isPlayingMedia
			|| hasActiveVideoPlayback
		// Suspension could interrupt unobservable page or extension operations.
		webView.configuration.preferences.inactiveSchedulingPolicy = requiresContinuousScheduling ? .none : .throttle
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
		updateInactiveSchedulingPolicy()
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
			unsafe createdWebView?.window?.makeFirstResponder(createdWebView)
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

	#if os(macOS)
		/// The browser stays responsible for a file upload while its open panel
		/// is active. Unlike JavaScript dialogs, file pickers legitimately move
		/// key-window focus to AppKit's sheet and its auxiliary panels.
		func ownsFileUpload(in webView: WKWebView, documentID: Int, window: NSWindow) -> Bool {
			guard owns(webView), navigationIdentifier == documentID,
			      promptOwnership?(webView) == true,
			      unsafe webView.window === window,
			      window.isVisible else { return false }
			return true
		}
	#endif

	func ownsPrompt(in webView: WKWebView, documentID: Int) -> Bool {
		guard owns(webView), navigationIdentifier == documentID,
		      promptOwnership?(webView) == true else { return false }
		#if os(macOS)
			guard let window = unsafe webView.window, window.isVisible else { return false }
			return window.isKeyWindow || window.attachedSheet?.isKeyWindow == true
		#else
			guard let window = unsafe webView.window, !window.isHidden,
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
				webViewMatchesOwnerWindow: unsafe webView.window == nil || (unsafe webView.window === owner.window)
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
		livePopupControllers.removeAllObjects()
		pictureInPictureControlUnavailable = false
		faviconTask?.cancel()
		faviconTask = nil
		faviconTintTask?.cancel()
		faviconTintTask = nil
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
		#if os(macOS)
			(createdWebView as? PeekSourceWebView)?.quoteDestinations = nil
			(createdWebView as? PeekSourceWebView)?.onQuoteRequested = nil
		#endif
		easelQuoteDestinations = nil
		addQuoteToEasel = nil
		(createdWebView as? PeekSourceWebView)?.onLayout = nil
		(createdWebView as? PeekSourceWebView)?.onZoomIn = nil
		(createdWebView as? PeekSourceWebView)?.onZoomOut = nil
		(createdWebView as? PeekSourceWebView)?.onResetZoom = nil
		for name in [Self.scrollPositionMessageName, Self.topEdgeMessageName, Self.zapFinishedMessageName, Self.pageTintMessageName, "pageActivityChanged", "pictureInPictureChanged", "linkHoverChanged", "faviconChanged", "readerAvailabilityChanged"] {
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
		appliedContentRuleLists.removeAll()
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
		// Only balance security scopes that were successfully opened. Keep the
		// selected files accessible while WebKit reads the upload, then release
		// them on the next navigation or when the controller is invalidated.
		for url in urls where url.startAccessingSecurityScopedResource() {
			uploadSecurityScopedFiles.append(url)
		}
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
		encryptedInteractionState(from: createdWebView?.interactionState)
	}

	func encryptedInteractionState(from state: Any?) -> Data? {
		guard !session.isPrivate, canRecordVisit, let committedURL,
		      let data = state as? Data else { return nil }
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
			webView.quoteDestinations = { [weak self] in self?.easelQuoteDestinations?() ?? [] }
			webView.onQuoteRequested = { [weak self] destinationID in
				self?.captureEaselQuote(for: destinationID)
			}
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
			name: Self.pageTintMessageName
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
		webView.configuration.userContentController.addUserScript(
			WKUserScript(source: Self.pageTintScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
		)
		// Install Boosts after Astra's own scripts and before navigation.
		if !session.isPrivate {
			BrowserBoostStore.shared.register(webView)
		}
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
					guard let self, self.owns(webView),
					      let url = change.newValue ?? webView.url else { return }
					self.finishFragmentNavigationIfNeeded(to: url)
					guard !self.awaitsNavigationCommit, !self.isDownloadHandoff else { return }
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
					let color = change.newValue ?? webView.themeColor
					if let color {
						webView.underPageBackgroundColor = color.withAlphaComponent(1)
					}
					// Once the document's one-shot sample has arrived,
					// live metadata changes must not retint the toolbar.
					if self.pageTintHandledGeneration != self.navigationGeneration {
						self.resolveThemeColor(in: webView)
					}
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
		let nextRuleLists = session.contentBlocking.ruleLists(for: origin, sitePreferences: session.sitePreferences)
		guard appliedContentRuleLists.map(\.identifier) != nextRuleLists.map(\.identifier) else { return }
		removeAppliedContentRuleList()
		for nextRuleList in nextRuleLists {
			webView.configuration.userContentController.add(nextRuleList)
		}
		appliedContentRuleLists = nextRuleLists
	}

	private func removeAppliedContentRuleList() {
		for list in appliedContentRuleLists {
			createdWebView?.configuration.userContentController.remove(list)
		}
		appliedContentRuleLists.removeAll()
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

	isolated deinit {
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
		faviconTintTask?.cancel()
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
		guard !isInvalidated, !snapshotNavigationOnly else { return }
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
		guard !isInvalidated, !snapshotNavigationOnly,
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
		guard !isInvalidated, !snapshotNavigationOnly, let url = request.url else { return }
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
		awaitsNavigationCommit = !isCurrentDocumentFragmentURL(webView.backForwardList.backItem?.url)
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
		awaitsNavigationCommit = !isCurrentDocumentFragmentURL(webView.backForwardList.forwardItem?.url)
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
			awaitsNavigationCommit = !isCurrentDocumentFragmentURL(item.url)
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
		guard !snapshotNavigationOnly else { return }
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
			faviconTintAttemptedGeneration = nil
			refreshCachedFaviconTint(in: webView)
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
			guard let image = await takeSnapshot(), owns(webView), generation == navigationGeneration else { return }
			previewSnapshot = image
			previewSnapshotGeneration = generation
		}

		func tabProcessMemorySnapshot() async -> BrowserTabProcessMemorySnapshot? {
			guard let webView = createdWebView, owns(webView) else { return nil }
			let generation = navigationGeneration

			let webContentPID = Self.privateProcessIdentifier("_webProcessIdentifier", on: webView)
			let graphicsPID = Self.privateProcessIdentifier("_gpuProcessIdentifier", on: webView)
			let modelPID = Self.privateProcessIdentifier("_modelProcessIdentifier", on: webView)
			let networkPID = Self.privateProcessIdentifier(
				"_networkProcessIdentifier",
				on: webView.configuration.websiteDataStore
			)

			let descriptors = [webContentPID, graphicsPID, networkPID, modelPID].compactMap(\.self)
			guard !descriptors.isEmpty else { return nil }
			let sampled = await Task.detached(priority: .utility) {
				Self.sampleProcessMemory(for: descriptors)
			}.value
			guard owns(webView), generation == navigationGeneration,
			      Self.privateProcessIdentifier("_webProcessIdentifier", on: webView) == webContentPID,
			      Self.privateProcessIdentifier("_gpuProcessIdentifier", on: webView) == graphicsPID,
			      Self.privateProcessIdentifier("_modelProcessIdentifier", on: webView) == modelPID,
			      Self.privateProcessIdentifier("_networkProcessIdentifier", on: webView.configuration.websiteDataStore) == networkPID
			else { return nil }
			let snapshot = BrowserTabProcessMemorySnapshot(
				webContent: webContentPID.flatMap { sampled[$0] },
				graphics: graphicsPID.flatMap { sampled[$0] },
				network: networkPID.flatMap { sampled[$0] },
				model: modelPID.flatMap { sampled[$0] }
			)
			return snapshot.knownProcessBytes == nil ? nil : snapshot
		}

		private static func privateProcessIdentifier(_ key: String, on object: NSObject) -> pid_t? {
			let selector = NSSelectorFromString(key)
			guard object.responds(to: selector),
			      let number = object.value(forKey: key) as? NSNumber
			else { return nil }
			let processIdentifier = number.int32Value
			return processIdentifier > 0 ? processIdentifier : nil
		}

		private nonisolated static func sampleProcessMemory(for processIdentifiers: [pid_t]) -> [pid_t: BrowserTabProcessMemorySnapshot.Process] {
			Dictionary(uniqueKeysWithValues: Set(processIdentifiers).map { pid in
				(pid, BrowserTabProcessMemorySnapshot.sample(pid))
			})
		}

	#endif

	private func isCurrentDocumentFragmentURL(_ destination: URL?) -> Bool {
		guard hasCurrentPageDocument, committedSecurityNavigationID == navigationIdentifier,
		      let committedURL, let destination, committedURL != destination,
		      var previous = URLComponents(url: committedURL, resolvingAgainstBaseURL: false),
		      var next = URLComponents(url: destination, resolvingAgainstBaseURL: false),
		      previous.fragment != next.fragment else { return false }
		previous.fragment = nil
		next.fragment = nil
		return previous == next
	}

	private func finishFragmentNavigationIfNeeded(to destination: URL) {
		// Same-document fragment loads report their URL through KVO without
		// necessarily sending didCommit or didFinish. Only release the gate for
		// the exact requested URL while the previously committed document lives.
		guard awaitsNavigationCommit, !isInvalidated, !isDownloadHandoff,
		      committedSecurityNavigationID == navigationIdentifier,
		      let committedURL, committedURL != destination,
		      var previous = URLComponents(url: committedURL, resolvingAgainstBaseURL: false),
		      var next = URLComponents(url: destination, resolvingAgainstBaseURL: false),
		      previous.fragment != next.fragment else { return }
		previous.fragment = nil
		next.fragment = nil
		guard previous == next else { return }
		if let request = currentRequest {
			guard request.url == destination, (request.httpMethod ?? "GET") == "GET",
			      request.httpBody == nil, request.httpBodyStream == nil else { return }
		} else {
			// Back/Forward traversals have no URLRequest. WebKit's current
			// history item identifies their destination without rebuilding it
			// as a GET request (which would lose POST restoration semantics).
			guard createdWebView?.backForwardList.currentItem?.url == destination else { return }
		}
		awaitsNavigationCommit = false
	}

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
		      ), let committedURL else { return }

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
		guard !isInvalidated, !snapshotNavigationOnly else { return }
		pendingWebArchive = nil
		pendingLocalFile = nil
		awaitsNavigationCommit = true
		currentRequest = isAuthenticationSessionBrowser ? nil : request
		failedRequest = nil
		if resetConnectivityRetry {
			retriedAfterConnectivityReturn = false
		}
		guard session.contentBlocking.isReadyForNavigation, let webView = createdWebView else {
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
			let savedHistory = history
			let savedIndex = historyIndex
			webView.interactionState = state
			if webView.backForwardList.currentItem != nil {
				let prefixCount = max(0, savedIndex - webView.backForwardList.backList.count)
				liveHistoryPrefix = Array(savedHistory.prefix(prefixCount))
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

	private func resolveThemeColor(in webView: WKWebView) {
		// Visible full-width page chrome wins. Explicit site metadata takes
		// precedence over ordinary body colour; background is the last fallback.
		let color = sampledChromeColor
			?? webView.themeColor
			?? sampledSurfaceColor
			?? sampledBrandColor
			?? sampledFaviconColor
			?? webView.underPageBackgroundColor
			?? PlatformColor.white
		updateThemeColor(color)
	}

	/// Only a pre-existing cached favicon is eligible. Its palette extraction
	/// runs off the main actor and never blocks scrolling or adds network work.
	private func refreshCachedFaviconTint(in webView: WKWebView) {
		guard owns(webView), !isInvalidated,
		      sampledChromeColor == nil, sampledSurfaceColor == nil,
		      sampledBrandColor == nil, webView.themeColor == nil,
		      faviconTintTask == nil,
		      faviconTintAttemptedGeneration != navigationGeneration,
		      session.favicons.hasCachedFavicon(for: webView.url)
		else { return }
		let generation = navigationGeneration
		let pageURL = webView.url
		faviconTintAttemptedGeneration = generation
		faviconTintTask = Task { @MainActor [weak self, weak webView] in
			guard let self, let webView else { return }
			let accent = await session.favicons.cachedAccentColor(for: pageURL)
			guard owns(webView), generation == navigationGeneration,
			      webView.url == pageURL
			else { return }
			faviconTintTask = nil
			guard sampledChromeColor == nil, sampledSurfaceColor == nil,
			      sampledBrandColor == nil, webView.themeColor == nil
			else { return }
			sampledFaviconColor = accent.map {
				PlatformColor(
					red: CGFloat($0.0), green: CGFloat($0.1),
					blue: CGFloat($0.2), alpha: 1
				)
			}
			resolveThemeColor(in: webView)
		}
	}

	private func updateThemeColor(_ color: PlatformColor) {
		#if os(macOS)
			// WCAG luminance is defined in sRGB, not device-dependent RGB.
			guard let color = color.usingColorSpace(.sRGB) else {
				return
			}
		#endif
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		#if os(iOS)
			guard unsafe color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
				return
			}
		#elseif os(macOS)
			unsafe color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		#endif

		let nextColor = Color(color.withAlphaComponent(1))
		// WCAG contrast: black is the higher-contrast choice above 0.179 luminance.
		let nextIsLight = BrowserColor(red: Double(red), green: Double(green), blue: Double(blue)).luminance > 0.179
		// Avoid invalidating SwiftUI chrome on unchanged fallback/probe events.
		if themeColor != nextColor {
			themeColor = nextColor
		}
		if themeColorIsLight != nextIsLight {
			themeColorIsLight = nextIsLight
		}
	}

	#if os(macOS)
		weak var screenshotReaderWebView: WKWebView?

		func captureScreenshot() async throws -> BrowserScreenshot {
			let view = readerHTML == nil ? createdWebView : screenshotReaderWebView
			guard let view, !view.bounds.isEmpty else {
				throw CocoaError(.coderInvalidValue)
			}
			let documentID = navigationIdentifier
			let wasReader = readerHTML != nil
			let configuration = WKSnapshotConfiguration()
			configuration.rect = view.bounds
			let scale = unsafe view.window?.backingScaleFactor ?? 2
			let image = try await view.takeSnapshot(configuration: configuration)
			guard !isInvalidated, navigationIdentifier == documentID,
			      wasReader == (readerHTML != nil)
			else {
				throw CocoaError(.userCancelled)
			}
			return BrowserScreenshot(image: image, scale: scale)
		}
	#endif

	private func takeSnapshot(snapshotWidth: CGFloat = 180) async -> SnapshotImage? {
		guard !isInvalidated, hasCurrentPageDocument, let webView = createdWebView, !webView.bounds.isEmpty else { return nil }
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
		decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
	) {
		guard owns(webView) else {
			decisionHandler(.cancel, preferences)
			return
		}
		if snapshotNavigationOnly {
			let isSnapshotLoad = navigationAction.targetFrame?.isMainFrame == true
				&& navigationAction.navigationType == .other
				&& navigationAction.request.url?.absoluteString == "about:blank"
			decisionHandler(isSnapshotLoad ? .allow : .cancel, preferences)
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
		decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
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

	func recordProxyAuthenticationChallenge(_ challenge: URLAuthenticationChallenge, in webView: WKWebView) {
		guard owns(webView), challenge.protectionSpace.isProxy() else { return }
		encounteredProxyAuthentication = true
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
			let failure = BrowserNavigationFailure(
				error: error,
				url: failedURL,
				encounteredProxyAuthentication: encounteredProxyAuthentication
			)
			navigationFailure = failure
			if failure.isProxyFailure {
				BrowserLog.notice(.navigation, "navigation.proxy-failure", metadata: [
					"controller": BrowserLog.id(id),
					"kind": failure.kind.rawValue,
					"error_domain": error.domain,
					"error_code": String(error.code),
				])
			}
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
		encounteredProxyAuthentication = false
		failedRequest = nil
		navigationFailure = nil
		awaitsNavigationCommit = true
		session.permissions.removeTemporaryDecisions(controllerID: id)
		navigationGeneration += 1
		sampledChromeColor = nil
		sampledSurfaceColor = nil
		sampledBrandColor = nil
		sampledFaviconColor = nil
		pageTintHandledGeneration = nil
		faviconTintTask?.cancel()
		faviconTintTask = nil
		faviconTintAttemptedGeneration = nil
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
		// Fragment navigation can finish without didCommit because WebKit keeps
		// the existing document. A successful finish of the current navigation
		// must release the readiness gate set by load(_:), too.
		awaitsNavigationCommit = false
		#if os(macOS)
			if BrowserPerformanceBenchmark.enabled,
			   BrowserPerformanceBenchmark.shouldMeasureNavigation(webView)
			{
				BrowserPerformanceBenchmark.recordNavigationFinished(
					controllerID: id,
					webView: webView,
					webContentPID: Self.privateProcessIdentifier("_webProcessIdentifier", on: webView),
					graphicsPID: Self.privateProcessIdentifier("_gpuProcessIdentifier", on: webView),
					networkPID: Self.privateProcessIdentifier("_networkProcessIdentifier", on: webView.configuration.websiteDataStore)
				)
				let generation = navigationGeneration
				webView.callAsyncJavaScript(
					"await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve(document.readyState))))",
					arguments: [:],
					in: nil,
					in: .page
				) { [weak self, weak webView] result in
					Task { @MainActor in
						guard case .success = result,
						      let self,
						      let webView,
						      self.navigationGeneration == generation,
						      self.owns(webView)
						else { return }
						BrowserPerformanceBenchmark.recordTwoRAF(controllerID: self.id)
					}
				}
			}
		#endif
		refreshContentBlocking(for: webView.url)
		applyEaselQuoteHighlight(in: webView)
		webView.evaluateJavaScript("globalThis.astraProbeReader?.(true)", in: nil, in: .defaultClient, completionHandler: nil)
		updateHistory()
		if showsFind, !findText.isEmpty {
			findNext()
		}
		resolveThemeColor(in: webView)
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

		if message.name == Self.pageTintMessageName {
			guard pageTintHandledGeneration != navigationGeneration,
			      message.frameInfo.isMainFrame, let webView = message.webView,
			      owns(webView), hasCurrentPageDocument, navigationFailure == nil,
			      let result = message.body as? [String: Any],
			      let urlString = result["url"] as? String, urlString == webView.url?.absoluteString,
			      let source = result["source"] as? String
			else { return }
			let color: PlatformColor? = if let rgb = result["rgb"] as? [NSNumber], rgb.count == 3,
			                               rgb.allSatisfy({ $0.doubleValue.isFinite && (0 ... 255).contains($0.doubleValue) })
			{
				PlatformColor(
					red: CGFloat(rgb[0].doubleValue / 255),
					green: CGFloat(rgb[1].doubleValue / 255),
					blue: CGFloat(rgb[2].doubleValue / 255),
					alpha: 1
				)
			} else {
				nil
			}
			pageTintHandledGeneration = navigationGeneration
			sampledChromeColor = source == "chrome" ? color : nil
			sampledSurfaceColor = source == "surface" ? color : nil
			sampledBrandColor = source == "brand" ? color : nil
			resolveThemeColor(in: webView)
			refreshCachedFaviconTint(in: webView)
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

extension BrowserController {
	#if os(macOS)
		/// Query at action time, avoiding races between WebKit's contextmenu event
		/// and AppKit's synchronous willOpenMenu callback.
		private func captureEaselQuote(for destinationID: UUID) {
			guard !session.isPrivate,
			      easelQuoteDestinations?().contains(where: { $0.id == destinationID }) == true,
			      hasCurrentPageDocument, let webView = createdWebView,
			      let url = webView.url.map(BrowserAddress.withoutCredentials),
			      BrowserEaselDocument.isSafeLink(url) else { return }
			let documentID = navigationIdentifier
			let script = """
			(() => {
			  const sel = window.getSelection();
			  if (!sel || sel.isCollapsed || !sel.rangeCount) return null;
			  const text = sel.toString().trim();
			  if (!text || text.length > 8192) return null;
			  let prefix = '', suffix = '';
			  try {
			    const range = sel.getRangeAt(0);
			    if (document.body?.contains(range.startContainer) &&
			        document.body?.contains(range.endContainer)) {
			      const before = document.createRange();
			      before.selectNodeContents(document.body);
			      before.setEnd(range.startContainer, range.startOffset);
			      prefix = before.toString().slice(-48);
			      const after = document.createRange();
			      after.selectNodeContents(document.body);
			      after.setStart(range.endContainer, range.endOffset);
			      suffix = after.toString().slice(0, 48);
			    }
			  } catch (_) {}
			  return {text, prefix, suffix};
			})()
			"""
			webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self, weak webView] result in
				guard let self, let webView, owns(webView),
				      navigationIdentifier == documentID, hasCurrentPageDocument,
				      let currentURL = webView.url.map(BrowserAddress.withoutCredentials),
				      currentURL == url, case let .success(value) = result,
				      let capture = value as? [String: String],
				      let text = capture["text"]?.trimmingCharacters(in: .whitespacesAndNewlines)
				else { return }
				let quote = BrowserEaselQuote(url: url, text: text,
				                              prefix: String((capture["prefix"] ?? "").suffix(48)),
				                              suffix: String((capture["suffix"] ?? "").prefix(48)))
				guard quote.isValid,
				      easelQuoteDestinations?().contains(where: { $0.id == destinationID }) == true else { return }
				addQuoteToEasel?(destinationID, quote)
			}
		}
	#endif

	private func applyEaselQuoteHighlight(in webView: WKWebView) {
		guard let quote = easelQuoteHighlight, quote.isValid, let url = webView.url,
		      var current = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      var original = URLComponents(url: quote.url, resolvingAgainstBaseURL: false) else { return }
		current.fragment = nil
		original.fragment = nil
		guard current.url == original.url,
		      let payload = try? JSONSerialization.data(withJSONObject: [
		      	"text": quote.text, "prefix": quote.prefix, "suffix": quote.suffix,
		      ]),
		      let json = String(data: payload, encoding: .utf8) else { return }
		let script = BrowserEaselQuote.highlightScript.replacingOccurrences(of: "__ASTRA_QUOTE__", with: json)
		webView.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil)
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
		guard owns(webView), !snapshotNavigationOnly else { return nil }
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
		if let controller = popup.navigationDelegate as? BrowserController {
			livePopupControllers.add(controller)
			if isAuthenticationSessionBrowser {
				controller.isAuthenticationSessionBrowser = true
			}
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
		guard !snapshotNavigationOnly else { return true }
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
						return ownsExplicitAddressPrompt(in: webView, documentID: documentID, owner: explicitOwner)
					}
				} else {
					guard let window = unsafe webView.window else { return }
					promptWindow = window
					promptOwnerIsCurrent = { [weak self, weak webView] in
						guard let self, let webView else { return false }
						return ownsPrompt(in: webView, documentID: documentID)
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
	#if os(macOS)
		var quoteDestinations: (() -> [BrowserEaselQuoteDestination])?
		var onQuoteRequested: ((UUID) -> Void)?

		override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
			super.willOpenMenu(menu, with: event)
			guard menu.items.contains(where: {
				$0.identifier?.rawValue == "WKMenuItemIdentifierCopy" || $0.title == "Copy"
			}), let destinations = quoteDestinations?(), !destinations.isEmpty else { return }
			let submenu = NSMenu(title: "Add to Easel")
			for destination in destinations {
				let option = NSMenuItem(title: destination.title, action: #selector(addSelectedQuote(_:)), keyEquivalent: "")
				option.target = self
				option.representedObject = destination.id.uuidString
				submenu.addItem(option)
			}
			menu.addItem(.separator())
			let item = NSMenuItem(title: "Add to Easel", action: nil, keyEquivalent: "")
			item.submenu = submenu
			menu.addItem(item)
		}

		@objc private func addSelectedQuote(_ sender: NSMenuItem) {
			guard let identifier = sender.representedObject as? String,
			      let id = UUID(uuidString: identifier) else { return }
			onQuoteRequested?(id)
		}
	#endif

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
			   unsafe event.window === window,
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
