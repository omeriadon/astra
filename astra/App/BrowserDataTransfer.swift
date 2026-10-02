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
						let duplicates = document.bookmarks.contains { bookmark in browser.bookmarks.contains { $0.url == bookmark.url } }
							|| document.readingList.contains { item in browser.readingList.contains { $0.url == item.url } }
						let applyImport: (Bool) -> Void = { replacing in
							browser.importBookmarks(document.bookmarks, replacingDuplicates: replacing)
							browser.importReadingList(document.readingList, replacingDuplicates: replacing)
							browser.importHistory(document.history)
							ToastManager.shared.show(symbol: "checkmark.circle", message: "Browsing data imported")
						}
						guard duplicates else {
							applyImport(false)
							return
						}
						let alert = NSAlert()
						alert.messageText = "Duplicate bookmarks or reading list items found"
						alert.informativeText = "Choose whether to keep your existing entries or replace their metadata with the imported entries."
						alert.addButton(withTitle: "Keep Existing")
		alert.addButton(withTitle: "Replace Existing")
		alert.addButton(withTitle: "Cancel Import")
		alert.beginSheetModal(for: window) { response in
			guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
			applyImport(response == .alertSecondButtonReturn)
		}
					} catch {
						ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Could not import data: \(error.localizedDescription)")
					}
				}
			}
		}

		static func exportData(from browser: Browser, window: NSWindow?, bookmarksOnly: Bool = false) {
			guard !browser.isPrivate, let window else { return }
		let document = BrowserUserData(bookmarks: browser.bookmarks, history: browser.historyVisits, readingList: browser.readingList)
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
