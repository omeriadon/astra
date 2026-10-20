#if os(macOS)
	import AppKit
	import WebKit

	@MainActor
	enum BrowserPerformanceBenchmark {
		static let enabled = ProcessInfo.processInfo.environment["ASTRA_PERFORMANCE_BENCHMARK"] == "1"

		private static var installed = false
		private static var activeObserver: NSObjectProtocol?
		private static var localEventMonitor: Any?
		private weak static var foregroundWindow: NSWindow?
		private weak static var foregroundBrowser: Browser?
		private static var observedAppKitUpdate = false
		private static var didReportUsable = false
		private static var keySequence = 0
		private static var lastKeyDownSequence: Int?
		private static var lastKeyDownEventTimestamp: TimeInterval?
		private static var acknowledgedAddressSequence: Int?

		static func install() {
			guard enabled, !installed else { return }
			installed = true
			#if DEBUG
				assert(isUsable(appActive: true, key: true, visible: true, occluded: true, miniaturized: false, canBecomeKey: true, firstResponder: true, hydrated: true, observedUpdate: true))
				assert(!isUsable(appActive: false, key: true, visible: true, occluded: true, miniaturized: false, canBecomeKey: true, firstResponder: true, hydrated: true, observedUpdate: true))
			#endif
			activeObserver = NotificationCenter.default.addObserver(
				forName: NSApplication.didBecomeActiveNotification,
				object: NSApp,
				queue: .main
			) { _ in
				Task { @MainActor in
					recordActivation()
				}
			}
			localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
				guard event.window?.isKeyWindow == true else { return event }
				MainActor.assumeIsolated {
					recordKeyDown(event)
				}
				return event
			}
		}

		static func recordActivation() {
			guard enabled else { return }
			BrowserLog.info(.performance, "benchmark.app-became-active", metadata: [
				"elapsed_ms": elapsedMilliseconds(),
				"active": String(NSApp.isActive),
			])
			evaluateUsableWindow()
		}

		static func recordWindowUpdate(_ window: NSWindow) {
			guard enabled, foregroundWindow == nil else { return }
			foregroundWindow = window
			observedAppKitUpdate = true
			BrowserLog.info(.performance, "benchmark.first-appkit-update", metadata: [
				"elapsed_ms": elapsedMilliseconds(),
				"visible": String(window.isVisible),
			])
			evaluateUsableWindow()
		}

		static func recordKeyChange(_ window: NSWindow) {
			guard enabled else { return }
			BrowserLog.info(.performance, "benchmark.window-became-key", metadata: [
				"elapsed_ms": elapsedMilliseconds(),
				"key": String(window.isKeyWindow),
				"active": String(NSApp.isActive),
			])
			evaluateUsableWindow()
		}

		static func recordOcclusionChange(_ window: NSWindow) {
			guard enabled else { return }
			BrowserLog.info(.performance, "benchmark.window-occlusion-changed", metadata: [
				"elapsed_ms": elapsedMilliseconds(),
				"visible": String(window.occlusionState.contains(.visible)),
			])
			evaluateUsableWindow()
		}

		static func recordForegroundReadiness(window: NSWindow, browser: Browser) {
			guard enabled else { return }
			foregroundWindow = window
			foregroundBrowser = browser
			BrowserLog.info(.performance, "benchmark.foreground-readiness", metadata: readinessMetadata(window: window, browser: browser))
			evaluateUsableWindow()
		}

		static func recordKeyDown(_ event: NSEvent) {
			guard enabled else { return }
			keySequence += 1
			let sequence = keySequence
			lastKeyDownSequence = sequence
			lastKeyDownEventTimestamp = event.timestamp
			let dispatchStart = BrowserLog.clock()
			BrowserLog.info(.performance, "benchmark.input-key-down", metadata: [
				"sequence": String(sequence),
				"native_event_uptime_ms": BrowserLog.fixedDecimal(event.timestamp * 1000, places: .thousandths),
				"native_to_monitor_ms": BrowserLog.fixedDecimal((dispatchStart - event.timestamp) * 1000),
				"dispatch_start_ms": BrowserLog.fixedDecimal((dispatchStart - (BrowserLog.mainEntryUptime ?? dispatchStart)) * 1000),
				"window_key": String(event.window?.isKeyWindow == true),
			])
			DispatchQueue.main.async {
				BrowserLog.info(.performance, "benchmark.input-runloop-ack", metadata: [
					"sequence": String(sequence),
					"elapsed_ms": elapsedMilliseconds(),
				])
			}
		}

		static func recordAddressTextChange() {
			guard enabled,
			      let sequence = lastKeyDownSequence,
			      let eventTimestamp = lastKeyDownEventTimestamp,
			      acknowledgedAddressSequence != sequence
			else { return }
			acknowledgedAddressSequence = sequence
			BrowserLog.info(.performance, "benchmark.address-text-acknowledged", metadata: [
				"sequence": String(sequence),
				"elapsed_ms": elapsedMilliseconds(),
				"native_to_change_ms": BrowserLog.fixedDecimal((BrowserLog.clock() - eventTimestamp) * 1000),
			])
		}

		static func shouldMeasureNavigation(_ webView: WKWebView) -> Bool {
			enabled && webView.url?.host?.lowercased() == "localhost" && webView.url?.port == 18766
		}

		static func recordNavigationFinished(
			controllerID: UUID,
			webView: WKWebView,
			webContentPID: pid_t?,
			graphicsPID: pid_t?,
			networkPID: pid_t?
		) {
			guard shouldMeasureNavigation(webView) else { return }
			BrowserLog.info(.performance, "benchmark.webkit-navigation-finished", metadata: [
				"controller": BrowserLog.id(controllerID),
				"web_content_pid": webContentPID.map(String.init) ?? "nil",
				"graphics_pid": graphicsPID.map(String.init) ?? "nil",
				"network_pid": networkPID.map(String.init) ?? "nil",
				"elapsed_ms": elapsedMilliseconds(),
			])
		}

		static func recordTwoRAF(controllerID: UUID) {
			guard enabled else { return }
			BrowserLog.info(.performance, "benchmark.webkit-two-raf", metadata: [
				"controller": BrowserLog.id(controllerID),
				"elapsed_ms": elapsedMilliseconds(),
				"scheduling_proxy": "true",
			])
		}

		static func seedTabsIfRequested(in browser: Browser) async {
			guard enabled,
			      Bundle.main.bundleIdentifier?.hasSuffix("foreground20261011") == true,
			      let rawCount = ProcessInfo.processInfo.environment["ASTRA_BENCHMARK_SEED_TABS"],
			      let count = Int(rawCount), [1, 10, 50, 100].contains(count)
			else { return }
			let existingTabs = browser.tabs
			guard existingTabs.allSatisfy({ $0.internalPage == nil && ($0.currentURL == nil || isFixtureURL($0.currentURL)) }) else {
				BrowserLog.error(.performance, "benchmark.seed-refused", metadata: ["reason": "non-fixture-restored-data"])
				return
			}
			var fixtureTabs = existingTabs
			while fixtureTabs.count > count {
				guard let tab = fixtureTabs.popLast(), tab !== fixtureTabs.first else { break }
				browser.closeTab(tab.id, confirmed: true)
			}
			while fixtureTabs.count < count {
				fixtureTabs.append(browser.addTab(inBackground: false))
			}
			guard fixtureTabs.count == count, let firstTab = fixtureTabs.first else {
				BrowserLog.error(.performance, "benchmark.seed-failed", metadata: ["reason": "tab-count-reconciliation"])
				return
			}
			#if DEBUG
				assert(fixtureTabs.count == count)
			#endif
			for (index, tab) in fixtureTabs.enumerated() {
				if tab.isHibernated {
					tab.wake()
				}
				guard let controller = tab.controller,
				      let url = URL(string: "http://localhost:18766/fixture.html?tab=\(index + 1)")
				else {
					BrowserLog.error(.performance, "benchmark.seed-failed", metadata: ["reason": "controller-missing", "tab": String(index + 1)])
					return
				}
				browser.selectTab(tab.id)
				controller.load(url)
				guard await waitForFixtureLoad(controller) else {
					BrowserLog.error(.performance, "benchmark.seed-failed", metadata: ["reason": "fixture-load-timeout", "tab": String(index + 1)])
					return
				}
				if tab !== firstTab {
					browser.selectTab(firstTab.id)
					browser.hibernateTab(tab.id, onlyIfBackground: true)
					guard await waitForHibernation(tab) else {
						BrowserLog.error(.performance, "benchmark.seed-failed", metadata: ["reason": "hibernate-timeout", "tab": String(index + 1)])
						return
					}
				}
			}
			browser.selectTab(firstTab.id)
			await browser.flushAndWaitForPersistence()
			guard browser.persistenceErrorDescription == nil else {
				BrowserLog.error(.performance, "benchmark.seed-failed", metadata: ["reason": "persistence-error"])
				return
			}
			BrowserLog.notice(.performance, "benchmark.seed-complete", metadata: [
				"requested": String(count),
				"actual_tabs": String(browser.tabs.count),
				"loaded_controllers": String(browser.tabs.filter { $0.controller != nil }.count),
				"hibernated": String(browser.tabs.filter(\.isHibernated).count),
				"selected_foreground": String(browser.selectedTabID == firstTab.id),
				"elapsed_ms": elapsedMilliseconds(),
			])
		}

		private static func isFixtureURL(_ url: URL?) -> Bool {
			url?.host?.lowercased() == "localhost" && url?.port == 18766 && url?.path == "/fixture.html"
		}

		private static func waitForFixtureLoad(_ controller: BrowserController) async -> Bool {
			let deadline = BrowserLog.clock() + 15
			while BrowserLog.clock() < deadline {
				if controller.navigationFailure != nil {
					return false
				}
				if controller.hasCurrentPageDocument, !controller.isLoading, isFixtureURL(controller.url) {
					return true
				}
				try? await Task.sleep(for: .milliseconds(25))
			}
			return false
		}

		private static func waitForHibernation(_ tab: BrowserTab) async -> Bool {
			let deadline = BrowserLog.clock() + 15
			while BrowserLog.clock() < deadline {
				if tab.isHibernated {
					return true
				}
				try? await Task.sleep(for: .milliseconds(25))
			}
			return false
		}

		private static func evaluateUsableWindow() {
			guard !didReportUsable,
			      let window = foregroundWindow,
			      let browser = foregroundBrowser,
			      isUsable(
			      	appActive: NSApp.isActive,
			      	key: window.isKeyWindow,
			      	visible: window.isVisible,
			      	occluded: window.occlusionState.contains(.visible),
			      	miniaturized: window.isMiniaturized,
			      	canBecomeKey: window.canBecomeKey,
			      	firstResponder: window.firstResponder != nil,
			      	hydrated: browser.isHydrationFinished,
			      	observedUpdate: observedAppKitUpdate
			      )
			else { return }
			didReportUsable = true
			BrowserLog.notice(.performance, "benchmark.foreground-usable-window", metadata: readinessMetadata(window: window, browser: browser))
		}

		private static func isUsable(
			appActive: Bool,
			key: Bool,
			visible: Bool,
			occluded: Bool,
			miniaturized: Bool,
			canBecomeKey: Bool,
			firstResponder: Bool,
			hydrated: Bool,
			observedUpdate: Bool
		) -> Bool {
			appActive && key && visible && occluded && !miniaturized && canBecomeKey && firstResponder && hydrated && observedUpdate
		}

		private static func readinessMetadata(window: NSWindow, browser: Browser) -> [String: String] {
			[
				"elapsed_ms": elapsedMilliseconds(),
				"app_active": String(NSApp.isActive),
				"key": String(window.isKeyWindow),
				"visible": String(window.isVisible),
				"occlusion_visible": String(window.occlusionState.contains(.visible)),
				"miniaturized": String(window.isMiniaturized),
				"can_become_key": String(window.canBecomeKey),
				"first_responder": String(window.firstResponder != nil),
				"hydrated": String(browser.isHydrationFinished),
				"observed_appkit_update": String(observedAppKitUpdate),
			]
		}

		private static func elapsedMilliseconds() -> String {
			let start = BrowserLog.mainEntryUptime ?? BrowserLog.clock()
			return BrowserLog.fixedDecimal((BrowserLog.clock() - start) * 1000)
		}
	}
#endif
