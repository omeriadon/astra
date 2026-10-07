"""Run with python3 checks/sidebar-hover-check.py. Does not launch the app."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
shell = (root / "astra/UI/Shell/DesktopBrowserShell.swift").read_text()
metrics = (root / "astra/UI/Chrome/BrowserChromeMetrics.swift").read_text()
start = shell.index("let revealWidth = isSidebarRevealed")
end = shell.index("withAnimation", start)
width = shell[start:end].replace("geometry.size.width", "windowWidth")
assignment = next(line.strip() for line in shell.splitlines() if "isSidebarRevealed = !sidebarShown" in line)
assert "sidebarShown: .constant(isSidebarVisible)" in shell
assert "isSidebarPinned || isSidebarRevealed" in shell
assert "sidebarShown: sidebarShown," in shell
assert "sidebarOverlaysContent: !isSidebarPinned" in shell
assert "case .ended:" in shell[end:shell.index(".background", end)]
assert "isSidebarRevealed = false" in shell[end:shell.index(".background", end)]

check = metrics + """
func revealed(shown: Bool, wasRevealed: Bool, x: CGFloat, windowWidth: CGFloat, showsAI: Bool) -> Bool {
    let sidebarShown = shown
    var isSidebarRevealed = wasRevealed
    let location = CGPoint(x: x, y: 100)
    let minimumPageWidth = BrowserChromeMetrics.minimumPageWidth(isSettings: false)
    WIDTH
    ASSIGNMENT
    return isSidebarRevealed
}

for showsAI in [false, true] {
    for windowWidth: CGFloat in [400, 800, 1200] {
        let width = BrowserChromeMetrics.sidebarWidth(
            preferred: BrowserChromeMetrics.expandedSidebarWidth,
            limits: BrowserChromeMetrics.sidebarWidthRange,
            availableWidth: windowWidth,
            minimumContentWidth: BrowserChromeMetrics.minimumPageWidth(isSettings: false)
                + (showsAI ? BrowserChromeMetrics.aiSidebarWidthRange.lowerBound : 0)
        )
        assert(revealed(shown: false, wasRevealed: false, x: 5, windowWidth: windowWidth, showsAI: showsAI))
        assert(!revealed(shown: false, wasRevealed: false, x: 6, windowWidth: windowWidth, showsAI: showsAI))
        assert(revealed(shown: false, wasRevealed: true, x: width - 1, windowWidth: windowWidth, showsAI: showsAI))
        assert(!revealed(shown: false, wasRevealed: true, x: width, windowWidth: windowWidth, showsAI: showsAI))
        assert(!revealed(shown: true, wasRevealed: true, x: 0, windowWidth: windowWidth, showsAI: showsAI))
    }
}
print("Sidebar hover check passed")
""".replace("WIDTH", width).replace("ASSIGNMENT", assignment)

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "sidebar-hover-check.swift"
    path.write_text(check)
    subprocess.run(["swift", str(path)], check=True)
