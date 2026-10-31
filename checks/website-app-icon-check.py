"""Exercise the production ICNS writer with favicon sizes and TIFF input."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/App/BrowserWebsiteAppFileWorker.swift").read_text()
start = source.index("\t\tprivate func writeIcon")
end = source.index("\n\t\tprivate func registerGeneratedApp", start)
writer = source[start:end].replace("private func", "func", 1)

with tempfile.TemporaryDirectory(prefix="astra-icon-check-") as directory:
    main = Path(directory) / "main.swift"
    main.write_text("""
import AppKit
import ImageIO

enum BrowserWebsiteAppFileError: Error {
    case malformedTemplate(String)
}
""" + writer + """
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [64, 180, 192, 16, 24, 32, 48, 128, 256, 512] {
    for height in [size, max(1, size / 2)] {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        for format in [NSBitmapImageRep.FileType.png, .tiff] {
            let data = bitmap.representation(using: format, properties: [:])!
            let url = directory.appendingPathComponent("WebsiteIcon.icns")
            try writeIcon(data, to: url)
            let decoded = CGImageSourceCreateWithURL(url as CFURL, nil)!
            assert(CGImageSourceGetType(decoded)! as String == "com.apple.icns")
            let image = CGImageSourceCreateImageAtIndex(decoded, 0, nil)!
            assert(image.width == 256 && image.height == 256)
        }
    }
}
do {
    try writeIcon(Data("invalid image".utf8), to: directory.appendingPathComponent("Invalid.icns"))
    fatalError("Invalid image data was accepted")
} catch BrowserWebsiteAppFileError.malformedTemplate {
}
print("Website-app ICNS sizes, aspect ratios, PNG/TIFF, and invalid input checks passed")
""")
    executable = Path(directory) / "icon-check"
    subprocess.run(["swiftc", str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable), directory], check=True)
