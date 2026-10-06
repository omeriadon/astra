"""Run with python3 checks/internal-page-chrome-check.py. Does not launch the app."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
split = (root / "astra/UI/Shell/BrowserSplitView.swift").read_text()
shell = (root / "astra/UI/Shell/DesktopBrowserShell.swift").read_text()
hidden = next(line.strip() for line in shell.splitlines() if "let hidden =" in line)
assert "let visibleWidth = width * sidebarVisibility" in split
assert ".onChange(of: showsTopBarOnPage)" in shell
assert "isTopBarRevealed = browser.selectedTab?.internalPage == nil" in shell

check = """
import SwiftUI

enum BrowserChromeMetrics {
    static let expandedSidebarWidth: CGFloat = 250
}

SPLIT

MainActor.assumeIsolated {
    for shown in [false, true] {
        var view = BrowserSplitView(sidebarShown: .constant(shown)) {
            Color.clear
        } content: {
            Color.clear
        }
        assert(view.animatableData == (shown ? 1 : 0))
        view.animatableData = 0.5
        assert(view.animatableData == 0.5)
        view.animatableData = -0.1
        assert(view.animatableData == 0)
        view.animatableData = 1.1
        assert(view.animatableData == 1)
    }
    for sidebarShown in [false, true] {
        for showsTopBarOnPage in [false, true] {
            for showsTopBar in [false, true] {
                for isTopBarRevealed in [false, true] {
                    HIDDEN
                    if !showsTopBarOnPage {
                        assert(hidden == !sidebarShown)
                    } else {
                        assert(hidden == !(sidebarShown || showsTopBar || isTopBarRevealed))
                    }
                }
            }
        }
    }
}
print("Internal page chrome check passed")
""".replace("SPLIT", split).replace("HIDDEN", hidden)

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "internal-page-chrome-check.swift"
    path.write_text(check)
    subprocess.run(["swift", str(path)], check=True)
