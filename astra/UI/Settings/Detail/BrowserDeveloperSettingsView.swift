import Defaults
import SwiftUI

struct BrowserDeveloperSettingsView: View {
	@Default(.browserSearchConfiguration) private var searchConfigurationValue
	#if os(macOS)
		@Default(.webInspectorEnabled) private var webInspectorEnabled
	#endif

	private var githubShorthandEnabled: Binding<Bool> {
		Binding {
			BrowserSearchConfiguration.decode(searchConfigurationValue).githubRepositoryShorthandEnabled
		} set: { enabled in
			var configuration = BrowserSearchConfiguration.decode(searchConfigurationValue)
			configuration.githubRepositoryShorthandEnabled = enabled
			searchConfigurationValue = configuration.encoded
		}
	}

	var body: some View {
		List {
			#if os(macOS)
				Section("Web Inspector") {
					Toggle("Allow Web Inspector in Safari", isOn: $webInspectorEnabled)
						.accessibilityLabel("Allow Web Inspector in Safari")
						.accessibilityIdentifier("web-inspector-enabled")
					Text("Inspect pages from Safari’s Develop menu. This applies when each page is created; Astra has no public embedded inspector command.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			#endif
			Section("GitHub") {
				Toggle("GitHub Repository Shorthand", isOn: githubShorthandEnabled)
					.accessibilityLabel("GitHub repository shorthand")
					.accessibilityIdentifier("github-repository-shorthand-enabled")
				Text("Open owner/repository directly on GitHub instead of searching for it. Suggestions show the GitHub icon and destination URL.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
	}
}
