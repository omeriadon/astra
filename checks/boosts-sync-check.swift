// Run with Xcode RunCodeSnippet in BrowserSyncDocument.swift's context.
// Sync must preserve source, metadata, and deletion tombstones across devices.
let tabID = UUID()
let tab = OpenTab(id: tabID)
let workspace = BrowserWorkspace.migrated(tabs: [tab], selectedTabID: tabID, theme: BrowserTheme())
var boost = BrowserBoost(name: "Site customizer", domain: "example.com")
boost.css = "html { color: red }"
boost.javascript = "document.documentElement.dataset.astraBoost = '1';"
let document = BrowserSyncDocument(
    tabs: [tab],
    workspace: workspace,
    bookmarks: [],
    browser: BrowserSnapshot(selectedTabID: tabID),
    settings: [:],
    boosts: [boost]
)
let portable = document.portableProjection()
precondition(portable.hasValidStructure)
precondition(portable.boosts == [boost])

let data = try JSONEncoder().encode(portable)
let decoded = try JSONDecoder().decode(BrowserSyncDocument.self, from: data)
precondition(decoded == portable)

var legacyObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
legacyObject.removeValue(forKey: "boosts")
legacyObject.removeValue(forKey: "deletedBoostsAt")
let legacy = try JSONDecoder().decode(
    BrowserSyncDocument.self,
    from: JSONSerialization.data(withJSONObject: legacyObject)
)
precondition(legacy.boosts.isEmpty)
precondition(legacy.deletedBoostsAt.isEmpty)

var newer = boost
newer.css = "html { color: blue }"
newer.modifiedAt = boost.modifiedAt.addingTimeInterval(1)
var remote = portable
remote.boosts = [newer]
let merged = portable.merging(remote)
precondition(merged.boosts == [newer])

var deletion = portable
deletion.boosts = []
deletion.deletedBoostsAt[boost.id] = newer.modifiedAt.addingTimeInterval(1)
let removed = merged.merging(deletion)
precondition(removed.boosts.isEmpty)
precondition(removed.deletedBoostsAt[boost.id] != nil)
precondition(removed.merging(portable).boosts.isEmpty)

var oversized = portable
oversized.boosts[0].css = String(repeating: "x", count: 131_073)
precondition(!oversized.hasValidStructure)
print("Boost synchronization: portable projection, Codable, LWW, tombstones, compatibility and size constraints passed")
