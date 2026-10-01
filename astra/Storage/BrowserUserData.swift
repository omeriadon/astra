import Foundation

nonisolated struct BrowserUserData: Codable {
	var version = 1
	var bookmarks: [Bookmark]
	var history: [BrowserVisit]

	static func decode(_ data: Data, isHTML: Bool) throws -> Self {
		guard data.count <= 16 * 1024 * 1024 else { throw ImportError.tooLarge }
		if isHTML {
			guard let html = String(data: data, encoding: .utf8) else { throw ImportError.invalidFile }
			return try Self(bookmarks: decodeHTML(html), history: [])
		}
		let document = try JSONDecoder().decode(Self.self, from: data)
		guard document.version == 1,
		      document.bookmarks.count <= 100_000,
		      document.history.count <= 100_000 else { throw ImportError.invalidFile }
		return document
	}

	func encodedHTML() -> Data {
		let entries = bookmarks.map { bookmark in
			"    <DT><A HREF=\"\(Self.escape(bookmark.url.absoluteString))\">\(Self.escape(bookmark.name))</A>"
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
		let expression = try NSRegularExpression(
			pattern: #"<a\b[^>]*\bhref\s*=\s*(["'])(.*?)\1[^>]*>(.*?)</a>"#,
			options: [.caseInsensitive, .dotMatchesLineSeparators]
		)
		let source = html as NSString
		let matches = expression.matches(in: html, range: NSRange(location: 0, length: source.length))
		guard matches.count <= 100_000 else { throw ImportError.tooLarge }
		return matches.compactMap { match in
			let address = unescape(source.substring(with: match.range(at: 2)))
			guard let url = URL(string: address),
			      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
			let title = unescape(source.substring(with: match.range(at: 3))
				.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
			return Bookmark(name: title.isEmpty ? url.host ?? address : title, url: url)
		}
	}

	private static func escape(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}

	private static func unescape(_ text: String) -> String {
		text.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#39;", with: "'")
			.replacingOccurrences(of: "&apos;", with: "'")
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: "&amp;", with: "&")
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
