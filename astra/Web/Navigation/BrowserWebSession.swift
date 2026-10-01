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
	var persistenceWriteTask: Task<Void, Never>?
	private var cleanupTask: Task<Void, Never>?

	init(isPrivate: Bool = false) {
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
	}

	func clearWebsiteData() async {
		#if os(macOS)
			if !isPrivate {
				BrowserWebPushManager.shared.removeDeliveredNotifications()
			}
		#endif
		await dataStore.removeData(
			ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
			modifiedSince: .distantPast
		)
		favicons.clear()
	}

	func endPrivateSession() async {
		guard isPrivate else { return }
		if let cleanupTask {
			await cleanupTask.value
			return
		}
		let task = Task { @MainActor in
			await downloads.endPrivateSession()
			await clearWebsiteData()
			permissions.reset()
		}
		cleanupTask = task
		await task.value
	}
}
