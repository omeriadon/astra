import AppKit

@main
struct ScreenshotCheck {
	@MainActor
	static func main() {
		let image = NSImage(size: CGSize(width: 100, height: 80))
		image.lockFocus()
		NSColor.red.setFill()
		CGRect(x: 0, y: 0, width: 100, height: 80).fill()
		image.unlockFocus()
		let capture = BrowserScreenshot(image: image, scale: 2)
		let size = BrowserScreenshot.framedSize(for: image.size)
		assert(size == CGSize(width: 204, height: 184))
		for dark in [false, true] {
			for neutral in [false, true] {
				let colors = BrowserScreenshot.gradientColors(hue: 0.65, neutral: neutral, dark: dark)
				assert(colors[0].usingColorSpace(.deviceRGB)!.brightnessComponent > colors[1].usingColorSpace(.deviceRGB)!.brightnessComponent)
				for noise in [0.0, 0.25] {
					let output = capture.framed(hue: 0.65, neutral: neutral, dark: dark, noiseAmount: noise)!
					assert(output.size == size)
					let bitmap = output.representations[0] as! NSBitmapImageRep
					assert(bitmap.pixelsWide == 408 && bitmap.pixelsHigh == 368)
					let center = bitmap.colorAt(x: 204, y: 184)!.usingColorSpace(.deviceRGB)!
					assert(center.redComponent > 0.95 && center.greenComponent < 0.05)
					if neutral {
						let background = bitmap.colorAt(x: 10, y: 10)!.usingColorSpace(.deviceRGB)!
						assert(abs(background.redComponent - background.greenComponent) < 0.01)
						assert(abs(background.greenComponent - background.blueComponent) < 0.01)
					}
				}
			}
		}
		print("Screenshot rendering checks passed")
	}
}
