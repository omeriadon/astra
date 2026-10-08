#if os(macOS)
	import AppKit
	import SwiftUI
	import UniformTypeIdentifiers

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
					Text("Website apps are pinned to the Dock when created. Use Keep in Dock to pin an existing website app again after removing its Dock icon.")
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
							try await registry.rename(installation.id, to: editingNames[installation.id] ?? installation.name)
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
						perform { try await registry.launch(installation.id) }
					}
					Button("Reveal", systemImage: "folder") {
						perform { try registry.reveal(installation.id) }
					}
					Button("Keep in Dock", systemImage: "dock.rectangle") {
						Task { @MainActor in
							do {
								try await registry.beginKeepInDockFlow(installation.id)
								errorMessage = nil
							} catch {
								errorMessage = error.localizedDescription
							}
						}
					}
					.accessibilityLabel("Keep \(installation.name) in Dock")
					.accessibilityIdentifier("website-app-keep-in-dock-\(installation.id)")
					Button("Choose Icon…", systemImage: "photo") {
						chooseIcon(for: installation.id)
					}
					Spacer()
					Button("Uninstall", systemImage: "trash", role: .destructive) {
						perform { try await registry.uninstall(installation.id) }
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
			perform { try await registry.updateIcon(id, icon: image) }
		}

		private func perform(_ action: @escaping @MainActor () async throws -> Void) {
			Task { @MainActor in
				do {
					try await action()
					errorMessage = nil
				} catch {
					errorMessage = error.localizedDescription
				}
			}
		}
	}
#endif
