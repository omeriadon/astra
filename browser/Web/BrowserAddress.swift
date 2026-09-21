import Foundation

enum BrowserAddress {
	static func destination(for input: String) -> URL? {
		let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return nil }

		if let components = URLComponents(string: text),
		   let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme)
		{
			guard !text.contains(where: \.isWhitespace),
			      let host = components.host, !host.isEmpty,
			      !host.contains(where: \.isWhitespace)
			else { return searchURL(for: text) }
			return components.url ?? searchURL(for: text)
		}

		if !text.contains(where: \.isWhitespace),
		   let components = URLComponents(string: "https://" + text),
		   let host = components.host,
		   host.contains(".") || host.lowercased() == "localhost",
		   !host.contains(where: \.isWhitespace),
		   let url = components.url
		{
			return url
		}

		return searchURL(for: text)
	}

	static func displayString(for url: URL?, style: AddressDisplayStyle, isEditing: Bool) -> String {
		guard let url else { return "" }
		guard style == .simple, !isEditing else {
			if style == .dimmed, !isEditing,
			   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			   let range = googleQueryValueRange(in: url.absoluteString, components: components),
			   let query = googleSearchQuery(for: url)
			{
				return url.absoluteString.replacingCharacters(in: range, with: query)
			}
			return url.absoluteString
		}
		if let query = googleSearchQuery(for: url) {
			return query
		}
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let host = hostWithoutWWW(for: components)
		else { return url.absoluteString }
		return host + components.percentEncodedPath
	}

	static func primaryTextRanges(for url: URL?, displayedText: String) -> [Range<String.Index>] {
		guard let url else { return [] }
		let text = url.absoluteString
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      components.string == text,
		      let hostRange = components.rangeOfHost
		else { return [] }

		if let query = googleSearchQuery(for: url) {
			if displayedText == query {
				return [displayedText.startIndex ..< displayedText.endIndex]
			}
			guard let range = googleQueryValueRange(in: text, components: components) else { return [] }
			let startOffset = text[..<range.lowerBound].utf16.count
			let start = String.Index(utf16Offset: startOffset, in: displayedText)
			let end = String.Index(utf16Offset: startOffset + query.utf16.count, in: displayedText)
			return [start ..< end]
		}

		guard components.string == displayedText else { return [] }
		let host = text[hostRange]
		let visibleHostStart = host.lowercased().hasPrefix("www.")
			? text.index(hostRange.lowerBound, offsetBy: 4)
			: hostRange.lowerBound
		var ranges = [visibleHostStart ..< hostRange.upperBound]
		if let pathRange = components.rangeOfPath, !pathRange.isEmpty {
			ranges.append(pathRange)
		}
		return ranges
	}

	static func isGoogleSearchURL(_ url: URL?) -> Bool {
		guard let url else { return false }
		return googleSearchQuery(for: url) != nil
	}

	private static func hostWithoutWWW(for components: URLComponents) -> String? {
		guard let host = components.host else { return nil }
		return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
	}

	private static func googleQueryValueRange(in text: String, components: URLComponents) -> Range<String.Index>? {
		guard let queryRange = components.rangeOfQuery,
		      let items = components.percentEncodedQueryItems
		else { return nil }

		let query = text[queryRange]
		var itemStart = query.startIndex
		for item in items {
			let itemEnd = query[itemStart...].firstIndex(of: "&") ?? query.endIndex
			let itemRange = itemStart ..< itemEnd
			let equals = query[itemRange].firstIndex(of: "=")
			if item.name == "q", item.value.flatMap(decodedQuery) != nil, let equals {
				return query.index(after: equals) ..< itemEnd
			}
			guard itemEnd < query.endIndex else { break }
			itemStart = query.index(after: itemEnd)
		}
		return nil
	}

	private static func googleSearchQuery(for url: URL) -> String? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let host = components.host?.lowercased(),
		      isGoogleHost(host),
		      components.path == "/search",
		      let items = components.percentEncodedQueryItems
		else { return nil }
		for item in items where item.name == "q" {
			if let query = item.value.flatMap(decodedQuery) {
				return query
			}
		}
		return nil
	}

	private nonisolated static func decodedQuery(_ value: String) -> String? {
		guard let query = value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
		      !query.isEmpty
		else { return nil }
		return query
	}

	private static func isGoogleHost(_ host: String) -> Bool {
		let labels = host.split(separator: ".")
		guard let googleIndex = labels.lastIndex(of: "google"), googleIndex + 1 < labels.count else { return false }
		let domainSuffix = labels[googleIndex...]
		let region = Array(domainSuffix.dropFirst())
		return region == ["com"]
			|| region.count == 1 && region[0].count == 2
			|| region.count == 2 && ["com", "co"].contains(region[0]) && region[1].count == 2
	}

	private static func searchURL(for query: String) -> URL? {
		var components = URLComponents(string: "https://www.google.com/search")
		components?.queryItems = [URLQueryItem(name: "q", value: query)]
		return components?.url
	}
}
