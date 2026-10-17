// Run with Xcode RunCodeSnippet in astra/Models/Core/BrowserSyncDocument.swift's context.
let tabID = UUID()
var item = BrowserEaselDocument.Item(kind: .text)
item.text = "Synced easel"
let payload = BrowserEaselDocument(items: [item])
let saved = OpenTab(id: tabID, internalPage: "easel", easel: payload)
var workspace = BrowserWorkspace.migrated(tabs: [saved], selectedTabID: tabID, theme: BrowserTheme())
workspace.spaces[0].pinnedTabIDs = [tabID]
let document = BrowserSyncDocument(tabs: [saved], workspace: workspace, bookmarks: [], browser: BrowserSnapshot(selectedTabID: tabID), settings: [:])
let portable = document.portableProjection()
precondition(portable.hasValidStructure)
precondition(portable.tabs.first?.easel == payload)
let encoded = try JSONEncoder().encode(portable)
let restored = try JSONDecoder().decode(BrowserSyncDocument.self, from: encoded)
precondition(restored == portable)
var remoteTab = saved
remoteTab.easel = .empty
remoteTab.modifiedAt = saved.modifiedAt.addingTimeInterval(1)
precondition(saved.applyingSynchronizedMetadata(from: remoteTab).easel == .empty)
var deleted = portable
deleted.browser.closedTabIDs.insert(tabID)
deleted.browser.closedTabsAt[tabID] = saved.modifiedAt.addingTimeInterval(2)
precondition(portable.merging(deleted).tabs.isEmpty)
var unsafe = portable
unsafe.tabs[0].easel?.items[0].url = URL(string: "https://user:secret@example.com")
precondition(!unsafe.hasValidStructure)
var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
legacyObject.removeValue(forKey: "easel")
let legacy = try JSONDecoder().decode(OpenTab.self, from: JSONSerialization.data(withJSONObject: legacyObject))
precondition(legacy.easel == nil)
print("Easel sync projection, decoding, merge updates, deletion and legacy decoding checks passed")

var shellObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
var shellTabs = shellObject["tabs"] as! [[String: Any]]
shellTabs[0].removeValue(forKey: "internalPage")
shellObject["tabs"] = shellTabs
let recovered = try JSONDecoder().decode(BrowserSyncDocument.self, from: JSONSerialization.data(withJSONObject: shellObject))
precondition(recovered.tabs[0].internalPage == "easel")
precondition(recovered.tabs[0].easel == payload)
print("Cached easel page-type recovery passed")

let newerShell = OpenTab(id: tabID, modifiedAt: saved.modifiedAt.addingTimeInterval(3))
var shellDocument = portable
shellDocument.tabs = [newerShell]
shellDocument.version = 3
shellDocument.workspace?.spaces[0].tabIDs = []
shellDocument.workspace?.spaces[0].pinnedTabIDs = []
shellDocument.workspace?.spaces[0].modifiedAt = saved.modifiedAt.addingTimeInterval(4)
let protected = portable.merging(shellDocument).preservingLocalOnlyData(from: portable)
precondition(protected.tabs[0].easel == payload)
precondition(protected.workspace?.spaces[0].pinnedTabIDs.contains(tabID) == true)
print("Easel identity and owning-space preservation passed")
