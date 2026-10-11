from pathlib import Path
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = (root / "astra/Models/Core/Browser.swift").read_text()
match = re.search(
    r"\n\tfunc reorderSpaces\(_ ids: \[UUID\], before destinationID: UUID\?\) \{.*?\n\t\}\n\n\tfunc deleteSpace",
    source,
    re.S,
)
assert match, "Browser.reorderSpaces was not found"
method = match.group(0).split("\n\n\tfunc deleteSpace", 1)[0].lstrip()

fixture = f"""
import Foundation

struct BrowserSpace {{
    let id: UUID
    var tabIDs: [UUID]
}}

struct BrowserWorkspace {{
    var spaces: [BrowserSpace]
    var selectedSpaceID: UUID
    var modifiedAt = Date(timeIntervalSince1970: 0)
}}

final class Browser {{
    var isPrivate = false
    var workspace: BrowserWorkspace
    var persistenceWrites = 0

    init(_ spaces: [BrowserSpace], selected: UUID) {{
        workspace = BrowserWorkspace(spaces: spaces, selectedSpaceID: selected)
    }}

    private func nextWorkspaceMutationDate() -> Date {{
        Date(timeIntervalSince1970: workspace.modifiedAt.timeIntervalSince1970 + 1)
    }}

    private func schedulePersistence() {{
        persistenceWrites += 1
    }}

{method}
}}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {{
    assert(condition(), message)
}}

let a = UUID(), b = UUID(), c = UUID(), d = UUID(), unknown = UUID()
let tabA = UUID(), tabB = UUID(), tabC = UUID(), tabD = UUID()
let spaces = [
    BrowserSpace(id: a, tabIDs: [tabA]),
    BrowserSpace(id: b, tabIDs: [tabB]),
    BrowserSpace(id: c, tabIDs: [tabC]),
    BrowserSpace(id: d, tabIDs: [tabD]),
]

func browser() -> Browser {{ Browser(spaces, selected: c) }}
func ids(_ browser: Browser) -> [UUID] {{ browser.workspace.spaces.map(\\.id) }}
func tabs(_ browser: Browser) -> [[UUID]] {{ browser.workspace.spaces.map(\\.tabIDs) }}

var test = browser()
test.reorderSpaces([c], before: a)
check(ids(test) == [c, a, b, d], "move earlier")
check(test.workspace.selectedSpaceID == c && tabs(test) == [[tabC], [tabA], [tabB], [tabD]], "selection and tabs preserved")
check(test.persistenceWrites == 1 && test.workspace.modifiedAt != Date(timeIntervalSince1970: 0), "changed order persists")

test = browser()
test.reorderSpaces([a], before: d)
check(ids(test) == [b, c, a, d], "move later")

test = browser()
test.reorderSpaces([b, d], before: nil)
check(ids(test) == [a, c, b, d], "multiple move to end")

for invalid in [([unknown], a), ([a, a], d), ([a], a)] as [([UUID], UUID?) ] {{
    test = browser()
    let before = ids(test)
    test.reorderSpaces(invalid.0, before: invalid.1)
    check(ids(test) == before && test.persistenceWrites == 0, "invalid reorder rejected")
}}

test = browser()
test.reorderSpaces([a], before: b)
check(ids(test) == [a, b, c, d] && test.persistenceWrites == 0, "no-op rejected")

test = browser()
test.isPrivate = true
test.reorderSpaces([a], before: d)
check(ids(test) == [a, b, c, d] && test.persistenceWrites == 0, "private browser rejected")
"""

with tempfile.TemporaryDirectory() as directory:
    fixture_path = Path(directory) / "SpaceReorderingCheck.swift"
    binary_path = Path(directory) / "space-reordering-check"
    fixture_path.write_text(fixture)
    subprocess.run(["swift", str(fixture_path)], check=True)
    subprocess.run(["swiftc", str(fixture_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True)

print("space reordering check passed")
