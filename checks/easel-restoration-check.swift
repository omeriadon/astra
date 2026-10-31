// Run with Xcode RunCodeSnippet in astra/Models/Core/Browser.swift's context.
// Mini browsers have no persistence store and are not registered as normal windows.
let isolatedBrowser = Browser(isMini: true)
let shellID = isolatedBrowser.selectedTabID
var noteItem = BrowserEaselDocument.Item(kind: .text)
noteItem.text = "Restoration fixture"
let noteContent = BrowserEaselDocument(items: [noteItem])
var restoredNote = OpenTab(id: shellID, internalPage: "easel", easel: noteContent)
var noteWorkspace = isolatedBrowser.workspace
noteWorkspace.spaces[0].tabIDs = [shellID]
noteWorkspace.spaces[0].pinnedTabIDs = [shellID]
var noteSnapshot = BrowserSyncDocument(tabs: [restoredNote], workspace: noteWorkspace, bookmarks: [], browser: BrowserSnapshot(selectedTabID: shellID), settings: [:])
isolatedBrowser.applySyncDocument(noteSnapshot)
precondition(isolatedBrowser.selectedTab?.internalPage == .easel)
precondition(isolatedBrowser.selectedTab?.easelDocument == noteContent)
precondition(isolatedBrowser.selectedSpace.pinnedTabIDs.contains(shellID))
let restoredInstance = isolatedBrowser.selectedTab!
restoredNote.easel = .empty
restoredNote.modifiedAt = restoredNote.modifiedAt.addingTimeInterval(1)
noteSnapshot.tabs = [restoredNote]
isolatedBrowser.applySyncDocument(noteSnapshot)
precondition(isolatedBrowser.selectedTab === restoredInstance)
precondition(restoredInstance.easelDocument == .empty)
noteSnapshot.tabs = []
noteSnapshot.browser.closedTabIDs.insert(shellID)
noteSnapshot.browser.closedTabsAt[shellID] = restoredNote.modifiedAt.addingTimeInterval(1)
isolatedBrowser.applySyncDocument(noteSnapshot)
precondition(!isolatedBrowser.tabs.contains { $0.id == shellID })
print("Cached-shell restoration, pinned placement, live updates and deletion checks passed")
