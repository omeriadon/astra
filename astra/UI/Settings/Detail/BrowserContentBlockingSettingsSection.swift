import Defaults
import SwiftUI

struct BrowserContentBlockingSettingsSection: View {
	let session: BrowserWebSession
	@State private var contentBlocking: BrowserContentBlocking
	@Default(.adBlockingEnabled) private var adBlockingEnabled

	init(session: BrowserWebSession) {
		self.session = session
		_contentBlocking = State(initialValue: session.contentBlocking)
	}

	var body: some View {
		Section("Content Blocking") {
			Toggle("Block Ads and Trackers", isOn: $adBlockingEnabled)
				.accessibilityIdentifier("ad-blocking-enabled")

			if let error = contentBlocking.errorDescription {
				Text(error)
					.foregroundStyle(.red)
					.accessibilityIdentifier("native-content-blocking-error")
			}

			Text("Astra blocks common ad networks and trackers before they load. The setting applies to normal and private browsing; site exceptions are controlled from the toolbar.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.task {
			await contentBlocking.prepare()
		}
	}
}
