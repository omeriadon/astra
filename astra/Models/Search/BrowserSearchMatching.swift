import Foundation

enum BrowserSearchMatching {
	static func shouldExpandAddressOnFocus(text: String, simpleAddress: String) -> Bool {
		text == simpleAddress
	}

	static func pastedHTTPURL(_ input: String) -> URL? {
		var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
		if value.count > 2,
		   let first = value.first, let last = value.last,
		   (first == "<" && last == ">") || (first == "'" && last == "'") || (first == "\"" && last == "\"")
		{
			value.removeFirst()
			value.removeLast()
			value = value.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		guard value.utf8.count <= 16384,
		      !value.unicodeScalars.contains(where: {
		      	CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
		      })
		else { return nil }
		let hasHTTPScheme = value.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil
		guard let components = URLComponents(string: hasHTTPScheme ? value : "https://\(value)"),
		      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
		      let host = components.host, !host.isEmpty,
		      components.user == nil, components.password == nil,
		      components.port.map({ (1 ... 65535).contains($0) }) ?? true,
		      let url = components.url
		else { return nil }
		let authorityStart = value.range(of: "://")?.upperBound ?? value.startIndex
		let authority = value[authorityStart...].prefix { !"/?#".contains($0) }
		guard validPastedAuthority(String(authority), port: components.port),
		      !host.unicodeScalars.contains(where: {
		      	CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)
		      })
		else { return nil }
		if !hasHTTPScheme {
			let hostInput = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
			guard host.contains(".") || host.lowercased() == "localhost" || hostInput.hasPrefix("[") else {
				return nil
			}
		}
		return url
	}

	private static func validPastedAuthority(_ authority: String, port: Int?) -> Bool {
		guard !authority.contains("@") else { return false }
		if authority.hasPrefix("[") {
			guard let closingBracket = authority.firstIndex(of: "]") else { return false }
			let suffix = authority[authority.index(after: closingBracket)...]
			if suffix.isEmpty {
				return port == nil
			}
			guard suffix.first == ":" else { return false }
			let value = suffix.dropFirst()
			return !value.isEmpty && value.utf8.allSatisfy { (48 ... 57).contains($0) } && port != nil
		}
		guard let colon = authority.firstIndex(of: ":") else { return port == nil }
		let value = authority[authority.index(after: colon)...]
		guard !value.isEmpty,
		      value.utf8.allSatisfy({ (48 ... 57).contains($0) }),
		      authority[..<colon].firstIndex(of: ":") == nil
		else { return false }
		return port != nil
	}

	static func openSearchTemplate(from data: Data) -> String? {
		guard data.count <= 65536,
		      let xml = String(data: data, encoding: .utf8)
		else { return nil }
		let declarations = xml.uppercased()
		guard !declarations.contains("<!DOCTYPE"), !declarations.contains("<!ENTITY") else { return nil }
		let parser = XMLParser(data: data)
		let delegate = OpenSearchTemplateParser()
		parser.delegate = delegate
		parser.shouldProcessNamespaces = true
		parser.externalEntityResolvingPolicy = .never
		guard parser.parse(), delegate.isOpenSearchDocument,
		      let template = delegate.template
		else { return nil }
		var configuration = BrowserSearchConfiguration.default
		configuration.customTemplate = template
		let remaining = template.replacingOccurrences(of: "{query}", with: "")
		guard !remaining.contains("{"), !remaining.contains("}") else { return nil }
		return configuration.customTemplateIsValid ? template : nil
	}

	nonisolated static func normalized(_ text: String) -> String {
		text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Exact > prefix > words > substring > typo/abbreviation.
	nonisolated static func score(_ query: String, in text: String) -> Double {
		score(normalizedQuery: normalized(query), in: text)
	}

	/// The caller can normalize once for an entire search across hundreds of
	/// candidate titles and URLs rather than repeating it for every candidate.
	nonisolated static func score(normalizedQuery query: String, in text: String) -> Double {
		let text = normalized(text)
		guard !query.isEmpty, !text.isEmpty else { return 0 }
		if query == text {
			return 1
		}
		if text.hasPrefix(query) {
			return 0.92
		}
		if text.contains(query) {
			return 0.78
		}
		let queryWords = query.split(whereSeparator: \.isWhitespace).map(String.init)
		let textWords = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
		let scores = queryWords.map { word in
			textWords.map { wordScore(word, in: $0) }.max() ?? 0
		}
		guard scores.allSatisfy({ $0 > 0 }) else { return 0 }
		return scores.reduce(0, +) / Double(scores.count)
	}

	private nonisolated static func wordScore(_ query: String, in word: String) -> Double {
		if query == word {
			return 0.9
		}
		if word.hasPrefix(query) {
			return 0.85
		}
		if word.contains(query) {
			return 0.72
		}
		// ponytail: one-edit typos and compact abbreviations; broaden tolerance if real queries require it.
		if query.count >= 4, abs(query.count - word.count) <= 1,
		   editDistance(query, word) <= 1
		{
			return 0.62
		}
		guard query.count >= 3, Double(query.count) / Double(word.count) >= 0.5 else { return 0 }
		var remaining = query[...]
		for character in word where remaining.first == character {
			remaining = remaining.dropFirst()
		}
		return remaining.isEmpty ? 0.5 : 0
	}

	private nonisolated static func editDistance(_ lhs: String, _ rhs: String) -> Int {
		let lhs = Array(lhs)
		let rhs = Array(rhs)
		var previousPrevious: [Int] = []
		var previous = Array(0 ... rhs.count)
		for (row, character) in lhs.enumerated() {
			var current = [row + 1]
			for (column, other) in rhs.enumerated() {
				current.append(min(
					current[column] + 1,
					previous[column + 1] + 1,
					previous[column] + (character == other ? 0 : 1)
				))
				if row > 0, column > 0,
				   character == rhs[column - 1], lhs[row - 1] == other
				{
					current[column + 1] = min(current[column + 1], previousPrevious[column - 1] + 1)
				}
			}
			previousPrevious = previous
			previous = current
		}
		return previous[rhs.count]
	}
}

private final class OpenSearchTemplateParser: NSObject, XMLParserDelegate {
	var template: String?
	private(set) var isOpenSearchDocument = false
	private var sawRoot = false

	func parser(
		_: XMLParser,
		didStartElement elementName: String,
		namespaceURI _: String?,
		qualifiedName _: String?,
		attributes: [String: String] = [:]
	) {
		if !sawRoot {
			sawRoot = true
			isOpenSearchDocument = elementName == "OpenSearchDescription"
		}
		guard isOpenSearchDocument else { return }
		let method = attributes["method"]?.lowercased()
		let type = attributes["type"]?.lowercased().split(separator: ";", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
		guard template == nil, elementName == "Url",
		      method == nil || method == "get",
		      ["text/html", "application/xhtml+xml"].contains(type ?? ""),
		      let value = attributes["template"], value.utf8.count <= 2048,
		      value.components(separatedBy: "{searchTerms}").count == 2
		else { return }
		template = value.replacingOccurrences(of: "{searchTerms}", with: "{query}")
	}
}
