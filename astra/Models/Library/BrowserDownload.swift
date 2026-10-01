import Foundation

enum BrowserDownloadStatus: String, Codable, Sendable {
	case downloading
	case paused
	case completed
	case failed
}

struct BrowserDownloadSegment: Codable, Equatable, Sendable {
	static let minimumSegmentBytes: Int64 = 128 * 1024 * 1024
	static let maximumConnections = 16

	let start: Int64
	let end: Int64
	var received: Int64 = 0
	var completed = false

	static func plan(total: Int64) -> [Self] {
		var count = 1
		while count < maximumConnections,
		      total / Int64(count * 2) >= minimumSegmentBytes
		{
			count *= 2
		}
		guard count > 1 else { return [] }

		let segmentSize = total / Int64(count)
		return (0 ..< count).map { number in
			let start = Int64(number) * segmentSize
			let end = number == count - 1 ? total - 1 : (Int64(number) + 1) * segmentSize - 1
			return Self(start: start, end: end)
		}
	}
}

struct BrowserDownload: Codable, Equatable, Identifiable, Sendable {
	let id: UUID
	let createdAt: Date
	let sourceURL: URL?
	var requestURL: URL?
	var retryURL: URL? = nil
	var destinationURL: URL? = nil
	var destinationIsFileScoped: Bool? = nil
	var requestMethod: String? = nil
	var requestHasBody: Bool? = nil
	var requestHasAuthorization: Bool? = nil
	var originalName: String
	var fileURL: URL
	var status: BrowserDownloadStatus
	var progress: Double
	var renamedByAppleIntelligence: Bool
	var resumeData: Data?
	var errorMessage: String?
	var segments: [BrowserDownloadSegment]? = nil
	var rangeValidator: String? = nil
	var totalBytes: Int64? = nil
	var receivedBytes: Int64? = nil
	var folderBookmark: Data? = nil
	var fileAccessBookmark: Data? = nil

	var name: String {
		status == .completed
			? fileURL.lastPathComponent
			: originalName
	}

	var progressLabel: String {
		let received = ByteCountFormatter.string(fromByteCount: receivedBytes ?? 0, countStyle: .file)
		if let totalBytes {
			return "\(received) of \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
		}
		return received
	}

	var statusSummary: String {
		switch status {
			case .downloading:
				return progressLabel
			case .paused:
				return "Paused · \(progressLabel)"
			case .completed:
				return "Downloaded · \(progressLabel)"
			case .failed:
				let error = errorMessage ?? "Download failed."
				guard (receivedBytes ?? 0) > 0 else { return error }
				return "\(error) · \(progressLabel)"
		}
	}

	var canRetry: Bool {
		status == .failed
			&& requestMethod?.uppercased() == "GET"
			&& requestHasBody != true
			&& requestHasAuthorization != true
			&& ["http", "https"].contains(retryURL?.scheme?.lowercased() ?? "")
	}

	static func safeFilename(_ suggestedName: String) -> String {
		let lastComponent = URL(fileURLWithPath: suggestedName).lastPathComponent
		let scalars = lastComponent.unicodeScalars.filter {
			!CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).contains($0)
		}
		let cleaned = String(String.UnicodeScalarView(scalars))
			.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
		let source = URL(fileURLWithPath: cleaned.isEmpty ? "Download" : cleaned)
		let stem = source.deletingPathExtension().lastPathComponent
		let ext = source.pathExtension
		let safeExtension = utf8Prefix(ext, maxBytes: 80)
		let stemLimit = max(1, 180 - safeExtension.utf8.count - (safeExtension.isEmpty ? 0 : 1))
		let safeStem = utf8Prefix(stem, maxBytes: stemLimit)
		guard !safeStem.isEmpty else { return "Download" }
		guard !safeExtension.isEmpty else { return safeStem }
		return "\(safeStem).\(safeExtension)"
	}

	static func collisionFreeURL(
		fileName: String,
		in directory: URL,
		reserved: Set<URL> = [],
		excluding: URL? = nil
	) -> URL {
		let safeName = safeFilename(fileName)
		let source = URL(fileURLWithPath: safeName)
		let stem = source.deletingPathExtension().lastPathComponent
		let fileExtension = source.pathExtension
		var candidate = directory.appendingPathComponent(safeName)
		var number = 2
		while FileManager.default.fileExists(atPath: candidate.path)
			|| candidate.standardizedFileURL == excluding?.standardizedFileURL
			|| reserved.contains(candidate.standardizedFileURL)
		{
			let suffix = " (\(number))"
			let budget = max(1, 180 - suffix.utf8.count - fileExtension.utf8.count - (fileExtension.isEmpty ? 0 : 1))
			let shortenedStem = utf8Prefix(stem, maxBytes: budget)
			let name = fileExtension.isEmpty
				? "\(shortenedStem)\(suffix)"
				: "\(shortenedStem)\(suffix).\(fileExtension)"
			candidate = directory.appendingPathComponent(name)
			number += 1
		}
		return candidate
	}

	private static func utf8Prefix(_ value: String, maxBytes: Int) -> String {
		var result = ""
		var count = 0
		for character in value {
			let bytes = String(character).utf8.count
			guard count + bytes <= maxBytes else { break }
			result.append(character)
			count += bytes
		}
		return result
	}

	var symbol: String {
		let extensionName = URL(fileURLWithPath: name).pathExtension.lowercased()
		return switch extensionName {
			case "dmg", "app", "pkg": "app.fill"
			case "png", "jpg", "jpeg", "heic", "gif", "webp", "svg": "photo.fill"
			case "mp4", "mov", "m4v": "film.fill"
			case "mp3", "wav", "m4a", "flac": "music.note"
			case "pdf": "doc.richtext.fill"
			case "zip", "tar", "gz", "7z": "archivebox.fill"
			default: "document.fill"
		}
	}
}
