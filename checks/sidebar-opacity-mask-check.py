"""Run with python3 checks/sidebar-opacity-mask-check.py. Does not launch Astra."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/UI/Shell/topVariableBlur.swift").read_text()
mask = source[source.index("private extension View {"):source.index("private struct SidebarScrollContentMarginsModifier")]
check = "import AppKit\nimport SwiftUI\n" + mask + """
@MainActor
func renderedMask(bottom: CGFloat, bottomOpacityHeight: CGFloat) -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: Color.white
        .frame(width: 8, height: 600)
        .sidebarScrollAlphaMask(
            top: 38,
            bottom: bottom,
            bottomOpacityHeight: bottomOpacityHeight
        ))
    renderer.scale = 1
    guard let image = renderer.cgImage else {
        fatalError("Opacity mask did not render")
    }
    return NSBitmapImageRep(cgImage: image)
}

MainActor.assumeIsolated {
    let withoutMedia = renderedMask(bottom: 45, bottomOpacityHeight: 34)
    func noMediaAlpha(_ y: Int) -> CGFloat {
        withoutMedia.colorAt(x: 4, y: y)!.alphaComponent
    }
    assert(abs(noMediaAlpha(20) - 0.3) < 0.08, "Top 20-point opacity stop changed")
    assert(noMediaAlpha(38) > 0.98, "Top fade must reach full opacity at 38 points")
    assert(noMediaAlpha(300) > 0.98, "Middle content must remain fully opaque")
    assert(noMediaAlpha(555) > 0.98, "No-media bottom ramp must start 45 points above the edge")
    assert(noMediaAlpha(560) > 0.45 && noMediaAlpha(560) < 0.85, "No-media bottom ramp must be smooth")
    assert(abs(noMediaAlpha(566) - 0.3) < 0.04, "No-media plateau must start 34 points above the edge")
    assert(abs(noMediaAlpha(599) - 0.3) < 0.04, "No-media opacity must stay at 0.3 through the window edge")

    let mediaHeight: CGFloat = 80
    let mediaOpacityHeight = mediaHeight + 8 + 33
    let mediaBottom = mediaOpacityHeight + 11
    let withMedia = renderedMask(bottom: mediaBottom, bottomOpacityHeight: mediaOpacityHeight)
    func mediaAlpha(_ y: Int) -> CGFloat {
        withMedia.colorAt(x: 4, y: y)!.alphaComponent
    }
    assert(mediaAlpha(300) > 0.98, "Media layout must preserve fully opaque middle content")
    assert(mediaAlpha(467) > 0.98, "Media ramp must be fully opaque just above its start")
    assert(mediaAlpha(473) > 0.45 && mediaAlpha(473) < 0.85, "Media bottom ramp must be smooth")
    assert(abs(mediaAlpha(479) - 0.3) < 0.04, "Media plateau must start at the media-card top")
    assert(abs(mediaAlpha(599) - 0.3) < 0.04, "Media opacity must stay at 0.3 through the window edge")
    print("Rendered sidebar opacity mask check passed")
}
"""
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "check.swift"
    path.write_text(check)
    subprocess.run(["swift", str(path)], check=True)
