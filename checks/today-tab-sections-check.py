"""Compile selected Browser methods with small in-memory collaborators."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/Models/Core/Browser.swift").read_text()


def extract(signature):
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError(signature)


apply = extract("func applyTodayTabGroups")
filtered = extract("nonisolated static func filteredTodayTabGroups")
pin = extract("func pinTodayTabGroupAsFolder")

harness = r'''
import Foundation

enum BrowserTabGroupingFeature {
    struct Group: Equatable, Identifiable {
        let name: String
        let tabIDs: [UUID]
        var id: String { name }
    }
}

struct PinnedTabFolder: Equatable {
    var id = UUID()
    var name: String
    var tabIDs: [UUID] = []
    var modifiedAt: Date
}

struct Space {
    var id: UUID
    var tabIDs: [UUID]
    var pinnedTabIDs: [UUID] = []
    var todayTabGroups: [BrowserTabGroupingFeature.Group] = []
    var pinnedFolders: [PinnedTabFolder] = []
    var modifiedAt = Date(timeIntervalSince1970: 1)
}

struct Workspace {
    var spaces: [Space]
    var modifiedAt = Date(timeIntervalSince1970: 1)
}

@MainActor
final class Browser {
    var isPrivate = false
    var workspace: Workspace
    var persistenceCalls = 0

    init(workspace: Workspace) { self.workspace = workspace }
    func nextWorkspaceMutationDate() -> Date { Date(timeIntervalSince1970: 100) }
    func persist() { persistenceCalls += 1 }
    func schedulePersistence() { persistenceCalls += 1 }

    APPLY
    FILTERED
    PIN
}

@main
struct Check {
    @MainActor static func main() {
        let spaceID = UUID()
        let otherID = UUID()
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let group = BrowserTabGroupingFeature.Group(name: "Research", tabIDs: [first, second])
        let space = Space(id: spaceID, tabIDs: [first, second, third], todayTabGroups: [group])
        let browser = Browser(workspace: Workspace(spaces: [space]))

        assert(browser.pinTodayTabGroupAsFolder(group.id, in: spaceID))
        let pinnedSpace = browser.workspace.spaces[0]
        assert(pinnedSpace.pinnedTabIDs == [first, second])
        assert(pinnedSpace.pinnedFolders.count == 1)
        assert(pinnedSpace.pinnedFolders[0].name == "Research")
        assert(pinnedSpace.pinnedFolders[0].tabIDs == [first, second])
        assert(pinnedSpace.todayTabGroups.isEmpty)
        assert(pinnedSpace.modifiedAt == Date(timeIntervalSince1970: 100.001))
        assert(browser.persistenceCalls == 1)
        assert(!browser.pinTodayTabGroupAsFolder(group.id, in: otherID))
        browser.isPrivate = true
        assert(!browser.pinTodayTabGroupAsFolder(group.id, in: spaceID))

        let restored = Browser.filteredTodayTabGroups(
            [
                BrowserTabGroupingFeature.Group(name: "Old", tabIDs: [first, second]),
                BrowserTabGroupingFeature.Group(name: "Kept", tabIDs: [third]),
            ],
            normalIDs: [first, third, UUID()]
        )
        assert(restored.map(\.name) == ["Old", "Kept"])
        assert(restored[0].tabIDs == [first])
        assert(restored[1].tabIDs == [third])
        let added = UUID()
        let undoBrowser = Browser(workspace: Workspace(spaces: [
            Space(id: spaceID, tabIDs: [first, second, third, added], pinnedTabIDs: [second]),
        ]))
        assert(!undoBrowser.applyTodayTabGroups(restored, in: spaceID, expectedIDs: [first, third]))
        assert(undoBrowser.persistenceCalls == 0)
        assert(undoBrowser.applyTodayTabGroups(restored, in: spaceID, expectedIDs: [first, third, added]))
        assert(undoBrowser.workspace.spaces[0].todayTabGroups == restored)
        assert(undoBrowser.workspace.spaces[0].tabIDs == [first, second, third, added])
        assert(undoBrowser.workspace.spaces[0].pinnedTabIDs == [second])
        assert(undoBrowser.persistenceCalls == 1)
        assert(Browser.filteredTodayTabGroups([group], normalIDs: [third]).isEmpty)
        let untouched = Browser(workspace: Workspace(spaces: [space]))
        assert(!untouched.pinTodayTabGroupAsFolder("Missing", in: spaceID))
        untouched.isPrivate = true
        assert(!untouched.pinTodayTabGroupAsFolder(group.id, in: spaceID))
        assert(untouched.persistenceCalls == 0)
        print("Today tab section pinning and filtered undo checks passed")
    }
}
'''.replace("APPLY", apply).replace("FILTERED", filtered).replace("PIN", pin)

with tempfile.TemporaryDirectory() as directory:
    check = Path(directory) / "today-tab-sections-check.swift"
    binary = Path(directory) / "today-tab-sections-check"
    check.write_text(harness)
    subprocess.run(["swiftc", "-Onone", "-parse-as-library", "-o", str(binary), str(check)], check=True)
    subprocess.run([str(binary)], check=True)
