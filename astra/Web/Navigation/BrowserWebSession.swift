import Foundation
import Observation
import WebKit

@MainActor
final class BrowserWebSession {
	static let shared = BrowserWebSession()
	let isPrivate: Bool
	let dataStore: WKWebsiteDataStore
	let downloads: BrowserDownloadManager
	let favicons: FaviconStore
	let permissions: BrowserSitePermissions
	var persistenceWriteTask: Task<Void, Never>?
	private var cleanupTask: Task<Void, Never>?

	init(isPrivate: Bool = false) {
		self.isPrivate = isPrivate
		dataStore = isPrivate ? .nonPersistent() : .default()
		downloads = isPrivate ? BrowserDownloadManager(privateDataStore: dataStore) : .shared
		favicons = isPrivate ? FaviconStore(isPrivate: true) : .shared
		permissions = BrowserSitePermissions(isPrivate: isPrivate)
		#if DEBUG
			assert(dataStore.isPersistent != isPrivate)
		#endif
	}

	func clearWebsiteData() async {
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
