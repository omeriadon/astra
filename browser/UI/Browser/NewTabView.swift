import SwiftUI

struct NewTabView: View {
	let browser: Browser

	var body: some View {
		List {
			Section("Bookmarks") {
				ForEach(browser.bookmarks) { bookmark in
					Button {
						browser.openBookmark(bookmark)
					} label: {
						Label {
							VStack(alignment: .leading) {
								Text(verbatim: bookmark.name)
								Text(verbatim: bookmark.url.absoluteString)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						} icon: {
							Image(systemName: "bookmark")
						}
					}
					.buttonStyle(.plain)
					.contextMenu {
						Button(role: .destructive) {
							browser.removeBookmark(bookmark.id)
						} label: {
							Label("Delete Bookmark", systemImage: "trash")
						}
					}
					.accessibilityIdentifier("bookmark-\(bookmark.id.uuidString)")
				}
			}
		}
		.listStyle(.plain)
		.scrollContentBackground(.hidden)
		.background(.black)
	}
}

#Preview {
	NewTabView(browser: Browser())
}
