"""Run with python3 checks/internal-page-chrome-check.py. Does not launch the app."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
split = (root / "astra/UI/Shell/BrowserSplitView.swift").read_text()
metrics = (root / "astra/UI/Chrome/BrowserChromeMetrics.swift").read_text()
titlebar = (root / "astra/UI/Windowing/NonDraggableTitlebarRegion.swift").read_text()
shell = (root / "astra/UI/Shell/DesktopBrowserShell.swift").read_text()
hidden = next(line.strip() for line in shell.splitlines() if "let hidden =" in line)
assert "let visibleWidth = width * sidebarVisibility" in split
assert ".onChange(of: showsTopBarOnPage)" in shell
assert "isTopBarRevealed = browser.selectedTab?.internalPage == nil" in shell

check = """
import SwiftUI

METRICS

TITLEBAR

SPLIT

MainActor.assumeIsolated {
    for shown in [false, true] {
        var view = BrowserSplitView(sidebarShown: .constant(shown)) {
            Color.clear
        } content: {
            Color.clear
        }
        let initial = view.animatableData.value
        assert(initial.0 == (shown ? 1 : 0))
        assert(initial.1 == (shown ? 1 : 0))
        view.animatableData = AnimatableValues(0.5, 0.25, 150)
        let intermediate = view.animatableData.value
        assert(intermediate.0 == 0.5)
        assert(intermediate.1 == 0.25)
        assert(intermediate.2 == 150)
        view.animatableData = AnimatableValues(-0.1, 1.1, -10)
        let clamped = view.animatableData.value
        assert(clamped.0 == 0)
        assert(clamped.1 == 1)
        assert(clamped.2 == 0)
        let overlay = BrowserSplitView(sidebarShown: .constant(shown), sidebarOverlaysContent: true) {
            Color.clear
        } content: {
            Color.clear
        }
        let overlaid = overlay.animatableData.value
        assert(overlaid.0 == (shown ? 1 : 0))
        assert(overlaid.1 == 0)
    }
    for sidebarShown in [false, true] {
        for showsTopBarOnPage in [false, true] {
            for showsTopBar in [false, true] {
                for isTopBarRevealed in [false, true] {
                    let isSidebarVisible = sidebarShown
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
""".replace("METRICS", metrics).replace("TITLEBAR", titlebar).replace("SPLIT", split).replace("HIDDEN", hidden)

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "internal-page-chrome-check.swift"
    path.write_text(check)
    subprocess.run(["swift", str(path)], check=True)
