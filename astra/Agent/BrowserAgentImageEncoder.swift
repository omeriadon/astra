#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
	import CoreGraphics
	import Foundation
	import ImageIO
	import UniformTypeIdentifiers

	/// Only CGImage capture crosses from WebKit; ImageIO compression and base64
	/// run on this actor, independently of AppKit's application actor.
	actor BrowserAgentImageEncoder {
		static let shared = BrowserAgentImageEncoder()
		nonisolated struct Encoded: Sendable {
			let data: String
			let mimeType: String
			let width: Int
			let height: Int
		}

		nonisolated enum EncodingError: LocalizedError {
			case invalidOptions, failed, oversized
			var errorDescription: String? {
				switch self {
					case .invalidOptions: "Invalid screenshot encoding options."
					case .failed: "Screenshot image encoding failed."
					case .oversized: "Encoded screenshot exceeds the 16 MiB output limit; request a smaller width or JPEG."
				}
			}
		}

		func encodePDF(_ data: Data, width: Int, height: Int, format: String, quality: Double) throws -> Encoded {
			try Task.checkCancellation()
			guard data.count <= 32 * 1024 * 1024, width > 0, height > 0,
			      width <= 4096, height <= 100_000, width * height <= 16_000_000,
			      let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
			      document.numberOfPages == 1, let page = document.page(at: 1),
			      let context = unsafe CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
			                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
			else { throw EncodingError.oversized }
			let rect = CGRect(x: 0, y: 0, width: width, height: height)
			context.setFillColor(CGColor(gray: 1, alpha: 1))
			context.fill(rect)
			context.concatenate(page.getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
			context.drawPDFPage(page)
			try Task.checkCancellation()
			guard let image = context.makeImage() else { throw EncodingError.failed }
			return try encode(image, format: format, maxWidth: width, quality: quality)
		}

		func encode(_ source: CGImage, format: String = "png", maxWidth: Int? = nil, quality: Double = 0.85) throws -> Encoded {
			try Task.checkCancellation()
			guard ["png", "jpeg"].contains(format), quality.isFinite, (0 ... 1).contains(quality), maxWidth == nil || (1 ... 8192).contains(maxWidth!) else { throw EncodingError.invalidOptions }
			guard source.width > 0, source.height > 0, source.width <= 32768, source.height <= 100_000, source.width * source.height <= 16_000_000 else { throw EncodingError.oversized }
			let started = ContinuousClock.now
			let image: CGImage
			if let maxWidth, source.width > maxWidth {
				let height = max(1, Int(Double(source.height) * Double(maxWidth) / Double(source.width)))
				guard let context = unsafe CGContext(data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EncodingError.failed }
				context.interpolationQuality = .high
				context.draw(source, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
				guard let scaled = context.makeImage() else { throw EncodingError.failed }
				image = scaled
			} else {
				image = source
			}
			let output = NSMutableData()
			let type = format == "jpeg" ? UTType.jpeg.identifier : UTType.png.identifier
			guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { throw EncodingError.failed }
			CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
			guard CGImageDestinationFinalize(destination) else { throw EncodingError.failed }
			try Task.checkCancellation()
			guard output.length <= 16 * 1024 * 1024 else { throw EncodingError.oversized }
			BrowserLog.debug(.agent, "agent.screenshot.encoding.end", metadata: ["duration": String(describing: started.duration(to: .now)), "bytes": String(output.length)])
			return Encoded(data: (output as Data).base64EncodedString(), mimeType: "image/\(format)", width: image.width, height: image.height)
		}
	}
#endif
