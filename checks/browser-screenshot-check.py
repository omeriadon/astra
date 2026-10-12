"""Exercise the screenshot renderer and the editor's actual sizing helpers."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
editor = (root / "astra/UI/Chrome/BrowserScreenshotButton.swift").read_text()
start = editor.index("\t\tprivate static func aspectRatio")
end = editor.index("\n\t}\n", start)
helpers = editor[start:end].replace("private static func", "static func")

with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / "main.swift"
    main.write_text("""
import AppKit

enum BrowserChromeMetrics {
    static let shellEdgePadding: CGFloat = 4
    static let tabWindowCornerRadiusWithSidebar: CGFloat = 12.5
}

@MainActor
struct EditorGeometry {
""" + helpers + """
}

@main
struct ScreenshotCheck {
    @MainActor
    static func main() {
        for size in [CGSize(width: 1200, height: 700), CGSize(width: 700, height: 1200), CGSize(width: 300, height: 900)] {
            let framed = BrowserScreenshot.framedSize(for: size)
            let preview = EditorGeometry.previewSize(for: size)
            assert(preview.width >= 300 && preview.width <= 520)
            assert(abs(preview.width / preview.height - framed.width / framed.height) < 0.0001)
        }
        for value in [0.0, 0.5, 1.0] {
            let colors = BrowserScreenshot.gradientColors(hue: 0.65, grayscale: value, grayscaleEnabled: true)
            let whites = colors.map { $0.whiteComponent }
            assert(abs(whites[1] - (1 - value)) < 0.001)
            assert(whites[0] <= whites[1])
        }
        let color = BrowserScreenshot.gradientColors(hue: 0.65, grayscale: 0, grayscaleEnabled: false)[0]
        assert(color.usingColorSpace(.deviceRGB)!.blueComponent > color.usingColorSpace(.deviceRGB)!.redComponent)
        let screenshot = BrowserScreenshot(image: NSImage(size: CGSize(width: 200, height: 100)), scale: 2)
        let exported = screenshot.framed(hue: 0.65, grayscale: 1, grayscaleEnabled: true, dark: true, noiseAmount: 0.16)!
        assert(exported.size == BrowserScreenshot.framedSize(for: screenshot.image.size))
        let bitmap = exported.representations[0] as! NSBitmapImageRep
        assert(bitmap.pixelsWide == Int(exported.size.width * 2))
        print("Screenshot sizing, grayscale endpoints, and export checks passed")
    }
}
""")
    executable = Path(directory) / "screenshot-check"
    subprocess.run(["swiftc", "-parse-as-library", str(root / "astra/Web/Navigation/BrowserScreenshot.swift"), str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
