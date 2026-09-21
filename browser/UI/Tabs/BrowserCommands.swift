#if os(macOS)
	import AppKit
	import SwiftUI

	extension FocusedValues {
		@Entry var browser: Browser?
	}

	struct BrowserCommands: Commands {
		@FocusedValue(\.browser) private var browser

		var body: some Commands {
			CommandMenu("Bookmarks") {
				Button("Add Bookmark", systemImage: "bookmark", action: addBookmark)
					.keyboardShortcut("B", modifiers: .command)
					.disabled(!(browser?.canBookmarkSelectedPage ?? false))
			}

			CommandMenu("Tab") {
				Button("Duplicate Tab", systemImage: "plus.square.on.square", action: duplicateSelectedTab)
					.keyboardShortcut("D", modifiers: .command)
					.disabled(browser == nil)

				Button("Copy URL", systemImage: "doc.on.doc", action: copySelectedURL)
					.keyboardShortcut("C", modifiers: .option)
					.disabled(browser?.selectedTab?.controller.url == nil)
			}
		}

		private func addBookmark() {
			browser?.bookmarkSelectedPage()
		}

		private func duplicateSelectedTab() {
			guard let browser else { return }
			browser.duplicateTab(browser.selectedTabID)
		}

		private func copySelectedURL() {
			guard let url = browser?.selectedTab?.controller.url else { return }
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(url.absoluteString, forType: .string)
		}
	}
#endif
