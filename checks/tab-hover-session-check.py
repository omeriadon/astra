"""Run with python3 checks/tab-hover-session-check.py. Does not launch the app."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/UI/Tabs/BrowserTabRow.swift").read_text()
start = source.index("\t@MainActor\n\t@Observable\n\tfinal class BrowserTabHoverPreviewCoordinator")
end = source.index("\n\tstruct BrowserTabHoverPreviewOverlay", start)
coordinator = source[start:end]

program = "import Foundation\nimport CoreGraphics\nimport Observation\n" + coordinator + r'''
@main
struct HoverSessionCheck {
    @MainActor
    static func main() async throws {
        let coordinator = BrowserTabHoverPreviewCoordinator.shared
        let window = UUID()
        let first = UUID()
        let second = UUID()
        let frame = CGRect(x: 10, y: 10, width: 200, height: 30)

        coordinator.hoverBegan(tabID: first, windowID: window, sourceFrame: frame)
        try await Task.sleep(for: .milliseconds(350))
        precondition(!coordinator.isVisible, "Initial hover must retain its cold delay")
        try await Task.sleep(for: .milliseconds(350))
        precondition(coordinator.presentedTabID == first)

        coordinator.hoverEnded(tabID: first, windowID: window)
        coordinator.hoverBegan(tabID: second, windowID: window, sourceFrame: frame)
        try await Task.sleep(for: .milliseconds(350))
        precondition(coordinator.presentedTabID == second)

        coordinator.hoverEnded(tabID: second, windowID: window)
        try await Task.sleep(for: .milliseconds(700))
        precondition(!coordinator.isVisible, "Heading hover must hide the old card")
        coordinator.hoverBegan(tabID: first, windowID: window, sourceFrame: frame)
        try await Task.sleep(for: .milliseconds(350))
        precondition(coordinator.presentedTabID == first, "Heading traversal must preserve the warm delay")

        coordinator.dismiss(for: window)
        coordinator.hoverBegan(tabID: second, windowID: window, sourceFrame: frame)
        try await Task.sleep(for: .milliseconds(350))
        precondition(!coordinator.isVisible, "Leaving the sidebar must reset the delay")
        coordinator.dismiss(for: window)
        try await Task.sleep(for: .milliseconds(350))
        precondition(!coordinator.isVisible, "Dismissal must cancel pending activation")
        print("Tab hover session checks passed")
    }
}
'''

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "main.swift"
    binary = Path(directory) / "hover-check"
    path.write_text(program)
    subprocess.run(["swiftc", "-parse-as-library", str(path), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
