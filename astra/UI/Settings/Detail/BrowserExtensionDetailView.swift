import SwiftUI

struct BrowserExtensionDetailView: View {
	let name: String
	let browser: Browser
	@State private var extensions = BrowserExtensionManager.shared
	@Environment(\.dismiss) private var dismiss
	@State private var showsRemoveConfirmation = false

	var body: some View {
		List {
			Section {
				Toggle("Enabled", isOn: Binding(
					get: { extensions.isEnabled(name) },
					set: { extensions.setEnabled($0, for: name) }
				))
				.accessibilityIdentifier("extension-enabled-\(name)")
				Toggle("Pin to Toolbar", isOn: Binding(
					get: { extensions.isPinned(name) },
					set: { extensions.setPinned($0, for: name) }
				))
				.accessibilityIdentifier("extension-pinned-\(name)")
				Button("Reload Extension", systemImage: "arrow.clockwise") {
					extensions.reloadExtension(name)
				}
				.disabled(!extensions.isEnabled(name))
				.accessibilityIdentifier("extension-reload-\(name)")
			}
			Section("About") {
				Text(extensions.description(for: name))
				LabeledContent("Version", value: extensions.version(for: name))
				LabeledContent("ID", value: name)
				LabeledContent("Source", value: extensions.source(for: name) == .chrome ? "Chrome" : "Safari")
				Text(extensions.sourcePath(for: name))
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
			}
			Section("Permissions") {
				Text(extensions.permissionSummary(for: name))
			}
			Section("Site Access") {
				Picker("Website Access", selection: Binding(
					get: { extensions.allowsAllSites(name) },
					set: { extensions.setAllowsAllSites($0, for: name) }
				)) {
					Text("On All Websites").tag(true)
					Text("When Used").tag(false)
				}
				.pickerStyle(.menu)
				.accessibilityIdentifier("extension-site-access-\(name)")
				Text("When Used grants access to the current website for five minutes after opening the extension.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Toggle("Allow Access to File URLs", isOn: Binding(
					get: { extensions.allowsFileAccess(name) },
					set: { extensions.setAllowsFileAccess($0, for: name) }
				))
				.accessibilityIdentifier("extension-file-access-\(name)")
			}
			if let options = extensions.optionsURL(for: name) {
				Section {
					Button("Extension Options", systemImage: "arrow.up.right.square") {
						browser.openHistoryURL(options, inBackground: false)
					}
					.accessibilityIdentifier("extension-options-\(name)")
				}
			}
			let errors = extensions.errors(for: name)
			if !errors.isEmpty {
				Section("Errors") {
					ForEach(errors, id: \.self) { Text($0).textSelection(.enabled) }
				}
			}
			if extensions.installedNames.contains(name) {
				Section {
					Button("Remove Extension", systemImage: "trash", role: .destructive) {
						showsRemoveConfirmation = true
					}
					.accessibilityIdentifier("extension-remove-\(name)")
				}
			}
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
		.navigationTitle(extensions.title(for: name))
		.confirmationDialog("Remove \(extensions.title(for: name))?", isPresented: $showsRemoveConfirmation) {
			Button("Remove Extension", systemImage: "trash", role: .destructive) {
				extensions.removeInstalled(name)
				dismiss()
			}
			Button(role: .cancel) {}
		}
	}
}
