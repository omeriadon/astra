import Foundation
import ImageIO
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

nonisolated struct BrowserAIFile: Codable, Equatable, Sendable {
	let name: String
	let mediaType: String
	let data: Data
	var hasExtractedText: Bool? = nil
}

nonisolated struct BrowserAIAttachment: Codable, Equatable, Identifiable, Sendable {
	let id: UUID
	let name: String
	let image: BrowserAIImage?
	let text: String?
	var file: BrowserAIFile? = nil

	static let maximumFileBytes = 32 * 1024 * 1024
	static let maximumTotalBytes = 64 * 1024 * 1024
	static let maximumFiles = 16
	private static let maximumTextBytes = 2 * 1024 * 1024

	@MainActor static func read(_ url: URL) async throws -> Self {
		let scoped = url.startAccessingSecurityScopedResource()
		defer {
			if scoped {
				url.stopAccessingSecurityScopedResource()
			}
		}
		let worker = Task.detached(priority: .userInitiated) { try prepare(url) }
		return try await withTaskCancellationHandler {
			let result = try await worker.value
			try Task.checkCancellation()
			return result
		} onCancel: { worker.cancel() }
	}

	private static func prepare(_ url: URL) throws -> Self {
		let name = String(url.lastPathComponent.prefix(200))
		let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
		guard values.isRegularFile == true, let size = values.fileSize, size <= maximumFileBytes else { throw BrowserAIError.attachmentTooLarge }
		try Task.checkCancellation()
		// A bounded read also handles files growing after the metadata check.
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		var data = Data()
		while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
			try Task.checkCancellation()
			guard data.count + chunk.count <= maximumFileBytes else { throw BrowserAIError.attachmentTooLarge }
			data.append(chunk)
		}
		let type = UTType(filenameExtension: url.pathExtension)
		if type?.conforms(to: .image) == true {
			guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
			      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
				kCGImageSourceCreateThumbnailFromImageAlways: true,
				kCGImageSourceCreateThumbnailWithTransform: true,
				kCGImageSourceThumbnailMaxPixelSize: 2048,
				kCGImageSourceShouldCacheImmediately: true,
			      ] as CFDictionary) else { throw BrowserAIError.attachmentUnreadable(name) }
			try Task.checkCancellation()
			let encoded = NSMutableData()
			guard let writer = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else { throw BrowserAIError.attachmentUnreadable(name) }
			CGImageDestinationAddImage(writer, image, nil)
			guard CGImageDestinationFinalize(writer), encoded.length <= 10 * 1024 * 1024 else { throw BrowserAIError.attachmentTooLarge }
			return Self(id: UUID(), name: name, image: BrowserAIImage(name: name, mediaType: "image/png", data: encoded as Data), text: nil)
		}
		let text: String?
		if type?.conforms(to: .pdf) == true {
			guard let document = PDFDocument(data: data), document.pageCount <= 500 else { throw BrowserAIError.attachmentTooLarge }
			var parts: [String] = []
			var bytes = 0
			for index in 0 ..< document.pageCount {
				try Task.checkCancellation()
				if let value = document.page(at: index)?.string {
					bytes += value.utf8.count
					guard bytes <= maximumTextBytes else { throw BrowserAIError.attachmentTooLarge }
					parts.append(value)
				}
			}
			text = parts.joined(separator: "\n\n")
		} else if ["rtf", "doc", "docx"].contains(url.pathExtension.lowercased()) {
			text = try? unsafe NSAttributedString(data: data, options: [:], documentAttributes: nil).string
		} else {
			text = String(data: data, encoding: .utf8) ?? (data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) ? String(data: data, encoding: .utf16) : nil)
		}
		try Task.checkCancellation()
		guard (text?.utf8.count ?? 0) <= maximumTextBytes else { throw BrowserAIError.attachmentTooLarge }
		let readableText = text.flatMap { value in
			value.contains("\0") || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
		}
		return Self(id: UUID(), name: name, image: nil, text: readableText, file: BrowserAIFile(name: name, mediaType: type?.preferredMIMEType ?? "application/octet-stream", data: data, hasExtractedText: readableText != nil))
	}

	static func validateBudget(_ attachments: [Self]) throws {
		guard attachments.count <= maximumFiles else { throw BrowserAIError.attachmentTooLarge }
		var bytes = 0
		var imageBytes = 0
		var images = 0
		for attachment in attachments {
			bytes += (attachment.file?.data.count ?? 0) + (attachment.image?.data.count ?? 0) + (attachment.text?.utf8.count ?? 0)
			if let image = attachment.image {
				images += 1; imageBytes += image.data.count
			}
			guard bytes <= maximumTotalBytes, images <= 8, imageBytes <= 10 * 1024 * 1024 else { throw BrowserAIError.attachmentTooLarge }
		}
	}

	var prompt: String {
		"<attached-file name=\(name)>\n\(text ?? (image != nil ? "Image attached separately." : "Original file attached separately."))\n</attached-file>"
	}
}
