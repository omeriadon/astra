import Foundation

nonisolated struct BrowserUserData: Codable, Sendable {
	var version = 1
	var bookmarks: [Bookmark]
	var history: [BrowserVisit]
	var readingList: [ReadingListItem] = []

	private enum CodingKeys: String, CodingKey {
		case version, bookmarks, history, readingList
	}

	init(version: Int = 1, bookmarks: [Bookmark], history: [BrowserVisit], readingList: [ReadingListItem] = []) {
		self.version = version
		self.bookmarks = bookmarks
		self.history = history
		self.readingList = readingList
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		version = try values.decode(Int.self, forKey: .version)
		bookmarks = try values.decode([Bookmark].self, forKey: .bookmarks)
		history = try values.decode([BrowserVisit].self, forKey: .history)
		readingList = try values.decodeIfPresent([ReadingListItem].self, forKey: .readingList) ?? []
	}

	static func decode(_ data: Data, isHTML: Bool) throws -> Self {
		guard data.count <= 16 * 1024 * 1024 else { throw ImportError.tooLarge }
		if isHTML {
			guard let html = String(data: data, encoding: .utf8) else { throw ImportError.invalidFile }
			return try Self(bookmarks: decodeHTML(html), history: [])
		}
		guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let rawHistory = root["history"] as? [[String: Any]],
		      rawHistory.count <= 100_000,
		      rawHistory.allSatisfy({ record in
		      	guard let address = record["url"] as? String,
		      	      let url = URL(string: address),
		      	      isPortableURL(url) else { return false }
		      	return true
		      }) else { throw ImportError.invalidFile }
		var document = try JSONDecoder().decode(Self.self, from: data)
		guard document.version == 1,
		      document.bookmarks.count <= 100_000,
		      document.history.count <= 100_000,
		      document.readingList.count <= 100_000,
		      Set(document.bookmarks.map(\.id)).count == document.bookmarks.count,
		      Set(document.history.map(\.id)).count == document.history.count,
		      Set(document.readingList.map(\.id)).count == document.readingList.count else { throw ImportError.invalidFile }
		guard document.bookmarks.allSatisfy({ bookmark in
			isPortableURL(bookmark.url)
				&& bookmark.name.utf8.count <= 16384
				&& bookmark.folder.utf8.count <= 4096
				&& (bookmark.order == Int.min || (0 ... 100_000).contains(bookmark.order))
				&& isSaneDate(bookmark.modifiedAt)
		}), document.readingList.allSatisfy({ item in
			isPortableURL(item.url)
				&& item.title.utf8.count <= 16384
				&& isSaneDate(item.addedAt)
				&& isSaneDate(item.modifiedAt)
		}), document.history.allSatisfy({ visit in
			isPortableURL(visit.url)
				&& visit.title.utf8.count <= 16384
				&& isSaneDate(visit.visitedAt)
				&& isSaneDate(visit.modifiedAt)
		}) else { throw ImportError.invalidFile }
		document.bookmarks = Bookmark.preservingLegacyOrder(document.bookmarks)
		return document
	}

	func encodedHTML() -> Data {
		let groups = Dictionary(grouping: bookmarks, by: \.folder)
		let entries = groups.keys.sorted().flatMap { folder in
			let items = (groups[folder] ?? []).sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
			let links = items.map { bookmark in
				"    <DT><A HREF=\"\(Self.escape(bookmark.url.absoluteString))\">\(Self.escape(bookmark.name))</A>"
			}
			return folder.isEmpty ? links : ["    <DT><H3>\(Self.escape(folder))</H3>", "    <DL><p>"] + links + ["    </DL><p>"]
		}
		let html = """
		<!DOCTYPE NETSCAPE-Bookmark-file-1>
		<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
		<TITLE>Bookmarks</TITLE>
		<H1>Bookmarks</H1>
		<DL><p>
		\(entries.joined(separator: "\n"))
		</DL><p>
		"""
		return Data(html.utf8)
	}

	private static func decodeHTML(_ html: String) throws -> [Bookmark] {
		// ponytail: quoted Netscape bookmark anchors; use a full HTML parser if other formats are required.
		let comments = try NSRegularExpression(pattern: #"<!--.*?-->"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
		let sanitized = comments.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "")
		let expression = try NSRegularExpression(
			pattern: #"<h3\b[^>]*>(.*?)</h3>|<a\b([^>]*)>(.*?)</a>|</?dl\b[^>]*>"#,
			options: [.caseInsensitive, .dotMatchesLineSeparators]
		)
		let source = sanitized as NSString
		let matches = expression.matches(in: sanitized, range: NSRange(location: 0, length: source.length))
		guard matches.count <= 400_000 else { throw ImportError.tooLarge }
		let anchorExpression = try NSRegularExpression(pattern: #"<a\b"#, options: .caseInsensitive)
		let anchorCount = anchorExpression.numberOfMatches(in: sanitized, range: NSRange(location: 0, length: source.length))
		guard anchorCount <= 100_000 else { throw ImportError.tooLarge }
		var folderStack: [String] = []
		var pendingFolder: String?
		var bookmarks: [Bookmark] = []
		let attributes = try NSRegularExpression(pattern: #"\bhref\s*=\s*(["'])(.*?)\1"#, options: .caseInsensitive)
		for match in matches {
			let token = source.substring(with: match.range)
			let lower = token.lowercased()
			if lower.hasPrefix("<h3") {
				let titleRange = match.range(at: 1)
				let title = unescape(source.substring(with: titleRange).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
				guard title.utf8.count <= 4096 else { throw ImportError.tooLarge }
				pendingFolder = title
			} else if lower.hasPrefix("</dl") {
				if !folderStack.isEmpty {
					folderStack.removeLast()
				}
				pendingFolder = nil
			} else if lower.hasPrefix("<dl") {
				folderStack.append(pendingFolder ?? "")
				pendingFolder = nil
			} else {
				let header = source.substring(with: match.range(at: 2))
				let headerRange = NSRange(location: 0, length: (header as NSString).length)
				guard let href = attributes.firstMatch(in: header, range: headerRange) else { throw ImportError.invalidFile }
				let address = unescape((header as NSString).substring(with: href.range(at: 2)))
				guard let url = URL(string: address), isPortableURL(url) else { throw ImportError.invalidFile }
				let title = unescape(source.substring(with: match.range(at: 3)).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
				guard title.utf8.count <= 16384 else { throw ImportError.tooLarge }
				let folder = folderStack.filter { !$0.isEmpty }.joined(separator: "/")
				bookmarks.append(Bookmark(name: title.isEmpty ? url.host ?? address : title, url: url, folder: folder, order: bookmarks.count))
				guard bookmarks.count <= 100_000 else { throw ImportError.tooLarge }
			}
		}
		let hasNetscapeHeader = html.range(of: "<!DOCTYPE NETSCAPE-Bookmark-file-1", options: .caseInsensitive) != nil
		let hasBookmarkList = html.range(of: "<DL", options: .caseInsensitive) != nil
			&& html.range(of: "</DL", options: .caseInsensitive) != nil
		guard bookmarks.count == anchorCount,
		      !bookmarks.isEmpty || (hasNetscapeHeader && hasBookmarkList) else { throw ImportError.invalidFile }
		return bookmarks
	}

	private static func isPortableURL(_ url: URL) -> Bool {
		guard url.absoluteString.utf8.count <= 16384,
		      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
		      let host = components.host, !host.isEmpty,
		      components.user == nil, components.password == nil,
		      components.port.map({ (1 ... 65535).contains($0) }) ?? true,
		      !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) })
		else { return false }
		return true
	}

	private static func escape(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}

	private static func unescape(_ text: String) -> String {
		guard let expression = try? NSRegularExpression(pattern: #"&(amp|quot|apos|lt|gt|nbsp|#\d+|#x[0-9a-f]+);"#, options: .caseInsensitive) else { return text }
		let mutable = NSMutableString(string: text)
		let matches = expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
		for match in matches.reversed() {
			let token = (text as NSString).substring(with: match.range).lowercased()
			let entity = (text as NSString).substring(with: match.range(at: 1)).lowercased()
			let replacement: String
			switch entity {
				case "amp": replacement = "&"
				case "quot": replacement = "\""
				case "apos", "#39": replacement = "'"
				case "lt": replacement = "<"
				case "gt": replacement = ">"
				case "nbsp": replacement = "\u{00a0}"
				case let numeric where numeric.hasPrefix("#x"):
					let value = UInt32(numeric.dropFirst(2), radix: 16)
					replacement = value.flatMap(UnicodeScalar.init).map(String.init) ?? token
				case let numeric where numeric.hasPrefix("#"):
					let value = UInt32(numeric.dropFirst())
					replacement = value.flatMap(UnicodeScalar.init).map(String.init) ?? token
				default: replacement = token
			}
			mutable.replaceCharacters(in: match.range, with: replacement)
		}
		return mutable as String
	}

	private static func isSaneDate(_ date: Date) -> Bool {
		date == .distantPast || (date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 >= -2_208_988_800 && date <= Date.now.addingTimeInterval(300.001))
	}

	enum ImportError: LocalizedError {
		case tooLarge
		case invalidFile

		var errorDescription: String? {
			switch self {
				case .tooLarge: "This browsing-data file is too large."
				case .invalidFile: "This file is not a supported browsing-data export."
			}
		}
	}
}
