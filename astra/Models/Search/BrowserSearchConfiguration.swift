import Foundation

struct BrowserSearchConfiguration: Codable, Equatable, Hashable {
	enum Engine: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
		case google
		case duckDuckGo
		case bing
		case custom

		var id: String { rawValue }

		var title: String {
			switch self {
				case .google: "Google"
				case .duckDuckGo: "DuckDuckGo"
				case .bing: "Bing"
				case .custom: "Custom"
			}
		}
	}

	var normalEngine: Engine = .google
	var privateEngine: Engine = .google
	var customTemplate = "https://www.google.com/search?q={query}"
	var keywordShortcuts = ""
	var privateSuggestionsEnabled = false

	static let `default` = Self()

	var customTemplateIsValid: Bool {
		Self.isValidTemplate(customTemplate)
	}

	static func decode(_ value: String) -> Self {
		guard value.utf8.count <= 8_192,
		      let data = value.data(using: .utf8),
		      let configuration = try? JSONDecoder().decode(Self.self, from: data)
		else {
			return Self(
				normalEngine: .custom,
				privateEngine: .custom,
				customTemplate: "",
				keywordShortcuts: "",
				privateSuggestionsEnabled: false
			)
		}
		return configuration
	}

	var encoded: String {
		guard let data = try? JSONEncoder().encode(self),
		      let value = String(data: data, encoding: .utf8)
		else { return "{}" }
		return value
	}

	func engine(isPrivate: Bool) -> Engine {
		isPrivate ? privateEngine : normalEngine
	}

	func searchURL(for query: String, isPrivate: Bool = false) -> URL? {
		let selectedEngine = engine(isPrivate: isPrivate)
		let template = selectedEngine == .custom ? customTemplate : selectedEngine.template
		return Self.url(for: query, template: template)
	}

	func destination(for input: String, isPrivate: Bool = false) -> URL? {
		let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
		if let shortcut = shortcutDestination(for: query) {
			return shortcut
		}
		return searchURL(for: query, isPrivate: isPrivate)
	}

	func query(for url: URL, isPrivate _: Bool = false) -> String? {
		matchingQuery(in: url)?.value
	}

	func queryParameterName(for url: URL) -> String? {
		matchingQuery(in: url)?.name
	}

	private func matchingQuery(in url: URL) -> (name: String, value: String)? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      components.user == nil, components.password == nil
		else { return nil }
		if Self.isGoogleRegionalSearch(components),
		   let item = components.percentEncodedQueryItems?.first(where: { $0.name == "q" }),
		   let encodedValue = item.value,
		   let value = encodedValue.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
		   !value.isEmpty
		{
			return ("q", value)
		}
		for template in searchTemplates where Self.isValidTemplate(template) {
			guard let expected = Self.templateComponents(template),
			      components.scheme?.lowercased() == expected.scheme?.lowercased(),
			      components.host?.lowercased() == expected.host?.lowercased(),
			      components.port == expected.port,
			      components.path == expected.path,
			      let expectedItems = expected.queryItems,
			      let actualItems = components.queryItems,
			      let encodedItems = components.percentEncodedQueryItems,
			      let marker = expectedItems.first(where: { $0.value == Self.marker })?.name,
			      let encodedValue = encodedItems.first(where: { $0.name == marker })?.value,
			      let value = encodedValue.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
			      !value.isEmpty
			else { continue }
			let staticItems = expectedItems.filter { $0.name != marker }
			guard staticItems.allSatisfy({ expectedItem in
				actualItems.contains(URLQueryItem(name: expectedItem.name, value: expectedItem.value))
			}) else { continue }
			return (marker, value)
		}
		return nil
	}

	private static func isGoogleRegionalSearch(_ components: URLComponents) -> Bool {
		guard components.scheme?.lowercased() == "https",
		      components.path == "/search",
		      components.port == nil,
		      let host = components.host?.lowercased(),
		      let query = components.queryItems?.first(where: { $0.name == "q" })?.value,
		      !query.isEmpty
		else { return false }
		let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
		let labels = normalizedHost.split(separator: ".")
		guard labels.first == "google" else { return false }
		let region = Array(labels.dropFirst())
		return region == ["com"]
			|| region.count == 1 && region[0].count == 2
			|| region.count == 2 && ["com", "co"].contains(region[0]) && region[1].count == 2
	}

	func searchLabel(for input: String, isPrivate: Bool) -> String {
		if let shortcutURL = shortcutDestination(for: input),
		   let host = shortcutURL.host
		{
			return "Search \(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)"
		}
		return "Search \(engine(isPrivate: isPrivate).title)"
	}

	func suggestionsProvider(isPrivate: Bool) -> Engine? {
		if isPrivate, !privateSuggestionsEnabled { return nil }
		let selected = engine(isPrivate: isPrivate)
		return selected == .google || selected == .duckDuckGo ? selected : nil
	}

	private var searchTemplates: [String] {
		var templates = [Engine.google.template, Engine.duckDuckGo.template, Engine.bing.template, customTemplate]
		guard keywordShortcuts.utf8.count <= 4_096 else { return templates }
		for line in keywordShortcuts.split(whereSeparator: \.isNewline).prefix(20) {
			guard let template = line.split(separator: "=", maxSplits: 1).last.map(String.init),
			      Self.isValidTemplate(template)
			else { continue }
			templates.append(template)
		}
		return templates
	}

	private func shortcutDestination(for input: String) -> URL? {
		let pieces = input.split(maxSplits: 1, whereSeparator: \.isWhitespace)
		guard pieces.count == 2 else { return nil }
		guard keywordShortcuts.utf8.count <= 4_096 else { return nil }
		let keyword = String(pieces[0]).lowercased()
		guard keyword.range(of: #"^[a-zA-Z][a-zA-Z0-9_-]{0,15}$"#, options: .regularExpression) != nil,
		      let line = keywordShortcuts.split(whereSeparator: \.isNewline).prefix(20).first(where: {
			$0.split(separator: "=", maxSplits: 1).first?.lowercased() == keyword
		}),
		let template = line.split(separator: "=", maxSplits: 1).last.map(String.init),
		Self.isValidTemplate(template)
		else { return nil }
		return Self.url(for: String(pieces[1]), template: template)
	}

	private static let marker = "ASTRA_SEARCH_QUERY_MARKER"

	private static func url(for query: String, template: String) -> URL? {
		guard isValidTemplate(template),
		      var components = templateComponents(template),
		      let items = components.queryItems
		else { return nil }
		components.queryItems = items.map { item in
			URLQueryItem(name: item.name, value: item.value == marker ? query : item.value)
		}
		components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
		return components.url
	}

	private static func isValidTemplate(_ value: String) -> Bool {
		guard value.utf8.count <= 2_048,
		      value.components(separatedBy: "{query}").count == 2,
		      let components = templateComponents(value),
		      components.queryItems?.contains(where: { $0.value == marker }) == true,
		      components.scheme?.lowercased() == "https",
		      let host = components.host, !host.isEmpty,
		      components.user == nil, components.password == nil,
		      components.port.map({ (1 ... 65_535).contains($0) }) ?? true
		else { return false }
		return true
	}

	private static func templateComponents(_ template: String) -> URLComponents? {
		guard template.components(separatedBy: "{query}").count == 2 else { return nil }
		return URLComponents(string: template.replacingOccurrences(of: "{query}", with: marker))
	}

}

private extension BrowserSearchConfiguration.Engine {
	var template: String {
		switch self {
			case .google: "https://www.google.com/search?q={query}"
			case .duckDuckGo: "https://duckduckgo.com/?q={query}"
			case .bing: "https://www.bing.com/search?q={query}"
			case .custom: "https://www.google.com/search?q={query}"
		}
	}
}
