import Foundation

enum BrowserDownloadStatus: String, Codable, Sendable {
	case downloading
	case paused
	case completed
	case failed
}

struct BrowserDownloadSegment: Codable, Sendable {
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

struct BrowserDownload: Codable, Identifiable, Sendable {
	let id: UUID
	let createdAt: Date
	let sourceURL: URL?
	var requestURL: URL?
	var requestMethod: String? = nil
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

	var name: String {
		status == .completed
			? fileURL.lastPathComponent
			: fileURL.deletingPathExtension().lastPathComponent
	}

	var symbol: String {
		let extensionName = status == .completed
			? fileURL.pathExtension.lowercased()
			: fileURL.deletingPathExtension().pathExtension.lowercased()
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
