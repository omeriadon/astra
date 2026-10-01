import Defaults
import SwiftUI

struct BrowserAdvancedSettingsView: View {
	@Default(.searchSuggestionsEnabled) private var searchSuggestionsEnabled
	@Default(.copyMailtoAddresses) private var copyMailtoAddresses
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
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
	}
}
