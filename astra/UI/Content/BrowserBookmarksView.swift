import SwiftUI

struct BrowserBookmarksView: View {
	let browser: Browser
	@Environment(\.editMode) private var editMode
	@Namespace private var transitions
	@State private var searchText = ""
	@State private var showingReadingList = false
	@State private var editingBookmark: Bookmark?

	private var visibleBookmarks: [Bookmark] {
		browser.bookmarks
			.filter { searchText.isEmpty || [$0.name, $0.url.absoluteString, $0.folder].contains { $0.localizedCaseInsensitiveContains(searchText) } }
			.sorted {
				if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
				if $0.folder != $1.folder { return $0.folder.localizedStandardCompare($1.folder) == .orderedAscending }
				if $0.order != $1.order { return $0.order < $1.order }
				return $0.name.localizedStandardCompare($1.name) == .orderedAscending
			}
	}

	var body: some View {
		List {
			if showingReadingList {
				Section("Reading List") {
					ForEach(browser.readingList.sorted { $0.addedAt > $1.addedAt }) { item in
						HistoryRow(
							title: item.title,
							detail: item.isRead ? "Read · \(item.url.absoluteString)" : item.url.absoluteString,
							url: item.url,
							symbol: item.isRead ? "text.book.closed" : "text.book.closed.fill",
							identifier: "reading-item-\(item.id.uuidString)",
							open: { browser.openHistoryURL(item.url, inBackground: false) },
							openInBackground: { browser.openHistoryURL(item.url, inBackground: true) }
						)
						.contextMenu {
							Button("Open Offline Copy", systemImage: "arrow.down.circle") {
								browser.openReadingListItem(item, offline: true)
							}
							Button(item.isRead ? "Mark as Unread" : "Mark as Read", systemImage: item.isRead ? "circle" : "checkmark.circle") {
								browser.setReadingListRead(item.id, isRead: !item.isRead)
							}
							Button("Remove from Reading List", systemImage: "trash", role: .destructive) {
								browser.removeReadingListItem(item.id)
							}
						}
					}
				}
			} else {
				ForEach(Array(Dictionary(grouping: visibleBookmarks, by: \.folder).keys.sorted()), id: \.self) { folder in
					Section(folder.isEmpty ? "Bookmarks" : folder) {
						ForEach(visibleBookmarks.filter { $0.folder == folder }) { bookmark in
							HistoryRow(
								title: bookmark.name,
								detail: bookmark.url.absoluteString,
								url: bookmark.url,
								symbol: bookmark.isFavorite ? "star.fill" : "bookmark",
								identifier: "bookmark-\(bookmark.id.uuidString)",
								open: { browser.openBookmark(bookmark) },
								openInBackground: { browser.openHistoryURL(bookmark.url, inBackground: true) }
							)
							.matchedTransitionSource(id: "bookmark-edit-\(bookmark.id.uuidString)", in: transitions)
							.contextMenu {
								Button("Edit Bookmark", systemImage: "pencil") { editingBookmark = bookmark }
								Button(bookmark.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: bookmark.isFavorite ? "star.slash" : "star") {
									browser.updateBookmark(bookmark.id, name: bookmark.name, folder: bookmark.folder, isFavorite: !bookmark.isFavorite, order: bookmark.order)
								}
								Button("Delete Bookmark", systemImage: "trash", role: .destructive) { browser.removeBookmark(bookmark.id) }
							}
						}
						.onMove { offsets, destination in
							var ids = visibleBookmarks.filter { $0.folder == folder }.map(\.id)
							ids.move(fromOffsets: offsets, toOffset: destination)
							browser.reorderBookmarks(ids)
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
		.safeAreaBar(edge: .top) {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Label(showingReadingList ? "Reading List" : "Bookmarks", systemImage: showingReadingList ? "text.book.closed" : "bookmark")
						.font(.title2.bold())
					Spacer()
					if !showingReadingList && searchText.isEmpty && visibleBookmarks.count > 1 {
						Button(editMode?.wrappedValue == .active ? "Done Reordering" : "Reorder Bookmarks", systemImage: editMode?.wrappedValue == .active ? "checkmark" : "arrow.up.arrow.down") {
							withAnimation { editMode?.wrappedValue = editMode?.wrappedValue == .active ? .inactive : .active }
						}
						.accessibilityIdentifier("reorder-bookmarks")
					}
					Button(showingReadingList ? "Show Bookmarks" : "Show Reading List", systemImage: showingReadingList ? "bookmark" : "text.book.closed") {
						showingReadingList.toggle()
					}
					.disabled(browser.isPrivate)
					.accessibilityIdentifier("toggle-reading-list")
					if showingReadingList {
						Button("Save Current Page Offline", systemImage: "arrow.down.circle") { browser.saveSelectedPageToReadingList() }
							.accessibilityIdentifier("save-reading-list-offline")
							.disabled(browser.isPrivate || !browser.readingList.contains { $0.url == browser.selectedTab?.currentURL })
					} else if !browser.isPrivate, let url = browser.selectedTab?.currentURL {
						Button("Add Current Page to Reading List", systemImage: "text.badge.plus") { browser.addToReadingList(url, title: browser.selectedTab?.title ?? url.host ?? url.absoluteString) }
							.accessibilityIdentifier("add-to-reading-list")
					}
				}
				TextField("Search Bookmarks", text: $searchText)
					.textFieldStyle(.plain)
					.accessibilityIdentifier("bookmark-search")
			}
			.padding(.horizontal, 24)
			.padding(.vertical, 14)
		}
		.sheet(item: $editingBookmark) { bookmark in
			BookmarkEditor(bookmark: bookmark) { name, folder, favorite in
				browser.updateBookmark(bookmark.id, name: name, folder: folder, isFavorite: favorite, order: bookmark.order)
			}
			.navigationTransition(.zoom(sourceID: "bookmark-edit-\(bookmark.id.uuidString)", in: transitions))
			.presentationDetents([.fraction(0.6)])
		}
		.overlay {
			if showingReadingList && browser.readingList.isEmpty {
				ContentUnavailableView("No Reading List Items", systemImage: "text.book.closed")
			} else if !showingReadingList && visibleBookmarks.isEmpty {
				ContentUnavailableView("No Bookmarks", systemImage: "bookmark")
			}
		}
	}
}

private struct BookmarkEditor: View {
	let bookmark: Bookmark
	let save: (String, String, Bool) -> Void
	@Environment(\.dismiss) private var dismiss
	@State private var name: String
	@State private var folder: String
	@State private var favorite: Bool

	init(bookmark: Bookmark, save: @escaping (String, String, Bool) -> Void) {
		self.bookmark = bookmark
		self.save = save
		_name = State(initialValue: bookmark.name)
		_folder = State(initialValue: bookmark.folder)
		_favorite = State(initialValue: bookmark.isFavorite)
	}

	var body: some View {
		NavigationStack {
			List {
				Section("Bookmark") {
					TextField("Name", text: $name)
					TextField("Folder", text: $folder)
					Toggle("Favorite", isOn: $favorite)
				}
			}
			.navigationTitle("Edit Bookmark")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save", systemImage: "checkmark", role: .confirm) {
						save(name, folder, favorite)
						dismiss()
					}
					.buttonStyle(.glassProminent)
					.accessibilityIdentifier("save-bookmark")
				}
			}
		}
	}
}
