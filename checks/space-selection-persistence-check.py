"""Compile and exercise the production space-selection method in stubs."""

from pathlib import Path
import os
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = (root / "astra/Models/Core/Browser.swift").read_text()
start = source.index("\tfunc selectSpace(")
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

enum BrowserLog {
    enum Category {
        case spaces
    }

    static func debug(_: Category, _: String, metadata: [String: String]) {}
    static func id(_ value: UUID) -> String { value.uuidString }
}

struct Space {
    var id: UUID
    var selectedTabID: UUID?
    var tabIDs: [UUID]
}

struct Workspace {
    var spaces: [Space]
    var selectedSpaceID: UUID
    var favouriteTabIDs: [UUID]
}

@MainActor
final class Browser {
    let windowID = UUID()
    var workspace: Workspace
    var spaceSwitchDirection = 1
    var tabSelections = 0
    var tabCreations = 0
    var fullPersistenceCalls = 0
    var selectionPersistenceCalls = 0

    var selectedSpace: Space {
        workspace.spaces.first { $0.id == workspace.selectedSpaceID }!
    }

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    func selectTab(_: UUID, inSpace: UUID? = nil) {
        if let inSpace {
            workspace.selectedSpaceID = inSpace
        }
        tabSelections += 1
    }

    func addTab() {
        tabCreations += 1
        schedulePersistence(fullState: true)
    }

    func schedulePersistence(fullState: Bool = true) {
        if fullState {
            fullPersistenceCalls += 1
        } else {
            selectionPersistenceCalls += 1
        }
    }

    func scheduleSelectionPersistence() {
        schedulePersistence(fullState: false)
    }

    METHOD
}

@MainActor
func run() {
    let first = UUID()
    let second = UUID()
    let favourite = UUID()
    let firstSpace = Space(id: UUID(), selectedTabID: first, tabIDs: [first])
    let normalSpace = Space(id: UUID(), selectedTabID: second, tabIDs: [second])
    let favouriteSpace = Space(id: UUID(), selectedTabID: favourite, tabIDs: [])
    let emptySpace = Space(id: UUID(), selectedTabID: nil, tabIDs: [])

    let browser = Browser(workspace: Workspace(
        spaces: [firstSpace, normalSpace, favouriteSpace, emptySpace],
        selectedSpaceID: firstSpace.id,
        favouriteTabIDs: [favourite]
    ))

    browser.selectSpace(normalSpace.id)
    assert(browser.workspace.selectedSpaceID == normalSpace.id)
    assert(browser.tabSelections == 1)
    assert(browser.fullPersistenceCalls == 0)
    assert(browser.selectionPersistenceCalls == 1)

    browser.selectSpace(favouriteSpace.id)
    precondition(browser.workspace.selectedSpaceID == favouriteSpace.id, "selected=\(browser.workspace.selectedSpaceID), expected=\(favouriteSpace.id)")
    precondition(browser.tabSelections == 2, "tab selections=\(browser.tabSelections)")
    precondition(browser.fullPersistenceCalls == 0, "full persistence=\(browser.fullPersistenceCalls)")
    precondition(browser.selectionPersistenceCalls == 2, "selection persistence=\(browser.selectionPersistenceCalls)")

    let emptyBrowser = Browser(workspace: Workspace(
        spaces: [firstSpace, emptySpace],
        selectedSpaceID: firstSpace.id,
        favouriteTabIDs: []
    ))
    emptyBrowser.selectSpace(emptySpace.id)
    assert(emptyBrowser.workspace.selectedSpaceID == emptySpace.id)
    assert(emptyBrowser.tabCreations == 1)
    assert(emptyBrowser.fullPersistenceCalls == 1)
    assert(emptyBrowser.selectionPersistenceCalls == 1)

    let actions = (browser.tabSelections, browser.tabCreations, browser.fullPersistenceCalls, browser.selectionPersistenceCalls)
    browser.selectSpace(UUID())
    assert((browser.tabSelections, browser.tabCreations, browser.fullPersistenceCalls, browser.selectionPersistenceCalls) == actions)

    browser.selectSpace(favouriteSpace.id)
    assert(browser.selectionPersistenceCalls == 2)
    print("Space selection persistence check passed")
}

@main
struct Check {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}
'''.replace("METHOD", method)

environment = os.environ.copy()
environment.setdefault(
    "DEVELOPER_DIR",
    "/Applications/Xcode-beta 27.2 beta 2.app/Contents/Developer",
)

with tempfile.TemporaryDirectory() as directory:
    check = Path(directory) / "space-selection-persistence-check.swift"
    binary = Path(directory) / "space-selection-persistence-check"
    check.write_text(harness)
    subprocess.run(
        ["swiftc", "-Onone", "-parse-as-library", "-o", str(binary), str(check)],
        check=True,
        env=environment,
    )
    subprocess.run([str(binary)], check=True)

    original_check = Path(directory) / "space-selection-persistence-original-check.swift"
    original_binary = Path(directory) / "space-selection-persistence-original-check"
    original_head, original_tail = harness.rsplit("scheduleSelectionPersistence()", 1)
    original_harness = original_head + "schedulePersistence()" + original_tail
    original_check.write_text(original_harness)
    subprocess.run(
        ["swiftc", "-Onone", "-parse-as-library", "-o", str(original_binary), str(original_check)],
        check=True,
        env=environment,
    )
    original = subprocess.run([str(original_binary)], capture_output=True, text=True)
    if original.returncode == 0:
        raise AssertionError("the regression check must fail with the old full-persistence call")
