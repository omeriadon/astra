import Defaults
import SwiftUI

struct BrowserAdvancedSettingsView: View {
	@Default(.copyMailtoAddresses) private var copyMailtoAddresses
	#if os(macOS)
		@Default(.requireDoublePressToQuit) private var requireDoublePressToQuit
	#endif

	var body: some View {
		List {
			Section("Links") {
				Toggle("Copy email addresses from mailto links", isOn: $copyMailtoAddresses)
					.accessibilityIdentifier("copy-mailto-addresses")
			}

			#if os(macOS)
				Section("Quit") {
					Toggle("Press Command-Q twice to quit", isOn: $requireDoublePressToQuit)
						.accessibilityIdentifier("require-double-press-to-quit")
				}
			#endif
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
	}
}
