"""Compile and exercise the production history-tab insertion method in stubs."""

from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = (root / "astra/Models/Core/Browser.swift").read_text()
start = source.index("\tfunc openHistoryEntry(")
brace = source.index("{", start)
depth = 0
end = brace
while end < len(source):
    if source[end] == "{":
        depth += 1
    elif source[end] == "}":
        depth -= 1
        if depth == 0:
            end += 1
            break
    end += 1
method = source[start:end]

harness = r'''
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
typealias UUID = String

final class HistoryItem {
    let url: URL
    init(_ url: URL) { self.url = url }
}

final class HistoryList {
    var entries: [Int: HistoryItem] = [:]
    func item(at offset: Int) -> HistoryItem? { entries[offset] }
}

final class WebView {
    let backForwardList = HistoryList()
}

final class BrowserController {
    let webView = WebView()
    var webViewIfLoaded: WebView? { webView }
    var navigatedURL: URL?
    var prepared = false
    func navigate(_ request: URLRequest) { navigatedURL = request.url }
    func prepareWebView() { prepared = true }
}

final class BrowserTab {
    let id: String
    let controller: BrowserController?
    var activeController: BrowserController? { controller }
    init(_ id: String, controller: BrowserController? = BrowserController()) {
        self.id = id
        self.controller = controller
    }
}

struct HistoryGroup {
    let name: String
    let tabIDs: [String]
    init(name: String = "group", tabIDs: [String]) {
        self.name = name
        self.tabIDs = tabIDs
    }
}

typealias Group = HistoryGroup

enum BrowserTabGroupingFeature {
    typealias Group = HistoryGroup
}

struct Space {
    var id: String
    var tabIDs: [String]
    var pinnedTabIDs: [String]
    var todayTabGroups: [Group]
}

struct Workspace {
    var spaces: [Space]
    var favouriteTabIDs: [String]
}

enum TabArea {
    case normal
}

final class Browser {
    var isPrivate = false
    var tabs: [BrowserTab]
    var selectedTabID: String
    var workspace: Workspace
    var selectedTab: BrowserTab? { tabs.first { $0.id == selectedTabID } }
    var selectedSpace: Space { workspace.spaces[0] }
    var nextID = 0

    init(tabs: [BrowserTab], selected: String, private: Bool = false, space: Space? = nil) {
        self.tabs = tabs
        selectedTabID = selected
        isPrivate = `private`
        let space = space ?? Space(id: "space", tabIDs: tabs.map(\.id), pinnedTabIDs: [], todayTabGroups: [])
        workspace = Workspace(spaces: [space], favouriteTabIDs: [])
    }

    @discardableResult
    func addTab(inBackground: Bool) -> BrowserTab {
        nextID += 1
        let tab = BrowserTab("new\(nextID)")
        tabs.append(tab)
        workspace.spaces[0].tabIDs.append(tab.id)
        return tab
    }

    func moveTab(_ id: String, to _: TabArea, in spaceID: String, before targetID: String?) {
        guard let spaceIndex = workspace.spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        var ids = workspace.spaces[spaceIndex].tabIDs.filter { $0 != id }
        let index = targetID.flatMap { ids.firstIndex(of: $0) } ?? ids.endIndex
        ids.insert(id, at: index)
        workspace.spaces[spaceIndex].tabIDs = ids
    }

    func markWorkspaceStructureChanged() {}
    func reconcileWorkspace() {}
    func schedulePersistence() {}

METHOD
}

@MainActor
func run() {
    let backURL = URL(string: "https://back.example")!
    let forwardURL = URL(string: "https://forward.example")!
    let sourceController = BrowserController()
    sourceController.webView.backForwardList.entries[-1] = HistoryItem(backURL)
    sourceController.webView.backForwardList.entries[1] = HistoryItem(forwardURL)
    let source = BrowserTab("source", controller: sourceController)
    let other = BrowserTab("other")
    let browser = Browser(tabs: [source, other], selected: "source", space: Space(id: "space", tabIDs: ["source", "other"], pinnedTabIDs: [], todayTabGroups: [Group(tabIDs: ["source"])]))
    browser.openHistoryEntry(from: sourceController, offset: -1)
    assert(sourceController.navigatedURL == nil)
    assert(browser.selectedTabID == "source")
    assert(browser.tabs.map(\.id) == ["source", "other", "new1"])
    assert(browser.workspace.spaces[0].tabIDs == ["source", "new1", "other"])
    assert(browser.workspace.spaces[0].todayTabGroups[0].tabIDs == ["source", "new1"])
    assert(browser.tabs[2].controller?.navigatedURL == backURL)
    assert(browser.tabs[2].controller?.prepared == true)

    browser.openHistoryEntry(from: sourceController, offset: 1)
    assert(browser.tabs.map(\.id) == ["source", "other", "new1", "new2"])
    assert(browser.workspace.spaces[0].tabIDs == ["source", "new2", "new1", "other"])
    assert(browser.workspace.spaces[0].todayTabGroups[0].tabIDs == ["source", "new2", "new1"])
    precondition(browser.tabs.contains { $0.controller?.navigatedURL == forwardURL }, "forward URL not opened")

    let count = browser.tabs.count
    browser.openHistoryEntry(from: sourceController, offset: 0)
    assert(browser.tabs.count == count)
    browser.openHistoryEntry(from: BrowserController(), offset: -1)
    assert(browser.tabs.count == count)
    sourceController.webView.backForwardList.entries.removeValue(forKey: -1)
    browser.openHistoryEntry(from: sourceController, offset: -1)
    assert(browser.tabs.count == count)
    sourceController.webView.backForwardList.entries[-1] = HistoryItem(backURL)

    let privateBrowser = Browser(tabs: [source, other], selected: "source", private: true)
    privateBrowser.openHistoryEntry(from: sourceController, offset: -1)
    assert(privateBrowser.tabs.map(\.id) == ["source", "new1", "other"])

    let pinnedSource = BrowserTab("pinned", controller: sourceController)
    let normal = BrowserTab("normal")
    let pinnedBrowser = Browser(tabs: [pinnedSource, normal], selected: "pinned", space: Space(id: "space", tabIDs: ["pinned", "normal"], pinnedTabIDs: ["pinned"], todayTabGroups: []))
    pinnedBrowser.openHistoryEntry(from: sourceController, offset: -1)
    assert(pinnedBrowser.workspace.spaces[0].tabIDs == ["pinned", "new1", "normal"])
}

MainActor.assumeIsolated { run() }
print("History tab order check passed")
'''.replace("METHOD", method)

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "history-tab-order-check.swift"
    path.write_text(harness)
    result = subprocess.run(["swift", str(path)], text=True, capture_output=True)
    print(result.stdout, end="")
    print(result.stderr, end="")
    result.check_returncode()
