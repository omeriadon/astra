import Darwin
import Foundation

enum BrowserPageExportPolicy {
	static func ownsDocument(
		capturedGeneration: Int,
		currentGeneration: Int,
		capturedURL: URL,
		currentURL: URL?,
		ownsWebView: Bool,
		ownsWindow: Bool,
		isCommitted: Bool,
		isLoading: Bool
	) -> Bool {
		ownsWebView
			&& ownsWindow
			&& isCommitted
			&& !isLoading
			&& capturedGeneration == currentGeneration
			&& capturedURL == currentURL
	}

	static func writeExclusively(_ data: Data, to destination: URL) throws {
		let staging = destination.deletingLastPathComponent()
			.appendingPathComponent(".astra-export-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: staging) }
		try data.write(to: staging, options: .atomic)
		guard link(staging.path, destination.path) == 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
		}
	}
}
