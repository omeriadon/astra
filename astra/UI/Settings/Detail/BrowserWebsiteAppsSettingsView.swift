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
			.onChange(of: registry.installations) { old, new in
				let current = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
				for previous in old where current[previous.id] != previous {
					WebsiteAppSettingsIconCache.shared.remove(previous.id)
				}
			}
		}

		private func websiteAppRow(_ installation: BrowserWebsiteAppInstallation) -> some View {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					WebsiteAppSettingsIcon(installation: installation)
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

	/// NSWorkspace is consulted once per installation version, outside row construction.
	/// Keep AppKit image lookup on MainActor; moving it to an unisolated task is unnecessary.
	@MainActor
	private final class WebsiteAppSettingsIconCache {
		static let shared = WebsiteAppSettingsIconCache()
		private final class Entry: NSObject {
			let installation: BrowserWebsiteAppInstallation
			let image: NSImage
			init(_ installation: BrowserWebsiteAppInstallation, image: NSImage) {
				self.installation = installation
				self.image = image
			}
		}

		private let entries: NSCache<NSString, Entry> = {
			let cache = NSCache<NSString, Entry>()
			cache.countLimit = 128
			cache.totalCostLimit = 8 * 1024 * 1024
			return cache
		}()

		func image(for installation: BrowserWebsiteAppInstallation) -> NSImage {
			let key = installation.id.uuidString as NSString
			if let entry = entries.object(forKey: key), entry.installation == installation {
				return entry.image
			}
			let source = NSWorkspace.shared.icon(forFile: installation.bundlePath)
			// Store a small raster backing rather than retaining every representation in the app icon.
			guard let bitmap = unsafe NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
			                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
			                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
				let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
			NSGraphicsContext.saveGraphicsState()
			NSGraphicsContext.current = context
			context.imageInterpolation = .high
			source.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
			NSGraphicsContext.restoreGraphicsState()
			guard let cgImage = bitmap.cgImage else { return source }
			let small = NSImage(cgImage: cgImage, size: NSSize(width: 32, height: 32))
			entries.setObject(Entry(installation, image: small), forKey: key, cost: 64 * 64 * 4)
			return small
		}

		func remove(_ id: UUID) {
			entries.removeObject(forKey: id.uuidString as NSString)
		}
	}

	private struct WebsiteAppSettingsIcon: View {
		let installation: BrowserWebsiteAppInstallation
		@State private var image: NSImage?
		var body: some View {
			Group {
				if let image {
					Image(nsImage: image).resizable()
				} else {
					Color.clear
				}
			}
			.frame(width: 32, height: 32)
			.accessibilityHidden(true)
			.task(id: installation) {
				await Task.yield()
				guard !Task.isCancelled else { return }
				image = WebsiteAppSettingsIconCache.shared.image(for: installation)
			}
		}
	}

#endif
