import SwiftUI

struct BrowserUBlockOriginSettingsSection: View {
	let browser: Browser
	@State private var installer = UBlockOriginInstaller.shared
	@State private var extensions = BrowserExtensionManager.shared
	@State private var showsEnablePrompt = false

	var body: some View {
		Section("uBlock Origin") {
			Text("Get the full uBlock Origin extension directly from its developer’s official release. Updates are checked and installed when you choose Check for Updates.")
				.foregroundStyle(.secondary)
			if let name = extensions.uBlockOriginName {
				NavigationLink {
					BrowserExtensionDetailView(name: name, browser: browser)
				} label: {
					LabeledContent("uBlock Origin", value: extensions.isEnabled(name) ? "On" : "Off")
				}
				.disabled(installer.isBusy)
			}
			Button(extensions.uBlockOriginName == nil ? "Get uBlock Origin" : "Check for Updates", systemImage: "arrow.down.circle") {
				installer.start()
			}
			.disabled(installer.isBusy)
			.accessibilityIdentifier("get-ublock-origin")
			if installer.isBusy {
				if let progress = installer.progress {
					ProgressView(value: progress)
				} else {
					ProgressView().controlSize(.small)
				}
				Button("Cancel", role: .cancel) { installer.cancel() }
					.disabled(installer.isInstalling)
					.accessibilityIdentifier("cancel-ublock-origin")
			}
			if let status = installer.status { Text(status).foregroundStyle(.secondary) }
			if let error = installer.error {
				Text(error).foregroundStyle(.red).textSelection(.enabled)
			}
			if let name = installer.installedName, extensions.installedNames.contains(name), !extensions.isEnabled(name) {
				Button("Review Permissions and Enable", systemImage: "checkmark.shield") { showsEnablePrompt = true }
			}
		}
		.onChange(of: installer.installedName) { _, name in
			showsEnablePrompt = name.map { !extensions.isEnabled($0) } ?? false
		}
		.confirmationDialog("Enable uBlock Origin?", isPresented: $showsEnablePrompt) {
			Button("Enable", systemImage: "checkmark", role: .confirm) {
				if let name = installer.installedName, extensions.installedNames.contains(name) {
					extensions.approveRequestedPermissions(for: name)
					extensions.setEnabled(true, for: name)
				}
			}
			Button(role: .cancel) {}
		} message: {
			Text(installer.installedName.map(extensions.permissionSummary(for:)) ?? "")
		}
	}
}
