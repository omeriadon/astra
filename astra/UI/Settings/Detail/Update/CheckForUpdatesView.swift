import SwiftUI

#if os(macOS)
	struct CheckForUpdatesView: View {
		let updates: UpdateManager

		var body: some View {
			Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") {
				updates.checkForUpdates()
			}
			.buttonStyle(.glass)
			.disabled(!updates.canCheckForUpdates)
			.accessibilityIdentifier("check-for-updates")
		}
	}
#endif
