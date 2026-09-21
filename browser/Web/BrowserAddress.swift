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
		guard style == .simple, !isEditing else { return url.absoluteString }
		if let query = googleSearchQuery(for: url) {
			return query
		}
		return hostWithoutWWW(for: url) ?? url.absoluteString
	}

	static func primaryTextRanges(for url: URL?) -> [Range<String.Index>] {
		guard let url else { return [] }
		let text = url.absoluteString
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let host = components.host,
		      let schemeEnd = text.range(of: "://")?.upperBound
		else { return [] }

		let authorityEnd = text[schemeEnd...].firstIndex(where: { "/?#".contains($0) }) ?? text.endIndex
		var ranges: [Range<String.Index>] = []
		if let hostRange = text.range(of: host, options: .caseInsensitive, range: schemeEnd ..< authorityEnd) {
			ranges.append(hostRange)
		}
		let pathEnd = text[authorityEnd...].firstIndex(where: { "?#".contains($0) }) ?? text.endIndex
		if authorityEnd < pathEnd {
			ranges.append(authorityEnd ..< pathEnd)
		}
		return ranges
	}

	private static func hostWithoutWWW(for url: URL) -> String? {
		guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host else { return nil }
		return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
	}

	private static func googleSearchQuery(for url: URL) -> String? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let host = components.host?.lowercased(),
		      isGoogleHost(host),
		      components.path == "/search",
		      let encodedQuery = components.percentEncodedQueryItems?.first(where: { $0.name == "q" })?.value,
		      let query = encodedQuery.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
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
