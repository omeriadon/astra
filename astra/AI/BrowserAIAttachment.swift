import Foundation
import PDFKit
import UniformTypeIdentifiers
#if os(macOS)
	import AppKit
#else
	import UIKit
#endif

nonisolated struct BrowserAIImage: Codable, Equatable, Sendable {
	let name: String
	let mediaType: String
	let data: Data
}

nonisolated struct BrowserAIAttachment: Codable, Equatable, Identifiable, Sendable {
	let id: UUID
	let name: String
	let image: BrowserAIImage?
	let text: String?

	@MainActor static func read(_ url: URL) async throws -> Self {
		let scoped = url.startAccessingSecurityScopedResource()
		defer {
			if scoped {
				url.stopAccessingSecurityScopedResource()
			}
		}
		let data = try await Task.detached(priority: .userInitiated) {
			let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
			guard size <= 20 * 1024 * 1024 else { throw BrowserAIError.attachmentTooLarge }
			return try Data(contentsOf: url)
		}.value
		try Task.checkCancellation()
		let name = String(url.lastPathComponent.prefix(200))
		let type = UTType(filenameExtension: url.pathExtension)
		if type?.conforms(to: .image) == true {
			#if os(macOS)
				guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { throw BrowserAIError.attachmentUnreadable(name) }
				let scale = min(1, 2048 / max(image.size.width, image.size.height))
				let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
				guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: max(1, Int(size.width)), pixelsHigh: max(1, Int(size.height)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
				      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw BrowserAIError.attachmentUnreadable(name) }
				NSGraphicsContext.saveGraphicsState()
				NSGraphicsContext.current = context
				image.draw(in: NSRect(origin: .zero, size: size))
				NSGraphicsContext.restoreGraphicsState()
				guard let encoded = bitmap.representation(using: .png, properties: [:]), encoded.count <= 10 * 1024 * 1024 else { throw BrowserAIError.attachmentTooLarge }
			#else
				guard let image = UIImage(data: data), let encoded = image.pngData(), encoded.count <= 10 * 1024 * 1024 else { throw BrowserAIError.attachmentUnreadable(name) }
			#endif
			return Self(id: UUID(), name: name, image: BrowserAIImage(name: name, mediaType: "image/png", data: encoded), text: nil)
		}
		let text: String? = if type?.conforms(to: .pdf) == true {
			await Task.detached(priority: .userInitiated) {
				guard let document = PDFDocument(data: data) else { return nil as String? }
				return (0 ..< document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
			}.value
		} else if ["rtf", "doc", "docx"].contains(url.pathExtension.lowercased()) {
			try? NSAttributedString(data: data, options: [:], documentAttributes: nil).string
		} else {
			String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
		}
		guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
		      !text.contains("\0") else { throw BrowserAIError.attachmentUnreadable(name) }
		return Self(id: UUID(), name: name, image: nil, text: text)
	}

	var prompt: String {
		"<attached-file name=\(name)>\n\(text ?? "Image attached separately.")\n</attached-file>"
	}
}
