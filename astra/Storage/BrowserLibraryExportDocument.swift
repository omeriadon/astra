import SwiftUI
import UniformTypeIdentifiers

nonisolated struct BrowserLibraryExportDocument: FileDocument {
	static var readableContentTypes: [UTType] {
		[.html, .json]
	}

	var data: Data

	init(data: Data) {
		self.data = data
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		self.data = data
	}

	func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}
