import SwiftUI

struct BrowserBookmarksView: View {
	let browser: Browser
	#if os(iOS)
		@Environment(\.editMode) private var editMode
	#endif
	@Namespace private var transitions
	@State private var searchText = ""
	@State private var showingReadingList = false
	@State private var editingBookmark: Bookmark?

	private var visibleBookmarks: [Bookmark] {
		browser.bookmarks
			.filter { searchText.isEmpty || [$0.name, $0.url.absoluteString, $0.folder].contains { $0.localizedCaseInsensitiveContains(searchText) } }
			.sorted {
				if $0.folder != $1.folder {
					return $0.folder.localizedStandardCompare($1.folder) == .orderedAscending
				}
				if $0.order != $1.order {
					return $0.order < $1.order
				}
				return $0.name.localizedStandardCompare($1.name) == .orderedAscending
			}
	}

	private var visibleReadingList: [ReadingListItem] {
		browser.readingList
			.filter { searchText.isEmpty || [$0.title, $0.url.absoluteString].contains { $0.localizedCaseInsensitiveContains(searchText) } }
			.sorted {
				$0.addedAt == $1.addedAt
					? $0.id.uuidString < $1.id.uuidString
					: $0.addedAt > $1.addedAt
			}
	}

	var body: some View {
		let bookmarkGroups = Dictionary(grouping: visibleBookmarks, by: \.folder)
		let bookmarkFolders = bookmarkGroups.keys.sorted()
		let bookmarkCount = bookmarkGroups.values.reduce(0) { $0 + $1.count }
		let readingItems = visibleReadingList
		List {
			if showingReadingList {
				Section("Reading List") {
					ForEach(readingItems) { item in
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
							.accessibilityIdentifier("reading-open-offline-\(item.id.uuidString)")
							Button(item.isRead ? "Mark as Unread" : "Mark as Read", systemImage: item.isRead ? "circle" : "checkmark.circle") {
								browser.setReadingListRead(item.id, isRead: !item.isRead)
							}
							.accessibilityIdentifier("reading-toggle-read-\(item.id.uuidString)")
							Button("Remove from Reading List", systemImage: "trash", role: .destructive) {
								browser.removeReadingListItem(item.id)
							}
							.accessibilityIdentifier("reading-remove-\(item.id.uuidString)")
						}
					}
				}
			} else {
				ForEach(bookmarkFolders, id: \.self) { folder in
					let items = bookmarkGroups[folder] ?? []
					Section(folder.isEmpty ? "Bookmarks" : folder) {
						bookmarkRows(items)
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
					BrowserLibraryTransferControls(browser: browser, scope: .bookmarks)
					#if os(iOS)
						if !showingReadingList, searchText.isEmpty, bookmarkCount > 1 {
							Button(editMode?.wrappedValue == .active ? "Done Reordering" : "Reorder Bookmarks", systemImage: editMode?.wrappedValue == .active ? "checkmark" : "arrow.up.arrow.down") {
								withAnimation { editMode?.wrappedValue = editMode?.wrappedValue == .active ? .inactive : .active }
							}
							.accessibilityIdentifier("reorder-bookmarks")
						}
					#endif
					Button(showingReadingList ? "Show Bookmarks" : "Show Reading List", systemImage: showingReadingList ? "bookmark" : "text.book.closed") {
						showingReadingList.toggle()
					}
					.disabled(browser.isPrivate)
					.accessibilityIdentifier("toggle-reading-list")
				}
				TextField(showingReadingList ? "Search Reading List" : "Search Bookmarks", text: $searchText)
					.textFieldStyle(.plain)
					.accessibilityIdentifier(showingReadingList ? "reading-list-search" : "bookmark-search")
			}
			.padding(.horizontal, 24)
			.padding(.vertical, 14)
		}
		.sheet(item: $editingBookmark) { bookmark in
			BookmarkEditor(bookmark: bookmark) { name, folder, favorite in
				browser.updateBookmark(bookmark.id, name: name, folder: folder, isFavorite: favorite, order: bookmark.order)
			}
			#if os(iOS)
			.navigationTransition(.zoom(sourceID: "bookmark-edit-\(bookmark.id.uuidString)", in: transitions))
			.presentationDetents([.fraction(0.6)])
			#endif
		}
		.overlay {
			if showingReadingList, readingItems.isEmpty, searchText.isEmpty {
				ContentUnavailableView("No Reading List Items", systemImage: "text.book.closed")
			} else if showingReadingList, readingItems.isEmpty {
				ContentUnavailableView("No Search Results", systemImage: "magnifyingglass")
			} else if !showingReadingList, bookmarkCount == 0 {
				ContentUnavailableView(searchText.isEmpty ? "No Bookmarks" : "No Search Results", systemImage: searchText.isEmpty ? "bookmark" : "magnifyingglass")
			}
		}
	}

	private func bookmarkRows(_ items: [Bookmark]) -> some View {
		ForEach(items) { bookmark in
			HistoryRow(
				title: bookmark.name,
				detail: bookmark.url.absoluteString,
				url: bookmark.url,
				symbol: bookmark.isFavorite ? "star.fill" : "bookmark",
				identifier: "bookmark-\(bookmark.id.uuidString)",
				open: { browser.openBookmark(bookmark) },
				openInBackground: { browser.openHistoryURL(bookmark.url, inBackground: true) }
			)
			.moveDisabled(!searchText.isEmpty)
			.matchedTransitionSource(id: "bookmark-edit-\(bookmark.id.uuidString)", in: transitions)
			.contextMenu {
				Button("Edit Bookmark", systemImage: "pencil") { editingBookmark = bookmark }
				Button(bookmark.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: bookmark.isFavorite ? "star.slash" : "star") {
					browser.updateBookmark(bookmark.id, name: bookmark.name, folder: bookmark.folder, isFavorite: !bookmark.isFavorite, order: bookmark.order)
				}
				Button("Add to Reading List", systemImage: "text.badge.plus") {
					browser.addToReadingList(bookmark.url, title: bookmark.name)
				}
				.disabled(!browser.canAddToReadingList(bookmark.url))
				.accessibilityIdentifier("bookmark-add-reading-list-\(bookmark.id.uuidString)")
				Button("Delete Bookmark", systemImage: "trash", role: .destructive) { browser.removeBookmark(bookmark.id) }
			}
		}
		.onMove { offsets, destination in
			guard searchText.isEmpty else { return }
			var ids = items.map(\.id)
			ids.move(fromOffsets: offsets, toOffset: destination)
			browser.reorderBookmarks(ids)
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
						.accessibilityLabel("Bookmark name")
						.accessibilityIdentifier("bookmark-name")
					TextField("Folder", text: $folder)
						.accessibilityLabel("Bookmark folder")
						.accessibilityIdentifier("bookmark-folder")
					Toggle("Favorite", isOn: $favorite)
						.accessibilityIdentifier("bookmark-favorite")
				}
			}
			.navigationTitle("Edit Bookmark")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) { dismiss() }
						.accessibilityLabel("Cancel editing bookmark")
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save", systemImage: "checkmark", role: .confirm) {
						save(name, folder, favorite)
						dismiss()
					}
					.buttonStyle(.glassProminent)
					.accessibilityLabel("Save bookmark changes")
					.accessibilityIdentifier("save-bookmark")
				}
			}
		}
	}
}
