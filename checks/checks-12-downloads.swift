import Foundation

@main
struct Checks {
	static func main() throws {
		let traversal = BrowserDownload.safeFilename("../../folder/escape:name?.pdf")
		assert(!traversal.contains("/"))
		assert(!traversal.contains(":"))
		assert(!traversal.contains("?"))
		assert(traversal.hasSuffix(".pdf"))

		var projectedDownload = BrowserDownload(
			id: UUID(),
			createdAt: .now,
			sourceURL: nil,
			requestURL: nil,
			originalName: "progress.bin",
			fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("progress.bin"),
			status: .downloading,
			progress: 0.25,
			renamedByAppleIntelligence: false,
			resumeData: nil,
			errorMessage: nil
		)
		projectedDownload.destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent("chosen name.bin")
		assert(projectedDownload.name == "chosen name.bin")
		assert(projectedDownload.progressDetails == projectedDownload.progressLabel)
		projectedDownload.throughput = 1_048_576
		projectedDownload.estimatedTimeRemaining = 61
		assert(projectedDownload.progressDetails.contains("/s"))
		assert(projectedDownload.progressDetails.contains("remaining"))
		projectedDownload.status = .failed
		projectedDownload.requestMethod = "GET"
		projectedDownload.retryURL = URL(string: "https://example.com/progress.bin")
		assert(!projectedDownload.canRetry)
		projectedDownload.requestHasBody = false
		projectedDownload.requestHasAuthorization = false
		assert(projectedDownload.canRetry)
		projectedDownload.requestHasBody = true
		assert(!projectedDownload.canRetry)
		projectedDownload.requestHasBody = false
		projectedDownload.requestHasAuthorization = true
		assert(!projectedDownload.canRetry)

		var credentialRequest = URLRequest(url: URL(string: "https://example.com")!)
		assert(!BrowserDownload.requestMayCarryCredentials(credentialRequest))
		assert(!BrowserDownload.requestHasSensitiveCredentials(credentialRequest))
		credentialRequest.setValue("Basic dXNlcjpwYXNz", forHTTPHeaderField: "Proxy-Authorization")
		assert(BrowserDownload.requestMayCarryCredentials(credentialRequest))
		assert(BrowserDownload.requestHasSensitiveCredentials(credentialRequest))
		credentialRequest.setValue("session=private", forHTTPHeaderField: "Cookie")
		assert(BrowserDownload.requestMayCarryCredentials(credentialRequest))
		assert(BrowserDownload.requestHasSensitiveCredentials(credentialRequest))

		var semanticHeaderRequest = URLRequest(url: URL(string: "https://example.com/file.bin")!)
		semanticHeaderRequest.setValue("https://example.com/page", forHTTPHeaderField: "Referer")
		assert(BrowserDownload.requestMayCarryCredentials(semanticHeaderRequest))
		assert(!BrowserDownload.requestHasSensitiveCredentials(semanticHeaderRequest))
		semanticHeaderRequest = URLRequest(url: URL(string: "https://example.com/file.bin")!)
		semanticHeaderRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
		assert(BrowserDownload.requestMayCarryCredentials(semanticHeaderRequest))
		assert(!BrowserDownload.requestHasSensitiveCredentials(semanticHeaderRequest))
		semanticHeaderRequest = URLRequest(url: URL(string: "https://example.com/file.bin")!)
		semanticHeaderRequest.setValue("signed-value", forHTTPHeaderField: "X-Download-Signature")
		assert(BrowserDownload.requestMayCarryCredentials(semanticHeaderRequest))
		assert(!BrowserDownload.requestHasSensitiveCredentials(semanticHeaderRequest))

		var bodyRequest = URLRequest(url: URL(string: "https://example.com")!)
		bodyRequest.httpBody = Data([1])
		assert(BrowserDownload.requestHasBody(bodyRequest))
		var streamedBodyRequest = URLRequest(url: URL(string: "https://example.com")!)
		streamedBodyRequest.httpBodyStream = InputStream(data: Data([1]))
		assert(BrowserDownload.requestHasBody(streamedBodyRequest))

		var cancellingDownload = projectedDownload
		cancellingDownload.status = .paused
		cancellingDownload.resumeData = Data([1])
		assert(cancellingDownload.canResume)
		cancellingDownload.markCancellationPending()
		assert(!cancellingDownload.canResume)

		projectedDownload.status = .downloading
		let finish = projectedDownload.estimatedFinish!
		assert(abs(finish.timeIntervalSinceNow - 61) < 1)
		projectedDownload.estimatedTimeRemaining = .infinity
		assert(projectedDownload.estimatedFinish == nil)
		projectedDownload.estimatedTimeRemaining = nil
		projectedDownload.status = .paused
		projectedDownload.resumeData = nil
		projectedDownload.segments = BrowserDownloadSegment.plan(total: 512 * 1024 * 1024)
		assert(projectedDownload.segments?.count == 16)
		assert(projectedDownload.canResume)
		assert(BrowserDownloadSegment.plan(total: 32 * 1024 * 1024).isEmpty)
		assert(BrowserDownloadSegment.plan(total: 100 * 1024 * 1024).count == 2)
		let persisted = try JSONDecoder().decode(BrowserDownload.self, from: JSONEncoder().encode(projectedDownload))
		assert(persisted.status == .paused && persisted.canResume)
		projectedDownload.status = .cancelled
		projectedDownload.requestHasAuthorization = false
		assert(projectedDownload.canRetry)
		assert(!projectedDownload.canResume)
		assert(projectedDownload.statusSummary.hasPrefix("Cancelled"))
		let cancelled = try JSONDecoder().decode(BrowserDownload.self, from: JSONEncoder().encode(projectedDownload))
		assert(cancelled.status == .cancelled && cancelled.canRetry)

		let longName = String(repeating: "🧭", count: 300) + ".pdf"
		let boundedName = BrowserDownload.safeFilename(longName)
		assert(boundedName.utf8.count <= 180)
		assert(boundedName.hasSuffix(".pdf"))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("astra-download-check-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let first = directory.appendingPathComponent("report.pdf")
		try Data([1]).write(to: first)
		let second = BrowserDownload.collisionFreeURL(fileName: "report.pdf", in: directory)
		assert(second.lastPathComponent == "report (2).pdf")
		try Data([2]).write(to: second)

		let third = BrowserDownload.collisionFreeURL(fileName: "report.pdf", in: directory)
		assert(third.lastPathComponent == "report (3).pdf")

		let reserved = BrowserDownload.collisionFreeURL(fileName: "report.pdf", in: directory, reserved: [third])
		assert(reserved.lastPathComponent == "report (4).pdf")

		let original = BrowserDownload(
			id: UUID(),
			createdAt: .now,
			sourceURL: URL(string: "https://example.com"),
			requestURL: URL(string: "https://example.com/report.pdf"),
			originalName: "report.pdf",
			fileURL: first,
			status: .paused,
			progress: 0.25,
			renamedByAppleIntelligence: false,
			resumeData: nil,
			errorMessage: nil
		)
		var legacyRecord = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
		for key in ["retryURL", "destinationURL", "destinationIsFileScoped", "requestHasBody", "requestHasAuthorization", "receivedBytes", "throughput", "estimatedTimeRemaining", "folderBookmark", "fileAccessBookmark"] {
			legacyRecord[key] = nil
		}
		let legacyData = try JSONSerialization.data(withJSONObject: legacyRecord)
		let restored = try JSONDecoder().decode(BrowserDownload.self, from: legacyData)
		assert(restored.id == original.id)
		assert(restored.fileURL == original.fileURL)
		assert(restored.progress == original.progress)
		assert(restored.destinationURL == nil)
		assert(restored.folderBookmark == nil)

		#if os(macOS)
			let quarantinedSource = directory.appendingPathComponent("stage.bin")
			let quarantinedCopy = directory.appendingPathComponent("final.bin")
			try Data([3, 4, 5]).write(to: quarantinedSource)
			try BrowserDownloadedFile.quarantine(
				quarantinedSource,
				downloadURL: URL(string: "https://example.com/file.bin"),
				sourceURL: URL(string: "https://example.com")
			)
			try FileManager.default.copyItem(at: quarantinedSource, to: quarantinedCopy)
			try BrowserDownloadedFile.quarantine(
				quarantinedCopy,
				downloadURL: URL(string: "https://example.com/file.bin"),
				sourceURL: URL(string: "https://example.com")
			)
			var quarantineProperties: AnyObject?
			try (quarantinedCopy as NSURL).getResourceValue(&quarantineProperties, forKey: .quarantinePropertiesKey)
			assert(quarantineProperties is [String: Any])
		#endif
	}
}
