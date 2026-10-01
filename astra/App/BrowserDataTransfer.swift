#if os(macOS)
	import AppKit
	import UniformTypeIdentifiers

	@MainActor
	enum BrowserDataTransfer {
		static func importData(into browser: Browser, window: NSWindow?) {
			guard !browser.isPrivate, let window else { return }
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [.json, .html]
			panel.allowsMultipleSelection = false
			panel.beginSheetModal(for: window) { response in
				guard response == .OK, let url = panel.url else { return }
				Task {
					do {
						let document = try await Task.detached(priority: .userInitiated) {
							let access = url.startAccessingSecurityScopedResource()
							defer {
								if access {
									url.stopAccessingSecurityScopedResource()
								}
							}
							return try BrowserUserData.decode(
								Data(contentsOf: url),
								isHTML: url.pathExtension.lowercased() == "html" || url.pathExtension.lowercased() == "htm"
							)
						}.value
						browser.importBookmarks(document.bookmarks)
						browser.importHistory(document.history)
						ToastManager.shared.show(symbol: "checkmark.circle", message: "Browsing data imported")
					} catch {
						ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Could not import data: \(error.localizedDescription)")
					}
				}
			}
		}

		static func exportData(from browser: Browser, window: NSWindow?, bookmarksOnly: Bool = false) {
			guard !browser.isPrivate, let window else { return }
			let document = BrowserUserData(bookmarks: browser.bookmarks, history: browser.historyVisits)
			let panel = NSSavePanel()
			panel.allowedContentTypes = bookmarksOnly ? [.html] : [.json]
			panel.nameFieldStringValue = bookmarksOnly ? "Astra Bookmarks.html" : "Astra Browsing Data.json"
			panel.beginSheetModal(for: window) { response in
				guard response == .OK, let url = panel.url else { return }
				Task {
					do {
						try await Task.detached(priority: .utility) {
							let data = try bookmarksOnly ? document.encodedHTML() : JSONEncoder().encode(document)
							let access = url.startAccessingSecurityScopedResource()
							defer {
								if access {
									url.stopAccessingSecurityScopedResource()
								}
							}
							try data.write(to: url, options: .atomic)
						}.value
					} catch {
						ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Could not export data: \(error.localizedDescription)")
					}
				}
			}
		}
	}
#endif
