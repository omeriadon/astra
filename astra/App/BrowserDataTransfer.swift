#if os(macOS)
	import AppKit
	import UniformTypeIdentifiers

	@MainActor
	enum BrowserDataTransfer {
		static func importData(into browser: Browser, window: NSWindow?) {
			BrowserLog.info(.persistence, "data-transfer.import.begin", metadata: ["window": BrowserLog.id(browser.windowID)])
			guard !browser.isPrivate, !browser.isMini, let window else { return }
			let isCurrent = currentBrowser(browser, in: window)
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [.json, .html]
			panel.allowsMultipleSelection = false
			panel.beginSheetModal(for: window) { response in
				guard response == .OK, let url = panel.url else { return }
				guard isCurrent() else {
					url.stopAccessingSecurityScopedResource()
					return
				}
				Task { @MainActor in
					do {
						let document = try await Task.detached(priority: .userInitiated) {
							defer { url.stopAccessingSecurityScopedResource() }
							return try BrowserUserData.decode(
								Data(contentsOf: url),
								isHTML: url.pathExtension.lowercased() == "html" || url.pathExtension.lowercased() == "htm"
							)
						}.value
						guard isCurrent() else { return }
						let hasDuplicates = document.bookmarks.contains { bookmark in
							browser.bookmarks.contains { $0.url == bookmark.url }
						} || document.readingList.contains { item in
							browser.readingList.contains { $0.url == item.url }
						}
						var replacingDuplicates = false
						if hasDuplicates {
							let alert = NSAlert()
							alert.messageText = "Duplicate bookmarks or reading list items found"
							alert.informativeText = "Choose whether to keep your existing entries or replace their metadata with the imported entries."
							alert.addButton(withTitle: "Keep Existing")
							alert.addButton(withTitle: "Replace Existing")
							alert.addButton(withTitle: "Cancel Import")
							let response = await BrowserWebsiteUI.present(alert, in: window, isCurrent: isCurrent)
							guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn,
							      isCurrent() else { return }
							replacingDuplicates = response == .alertSecondButtonReturn
						}
						guard isCurrent() else { return }
						browser.importBookmarks(document.bookmarks, replacingDuplicates: replacingDuplicates)
						browser.importReadingList(document.readingList, replacingDuplicates: replacingDuplicates)
						browser.importHistory(document.history)
						BrowserLog.info(.persistence, "data-transfer.import.success", metadata: ["bookmarks": String(document.bookmarks.count), "reading_list": String(document.readingList.count), "history": String(document.history.count), "source": BrowserLog.path(url)])
						ToastManager.shared.show(symbol: "checkmark.circle", message: "Browsing data imported")
					} catch {
						guard isCurrent() else { return }
						BrowserLog.error(.persistence, "data-transfer.import.failed", metadata: ["error": BrowserLog.errorDescription(error), "source": BrowserLog.path(url)])
						ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Could not import data: \(error.localizedDescription)")
					}
				}
			}
		}

		static func exportData(from browser: Browser, window: NSWindow?, bookmarksOnly: Bool = false) {
			BrowserLog.info(.persistence, "data-transfer.export.begin", metadata: ["window": BrowserLog.id(browser.windowID), "bookmarks_only": String(bookmarksOnly), "bookmarks": String(browser.bookmarks.count), "history": String(browser.historyVisits.count)])
			guard !browser.isPrivate, !browser.isMini, let window else { return }
			let isCurrent = currentBrowser(browser, in: window)
			let panel = NSSavePanel()
			panel.allowedContentTypes = bookmarksOnly ? [.html] : [.json]
			panel.nameFieldStringValue = bookmarksOnly ? "Astra Bookmarks.html" : "Astra Browsing Data.json"
			panel.beginSheetModal(for: window) { response in
				guard response == .OK, let url = panel.url else { return }
				guard isCurrent() else {
					url.stopAccessingSecurityScopedResource()
					return
				}
				let document = BrowserUserData(bookmarks: browser.bookmarks, history: browser.historyVisits, readingList: browser.readingList)
				Task { @MainActor in
					do {
						try await Task.detached(priority: .utility) {
							defer { url.stopAccessingSecurityScopedResource() }
							let data = try bookmarksOnly ? document.encodedHTML() : JSONEncoder().encode(document)
							try data.write(to: url, options: .atomic)
						}.value
						guard isCurrent() else { return }
					} catch {
						guard isCurrent() else { return }
						ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Could not export data: \(error.localizedDescription)")
					}
				}
			}
		}

		private static func currentBrowser(_ browser: Browser, in window: NSWindow) -> @MainActor () -> Bool {
			let id = browser.windowID
			return {
				window.isVisible
					&& !browser.isPrivate
					&& !browser.isMini
					&& browser.windowID == id
					&& BrowserWindowRegistry.shared.openBrowsers.contains { $0 === browser }
			}
		}
	}
#endif
