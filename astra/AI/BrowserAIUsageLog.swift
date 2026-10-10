import Foundation
import Observation

@MainActor
@Observable
final class BrowserAIUsageLog {
	static let shared = BrowserAIUsageLog()
	private(set) var errorDescription: String?
	@ObservationIgnored private let writer = BrowserAIUsageLogWriter()

	func record(id: UUID, feature: String, provider: String, event: String, details: String) async {
		let line = "\(Date().ISO8601Format()) request=\(id.uuidString) feature=\(Self.field(feature)) provider=\(Self.field(provider)) event=\(Self.field(event)) \(Self.field(details))\n"
		do {
			try await writer.append(line)
			errorDescription = nil
		} catch {
			errorDescription = "The AI usage log could not be written. Check available disk space and folder permissions."
		}
	}

	func location() async -> URL? {
		do {
			let url = try await writer.location()
			errorDescription = nil
			return url
		} catch {
			errorDescription = "The AI usage log could not be opened. Check available disk space and folder permissions."
			return nil
		}
	}

	private nonisolated static func field(_ text: String) -> String {
		String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
	}
}

private actor BrowserAIUsageLogWriter {
	func location() throws -> URL {
		let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		let directory = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let url = directory.appendingPathComponent("ai-usage.log")
		if !FileManager.default.fileExists(atPath: url.path) {
			guard FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
				throw CocoaError(.fileWriteNoPermission)
			}
		}
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
		return url
	}

	func append(_ line: String) throws {
		let handle = try FileHandle(forWritingTo: location())
		defer { try? handle.close() }
		try handle.seekToEnd()
		try handle.write(contentsOf: Data(line.utf8))
	}
}
