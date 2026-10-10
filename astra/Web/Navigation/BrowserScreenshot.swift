#if os(macOS)
	import AppKit
	import CoreImage

	@MainActor
	final class BrowserScreenshot {
		let image: NSImage
		let scale: CGFloat
		private lazy var noise: NSImage? = {
			let size = Self.framedSize(for: image.size)
			let extent = CGRect(x: 0, y: 0, width: ceil(size.width * scale), height: ceil(size.height * scale))
			guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
			let monochrome = random.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
			guard let texture = CIContext().createCGImage(monochrome, from: extent) else { return nil }
			return NSImage(cgImage: texture, size: size)
		}()

		init(image: NSImage, scale: CGFloat) {
			self.image = image
			self.scale = scale
		}

		static func framedSize(for size: CGSize) -> CGSize {
			let inset = 48 + BrowserChromeMetrics.shellEdgePadding
			return CGSize(width: size.width + inset * 2, height: size.height + inset * 2)
		}

		static func gradientColors(hue: Double, neutral: Bool, dark: Bool) -> [NSColor] {
			if neutral {
				return dark
					? [NSColor(white: 0.3, alpha: 1), .black]
					: [NSColor(white: 1, alpha: 1), NSColor(white: 0.9, alpha: 1)]
			}
			return [
				NSColor(calibratedHue: hue, saturation: 0.35, brightness: 0.88, alpha: 1),
				NSColor(calibratedHue: hue, saturation: 0.5, brightness: 0.55, alpha: 1),
			]
		}

		func framed(hue: Double, neutral: Bool, dark: Bool, noiseAmount: Double) -> NSImage? {
			let size = Self.framedSize(for: image.size)
			guard let bitmap = NSBitmapImageRep(
				bitmapDataPlanes: nil,
				pixelsWide: Int(ceil(size.width * scale)),
				pixelsHigh: Int(ceil(size.height * scale)),
				bitsPerSample: 8,
				samplesPerPixel: 4,
				hasAlpha: true,
				isPlanar: false,
				colorSpaceName: .deviceRGB,
				bytesPerRow: 0,
				bitsPerPixel: 0
			), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
			bitmap.size = size
			NSGraphicsContext.saveGraphicsState()
			NSGraphicsContext.current = context
			context.cgContext.scaleBy(x: scale, y: scale)
			let colors = Self.gradientColors(hue: hue, neutral: neutral, dark: dark)
			NSGradient(starting: colors[1], ending: colors[0])?.draw(in: CGRect(origin: .zero, size: size), angle: 90)
			if noiseAmount > 0 {
				guard let noise else {
					NSGraphicsContext.restoreGraphicsState()
					return nil
				}
				noise.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: noiseAmount)
			}

			let padding = BrowserChromeMetrics.shellEdgePadding
			let pageRect = CGRect(origin: CGPoint(x: 48 + padding, y: 48 + padding), size: image.size)
			let radius = BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar
			let border = NSBezierPath(roundedRect: pageRect.insetBy(dx: -padding, dy: -padding), xRadius: radius + padding, yRadius: radius + padding)
			NSColor(white: dark ? 0.24 : 0.92, alpha: 1).setFill()
			border.fill()
			NSBezierPath(roundedRect: pageRect, xRadius: radius, yRadius: radius).addClip()
			image.draw(in: pageRect, from: .zero, operation: .sourceOver, fraction: 1)
			NSGraphicsContext.restoreGraphicsState()
			let result = NSImage(size: size)
			result.addRepresentation(bitmap)
			return result
		}

		static func copy(_ image: NSImage) -> Bool {
			guard let data = image.tiffRepresentation,
			      let bitmap = NSBitmapImageRep(data: data),
			      let png = bitmap.representation(using: .png, properties: [:]) else { return false }
			NSPasteboard.general.clearContents()
			return NSPasteboard.general.setData(png, forType: .png)
		}
	}
#endif
