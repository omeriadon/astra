import Defaults
import SwiftUI
import WebKit

struct BrowserPrivacyAndSecuritySettingsView: View {
	var session: BrowserWebSession = .shared
	@State private var records: [WKWebsiteDataRecord] = []
	@State private var isClearing = false
	@State private var confirmsClear = false
	@Default(.historyRetentionDays) private var historyRetentionDays
	@Default(.tryHTTPSFirst) private var tryHTTPSFirst
	@Default(.globalPrivacyControl) private var globalPrivacyControl

	var body: some View {
		List {
			#if os(macOS)
				Section("Protection") {
					Toggle("Try HTTPS First", isOn: $tryHTTPSFirst)
						.accessibilityIdentifier("try-https-first")
					Toggle("Send Global Privacy Control", isOn: $globalPrivacyControl)
						.accessibilityIdentifier("global-privacy-control")
					Text("HTTPS is tried before falling back to HTTP. Global Privacy Control asks websites not to sell or share your personal information.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			#endif
			Section("Browsing History") {
				Picker("Keep History", selection: $historyRetentionDays) {
					Text("Until Cleared").tag(0)
					Text("7 Days").tag(7)
					Text("30 Days").tag(30)
					Text("90 Days").tag(90)
					Text("1 Year").tag(365)
				}
				.accessibilityIdentifier("history-retention")
			}
			Section("Website Data") {
				Text(session.isPrivate
					? "This window uses temporary website storage. Downloaded files are kept."
					: "Spaces share cookies, logins, and website storage. WebKit manages HTTP caching automatically.")
					.foregroundStyle(.secondary)
				Button("Clear All Website Data", systemImage: "trash", role: .destructive) {
					confirmsClear = true
				}
				.disabled(isClearing)
				.accessibilityIdentifier("clear-all-website-data")
				.id("Clear All Website Data")
				Button("Clear Cache", systemImage: "arrow.clockwise") {
					Task {
						isClearing = true
						await session.dataStore.removeData(
							ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache],
							modifiedSince: .distantPast
						)
						await refreshRecords()
						isClearing = false
					}
				}
				.disabled(isClearing)
				.accessibilityIdentifier("clear-website-cache")
				.id("Clear Cache")
				Button("Clear All Favicons", systemImage: "trash", role: .destructive, action: session.favicons.clear)
					.disabled(session.favicons.isEmpty)
					.accessibilityIdentifier("clear-all-favicons")
					.id("Clear All Favicons")
				ForEach(records, id: \.displayName) { record in
					HStack {
						Text(verbatim: record.displayName)
						Spacer()
						Button("Remove Website Data", systemImage: "trash", role: .destructive) {
							Task {
								isClearing = true
								await session.dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: [record])
								await refreshRecords()
								isClearing = false
							}
						}
						.labelStyle(.iconOnly)
						.disabled(isClearing)
						.accessibilityLabel("Remove data for \(record.displayName)")
						.accessibilityIdentifier("clear-site-\(record.displayName)")
					}
				}
			}
			.id("Website Data")

			Section("Website Permissions") {
				if session.permissions.entries.isEmpty {
					Text("Websites ask before accessing your camera, microphone, or location.")
						.foregroundStyle(.secondary)
				}
				ForEach(session.permissions.entries) { entry in
					HStack {
						VStack(alignment: .leading, spacing: 3) {
							Text(verbatim: entry.origin)
							BrowserSitePermissionPicker(permissions: session.permissions, origin: entry.origin, topOrigin: entry.topOrigin, capability: entry.capability, onChange: { stopCapture(for: entry) })
							if entry.origin != entry.topOrigin {
								Text("Embedded in \(entry.topOrigin)")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						Spacer()
						Button("Reset Permission", systemImage: "arrow.counterclockwise") {
							stopCapture(for: entry)
							session.permissions.remove(entry)
						}
						.labelStyle(.iconOnly)
						.accessibilityLabel("Reset \(entry.capability.title) permission for \(entry.origin)")
						.accessibilityIdentifier("reset-site-permission-\(entry.id)")
					}
				}
				Button("Reset All Website Permissions", systemImage: "arrow.counterclockwise") {
					stopCapture()
					session.permissions.reset()
				}
				.disabled(session.permissions.entries.isEmpty)
				.accessibilityIdentifier("reset-all-site-permissions")
				.id("Reset All Website Permissions")
			}
			.id("Website Permissions")
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
		.task { await refreshRecords() }
		.confirmationDialog("Clear all website data?", isPresented: $confirmsClear) {
			Button("Clear Website Data", systemImage: "trash", role: .destructive) {
				Task {
					isClearing = true
					await session.clearWebsiteData()
					await refreshRecords()
					isClearing = false
				}
			}
			Button(role: .cancel) {}
		} message: {
			Text("This removes cookies, cached content, and website storage, and signs you out of websites.")
		}
	}

	private func refreshRecords() async {
		records = await session.dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
	}

	private func stopCapture(for entry: BrowserSitePermissions.Entry? = nil) {
		for browser in BrowserWindowRegistry.shared.openBrowsers where browser.session === session {
			for tab in browser.tabs {
				let controllers = [tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)
				for controller in controllers {
					if let entry,
					   controller.url.flatMap(BrowserSitePermissions.origin(for:)) != entry.topOrigin
					{
						continue
					}
					controller.stopCapture(capability: entry?.capability)
				}
			}
		}
	}
}
