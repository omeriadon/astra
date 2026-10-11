import Defaults
import SwiftUI

#if os(macOS)
	import AppKit
#endif

struct BrowserDeveloperSettingsView: View {
	@Default(.browserSearchConfiguration) private var searchConfigurationValue
	@Default(.developerModeEnabled) private var developerModeEnabled
	@Default(.usageLimitsProvider) private var usageLimitsProvider
	#if os(macOS)
		@Default(.webInspectorEnabled) private var webInspectorEnabled
		@State private var browserAgentServer = BrowserAgentServer.shared
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

	#if os(macOS)
		private var browserUseEnabled: Binding<Bool> {
			Binding {
				browserAgentServer.isEnabled
			} set: { enabled in
				browserAgentServer.setEnabled(enabled)
			}
		}
	#endif

	var body: some View {
		List {
			#if os(macOS)
				Section("Web Inspector") {
					Toggle("Enable Web Inspector", isOn: $webInspectorEnabled)
						.accessibilityLabel("Enable Web Inspector")
						.accessibilityIdentifier("web-inspector-enabled")
					Text("Open Astra’s Web Inspector with Option-Command-I or View → Web Inspector. Pages can also be inspected from Safari’s Develop menu.")
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
			Section("Developer Mode") {
				Toggle("Enable Developer Mode", isOn: $developerModeEnabled)
					.accessibilityLabel("Enable Developer Mode")
					.accessibilityIdentifier("developer-mode-enabled")
				Picker("Usage Limits", selection: $usageLimitsProvider) {
					ForEach(BrowserUsageLimitsProvider.allCases, id: \.self) { provider in
						Text(provider.title).tag(provider)
					}
				}
				.pickerStyle(.menu)
				.accessibilityLabel("Usage limits provider")
				.accessibilityIdentifier("usage-limits-provider")
				Text("Localhost tabs enter developer mode automatically. Usage limits use your account signed in to ChatGPT or Claude in Astra and update every two minutes.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			#if os(macOS)
				Section("Browser Use") {
					Toggle("Enable Browser Use", isOn: browserUseEnabled)
						.accessibilityLabel("Enable Browser Use")
						.accessibilityIdentifier("browser-use-enabled")
					LabeledContent("Status", value: browserAgentServer.status)
						.accessibilityIdentifier("browser-use-status")
					if browserAgentServer.isEnabled {
						LabeledContent("Endpoint", value: browserAgentServer.endpoint)
							.accessibilityIdentifier("browser-use-endpoint")
						Button("Copy Codex Configuration", systemImage: "doc.on.doc") {
							NSPasteboard.general.clearContents()
							NSPasteboard.general.setString(browserAgentServer.codexConfiguration, forType: .string)
						}
						.accessibilityLabel("Copy Codex Configuration")
						.accessibilityIdentifier("copy-codex-configuration")
						.disabled(browserAgentServer.codexConfiguration.isEmpty)
					}
					Text("Runs locally and accesses only pages you share or tabs created by an agent. Private tabs are never shared. Access and the connection credential reset when Browser Use is disabled or Astra quits.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			#endif
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
	}
}
