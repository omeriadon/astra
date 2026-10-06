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
			Button("Monitor Website", systemImage: "bell.and.waves.left.and.right") { presented = true }
				.labelStyle(.iconOnly)
				.buttonStyle(.bordered)
				.help("Monitor website")
				.accessibilityIdentifier("monitor-website")
				.matchedTransitionSource(id: "monitor-website", in: transitions)
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
					.presentationDetents([.fraction(0.6)])
					#if os(iOS)
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
