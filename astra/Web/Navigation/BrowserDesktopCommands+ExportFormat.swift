#if os(macOS)
extension BrowserDesktopCommands.ExportFormat: Equatable {
	static func == (lhs: Self, rhs: Self) -> Bool {
		switch (lhs, rhs) {
			case (.pdf, .pdf), (.webArchive, .webArchive), (.source, .source): true
			default: false
		}
	}
}
#endif
