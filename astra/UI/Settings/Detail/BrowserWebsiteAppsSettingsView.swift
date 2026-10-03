#if os(macOS)
	import AppKit
	import SwiftUI

	struct BrowserWebsiteAppsSettingsView: View {
		@State private var registry = BrowserWebsiteAppRegistry.shared
		@State private var editingNames: [UUID: String] = [:]
		@State private var errorMessage: String?

		var body: some View {
			List {
				Section("Website Apps") {
					if registry.installations.isEmpty {
						ContentUnavailableView(
							"No Website Apps",
							systemImage: "macwindow.badge.plus",
							description: Text("Use File → Add Website to Dock… from a normal webpage to create one.")
						)
					} else {
						ForEach(registry.installations) { installation in
							websiteAppRow(installation)
						}
					}
				}

				Section("Dock") {
					Text("Astra can create and launch the website app, which gives it its own running Dock icon. macOS does not provide a supported public API for silently pinning another app permanently, so Keep in Dock remains a system-assisted action.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				if let errorMessage {
					Section("Last Error") {
						Text(verbatim: errorMessage)
							.foregroundStyle(.red)
					}
				}
			}
			.scrollContentBackground(.hidden)
			.listStyle(.sidebar)
		}

		@ViewBuilder
		private func websiteAppRow(_ installation: BrowserWebsiteAppInstallation) -> some View {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Image(nsImage: NSWorkspace.shared.icon(forFile: installation.bundlePath))
						.resizable()
						.frame(width: 32, height: 32)
						.accessibilityHidden(true)
					TextField(
						"Name",
						text: Binding(
							get: { editingNames[installation.id] ?? installation.name },
							set: { editingNames[installation.id] = $0 }
						)
					)
					.textFieldStyle(.roundedBorder)
					.accessibilityIdentifier("website-app-name-\(installation.id)")
					Button("Save Name") {
						perform {
							try registry.rename(installation.id, to: editingNames[installation.id] ?? installation.name)
							editingNames[installation.id] = nil
						}
					}
					.accessibilityIdentifier("website-app-save-name-\(installation.id)")
				}

				Text(installation.launchURL.absoluteString)
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)

				HStack {
					Button("Launch", systemImage: "play") {
						perform { try registry.launch(installation.id) }
					}
					Button("Reveal", systemImage: "folder") {
						perform { try registry.reveal(installation.id) }
					}
					Button("Keep in Dock…", systemImage: "dock.rectangle") {
						perform { try registry.beginKeepInDockFlow(installation.id) }
					}
					Button("Choose Icon…", systemImage: "photo") {
						chooseIcon(for: installation.id)
					}
					Spacer()
					Button("Uninstall", systemImage: "trash", role: .destructive) {
						perform { try registry.uninstall(installation.id) }
					}
				}
				.buttonStyle(.borderless)
			}
			.padding(.vertical, 4)
		}

		private func chooseIcon(for id: UUID) {
			let panel = NSOpenPanel()
			panel.canChooseDirectories = false
			panel.allowsMultipleSelection = false
			panel.allowedContentTypes = [.png, .jpeg, .heic]
			guard panel.runModal() == .OK,
			      let url = panel.url,
			      let image = NSImage(contentsOf: url)
			else { return }
			perform { try registry.updateIcon(id, icon: image) }
		}

		private func perform(_ action: () throws -> Void) {
			do {
				try action()
				errorMessage = nil
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}
#endif
