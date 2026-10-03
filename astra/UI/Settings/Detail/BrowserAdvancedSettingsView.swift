import Defaults
import SwiftUI

struct BrowserAdvancedSettingsView: View {
	@Default(.searchSuggestionsEnabled) private var searchSuggestionsEnabled
	@Default(.copyMailtoAddresses) private var copyMailtoAddresses
	@State private var showingResetConfirmation = false
	#if os(macOS)
		@Default(.requireDoublePressToQuit) private var requireDoublePressToQuit
	#endif

	var body: some View {
		List {
			Section("Search") {
				Toggle("Show Search Suggestions", isOn: $searchSuggestionsEnabled)
					.accessibilityIdentifier("search-suggestions-enabled")
				Text("Suggestions send what you type to the search provider. They are disabled in private windows.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Section("Links") {
				Toggle("Copy email addresses from mailto links", isOn: $copyMailtoAddresses)
					.accessibilityIdentifier("copy-mailto-addresses")
					.id("Copy email addresses from mailto links")
			}
			.id("Links")

			#if os(macOS)
				Section("Quit") {
					Toggle("Press Command-Q twice to quit", isOn: $requireDoublePressToQuit)
						.accessibilityIdentifier("require-double-press-to-quit")
						.id("Press Command-Q twice to quit")
				}
				.id("Quit")
			#endif

			Section("Reset") {
				Button("Reset Browser Settings", systemImage: "arrow.counterclockwise") {
					showingResetConfirmation = true
				}
				.accessibilityIdentifier("reset-browser-settings")
				Text("Restores browser preferences. History, website data, bookmarks, downloads, extensions, credentials and account data are not deleted.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
		.confirmationDialog(
			"Reset browser settings?",
			isPresented: $showingResetConfirmation,
			titleVisibility: .visible
		) {
			Button("Reset Settings", role: .destructive) {
				BrowserSettingsSchema.resetBrowserSettings()
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Browsing data and account data will remain unchanged.")
		}
	}
}
