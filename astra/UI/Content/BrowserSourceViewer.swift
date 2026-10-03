#if os(macOS)
	import AppKit
	import SwiftUI
	import UniformTypeIdentifiers

	nonisolated enum BrowserSourceDocumentPolicy {
		static let maximumBytes = 5 * 1024 * 1024

		static func accepts(_ source: String) -> Bool {
			!source.isEmpty && source.utf8.count <= maximumBytes
		}
	}

	@MainActor
	enum BrowserSourceViewer {
		static func show(source: String, title: String, sourceURL: URL?) {
			guard BrowserSourceDocumentPolicy.accepts(source) else { return }
			let view = BrowserSourceViewerView(source: source, title: title, sourceURL: sourceURL)
			let window = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
				styleMask: [.titled, .closable, .miniaturizable, .resizable],
				backing: .buffered,
				defer: false
			)
			window.title = "Source — \(title)"
			window.minSize = NSSize(width: 520, height: 320)
			window.isReleasedWhenClosed = true
			window.contentView = NSHostingView(rootView: view)
			window.center()
			window.makeKeyAndOrderFront(nil)
			NSApp.activate()
		}
	}

	private struct BrowserSourceViewerView: View {
		let source: String
		let title: String
		let sourceURL: URL?
		@State private var saveError: String?

		var body: some View {
			VStack(spacing: 0) {
				HStack(spacing: 8) {
					VStack(alignment: .leading, spacing: 2) {
						Text("Current DOM Source")
							.font(.headline)
						Text("A read-only serialization of the currently committed document. It is not fetched again and cannot execute.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Spacer()
					Button("Copy Source", systemImage: "doc.on.doc") {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(source, forType: .string)
					}
					.accessibilityIdentifier("copy-current-dom-source")
					Button("Save Source", systemImage: "square.and.arrow.down") {
						save()
					}
					.accessibilityIdentifier("save-current-dom-source")
				}
				.padding(12)

				Divider()

				ScrollView([.horizontal, .vertical]) {
					Text(verbatim: source)
						.font(.system(.body, design: .monospaced))
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .topLeading)
						.padding(12)
				}
				.accessibilityIdentifier("current-dom-source-text")

				if let saveError {
					Divider()
					Text(verbatim: saveError)
						.font(.caption)
						.foregroundStyle(.red)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(8)
				}
			}
		}

		private func save() {
			let panel = NSSavePanel()
			panel.allowedContentTypes = [.html, .plainText]
			panel.nameFieldStringValue = BrowserDownloadManager.safeStem(title) + ".html"
			guard panel.runModal() == .OK, let destination = panel.url else { return }
			do {
				try BrowserPageExportPolicy.writeExclusively(Data(source.utf8), to: destination)
				if let sourceURL {
					let attributionURL = BrowserAddress.withoutCredentials(sourceURL)
					try BrowserDownloadedFile.quarantine(destination, downloadURL: attributionURL, sourceURL: attributionURL)
				}
				saveError = nil
			} catch {
				saveError = "Could not save source: \(error.localizedDescription)"
			}
		}
	}
#endif
