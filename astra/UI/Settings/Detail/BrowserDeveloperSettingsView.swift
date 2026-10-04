import Defaults
import SwiftUI

struct BrowserDeveloperSettingsView: View {
	@Default(.browserSearchConfiguration) private var searchConfigurationValue

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
