#if ASTRA_WEBSITE_APP_RUNTIME
	import AstraWebPushBridge
#endif
import Defaults
import Foundation
import Observation
import WebKit

@MainActor
final class BrowserWebSession {
	static let shared = BrowserWebSession()
	let isPrivate: Bool
	let dataStore: WKWebsiteDataStore
	let toastManager: ToastManager
	let downloads: BrowserDownloadManager
	let favicons: FaviconStore
	let permissions: BrowserSitePermissions
	let sitePreferences: BrowserSitePreferences
	let contentBlocking: BrowserContentBlocking
	let usageLimits: BrowserUsageLimitsStore
	var persistenceWriteTask: Task<Void, Never>?
	private var cleanupTask: Task<Void, Never>?

	init(isPrivate: Bool = false) {
		BrowserLog.info(.lifecycle, "web-session.init", metadata: ["private": String(isPrivate)])
		self.isPrivate = isPrivate
		let toastManager = isPrivate ? ToastManager() : .shared
		self.toastManager = toastManager
		#if os(macOS)
			dataStore = isPrivate ? .nonPersistent() : AstraCreateWebPushDataStore() ?? .default()
		#else
			dataStore = isPrivate ? .nonPersistent() : .default()
		#endif
		downloads = isPrivate
			? BrowserDownloadManager(privateDataStore: dataStore, toastManager: toastManager)
			: .shared
		favicons = isPrivate ? FaviconStore(isPrivate: true) : .shared
		permissions = BrowserSitePermissions(isPrivate: isPrivate)
		sitePreferences = isPrivate ? BrowserSitePreferences(isPrivate: true) : .shared
		contentBlocking = isPrivate ? BrowserContentBlocking(isPrivate: true) : .shared
		usageLimits = BrowserUsageLimitsStore(dataStore: dataStore)
		sitePreferences.didUpdateContentBlockingException = { [weak self] origin in
			self?.refreshContentBlocking(for: origin)
		}
		contentBlocking.didUpdate = { [weak self] in
			self?.refreshContentBlocking()
		}
		sitePreferences.didUpdateZoom = { [weak sitePreferences] origin, zoom in
			guard let sitePreferences else { return }
			let inheritedZoom = zoom ?? Defaults[.defaultPageZoom]
			for browser in BrowserWindowRegistry.shared.openBrowsers where browser.session.sitePreferences === sitePreferences {
				for tab in browser.tabs {
					let controllers = [tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)
					for controller in controllers where controller.canApplySitePreferencesToCurrentPage
						&& controller.committedURL.flatMap(BrowserSitePermissions.origin(for:)) == origin
					{
						controller.applySiteZoom(inheritedZoom)
					}
				}
			}
		}
		permissions.didUpdate = { [weak permissions] entry in
			guard let permissions,
			      entry == nil || entry?.decision != .allowOnce else { return }
			for browser in BrowserWindowRegistry.shared.openBrowsers where browser.session.permissions === permissions {
				for tab in browser.tabs {
					let controllers = [tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)
					for controller in controllers {
						guard let entry else {
							controller.stopCapture()
							continue
						}
						guard entry.capability == .camera || entry.capability == .microphone,
						      (controller.committedURL ?? controller.url).flatMap(BrowserSitePermissions.origin(for:)) == entry.topOrigin else { continue }
						controller.stopCapture(capability: entry.capability)
					}
				}
			}
		}
		#if os(macOS)
			if !isPrivate {
				BrowserWebPushManager.shared.attach(to: dataStore, permissions: permissions)
				permissions.didChange = { BrowserWebPushManager.shared.permissionsChanged() }
			}
		#endif
		#if DEBUG
			assert(dataStore.isPersistent != isPrivate)
			assert(isPrivate ? toastManager !== ToastManager.shared : toastManager === ToastManager.shared)
		#endif
		if !isPrivate {
			Task { await contentBlocking.prepare() }
		}
	}

	func clearWebsiteData(since: Date = .distantPast) async {
		let logStarted = BrowserLog.clock()
		BrowserLog.notice(.browser, "website-data.clear.begin", metadata: ["private": String(isPrivate), "since": String(since.timeIntervalSince1970)])
		#if os(macOS)
			if !isPrivate, since == .distantPast {
				BrowserWebPushManager.shared.removeDeliveredNotifications()
			}
		#endif
		await dataStore.removeData(
			ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
			modifiedSince: since
		)
		BrowserLog.duration(.browser, "website-data.clear.end", since: logStarted, warnAboveMilliseconds: 500, metadata: ["private": String(isPrivate)])
		favicons.clear()
	}

	private func refreshContentBlocking(for origin: String? = nil) {
		BrowserLog.trace(.contentBlocking, "content-blocking.notify-controllers", metadata: ["origin": BrowserLog.value(origin)])
		for browser in BrowserWindowRegistry.shared.openBrowsers where browser.session === self {
			for tab in browser.tabs {
				let controllers = [tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)
				for controller in controllers {
					if let origin,
					   controller.committedURL.flatMap(BrowserSitePermissions.origin(for:)) != origin,
					   controller.url.flatMap(BrowserSitePermissions.origin(for:)) != origin
					{
						continue
					}
					controller.contentBlockingDidBecomeReady()
				}
			}
		}
	}

	func clearWebsiteData(for record: WKWebsiteDataRecord) async {
		BrowserLog.notice(.browser, "website-data.clear-record", metadata: ["display_name": BrowserLog.value(record.displayName), "types": String(record.dataTypes.count)])
		await dataStore.removeData(
			ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
			for: [record]
		)
		favicons.clear()
	}

	func endPrivateSession() async {
		BrowserLog.notice(.lifecycle, "private-session.end")
		guard isPrivate else { return }
		if let cleanupTask {
			await cleanupTask.value
			return
		}
		let task = Task { @MainActor in
			await downloads.endPrivateSession()
			await clearWebsiteData()
			permissions.reset()
			await contentBlocking.endPrivateSession()
		}
		cleanupTask = task
		await task.value
	}
}
