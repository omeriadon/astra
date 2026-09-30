import SwiftUI

struct BrowserBookmarksView: View {
	let browser: Browser

	var body: some View {
		List {
			Section("Bookmarks") {
				ForEach(browser.bookmarks) { bookmark in
					HistoryRow(
						title: bookmark.name,
						detail: bookmark.url.absoluteString,
						url: bookmark.url,
						symbol: "bookmark",
						identifier: "bookmark-\(bookmark.id.uuidString)",
						open: { browser.openBookmark(bookmark) },
						openInBackground: { browser.openHistoryURL(bookmark.url, inBackground: true) }
					)
					.equatable()
					.contextMenu {
						Button(role: .destructive) {
							browser.removeBookmark(bookmark.id)
						} label: {
							Label("Delete Bookmark", systemImage: "trash")
						}
					}
				}
			}
		}
		#if os(iOS)
		.listStyle(.insetGrouped)
		#else
		.listStyle(.sidebar)
		#endif
		.scrollContentBackground(.hidden)
		#if os(macOS)
			.safeAreaBar(edge: .top) {
				Label("Bookmarks", systemImage: "bookmark")
					.font(.title2.bold())
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 24)
					.padding(.vertical, 14)
			}
		#endif
			.overlay {
				if browser.bookmarks.isEmpty {
					ContentUnavailableView("No Bookmarks", systemImage: "bookmark")
				}
			}
	}
}

#Preview {
	BrowserBookmarksView(browser: Browser())
}
