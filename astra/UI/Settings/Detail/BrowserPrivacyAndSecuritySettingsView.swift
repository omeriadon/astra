import Defaults
import SwiftUI
import WebKit

struct BrowserPrivacyAndSecuritySettingsView: View {
	var session: BrowserWebSession = .shared
	@State private var records: [WKWebsiteDataRecord] = []
	@State private var isClearing = false
	@State private var confirmsClear = false
	@State private var confirmsSitePreferenceReset = false
	@State private var websiteDataRange: BrowserWebsiteDataRange = .allTime
	@State private var recordsRefreshID = UUID()
	@Default(.historyRetentionDays) private var historyRetentionDays
	@Default(.tryHTTPSFirst) private var tryHTTPSFirst
	@Default(.globalPrivacyControl) private var globalPrivacyControl

	private var visiblePermissionEntries: [BrowserSitePermissions.Entry] {
		session.permissions.entries.filter { BrowserSitePermissions.websiteCapabilities.contains($0.capability) }
	}

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
			BrowserContentBlockingSettingsSection(session: session)
			Section("Media Playback") {
				Text("Audio and video require a click to play on every site.")
					.foregroundStyle(.secondary)
			}
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
			Section("Site Preferences") {
				Text("Sites without an override keep the tab's zoom, which starts from Default Page Zoom. Site zoom changes apply to matching open tabs. Desktop, mobile, and custom user-agent changes apply on the next navigation.")
					.font(.caption)
					.foregroundStyle(.secondary)
				if session.sitePreferences.isZoomDataReadOnly || session.sitePreferences.isLocalDataReadOnly {
					Text("Astra preserved saved preferences it cannot read and disabled changes to those preference types.")
						.foregroundStyle(.secondary)
				}
				Button("Reset All Site Preferences", systemImage: "arrow.counterclockwise", role: .destructive) {
					confirmsSitePreferenceReset = true
				}
				.disabled(!session.sitePreferences.hasPreferences || (session.sitePreferences.isZoomDataReadOnly && session.sitePreferences.isLocalDataReadOnly))
				.accessibilityIdentifier("reset-all-site-preferences")
			}
			.id("Site Preferences")
			Section("Website Data") {
				Text(session.isPrivate
					? "This window uses temporary website storage. Downloaded files are kept."
					: "Spaces share cookies, logins, and website storage. WebKit manages HTTP caching automatically.")
					.foregroundStyle(.secondary)
				Picker("Time Range", selection: $websiteDataRange) {
					ForEach(BrowserWebsiteDataRange.allCases) { range in
						Text(range.title).tag(range)
					}
				}
				.accessibilityIdentifier("website-data-range")
				Button("Clear Website Data", systemImage: "trash", role: .destructive) {
					confirmsClear = true
				}
				.disabled(isClearing)
				.accessibilityIdentifier("clear-website-data")
				.id("Clear Website Data")
				Text("WebKit selects website records by when a website last changed the record. It cannot promise exact per-cookie or per-origin time deletion. Each listed site is WebKit's grouped domain label, not an exact origin. Clearing website data also clears all saved Astra favicons. History and website permission choices remain separate.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Button("Clear Cache", systemImage: "arrow.clockwise") {
					Task {
						guard !isClearing else { return }
						isClearing = true
						defer { isClearing = false }
						await session.dataStore.removeData(
							ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache],
							modifiedSince: .distantPast
						)
						await refreshRecords()
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
								guard !isClearing else { return }
								isClearing = true
								defer { isClearing = false }
								await session.clearWebsiteData(for: record)
								await refreshRecords()
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
				if session.permissions.isSavedDataReadOnly {
					Text("Saved permission settings use a newer format. Reset all website permissions before changing them.")
						.foregroundStyle(.secondary)
				}
				if visiblePermissionEntries.isEmpty {
					Text("Website controls include camera, microphone, location, pop-ups, and automatic downloads. Camera, microphone, and location also require system permission. Motion access is available on iOS.")
						.foregroundStyle(.secondary)
				}
				ForEach(visiblePermissionEntries) { entry in
					HStack {
						VStack(alignment: .leading, spacing: 3) {
							Text(verbatim: entry.origin)
							BrowserSitePermissionPicker(permissions: session.permissions, origin: entry.origin, topOrigin: entry.topOrigin, capability: entry.capability)
							if entry.origin != entry.topOrigin {
								Text("Embedded in \(entry.topOrigin)")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						Spacer()
						Button("Reset Permission", systemImage: "arrow.counterclockwise") {
							session.permissions.remove(entry)
						}
						.labelStyle(.iconOnly)
						.accessibilityLabel("Reset \(entry.capability.title) permission for \(entry.origin)")
						.accessibilityIdentifier("reset-site-permission-\(entry.id)")
					}
				}
				Button("Reset All Website Permissions", systemImage: "arrow.counterclockwise") {
					session.permissions.reset()
				}
				.disabled(!session.permissions.hasDecisions)
				.accessibilityIdentifier("reset-all-site-permissions")
				.id("Reset All Website Permissions")
			}
			.id("Website Permissions")
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
		.task { await refreshRecords() }
		.confirmationDialog("Clear website data for the selected range?", isPresented: $confirmsClear) {
			Button("Clear Website Data", systemImage: "trash", role: .confirm) {
				Task { await clearWebsiteData() }
			}
			.buttonStyle(.glassProminent)
			Button(role: .cancel) {}
		} message: {
			Text(verbatim: clearWebsiteDataMessage)
		}
		.confirmationDialog("Reset all site preferences?", isPresented: $confirmsSitePreferenceReset) {
			Button("Reset Site Preferences", systemImage: "arrow.counterclockwise", role: .confirm) {
				session.sitePreferences.resetAll()
			}
			.buttonStyle(.glassProminent)
			Button(role: .cancel) {}
		} message: {
			Text("Per-site zoom, desktop/mobile choices, and custom user agents will be removed. Matching open tabs return to Default Page Zoom. Website data, history, and permissions remain separate.")
		}
	}

	private var clearWebsiteDataMessage: String {
		let rangeDescription = switch websiteDataRange {
			case .lastHour: "records changed during the last hour"
			case .today: "records changed since the start of today"
			case .allTime: "all website data records"
		}
		return "This removes \(rangeDescription), clears all saved Astra favicons, and signs you out where matching records are removed. History and website permission choices remain separate."
	}

	private func clearWebsiteData() async {
		guard !isClearing else { return }
		isClearing = true
		defer { isClearing = false }
		await session.clearWebsiteData(since: websiteDataRange.modifiedSince())
		await refreshRecords()
	}

	private func refreshRecords() async {
		let refreshID = UUID()
		recordsRefreshID = refreshID
		let updatedRecords = await session.dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
		guard recordsRefreshID == refreshID else { return }
		records = updatedRecords
	}

}
