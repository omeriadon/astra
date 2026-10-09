"""Library filtering must depend on scalar mutations, not full collection equality."""
from pathlib import Path
browser = Path("astra/Models/Core/Browser.swift").read_text()
view = Path("astra/UI/Content/BrowserBookmarksView.swift").read_text()
assert "private(set) var libraryChangeRevision = 0" in browser
for prop in ("bookmarks: [Bookmark]", "readingList: [ReadingListItem]"):
    chunk = browser.split(f"private(set) var {prop}", 1)[1].split("\n\t}", 1)[0]
    assert "didSet { libraryChangeRevision &+= 1 }" in chunk
assert ".onChange(of: browser.libraryChangeRevision)" in view
assert ".onChange(of: browser.bookmarks)" not in view
assert ".onChange(of: browser.readingList)" not in view
assert "guard !Task.isCancelled, revision == libraryRevision" in view
assert "BrowserLibraryProjection.build(bookmarks: bookmarks, readingList: readingList" in view
print("Library Observation revision, cancellation and projection freshness checks passed")
