import SwiftUI

struct BrowserPrivacyAndSecuritySettingsView: View {
	var body: some View {
		List {
			Section("Website Data") {
				Button(role: .destructive, action: FaviconStore.shared.clear) {
					Label("Clear All Favicons", systemImage: "trash")
				}
				.disabled(FaviconStore.shared.isEmpty)
				.accessibilityIdentifier("clear-all-favicons")
				.id("Clear All Favicons")
			}
			.id("Website Data")
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
	}
}
