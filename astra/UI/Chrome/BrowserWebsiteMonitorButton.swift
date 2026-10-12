import Defaults
import SwiftUI

struct BrowserWebsiteMonitorButton: View {
	let browser: Browser
	@Default(.aiFeaturesEnabled) private var allFeatures
	@Default(.aiWebsiteMonitoring) private var monitoringEnabled
	@State private var presented = false
	@State private var criterion = ""
	@State private var interval = 1
	@State private var saving = false
	@State private var error: String?
	@Namespace private var transitions

	var body: some View {
		if allFeatures, monitoringEnabled, browser.canShowAISidebar {
			Color.clear
				.frame(width: 0, height: 0)
				.onReceive(NotificationCenter.default.publisher(for: .astraMonitorWebsite)) { notification in
					guard let owner = notification.object as? Browser, owner === browser else { return }
					guard browser.selectedTab?.activeController?.hasCurrentPageDocument == true else { return }
					presented = true
				}
				.sheet(isPresented: $presented) {
					NavigationStack {
						List {
							Section("Condition") {
								TextField("Tell me when this website…", text: $criterion, axis: .vertical)
									.lineLimit(3 ... 6)
									.accessibilityIdentifier("monitor-condition")
								Picker("Check Every", selection: $interval) {
									Text("Day").tag(1)
									Text("Week").tag(7)
									Text("Two Weeks").tag(14)
									Text("Month").tag(30)
								}
								.accessibilityIdentifier("monitor-interval")
								Text("Checks run on the server even when your Mac is closed. The public page and condition use Default AI and require an Astra account. Results are delivered when Astra reconnects.")
									.font(.caption)
									.foregroundStyle(.secondary)
								if let error {
									Text(error).foregroundStyle(.secondary)
								}
							}
						}
						.listStyle(.sidebar)
						.scrollContentBackground(.hidden)
						.navigationTitle("Monitor Website")
						.toolbar {
							ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { presented = false } }
							ToolbarItem(placement: .confirmationAction) {
								Button("Start Monitoring", systemImage: "bell.badge", role: .confirm, action: save)
									.buttonStyle(.glassProminent)
									.disabled(saving || criterion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
									.accessibilityIdentifier("monitor-start")
							}
						}
					}
					#if os(macOS)
					.frame(minWidth: 400, idealWidth: 480, minHeight: 360, idealHeight: 420)
					.presentationSizing(.fitted)
					#else
					.presentationDetents([.fraction(0.6)])
					.navigationTransition(.zoom(sourceID: "monitor-website", in: transitions))
					#endif
				}
		}
	}

	private func save() {
		saving = true
		Task {
			defer { saving = false }
			do {
				try await BrowserWebsiteMonitoring.shared.create(browser: browser, criterion: criterion, intervalDays: interval)
				presented = false
				criterion = ""
			} catch { self.error = error.localizedDescription }
		}
	}
}
