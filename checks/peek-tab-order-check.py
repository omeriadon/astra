"""Run the production peek insertion block with minimal sidebar collaborators."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/Models/Core/Browser.swift").read_text()
promotion = source.split("func promotePeek(", 1)[1].split("func closeTabsAbove", 1)[0]
insertion = promotion[promotion.index("\t\ttabs.insert"):promotion.index("\t\tselectTab")]

program = r'''
import Foundation

struct Tab {
    let id = UUID()
}

struct Group {
    var tabIDs: [UUID]
}

struct Space {
    let id = UUID()
    var tabIDs: [UUID]
    var todayTabGroups: [Group]
}

struct Workspace {
    var spaces: [Space]
}

struct Browser {
    var tabs: [Tab]
    var workspace: Workspace

    mutating func reconcileWorkspace() {
        guard !workspace.spaces.isEmpty else { return }
        let assigned = Set(workspace.spaces.flatMap(\.tabIDs))
        workspace.spaces[0].tabIDs += tabs.map(\.id).filter { !assigned.contains($0) }
    }

    mutating func moveTab(_ id: UUID, to: Area, in spaceID: UUID, before targetID: UUID?) {
        guard targetID != id else { return }
        let index = workspace.spaces.firstIndex { $0.id == spaceID }!
        workspace.spaces[index].tabIDs.removeAll { $0 == id }
        let insertion = targetID.flatMap { workspace.spaces[index].tabIDs.firstIndex(of: $0) }
            ?? workspace.spaces[index].tabIDs.endIndex
        workspace.spaces[index].tabIDs.insert(id, at: insertion)
    }

    enum Area { case normal }
    func markWorkspaceStructureChanged() {}

    mutating func insert(_ tab: Tab, after source: Tab) {
        let sourceIndex = tabs.firstIndex { $0.id == source.id }!
''' + insertion + r'''
    }
}

let first = Tab()
let base = Tab()
let last = Tab()
for grouped in [false, true] {
    for atEnd in [false, true] {
        let original = atEnd ? [first, base] : [first, base, last]
        let groups = grouped ? [Group(tabIDs: original.map(\.id))] : []
        var browser = Browser(tabs: original, workspace: Workspace(spaces: [
            Space(tabIDs: original.map(\.id), todayTabGroups: groups)
        ]))
        let promoted = Tab()
        browser.insert(promoted, after: base)
        let expected = [first.id, base.id, promoted.id] + (atEnd ? [] : [last.id])
        precondition(browser.tabs.map(\.id) == expected)
        precondition(browser.workspace.spaces[0].tabIDs == expected)
        if grouped {
            precondition(browser.workspace.spaces[0].todayTabGroups[0].tabIDs == expected)
        }
    }
}
var privateBrowser = Browser(tabs: [base, last], workspace: Workspace(spaces: []))
let promoted = Tab()
privateBrowser.insert(promoted, after: base)
precondition(privateBrowser.tabs.map(\.id) == [base.id, promoted.id, last.id])
print("Peek tab ordering passed: middle, end, grouped, and private tabs.")
'''

with tempfile.TemporaryDirectory() as directory:
    check = Path(directory) / "main.swift"
    check.write_text(program)
    subprocess.run(["swift", str(check)], check=True)
