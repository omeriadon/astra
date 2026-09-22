#if os(macOS)
	import AppKit
	import SwiftUI

	extension FocusedValues {
		@Entry var browser: Browser?
	}

	struct BrowserCommands: Commands {
		@FocusedValue(\.browser) private var browser

		var body: some Commands {
			CommandMenu("Navigation") {
				Button("Back", systemImage: "chevron.backward", action: goBack)
					.keyboardShortcut("[", modifiers: .command)
					.disabled(!(browser?.selectedTab?.controller.canGoBack ?? false))

				Button("Forward", systemImage: "chevron.forward", action: goForward)
					.keyboardShortcut("]", modifiers: .command)
					.disabled(!(browser?.selectedTab?.controller.canGoForward ?? false))

				Divider()

				Button("Reload", systemImage: "arrow.clockwise", action: reload)
					.keyboardShortcut("R", modifiers: .command)
					.disabled(browser?.selectedTab?.controller.url == nil)

				Button("Force Reload", systemImage: "arrow.trianglehead.2.clockwise.rotate.90", action: forceReload)
					.keyboardShortcut("R", modifiers: [.command, .shift])
					.disabled(browser?.selectedTab?.controller.url == nil)
			}

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

		private func goBack() {
			browser?.selectedTab?.controller.goBack()
		}

		private func goForward() {
			browser?.selectedTab?.controller.goForward()
		}

		private func reload() {
			browser?.selectedTab?.controller.reload()
		}

		private func forceReload() {
			browser?.selectedTab?.controller.reloadFromOrigin()
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
