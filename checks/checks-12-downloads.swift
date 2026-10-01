import Foundation

@main
struct Checks {
	static func main() throws {
		let traversal = BrowserDownload.safeFilename("../../folder/escape:name?.pdf")
		assert(!traversal.contains("/"))
		assert(!traversal.contains(":"))
		assert(!traversal.contains("?"))
		assert(traversal.hasSuffix(".pdf"))

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
		for key in ["retryURL", "destinationURL", "destinationIsFileScoped", "requestHasBody", "requestHasAuthorization", "receivedBytes", "folderBookmark", "fileAccessBookmark"] {
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
