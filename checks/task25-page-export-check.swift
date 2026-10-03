import Foundation

@main
struct Task25PageExportCheck {
	static func main() throws {
		let pageURL = URL(string: "https://example.test/page")!
		assert(BrowserPageExportPolicy.ownsDocument(
			capturedGeneration: 4,
			currentGeneration: 4,
			capturedURL: pageURL,
			currentURL: pageURL,
			ownsWebView: true,
			ownsWindow: true,
			isCommitted: true,
			isLoading: false
		))
		assert(!BrowserPageExportPolicy.ownsDocument(
			capturedGeneration: 4,
			currentGeneration: 5,
			capturedURL: pageURL,
			currentURL: pageURL,
			ownsWebView: true,
			ownsWindow: true,
			isCommitted: true,
			isLoading: false
		))
		assert(!BrowserPageExportPolicy.ownsDocument(
			capturedGeneration: 4,
			currentGeneration: 4,
			capturedURL: pageURL,
			currentURL: URL(string: "https://example.test/other"),
			ownsWebView: true,
			ownsWindow: true,
			isCommitted: true,
			isLoading: false
		))
		assert(!BrowserPageExportPolicy.ownsDocument(
			capturedGeneration: 4,
			currentGeneration: 4,
			capturedURL: pageURL,
			currentURL: pageURL,
			ownsWebView: false,
			ownsWindow: true,
			isCommitted: true,
			isLoading: false
		))

		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let destination = directory.appendingPathComponent("page.pdf")
		let original = Data("first export".utf8)
		try BrowserPageExportPolicy.writeExclusively(original, to: destination)
		let saved = try Data(contentsOf: destination)
		assert(saved == original)
		do {
			try BrowserPageExportPolicy.writeExclusively(Data("replacement".utf8), to: destination)
			assertionFailure("An existing export destination must be preserved")
		} catch {
			let preserved = try Data(contentsOf: destination)
			assert(preserved == original)
		}
		print("Task 25 page export policy checks passed")
	}
}
