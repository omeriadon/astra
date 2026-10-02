import Foundation

@main
struct Task25DownloadDragCheck {
	static func main() throws {
		let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: sourceDirectory) }
		let source = sourceDirectory.appendingPathComponent("completed archive.zip")
		let contents = Data("completed download bytes".utf8)
		try contents.write(to: source)

		let transferDirectory: URL
		do {
			let transfer = BrowserDownloadDragFile()
			let result = try transfer.copy(source, named: source.lastPathComponent, bookmark: nil)
			let copy = result.fileURL
			assert(copy.lastPathComponent == source.lastPathComponent)
			let copiedContents = try Data(contentsOf: copy)
			assert(copiedContents == contents)
			transferDirectory = copy.deletingLastPathComponent()
		}
		assert(!FileManager.default.fileExists(atPath: transferDirectory.path))
		print("Task 25 download drag checks passed")
	}
}
