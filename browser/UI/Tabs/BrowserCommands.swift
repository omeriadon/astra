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
				Button("Open Location", systemImage: "link", action: openLocation)
					.keyboardShortcut("L", modifiers: .command)
					.disabled(browser == nil)

				Button("Back", systemImage: "chevron.backward", action: goBack)
					.keyboardShortcut("[", modifiers: .command)
					.disabled(!(browser?.selectedTab?.activeController?.canGoBack ?? false))

				Button("Forward", systemImage: "chevron.forward", action: goForward)
					.keyboardShortcut("]", modifiers: .command)
					.disabled(!(browser?.selectedTab?.activeController?.canGoForward ?? false))

				Divider()

				Button("Reload", systemImage: "arrow.clockwise", action: reload)
					.keyboardShortcut("R", modifiers: .command)
					.disabled(browser?.selectedTab?.activeController?.url == nil)

				Button("Force Reload", systemImage: "arrow.trianglehead.2.clockwise.rotate.90", action: forceReload)
					.keyboardShortcut("R", modifiers: [.command, .shift])
					.disabled(browser?.selectedTab?.activeController?.url == nil)

				Divider()

				Button("Zoom In", systemImage: "plus.magnifyingglass", action: zoomIn)
					.keyboardShortcut("=", modifiers: .command)
					.disabled(browser?.selectedTab?.activeController?.url == nil)

				Button("Zoom Out", systemImage: "minus.magnifyingglass", action: zoomOut)
					.keyboardShortcut("-", modifiers: .command)
					.disabled(browser?.selectedTab?.activeController?.url == nil)

				Button("Actual Size", systemImage: "1.magnifyingglass") {
					browser?.selectedTab?.activeController?.resetZoom()
				}
				.keyboardShortcut("0", modifiers: .command)
				.disabled(browser?.selectedTab?.activeController?.url == nil)
				.accessibilityIdentifier("browser-reset-zoom")
			}

			CommandMenu("Bookmarks") {
				Button("Add Bookmark", systemImage: "bookmark", action: addBookmark)
					.keyboardShortcut("B", modifiers: .command)
					.disabled(!(browser?.canBookmarkSelectedPage ?? false))
			}

			CommandMenu("Tab") {
				Button("Duplicate Tab", systemImage: "plus.square.on.square", action: duplicateSelectedTab)
					.keyboardShortcut("D", modifiers: .command)
					.disabled(browser?.selectedTab == nil || browser?.selectedTab?.internalPage != nil)

				Button("Copy URL", systemImage: "doc.on.doc", action: copySelectedURL)
					.keyboardShortcut("C", modifiers: .option)
					.disabled(browser?.selectedTab?.activeController?.url == nil)
			}
		}

		private func openLocation() {
			guard let browser else { return }
			if browser.selectedTab?.internalPage != nil {
				browser.addTab()
			} else {
				browser.addressFocusRequest += 1
			}
		}

		private func goBack() {
			browser?.selectedTab?.activeController?.goBack()
		}

		private func goForward() {
			browser?.selectedTab?.activeController?.goForward()
		}

		private func reload() {
			browser?.selectedTab?.activeController?.reload()
		}

		private func forceReload() {
			browser?.selectedTab?.activeController?.reloadFromOrigin()
		}

		private func zoomIn() {
			browser?.selectedTab?.activeController?.zoomIn()
		}

		private func zoomOut() {
			browser?.selectedTab?.activeController?.zoomOut()
		}

		private func addBookmark() {
			browser?.bookmarkSelectedPage()
		}

		private func duplicateSelectedTab() {
			guard let browser else { return }
			browser.duplicateTab(browser.selectedTabID)
		}

		private func copySelectedURL() {
			guard let url = browser?.selectedTab?.activeController?.url else { return }
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(url.absoluteString, forType: .string)
		}
	}
#endif
