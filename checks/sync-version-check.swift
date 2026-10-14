// Run with Xcode RunCodeSnippet in BrowserSyncDocument.swift's context.

let syncVersionCheckDocument = BrowserSyncDocument(
	tabs: [],
	workspace: BrowserWorkspace(spaces: [], favouriteTabIDs: [], selectedSpaceID: BrowserSpace.firstID),
	bookmarks: [],
	browser: BrowserSnapshot(selectedTabID: BrowserSpace.firstID),
	settings: [:]
)
let syncVersionCheckData = try JSONEncoder().encode(syncVersionCheckDocument)
var syncVersionCheckObject = try JSONSerialization.jsonObject(with: syncVersionCheckData) as! [String: Any]
syncVersionCheckObject["version"] = 99
syncVersionCheckObject["unknown"] = "ignored"
let syncVersionCheckFutureData = try JSONSerialization.data(withJSONObject: syncVersionCheckObject)
let syncVersionCheckFuture = try JSONDecoder().decode(BrowserSyncDocument.self, from: syncVersionCheckFutureData)
assert(syncVersionCheckFuture.version == 99)
assert(syncVersionCheckFuture.hasValidStructure)
assert(syncVersionCheckFuture.merging(syncVersionCheckDocument) == syncVersionCheckFuture)

syncVersionCheckObject["version"] = 1
let syncVersionCheckLegacyData = try JSONSerialization.data(withJSONObject: syncVersionCheckObject)
let syncVersionCheckLegacy = try JSONDecoder().decode(BrowserSyncDocument.self, from: syncVersionCheckLegacyData)
assert(syncVersionCheckLegacy.version == 1)

let duplicateTab = OpenTab(id: UUID(), url: URL(string: "https://example.com")!)
let duplicateDocument = BrowserSyncDocument(
	tabs: [duplicateTab, duplicateTab],
	workspace: syncVersionCheckDocument.workspace!,
	bookmarks: [],
	browser: syncVersionCheckDocument.browser,
	settings: [:]
)
assert(!duplicateDocument.hasValidStructure)

print("Sync version decoding, merge, unknown-field and structural validation checks passed")
