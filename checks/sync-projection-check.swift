// Run with Xcode RunCodeSnippet in BrowserSyncDocument.swift's context.
// Exercises real model projection, validation, identities and local-only exclusions.
let portableURL = URL(string: "https://user:secret@bücher.example:443/path")!
let portableTab = OpenTab(id: UUID(), url: portableURL)
let localTab = OpenTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/local"))
let portableBookmark = Bookmark(name: "Portable", url: portableURL)
let localBookmark = Bookmark(name: "Local", url: URL(fileURLWithPath: "/tmp/local"))
let workspace = BrowserWorkspace.migrated(tabs: [portableTab, localTab], selectedTabID: portableTab.id, theme: BrowserTheme())
let source = BrowserSyncDocument(
    tabs: [portableTab, localTab], workspace: workspace,
    bookmarks: [portableBookmark, localBookmark],
    browser: BrowserSnapshot(selectedTabID: portableTab.id), settings: [:]
)
let projected = source.portableProjection()
precondition(projected.tabs.map(\.id) == [portableTab.id])
precondition(projected.bookmarks.map(\.id) == [portableBookmark.id])
precondition(projected.tabs[0].url?.user == nil && projected.tabs[0].url?.password == nil)
precondition(projected.bookmarks[0].url.user == nil && projected.bookmarks[0].url.password == nil)
precondition(projected.hasValidStructure)
precondition(projected.portableProjection() == projected)
precondition(source.tabs[0].url?.password == "secret", "Projection must not mutate source")
let restored = try JSONDecoder().decode(BrowserSyncDocument.self, from: JSONEncoder().encode(projected))
precondition(restored == projected)
var invalid = projected
invalid.tabs[0].url = portableURL
precondition(!invalid.hasValidStructure, "Remote credentials must be rejected")
invalid = projected
invalid.tabs[0].history = [URL(string: "https://example.org:65536/")!]
precondition(!invalid.hasValidStructure)
invalid = projected
invalid.tabs[0].url = URL(string: "https://example.org/" + String(repeating: "a", count: 16384))!
precondition(!invalid.hasValidStructure)
print("Sync projection identity, sanitization, idempotence and invalid remote checks passed")
