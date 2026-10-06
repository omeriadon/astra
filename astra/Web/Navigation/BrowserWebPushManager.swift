#if ASTRA_WEBSITE_APP_RUNTIME
	import AstraWebPushBridge
#endif
#if os(macOS)
	import AppKit
	import UserNotifications
	import WebKit

	@MainActor
	final class BrowserWebPushManager: NSObject, UNUserNotificationCenterDelegate {
		static let shared = BrowserWebPushManager()
		private static let category = "astra.webpush"
		private static let prefix = "astra.webpush."
		private weak var dataStore: WKWebsiteDataStore?
		private weak var permissions: BrowserSitePermissions?
		private var drainTask: Task<Void, Never>?
		private var needsAnotherDrain = false
		private(set) var hasNativeSupport = false
		private(set) var deliveryFailed = false
		var openRequested: ((URL) -> WKWebView?)?

		func attach(to store: WKWebsiteDataStore, permissions: BrowserSitePermissions) {
			guard store.isPersistent else { return }
			dataStore = store
			self.permissions = permissions
			hasNativeSupport = AstraInstallWebPushHost(store, self)
			let center = UNUserNotificationCenter.current()
			center.delegate = self
			let category = UNNotificationCategory(
				identifier: Self.category,
				actions: [],
				intentIdentifiers: [],
				options: [.customDismissAction]
			)
			Task {
				var categories = await center.notificationCategories()
				categories.insert(category)
				center.setNotificationCategories(categories)
			}
		}

		static func originURL(_ origin: WKSecurityOrigin) -> URL? {
			var parts = URLComponents()
			parts.scheme = origin.protocol
			parts.host = origin.host
			parts.port = origin.port > 0 ? origin.port : nil
			return parts.url
		}

		func requestPermission(origin: WKSecurityOrigin, webView: WKWebView, documentID: Int, controller: BrowserController) async -> Bool {
			guard hasNativeSupport, !controller.session.isPrivate,
			      let url = Self.originURL(origin), url.scheme == "https",
			      let originID = BrowserSitePermissions.origin(for: url),
			      webView.url.flatMap(BrowserSitePermissions.origin(for:)) == originID,
			      controller.ownsPrompt(in: webView, documentID: documentID),
			      let window = webView.window, window.isVisible,
			      let permissions else { return false }
			let decision = permissions.decision(origin: originID, topOrigin: originID, capability: .notifications)
			if decision == false {
				return false
			}
			if decision == nil {
				let alert = BrowserWebsiteUI.alert(
					title: "Allow notifications from \(originID)?",
					message: "This website can send notifications when its tabs are closed. You can change this permission in Privacy and Security settings.",
					confirm: "Allow",
					cancel: "Don't Allow"
				)
				let response = await BrowserWebsiteUI.present(alert, in: window) {
					controller.ownsPrompt(in: webView, documentID: documentID)
				}
				guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return false }
				if response == .alertSecondButtonReturn {
					permissions.set(false, origin: originID, topOrigin: originID, capability: .notifications)
					return false
				}
			}
			let granted: Bool
			do {
				granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
			} catch {
				return false
			}
			guard controller.ownsPrompt(in: webView, documentID: documentID) else { return false }
			permissions.set(granted, origin: originID, topOrigin: originID, capability: .notifications)
			return granted
		}

		private func allows(_ origin: String) -> Bool {
			permissions?.decision(origin: origin, topOrigin: origin, capability: .notifications) == true
		}

		func permissionsChanged() {
			Task {
				let center = UNUserNotificationCenter.current()
				let identifiers = await center.deliveredNotifications().compactMap { notification -> String? in
					let request = notification.request
					guard request.content.categoryIdentifier == Self.category,
					      let origin = request.content.userInfo["astraOrigin"] as? String,
					      !allows(origin) else { return nil }
					return request.identifier
				}
				center.removeDeliveredNotifications(withIdentifiers: identifiers)
				center.removePendingNotificationRequests(withIdentifiers: identifiers)
			}
		}

		func removeDeliveredNotifications() {
			Task {
				let center = UNUserNotificationCenter.current()
				let delivered = await center.deliveredNotifications().map(\.request)
				let pending = await center.pendingNotificationRequests()
				let identifiers = (delivered + pending).filter { $0.content.categoryIdentifier == Self.category }.map(\.identifier)
				center.removeDeliveredNotifications(withIdentifiers: identifiers)
				center.removePendingNotificationRequests(withIdentifiers: identifiers)
			}
		}

		func drainPendingMessages() {
			guard hasNativeSupport, let dataStore else { return }
			needsAnotherDrain = true
			guard drainTask == nil else { return }
			drainTask = Task {
				defer { drainTask = nil }
				repeat {
					needsAnotherDrain = false
					let messages: [[AnyHashable: Any]] = await withCheckedContinuation { continuation in
						AstraReadPendingWebPush(dataStore) { continuation.resume(returning: $0) }
					}
					for message in messages {
						let processed: Bool = await withCheckedContinuation { continuation in
							AstraProcessWebPush(dataStore, message) { continuation.resume(returning: $0) }
						}
						if !processed {
							deliveryFailed = true
						}
					}
				} while needsAnotherDrain && !Task.isCancelled
			}
		}

		@objc(notificationPermissionsForWebsiteDataStore:)
		func notificationPermissions(for store: WKWebsiteDataStore) -> [String: NSNumber] {
			guard store === dataStore, let permissions else { return [:] }
			return Dictionary(permissions.entries.filter {
				$0.capability == .notifications && $0.origin == $0.topOrigin
			}.map { ($0.origin, NSNumber(value: $0.allowed)) }, uniquingKeysWith: { _, latest in latest })
		}

		@objc(websiteDataStore:showNotification:)
		func websiteDataStore(_ store: WKWebsiteDataStore, showNotification data: NSObject) {
			guard store === dataStore,
			      ["identifier", "origin", "title", "body", "userInfo"].allSatisfy({ data.responds(to: NSSelectorFromString($0)) }),
			      let identifier = data.value(forKey: "identifier") as? String,
			      let origin = data.value(forKey: "origin") as? String, allows(origin),
			      let info = data.value(forKey: "userInfo") as? [String: Any] else { return }
			let content = UNMutableNotificationContent()
			content.title = String((data.value(forKey: "title") as? String ?? "").prefix(4000))
			content.body = String((data.value(forKey: "body") as? String ?? "").prefix(8000))
			content.subtitle = origin
			content.categoryIdentifier = Self.category
			content.threadIdentifier = origin
			content.userInfo = ["astraWebPush": info, "astraOrigin": origin]
			if data.responds(to: NSSelectorFromString("alert")), (data.value(forKey: "alert") as? NSNumber)?.intValue == 2 {
				content.sound = .default
			}
			Task {
				guard allows(origin) else { return }
				do {
					try await UNUserNotificationCenter.current().add(UNNotificationRequest(
						identifier: Self.prefix + identifier,
						content: content,
						trigger: nil
					))
				} catch {
					deliveryFailed = true
				}
			}
		}

		@objc(websiteDataStore:getDisplayedNotificationsForWorkerOrigin:completionHandler:)
		func websiteDataStore(_ store: WKWebsiteDataStore, getDisplayedNotificationsForWorkerOrigin origin: WKSecurityOrigin, completionHandler: @escaping ([[String: Any]]) -> Void) {
			guard store === dataStore,
			      let originID = Self.originURL(origin).flatMap(BrowserSitePermissions.origin(for:)), allows(originID)
			else {
				completionHandler([])
				return
			}
			Task {
				let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
				completionHandler(notifications.compactMap { notification in
					let content = notification.request.content
					guard content.categoryIdentifier == Self.category,
					      content.userInfo["astraOrigin"] as? String == originID else { return nil }
					return content.userInfo["astraWebPush"] as? [String: Any]
				})
			}
		}

		@objc(websiteDataStore:openWindow:fromServiceWorkerOrigin:completionHandler:)
		func websiteDataStore(_ store: WKWebsiteDataStore, openWindow url: URL, fromServiceWorkerOrigin origin: WKSecurityOrigin, completionHandler: @escaping (WKWebView?) -> Void) {
			guard store === dataStore, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
			      let originID = Self.originURL(origin).flatMap(BrowserSitePermissions.origin(for:)), allows(originID)
			else {
				completionHandler(nil)
				return
			}
			completionHandler(openRequested?(url))
		}

		@objc(websiteDataStore:navigateToNotificationActionURL:)
		func websiteDataStore(_ store: WKWebsiteDataStore, navigateToNotificationActionURL url: URL) {
			guard store === dataStore, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
			_ = openRequested?(url)
		}

		nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
			await presentationOptions(for: notification)
		}

		private func presentationOptions(for notification: UNNotification) -> UNNotificationPresentationOptions {
			if notification.request.content.categoryIdentifier == BrowserWebsiteMonitoring.category {
				return [.banner, .list, .sound]
			}
			guard notification.request.content.categoryIdentifier == Self.category,
			      let origin = notification.request.content.userInfo["astraOrigin"] as? String, allows(origin) else { return [] }
			return [.banner, .list, .sound]
		}

		nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
			await process(response)
		}

		private func process(_ response: UNNotificationResponse) async {
			let content = response.notification.request.content
			if content.categoryIdentifier == BrowserWebsiteMonitoring.category {
				if let id = content.userInfo["monitorID"] as? String, response.actionIdentifier == UNNotificationDefaultActionIdentifier {
					BrowserWebsiteMonitoring.shared.openNotification(id)
				}
				return
			}
			guard content.categoryIdentifier == Self.category, let dataStore,
			      let origin = content.userInfo["astraOrigin"] as? String, allows(origin),
			      let info = content.userInfo["astraWebPush"] as? [String: Any] else { return }
			let clicked = response.actionIdentifier == UNNotificationDefaultActionIdentifier
			guard clicked || response.actionIdentifier == UNNotificationDismissActionIdentifier else { return }
			let processed: Bool = await withCheckedContinuation { continuation in
				AstraProcessWebNotificationResponse(dataStore, info, clicked) { continuation.resume(returning: $0) }
			}
			if !processed {
				deliveryFailed = true
			}
		}
	}

	extension BrowserController {
		@objc(_webView:requestNotificationPermissionForSecurityOrigin:decisionHandler:)
		func requestWebsiteNotificationPermission(_ webView: WKWebView, origin: WKSecurityOrigin, decisionHandler: @escaping (Bool) -> Void) {
			let documentID = navigationIdentifier
			Task {
				let granted = await BrowserWebPushManager.shared.requestPermission(origin: origin, webView: webView, documentID: documentID, controller: self)
				decisionHandler(granted)
			}
		}
	}
#endif
