import Foundation

enum BrowserAddress {
	nonisolated static func externalApplicationScheme(for url: URL) -> String? {
		BrowserNavigationPolicy.externalApplicationScheme(for: url)
	}

	nonisolated static func withoutCredentials(_ url: URL) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return url
		}
		components.user = nil
		components.password = nil
		return components.url ?? url
	}

	static func destination(
		for input: String,
		configuration: BrowserSearchConfiguration = .default,
		isPrivate: Bool = false
	) -> URL? {
		let text = unwrapped(input)
		guard !text.isEmpty else {
			return nil
		}

		if let components = URLComponents(string: text),
		   let scheme = components.scheme?.lowercased()
		{
			if ["http", "https"].contains(scheme) {
				guard !text.contains(where: \.isWhitespace),
				      let host = components.host, !host.isEmpty,
				      !host.contains(where: \.isWhitespace),
				      components.user == nil, components.password == nil,
				      validPort(components.port)
				else {
					return nil
				}
				return components.url
			}

			if hasScheme(text), !hasAmbiguousHostPort(text) {
				guard let url = components.url else {
					return nil
				}
				return externalApplicationScheme(for: url) == nil ? nil : url
			}
		}

		if !text.contains(where: \.isWhitespace),
		   let components = URLComponents(string: "https://" + text),
		   let host = components.host,
		   host.contains(".") || host.lowercased() == "localhost" || isIPAddress(host),
		   validHost(host),
		   components.user == nil,
		   components.password == nil,
		   validPort(components.port),
		   let url = components.url
		{
			return url
		}

		return configuration.destination(for: text, isPrivate: isPrivate)
	}

	static func displayString(
		for url: URL?,
		style: AddressDisplayStyle,
		isEditing: Bool,
		configuration: BrowserSearchConfiguration = .default,
		isPrivate: Bool = false
	) -> String {
		guard let originalURL = url else {
			return ""
		}
		let url = withoutCredentials(originalURL)
		if isEditing || style == .full {
			return url.absoluteString
		}
		if style == .dimmed,
		   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		   let query = configuration.query(for: url, isPrivate: isPrivate),
		   let range = searchQueryValueRange(
		   	in: url.absoluteString,
		   	components: components,
		   	parameterName: configuration.queryParameterName(for: url)
		   )
		{
			return displayText(String(url.absoluteString[..<range.lowerBound]))
				+ query
				+ displayText(String(url.absoluteString[range.upperBound...]))
		}
		if style == .dimmed {
			return displayText(url.absoluteString)
		}
		if let query = configuration.query(for: url, isPrivate: isPrivate) {
			return query
		}
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let host = hostWithoutWWW(for: components)
		else {
			return displayText(url.absoluteString)
		}
		return displayText(host + components.percentEncodedPath)
	}

	static func primaryTextRanges(
		for url: URL?,
		displayedText: String,
		configuration: BrowserSearchConfiguration = .default,
		isPrivate: Bool = false
	) -> [Range<String.Index>] {
		guard let originalURL = url else {
			return []
		}
		let url = withoutCredentials(originalURL)
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      components.string == url.absoluteString,
		      let hostRange = components.rangeOfHost
		else {
			return []
		}
		let text = url.absoluteString
		if let query = configuration.query(for: url, isPrivate: isPrivate) {
			if displayedText == query {
				return [displayedText.startIndex ..< displayedText.endIndex]
			}
			guard let range = searchQueryValueRange(
				in: text,
				components: components,
				parameterName: configuration.queryParameterName(for: url)
			) else {
				return []
			}
			if displayedText == text {
				return [range]
			}
			let decodedDisplay = displayText(String(text[..<range.lowerBound]))
				+ query
				+ displayText(String(text[range.upperBound...]))
			guard displayedText == decodedDisplay else {
				return []
			}
			let startOffset = displayText(String(text[..<range.lowerBound])).utf16.count
			let endOffset = startOffset + query.utf16.count
			guard endOffset <= displayedText.utf16.count else { return [] }
			let start = String.Index(utf16Offset: startOffset, in: displayedText)
			let end = String.Index(utf16Offset: endOffset, in: displayedText)
			return [start ..< end]
		}
		guard components.string == text,
		      displayText(text) == displayedText
		else {
			return []
		}
		let host = text[hostRange]
		let visibleHostStart = host.lowercased().hasPrefix("www.")
			? text.index(hostRange.lowerBound, offsetBy: 4)
			: hostRange.lowerBound
		guard let visibleHostRange = transformedRange(
			for: visibleHostStart ..< hostRange.upperBound,
			in: text,
			as: displayedText
		) else {
			return []
		}
		var ranges = [visibleHostRange]
		if let pathRange = components.rangeOfPath, !pathRange.isEmpty {
			let pathEnd = text[pathRange].last == "/" ? text.index(before: pathRange.upperBound) : pathRange.upperBound
			if pathRange.lowerBound < pathEnd {
				if let displayedPathRange = transformedRange(
					for: pathRange.lowerBound ..< pathEnd,
					in: text,
					as: displayedText
				) {
					ranges.append(displayedPathRange)
				}
			}
		}
		return ranges
	}

	private static func displayText(_ text: String) -> String {
		text.replacingOccurrences(of: "%20", with: " ")
	}

	private static func transformedRange(
		for range: Range<String.Index>,
		in original: String,
		as displayed: String
	) -> Range<String.Index>? {
		let startOffset = displayText(String(original[..<range.lowerBound])).utf16.count
		let endOffset = displayText(String(original[..<range.upperBound])).utf16.count
		guard endOffset <= displayed.utf16.count else {
			return nil
		}
		let start = String.Index(utf16Offset: startOffset, in: displayed)
		let end = String.Index(utf16Offset: endOffset, in: displayed)
		return start <= end ? start ..< end : nil
	}

	static func isSearchURL(
		_ url: URL?,
		configuration: BrowserSearchConfiguration = .default,
		isPrivate: Bool = false
	) -> Bool {
		guard let url else {
			return false
		}
		return configuration.query(for: url, isPrivate: isPrivate) != nil
	}

	private static func searchQueryValueRange(
		in text: String,
		components: URLComponents,
		parameterName: String?
	) -> Range<String.Index>? {
		guard let parameterName,
		      let queryRange = components.rangeOfQuery,
		      let items = components.percentEncodedQueryItems
		else {
			return nil
		}
		let query = text[queryRange]
		var itemStart = query.startIndex
		for item in items {
			let itemEnd = query[itemStart...].firstIndex(of: "&") ?? query.endIndex
			let itemRange = itemStart ..< itemEnd
			let decodedName = item.name.removingPercentEncoding ?? item.name
			if decodedName == parameterName, item.value != nil,
			   let equals = query[itemRange].firstIndex(of: "=")
			{
				return query.index(after: equals) ..< itemEnd
			}
			guard itemEnd < query.endIndex else {
				break
			}
			itemStart = query.index(after: itemEnd)
		}
		return nil
	}

	private static func unwrapped(_ input: String) -> String {
		var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
		if value.count >= 2,
		   let first = value.first, let last = value.last,
		   (first == "<" && last == ">") || (first == "'" && last == "'") || (first == "\"" && last == "\"")
		{
			value.removeFirst()
			value.removeLast()
			value = value.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return value
	}

	private static func hasScheme(_ value: String) -> Bool {
		value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
	}

	private static func validPort(_ port: Int?) -> Bool {
		guard let port else {
			return true
		}
		return (1 ... 65535).contains(port)
	}

	private static func hasAmbiguousHostPort(_ value: String) -> Bool {
		guard let colon = value.firstIndex(of: ":") else {
			return false
		}
		let authority = value[value.index(after: colon)...]
		guard !authority.hasPrefix("//") else {
			return false
		}
		let prefix = value[..<colon]
		return prefix.contains(".") || prefix.lowercased() == "localhost"
	}

	private static func validHost(_ host: String) -> Bool {
		guard !host.hasPrefix(".") else { return false }
		let labels = host.split(separator: ".")
		guard labels.count == 4, labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
			return true
		}
		return labels.allSatisfy { UInt8($0) != nil }
	}

	private static func isIPAddress(_ host: String) -> Bool {
		(host.contains(":")) || host.split(separator: ".").count == 4
	}

	private static func hostWithoutWWW(for components: URLComponents) -> String? {
		guard let host = components.host else {
			return nil
		}
		return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
	}
}
