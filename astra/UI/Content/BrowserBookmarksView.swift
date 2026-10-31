import Defaults
import SwiftUI

struct BrowserBookmarksView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let browser: Browser
	#if os(iOS)
		@Environment(\.editMode) private var editMode
	#endif
	@State private var searchText = ""
	@State private var showingReadingList = false
	@State private var editingBookmark: Bookmark?
	@Default(.bookmarkFolderNames) private var emptyFolders
	@Default(.aiFeaturesEnabled) private var allAI
	@Default(.aiBookmarkTitles) private var aiTitles
	@State private var cleanupRequested = false
	@State private var cleanupError: String?
	@State private var libraryProjection = BrowserLibraryProjection.empty
	@State private var libraryTask: Task<Void, Never>?
	@State private var libraryRevision = 0

	var body: some View {
		let bookmarkGroups = libraryProjection.bookmarkGroups
		let bookmarkFolders = Set(Array(bookmarkGroups.keys) + emptyFolders.filter { searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText) }).sorted()
		let bookmarkCount = bookmarkGroups.values.reduce(0) { $0 + $1.count }
		let readingItems = libraryProjection.readingItems
		let sections: [BrowserNativeLibrarySection] = showingReadingList
			? [
				BrowserNativeLibrarySection(
					title: "Reading List",
					rows: readingItems.map { item in
						BrowserNativeLibraryRow(
							id: "reading-item-\(item.id.uuidString)",
							recordID: item.id, kind: .readingList,
							title: item.title,
							detail: item.isRead ? "Read · \(item.url.absoluteString)" : item.url.absoluteString,
							url: item.url,
							symbol: item.isRead ? "text.book.closed" : "text.book.closed.fill",
							isRead: item.isRead
						)
					}
				),
			]
			: bookmarkFolders.map { folder in
				BrowserNativeLibrarySection(
					title: folder.isEmpty ? "Bookmarks" : folder,
					rows: (bookmarkGroups[folder] ?? []).map { bookmark in
						BrowserNativeLibraryRow(
							id: "bookmark-\(bookmark.id.uuidString)",
							recordID: bookmark.id, kind: .bookmark,
							title: bookmark.name, detail: bookmark.url.absoluteString,
							url: bookmark.url,
							symbol: bookmark.isFavorite ? "star.fill" : "bookmark",
							isFavorite: bookmark.isFavorite,
							canAddToReadingList: browser.canAddToReadingList(bookmark.url)
						)
					},
					emptyMessage: "No bookmarks in this folder"
				)
			}
		BrowserNativeLibraryList(
			sections: sections,
			canReorder: !showingReadingList && searchText.isEmpty,
			isReordering: isReordering,
			open: { row, background in
				if background {
					browser.openHistoryURL(row.url, inBackground: true)
				} else if row.kind == .bookmark,
				          let bookmark = browser.bookmarks.first(where: { $0.id == row.recordID })
				{
					browser.openBookmark(bookmark)
				} else {
					browser.openHistoryURL(row.url, inBackground: false)
				}
			},
			action: { row, action in
				switch action {
					case .editBookmark:
						editingBookmark = browser.bookmarks.first(where: { $0.id == row.recordID })
					case .toggleFavorite:
						if let bookmark = browser.bookmarks.first(where: { $0.id == row.recordID }) {
							browser.updateBookmark(bookmark.id, name: bookmark.name, folder: bookmark.folder,
							                       isFavorite: !bookmark.isFavorite, order: bookmark.order)
						}
					case .addToReadingList:
						if browser.canAddToReadingList(row.url) {
							browser.addToReadingList(row.url, title: row.title)
						}
					case .deleteBookmark:
						browser.removeBookmark(row.recordID)
					case .openOffline:
						if let item = browser.readingList.first(where: { $0.id == row.recordID }) {
							browser.openReadingListItem(item, offline: true)
						}
					case .toggleRead:
						browser.setReadingListRead(row.recordID, isRead: !row.isRead)
					case .removeReadingList:
						browser.removeReadingListItem(row.recordID)
					case .removePageHistory, .removeHistoryVisit:
						break
				}
			},
			reorder: { _, ids in browser.reorderBookmarks(ids) }
		)
		.scrollContentBackground(.hidden)
		.safeAreaBar(edge: .top) {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Label(showingReadingList ? "Reading List" : "Bookmarks", systemImage: showingReadingList ? "text.book.closed" : "bookmark")
						.font(.title2.bold())
					Spacer()
					if !showingReadingList, allAI, aiTitles {
						Button("Clean Bookmark Titles", systemImage: "text.badge.checkmark") { cleanupRequested = true }
							.disabled(cleanupRequested || browser.isPrivate || browser.bookmarks.isEmpty)
							.accessibilityIdentifier("clean-bookmark-titles")
					}
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
				if let cleanupError {
					Text(cleanupError).font(.caption).foregroundStyle(.secondary)
				}
			}
			.padding(.horizontal, 24)
			.padding(.vertical, 14)
		}
		.onAppear { updateLibraryProjection() }
		.onChange(of: browser.libraryChangeRevision) { _, _ in updateLibraryProjection() }
		.onChange(of: searchText) { _, _ in updateLibraryProjection() }
		.onDisappear { libraryTask?.cancel() }
		.sheet(item: $editingBookmark) { bookmark in
			BookmarkEditor(bookmark: bookmark) { name, folder, favorite in
				browser.updateBookmark(bookmark.id, name: name, folder: folder, isFavorite: favorite, order: bookmark.order)
			}
			#if os(iOS)
			.presentationDetents([.fraction(0.6)])
			#endif
		}
		.task(id: cleanupRequested) {
			guard cleanupRequested else { return }
			defer { cleanupRequested = false }
			cleanupError = nil
			do {
				let originals = browser.bookmarks
				for bookmark in originals {
					var displayed = bookmark
					var completed = false
					defer {
						if !completed, browser.bookmarks.first(where: { $0.id == bookmark.id }) == displayed {
							withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
								browser.updateBookmark(bookmark.id, name: bookmark.name, folder: bookmark.folder, isFavorite: bookmark.isFavorite, order: bookmark.order)
							}
						}
					}
					let title = try await BrowserAI.shared.performStreaming(BrowserBookmarkTitleFeature(), input: bookmark) { snapshot in
						let partial = BrowserAIOutput.title(snapshot)
						guard !Task.isCancelled, allAI, aiTitles,
						      BrowserAIOutput.validLine(partial, maximumWords: 40),
						      browser.bookmarks.first(where: { $0.id == bookmark.id }) == displayed else { return }
						withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
							browser.updateBookmark(bookmark.id, name: partial, folder: bookmark.folder, isFavorite: bookmark.isFavorite, order: bookmark.order)
						}
						if let current = browser.bookmarks.first(where: { $0.id == bookmark.id }) {
							displayed = current
						}
					}
					try Task.checkCancellation()
					guard browser.bookmarks.first(where: { $0.id == bookmark.id }) == displayed, allAI, aiTitles else { throw BrowserAIError.pageUnavailable }
					withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
						browser.updateBookmark(bookmark.id, name: title, folder: bookmark.folder, isFavorite: bookmark.isFavorite, order: bookmark.order)
					}
					completed = true
				}
			} catch {
				if !Task.isCancelled {
					cleanupError = error.localizedDescription
				}
			}
		}
		.overlay {
			if showingReadingList, readingItems.isEmpty, searchText.isEmpty {
				ContentUnavailableView("No Reading List Items", systemImage: "text.book.closed")
			} else if showingReadingList, readingItems.isEmpty {
				ContentUnavailableView("No Search Results", systemImage: "magnifyingglass")
			} else if !showingReadingList, bookmarkCount == 0, bookmarkFolders.isEmpty {
				ContentUnavailableView(searchText.isEmpty ? "No Bookmarks" : "No Search Results", systemImage: searchText.isEmpty ? "bookmark" : "magnifyingglass")
			}
		}
	}

	private func updateLibraryProjection() {
		libraryRevision &+= 1
		let revision = libraryRevision
		let query = searchText
		libraryTask?.cancel()
		libraryTask = Task { @MainActor in
			// Search typing should not queue multiple full-library scans.
			if !query.isEmpty {
				do {
					try await Task.sleep(for: .milliseconds(100))
				} catch {
					return
				}
			}
			guard !Task.isCancelled, revision == libraryRevision else { return }
			// Capture the COW arrays only after search debouncing. Rapid typing
			// should not pin successive library buffers before they are needed.
			let bookmarks = browser.bookmarks
			let readingList = browser.readingList
			let worker = Task.detached(priority: .userInitiated) {
				BrowserLibraryProjection.build(bookmarks: bookmarks, readingList: readingList, query: query)
			}
			let result = await withTaskCancellationHandler {
				await worker.value
			} onCancel: {
				worker.cancel()
			}
			guard !Task.isCancelled, revision == libraryRevision, let result else { return }
			libraryProjection = result
		}
	}

	private var isReordering: Bool {
		#if os(iOS)
			editMode?.wrappedValue == .active
		#else
			false
		#endif
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
