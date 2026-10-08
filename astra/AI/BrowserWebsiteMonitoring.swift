import Defaults
import Foundation
import Observation
import UserNotifications

nonisolated struct BrowserWebsiteMonitor: Codable, Identifiable, Equatable, Sendable {
	let id: UUID
	let spaceID: UUID
	let url: String
	let title: String
	let criterion: String
	let intervalDays: Int
	let enabled: Bool
	let nextCheck: Double
	let matchedAt: Double?
	let message: String?
	let lastError: String?
	let checks: Int
}

nonisolated struct BrowserWebsiteMonitorInput: Encodable, Sendable {
	let spaceID: UUID
	let url: String
	let title: String
	let criterion: String
	let instructions: String
	let intervalDays: Int
}

nonisolated struct BrowserMonitorMatch: Codable, Equatable, Sendable {
	let id: UUID
	let criterion: String
	let message: String
}

nonisolated struct BrowserMonitorState: Codable { let enabled: Bool }
nonisolated struct BrowserMonitorDeleted: Decodable { let deleted: Bool }

@MainActor
@Observable
final class BrowserWebsiteMonitoring {
	static let shared = BrowserWebsiteMonitoring()
	static let category = "astra.website-monitor"
	private(set) var monitors: [BrowserWebsiteMonitor] = []
	private(set) var error: String?
	@ObservationIgnored private var polling: Task<Void, Never>?
	@ObservationIgnored private var isRefreshing = false

	func start() {
		BrowserLog.info(.ai, "website-monitoring.start")
		guard polling == nil else { return }
		polling = Task {
			while !Task.isCancelled {
				await refresh()
				do { try await Task.sleep(for: .seconds(60)) } catch { break }
			}
		}
	}

	func create(browser: Browser, criterion: String, intervalDays: Int) async throws {
		BrowserLog.info(.ai, "website-monitor.create", metadata: ["window": BrowserLog.id(browser.windowID), "criterion": BrowserLog.value(criterion), "interval_days": String(intervalDays), "url": BrowserLog.url(browser.selectedTab?.currentURL)])
		guard browser.canShowAISidebar, Defaults[.aiFeaturesEnabled], Defaults[.aiWebsiteMonitoring],
		      let tab = browser.selectedTab, let url = tab.currentURL else { throw BrowserAIError.disabled }
		let input = BrowserWebsiteMonitorInput(spaceID: browser.selectedSpace.id, url: BrowserAddress.withoutCredentials(url).absoluteString, title: String(tab.title.prefix(240)), criterion: criterion, instructions: BrowserAIPrompts.websiteMonitor, intervalDays: intervalDays)
		let result = try await BrowserSync.shared.createWebsiteMonitor(input)
		monitors.append(result)
		await BrowserAIUsageLog.shared.record(id: result.id, feature: "Website Monitoring", provider: "Default", event: "success", details: "phase=scheduled interval_days=\(intervalDays)")
		_ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
	}

	func setEnabled(_ enabled: Bool) async {
		BrowserLog.notice(.ai, "website-monitoring.set-enabled", metadata: ["enabled": String(enabled)])
		guard BrowserSync.shared.isSignedIn else { return }
		do { try await BrowserSync.shared.setWebsiteMonitorsEnabled(enabled); await refresh() }
		catch { self.error = error.localizedDescription }
	}

	func remove(_ id: UUID) async {
		BrowserLog.info(.ai, "website-monitor.remove", metadata: ["id": BrowserLog.id(id)])
		do { try await BrowserSync.shared.deleteWebsiteMonitor(id); monitors.removeAll { $0.id == id } }
		catch { self.error = error.localizedDescription }
	}

	func refresh() async {
		BrowserLog.debug(.ai, "website-monitoring.refresh")
		guard !isRefreshing, BrowserSync.shared.isSignedIn else { return }
		isRefreshing = true
		defer { isRefreshing = false }
		do {
			let latest = try await BrowserSync.shared.websiteMonitors()
			// The polling response is usually identical. Avoid invalidating all
			// consumers of this observable array every minute for no state change.
			if latest != monitors { monitors = latest }
			if error != nil { error = nil }
			guard Defaults[.aiFeaturesEnabled], Defaults[.aiWebsiteMonitoring] else { return }
			for monitor in monitors where monitor.matchedAt != nil {
				let key = monitor.id.uuidString
				guard Defaults[.deliveredWebsiteMonitors][key] == nil,
				      let url = BrowserHomepage.validURL(monitor.url), let message = monitor.message,
				      let browser = BrowserWindowRegistry.shared.openBrowsers.first(where: { !$0.isPrivate && $0.isReadyForSync && $0.workspace.spaces.contains(where: { $0.id == monitor.spaceID }) }) else { continue }
				let tab = browser.tabs.first(where: { $0.monitorMatch?.id == monitor.id }) ?? browser.openHistoryURL(url, inBackground: true)
				browser.moveTab(tab.id, to: .pinned, in: monitor.spaceID)
				tab.setMonitorMatch(.init(id: monitor.id, criterion: monitor.criterion, message: message))
				await browser.flushAndWaitForPersistence()
				guard browser.persistenceErrorDescription == nil,
				      BrowserWindowRegistry.shared.openBrowsers.contains(where: { $0 === browser })
				else {
					error = "The matched website tab could not be saved yet. Delivery will be retried."
					continue
				}
				Defaults[.deliveredWebsiteMonitors][key] = tab.id.uuidString
				let content = UNMutableNotificationContent()
				content.title = "Website condition met"
				content.body = message
				content.sound = .default
				content.categoryIdentifier = Self.category
				content.userInfo = ["monitorID": key]
				try? await UNUserNotificationCenter.current().add(.init(identifier: "astra.monitor.\(key)", content: content, trigger: nil))
				await BrowserAIUsageLog.shared.record(id: monitor.id, feature: "Website Monitoring", provider: "Default", event: "success", details: "phase=fulfilled server_checks=\(monitor.checks)")
			}
		} catch {
			if !Task.isCancelled {
				self.error = error.localizedDescription
			}
		}
	}

	func openNotification(_ id: String) {
		BrowserLog.info(.ai, "website-monitor.notification-open", metadata: ["id": BrowserLog.value(id)])
		guard let tabID = Defaults[.deliveredWebsiteMonitors][id].flatMap(UUID.init(uuidString:)),
		      let browser = BrowserWindowRegistry.shared.openBrowsers.first(where: { !$0.isPrivate && $0.tabs.contains(where: { $0.id == tabID }) }) else { return }
		browser.selectTab(tabID)
	}
}
