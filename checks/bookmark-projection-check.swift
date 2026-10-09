import Foundation

@main
struct BookmarkProjectionCheck {
	static func main() async {
		let example = URL(string: "https://example.com")!
		let documentation = URL(string: "https://docs.example.com")!
		let alpha = Bookmark(name: "Alpha", url: example, folder: "Work", order: 0)
		let zulu = Bookmark(name: "Zulu", url: documentation, folder: "Work", order: 1)
		let other = Bookmark(name: "Personal", url: example, folder: "Home", order: 0)
		let old = ReadingListItem(url: example, title: "Older", addedAt: Date(timeIntervalSince1970: 10))
		let recent = ReadingListItem(url: documentation, title: "Newer", addedAt: Date(timeIntervalSince1970: 20))

		let all = BrowserLibraryProjection.build(
			bookmarks: [zulu, other, alpha], readingList: [old, recent], query: ""
		)!
		precondition(all.bookmarkGroups["Work"]?.map(\.name) == ["Alpha", "Zulu"])
		precondition(all.bookmarkGroups["Home"]?.map(\.name) == ["Personal"])
		precondition(all.readingItems.map(\.title) == ["Newer", "Older"])

		let filtered = BrowserLibraryProjection.build(
			bookmarks: [zulu, other, alpha], readingList: [old, recent], query: "DOCS"
		)!
		precondition(filtered.bookmarkGroups.keys.count == 1)
		precondition(filtered.bookmarkGroups["Work"]?.map(\.id) == [zulu.id])
		precondition(filtered.readingItems.map(\.id) == [recent.id])

		let cancelled = Task.detached {
			withUnsafeCurrentTask { $0?.cancel() }
			return BrowserLibraryProjection.build(
				bookmarks: [zulu, other, alpha], readingList: [old, recent], query: ""
			)
		}
		let discarded = await cancelled.value
		precondition(discarded == nil, "Cancelled projection should discard its result")
		print("Bookmark library projection checks passed")
	}
}
