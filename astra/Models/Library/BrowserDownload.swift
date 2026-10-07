import Foundation

enum BrowserDownloadStatus: String, Codable, Sendable {
	case downloading
	case paused
	case completed
	case cancelled
	case failed
}

struct BrowserDownloadSegment: Codable, Equatable, Sendable {
	static let minimumSegmentBytes: Int64 = 32 * 1024 * 1024
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
	var throughput: Int? = nil
	var estimatedTimeRemaining: TimeInterval? = nil
	var folderBookmark: Data? = nil
	var fileAccessBookmark: Data? = nil

	var name: String {
		status == .completed
			? fileURL.lastPathComponent
			: destinationURL?.lastPathComponent ?? originalName
	}

	var progressLabel: String {
		let received = ByteCountFormatter.string(fromByteCount: receivedBytes ?? 0, countStyle: .file)
		if let totalBytes {
			return "\(received) of \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
		}
		return received
	}

	var progressDetails: String {
		var details = [progressLabel]
		if let throughput, throughput > 0 {
			let rate = ByteCountFormatter.string(fromByteCount: Int64(throughput), countStyle: .file)
			details.append("\(rate)/s")
		}
		if let estimatedTimeRemaining, estimatedTimeRemaining.isFinite, estimatedTimeRemaining > 0 {
			let formatter = DateComponentsFormatter()
			formatter.allowedUnits = [.hour, .minute, .second]
			formatter.unitsStyle = .abbreviated
			formatter.maximumUnitCount = 2
			if let remaining = formatter.string(from: estimatedTimeRemaining) {
				details.append("\(remaining) remaining")
			}
		}
		return details.joined(separator: " · ")
	}

	static func averageThroughput(samples: [(bytes: Int64, at: Date)]) -> Double? {
		guard let first = samples.first, let last = samples.last else { return nil }
		let cutoff = last.at.addingTimeInterval(-20)
		var startBytes = Double(first.bytes)
		var startTime = first.at
		if first.at < cutoff, samples.count > 1 {
			let next = samples[1]
			let interval = next.at.timeIntervalSince(first.at)
			guard interval > 0 else { return nil }
			startBytes += Double(next.bytes - first.bytes) * cutoff.timeIntervalSince(first.at) / interval
			startTime = cutoff
		}
		let elapsed = last.at.timeIntervalSince(startTime)
		guard elapsed > 0 else { return nil }
		return max(0, (Double(last.bytes) - startBytes) / elapsed)
	}

	static func smoothedThroughput(previous: Double?, observed: Double, elapsed: TimeInterval) -> Double {
		guard observed.isFinite, observed >= 0 else { return previous ?? 0 }
		guard let previous, previous.isFinite, previous >= 0, elapsed > 0 else { return observed }
		let alpha = min(max(1 - exp(-elapsed / 4), 0.04), 0.35)
		return previous + alpha * (observed - previous)
	}

	static func smoothedTimeRemaining(
		previous: TimeInterval?,
		observed: TimeInterval,
		elapsed: TimeInterval
	) -> TimeInterval? {
		guard observed.isFinite, observed > 0 else { return previous }
		guard let previous, previous.isFinite, previous > 0, elapsed > 0 else {
			return observed
		}
		let predicted = max(0, previous - elapsed)
		var alpha = min(max(1 - exp(-elapsed / 8), 0.025), 0.20)
		if observed > max(predicted * 2, predicted + 60)
			|| observed < min(predicted * 0.5, max(0, predicted - 60))
		{
			alpha = max(alpha, 0.08)
		}
		return max(0, predicted + alpha * (observed - predicted))
	}

	static func displayTimeRemaining(_ value: TimeInterval) -> TimeInterval {
		guard value.isFinite, value > 0 else { return value }
		let quantum: TimeInterval = if value < 60 {
			5
		} else if value < 10 * 60 {
			10
		} else if value < 60 * 60 {
			30
		} else {
			60
		}
		return max(quantum, (value / quantum).rounded() * quantum)
	}

	var estimatedFinish: Date? {
		guard status == .downloading,
		      let estimatedTimeRemaining,
		      estimatedTimeRemaining.isFinite,
		      estimatedTimeRemaining > 0
		else { return nil }
		return Date.now.addingTimeInterval(estimatedTimeRemaining)
	}

	var statusSummary: String {
		switch status {
			case .downloading:
				return progressDetails
			case .paused:
				return "\(errorMessage ?? "Paused") · \(progressLabel)"
			case .completed:
				if destinationIsFileScoped == true, fileAccessBookmark == nil {
					return "Downloaded · renewed access needed · \(progressLabel)"
				}
				return "Downloaded · \(progressLabel)"
			case .cancelled:
				return "Cancelled · \(progressLabel)"
			case .failed:
				let error = errorMessage ?? "Download failed."
				guard (receivedBytes ?? 0) > 0 else { return error }
				return "\(error) · \(progressLabel)"
		}
	}

	var canRetry: Bool {
		[.failed, .cancelled, .paused].contains(status)
			&& requestMethod?.uppercased() == "GET"
			&& requestHasBody == false
			&& requestHasAuthorization == false
			&& ["http", "https"].contains(retryURL?.scheme?.lowercased() ?? "")
	}

	var canResume: Bool {
		status == .paused && (resumeData != nil || segments?.isEmpty == false)
	}

	mutating func markCancellationPending() {
		status = .paused
		resumeData = nil
		errorMessage = "Canceling download."
		throughput = nil
		estimatedTimeRemaining = nil
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

	static func requestHasBody(_ request: URLRequest) -> Bool {
		request.httpBody != nil || request.httpBodyStream != nil
	}

	private static let sensitiveRequestHeaders: Set<String> = [
		"authorization",
		"cookie",
		"cookie2",
		"proxy-authorization",
	]

	/// Segmented transfers may replay ordinary request semantics such as Accept,
	/// Referer and User-Agent, but must never detach browser-managed credentials.
	static func requestHasSensitiveCredentials(_ request: URLRequest) -> Bool {
		if request.url?.user != nil || request.url?.password != nil {
			return true
		}
		return (request.allHTTPHeaderFields ?? [:]).keys.contains {
			sensitiveRequestHeaders.contains($0.lowercased())
		}
	}

	/// Fresh retry does not persist arbitrary request headers, so it remains more
	/// conservative than segmented transfer and leaves any header-bearing request
	/// owned by WebKit.
	static func requestMayCarryCredentials(_ request: URLRequest) -> Bool {
		requestHasSensitiveCredentials(request)
			|| !(request.allHTTPHeaderFields ?? [:]).isEmpty
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
