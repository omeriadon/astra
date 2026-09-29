import Defaults
import SwiftUI

struct BrowserAdvancedSettingsView: View {
	@Default(.copyMailtoAddresses) private var copyMailtoAddresses

	var body: some View {
		List {
			Section("Links") {
				Toggle("Copy email addresses from mailto links", isOn: $copyMailtoAddresses)
					.accessibilityIdentifier("copy-mailto-addresses")
			}
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
	}
}
