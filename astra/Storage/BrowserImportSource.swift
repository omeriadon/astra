import Foundation

nonisolated enum BrowserImportSource: String, CaseIterable, Identifiable, Sendable {
	case chrome = "Chrome"
	case safari = "Safari"
	case edge = "Edge"
	case firefox = "Firefox"
	case arc = "Arc"
	case dia = "Dia"
	case brave = "Brave"
	case opera = "Opera"
	case vivaldi = "Vivaldi"
	case chromium = "Chromium"

	var id: String {
		rawValue
	}

	var libraryPath: String {
		switch self {
			case .chrome: "Application Support/Google/Chrome"
			case .safari: "Safari"
			case .edge: "Application Support/Microsoft Edge"
			case .firefox: "Application Support/Firefox/Profiles"
			case .arc: "Application Support/Arc/User Data"
			case .dia: "Application Support/Dia/User Data"
			case .brave: "Application Support/BraveSoftware/Brave-Browser"
			case .opera: "Application Support/com.operasoftware.Opera"
			case .vivaldi: "Application Support/Vivaldi"
			case .chromium: "Application Support/Chromium"
		}
	}

	var folderHint: String {
		switch self {
			case .safari: "Choose the Safari folder containing Bookmarks.plist and History.db. macOS may require Full Disk Access to read Safari data."
			case .firefox: "Choose a Firefox profile folder containing places.sqlite."
			case .arc: "Choose Arc’s Application Support folder to include pinned tabs, favorites, spaces and folders from StorableSidebar.json."
			default: "Choose a profile folder containing Bookmarks and History, or the browser’s data folder to select a profile."
		}
	}
}

nonisolated struct BrowserImportProfile: Identifiable, Hashable, Sendable {
	let source: BrowserImportSource
	let directory: URL
	let name: String
	let sidebar: URL?

	var id: URL {
		directory
	}
}

nonisolated enum BrowserImportScope: String, Sendable {
	case all
	case bookmarks
	case history

	var includesBookmarks: Bool {
		self != .history
	}

	var includesHistory: Bool {
		self != .bookmarks
	}

	func selecting(_ document: BrowserUserData) -> BrowserUserData {
		BrowserUserData(
			bookmarks: includesBookmarks ? document.bookmarks : [],
			history: includesHistory ? document.history : []
		)
	}
}
