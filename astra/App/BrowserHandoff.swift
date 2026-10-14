import Foundation

#if !ASTRA_WEBSITE_APP_RUNTIME
	/// Connects Apple's NSUserActivity transport to Astra's existing tab sync.
	/// Receiving Handoff never constructs a new BrowserTab or navigates by URL.
	@MainActor
	final class BrowserHandoff: NSObject, NSUserActivityDelegate {
		static let shared = BrowserHandoff()

		private var receivingTabID: UUID?
		private var continuationTask: Task<Void, Never>?

		private override init() { super.init() }

		// A newly advertised tab may still be pending the periodic upload.
		// Publish when Handoff is actually used, without syncing on selection.
		nonisolated func userActivityWasContinued(_ userActivity: NSUserActivity) {
			guard userActivity.activityType == BrowserHandoffTabReference.activityType else { return }
			Task { @MainActor in await BrowserSync.shared.syncForHandoff() }
		}

		static func canAdvertise(from browser: Browser, sceneIsActive: Bool) -> Bool {
			guard sceneIsActive,
			      !browser.isPrivate, !browser.isMini, !browser.showsQuickSearch,
			      browser.isReadyForSync, BrowserSync.shared.isSignedIn,
			      BrowserWindowRegistry.shared.activeBrowserID == browser.windowID,
			      let tab = browser.selectedTab, tab.internalPage == nil,
			      let url = tab.currentURL
			else { return false }
			return isWebURL(url)
		}

		static func configure(_ activity: NSUserActivity, from browser: Browser) {
			guard let tab = browser.selectedTab,
			      tab.internalPage == nil,
			      let url = tab.currentURL, isWebURL(url)
			else { return }
			activity.title = tab.title
			activity.userInfo = BrowserHandoffTabReference(tabID: tab.id).userInfo
			activity.webpageURL = BrowserAddress.withoutCredentials(url)
			activity.isEligibleForHandoff = true
			activity.isEligibleForSearch = false
			activity.isEligibleForPublicIndexing = false
			activity.delegate = shared
		}

		static func reference(from activity: NSUserActivity) -> BrowserHandoffTabReference? {
			guard activity.activityType == BrowserHandoffTabReference.activityType else { return nil }
			return BrowserHandoffTabReference(userInfo: activity.userInfo)
		}

		@discardableResult
		func continueActivity(_ activity: NSUserActivity, in browser: Browser) -> Bool {
			guard let reference = Self.reference(from: activity),
			      !browser.isPrivate, !browser.isMini
			else { return false }

			// Both AppKit and SwiftUI may deliver one continuation. Do not start
			// duplicate network operations or race two window selections.
			guard receivingTabID != reference.tabID else { return true }
			continuationTask?.cancel()
			receivingTabID = reference.tabID
			continuationTask = Task { @MainActor [weak self, weak browser] in
				guard let self, let browser else { return }
				await restore(reference, in: browser)
				if receivingTabID == reference.tabID {
					receivingTabID = nil
					continuationTask = nil
				}
			}
			return true
		}

		private func restore(_ reference: BrowserHandoffTabReference, in browser: Browser) async {
			let sync = BrowserSync.shared
			// A continuation may arrive during cold-start disk hydration or
			// before the asynchronously loaded Keychain session is available.
			for _ in 0 ..< 100 where !Task.isCancelled {
				if browser.isReadyForSync, sync.isSignedIn {
					break
				}
				try? await Task.sleep(for: .milliseconds(100))
			}
			guard !Task.isCancelled else { return }
			guard browser.isReadyForSync else {
				browser.session.toastManager.show(
					symbol: "exclamationmark.triangle",
					message: "Handoff unavailable until tabs finish restoring"
				)
				return
			}
			guard sync.isSignedIn else {
				browser.session.toastManager.show(
					symbol: "exclamationmark.triangle",
					message: "Sign in to Astra Sync to continue this tab"
				)
				return
			}

			sync.attach(browser)
			// The source device may still be pushing its latest tab snapshot.
			// Refresh on receipt, then retry briefly if that UUID is absent.
			for attempt in 0 ..< 4 {
				guard !Task.isCancelled else { return }
				for _ in 0 ..< 100 where sync.isSyncing && !Task.isCancelled {
					try? await Task.sleep(for: .milliseconds(100))
				}
				guard !Task.isCancelled else { return }
				if !sync.isSyncing {
					await sync.syncNow()
				}
				guard !Task.isCancelled else { return }

				if let tab = browser.tab(withID: reference.tabID),
				   tab.internalPage == nil,
				   let url = tab.currentURL,
				   Self.isWebURL(url)
				{
					BrowserWindowRegistry.shared.activate(browser)
					browser.selectTab(reference.tabID)
					return
				}
				if attempt < 3 {
					let retryDelay: Int = [750, 1500, 2500][attempt]
					try? await Task.sleep(for: .milliseconds(retryDelay))
				}
			}
			guard !Task.isCancelled else { return }
			browser.session.toastManager.show(
				symbol: "exclamationmark.triangle",
				message: sync.errorDescription == nil
					? "Handoff tab is not available in synced tabs"
					: "Could not sync the Handoff tab"
			)
		}

		private static func isWebURL(_ url: URL) -> Bool {
			guard let scheme = url.scheme?.lowercased() else { return false }
			return scheme == "https" || scheme == "http"
		}
	}
#endif
