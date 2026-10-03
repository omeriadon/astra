import Foundation

@main
struct AddressSearchChecks {
	static func main() {
		let configuration = BrowserSearchConfiguration.default
		precondition(BrowserSearchConfiguration.decode(configuration.encoded) == configuration)
		precondition(configuration.encoded == configuration.encoded)
		var escapedConfiguration = configuration
		escapedConfiguration.customTemplate = String(repeating: "\u{1}", count: 2_048)
		escapedConfiguration.keywordShortcuts = String(repeating: "\u{1}", count: 4_096)
		precondition(BrowserSearchConfiguration.decode(escapedConfiguration.encoded) == escapedConfiguration)
		checkAddress("https://example.com/path?a=1#section", expected: "https://example.com/path?a=1#section", configuration: configuration)
		checkAddress("example.com:8443/path", expected: "https://example.com:8443/path", configuration: configuration)
		checkAddress("localhost:8080/path", expected: "https://localhost:8080/path", configuration: configuration)
		checkAddress("192.168.1.2:8443", expected: "https://192.168.1.2:8443", configuration: configuration)
		precondition(BrowserAddress.destination(for: "999.168.1.2", configuration: configuration)?.host == "www.google.com")
		checkAddress("[::1]:8080", expected: "https://[::1]:8080", configuration: configuration)
		checkAddress("<https://example.com/hello>", expected: "https://example.com/hello", configuration: configuration)
		let unicodeAddress = BrowserAddress.destination(for: "https://例え.テスト/検索?q=%E3%81%82", configuration: configuration)
		precondition(unicodeAddress?.host?.hasPrefix("xn--") == true)
		precondition(URLComponents(url: unicodeAddress!, resolvingAgainstBaseURL: false)?.percentEncodedQuery == "q=%E3%81%82")
		precondition(BrowserAddress.destination(for: "javascript:alert(1)", configuration: configuration) == nil)
		precondition(BrowserAddress.destination(for: "file:///etc/passwd", configuration: configuration) == nil)
		precondition(BrowserAddress.destination(for: "mailto:test@example.com", configuration: configuration)?.scheme == "mailto")
		precondition(BrowserAddress.destination(for: "com.example.app://target", configuration: configuration)?.scheme == "com.example.app")
		precondition(BrowserAddress.destination(for: "example.com:notaport", configuration: configuration)?.host == "www.google.com")
		precondition(BrowserAddress.destination(for: "javascript://alert", configuration: configuration) == nil)

		checkAddress("omeriadon/astra", expected: "https://github.com/omeriadon/astra", configuration: configuration)
		checkAddress("apple/swift", expected: "https://github.com/apple/swift", configuration: configuration)
		let invalidRepository = BrowserAddress.destination(for: ".github/.github", configuration: configuration)!
		precondition(invalidRepository.host == "www.google.com")
		precondition(configuration.query(for: invalidRepository) == ".github/.github")
		precondition(BrowserSearchConfiguration.githubRepositoryDestination(for: "owner/repo/extra") == nil)
		precondition(BrowserSearchConfiguration.githubRepositoryDestination(for: "-owner/repo") == nil)
		precondition(BrowserSearchConfiguration.githubRepositoryDestination(for: "owner/repo name") == nil)
		precondition(configuration.searchLabel(for: "omeriadon/astra", isPrivate: false) == "Open GitHub Repository")

		let query = "C++ & 100%=x # café"
		guard let searchURL = configuration.searchURL(for: query) else { fatalError("missing default search URL") }
		precondition(searchURL.absoluteString.contains("C%2B%2B"))
		precondition(configuration.query(for: searchURL) == query)
		precondition(BrowserAddress.isSearchURL(searchURL, configuration: configuration))
		let dimmedSearch = BrowserAddress.displayString(
			for: searchURL,
			style: .dimmed,
			isEditing: false,
			configuration: configuration
		)
		let fullHighlight = BrowserAddress.primaryTextRanges(
			for: searchURL,
			displayedText: searchURL.absoluteString,
			configuration: configuration
		)
		precondition(fullHighlight.first.map { String(searchURL.absoluteString[$0]) } == "C%2B%2B%20%26%20100%25%3Dx%20%23%20caf%C3%A9")
		let highlighted = BrowserAddress.primaryTextRanges(
			for: searchURL,
			displayedText: dimmedSearch,
			configuration: configuration
		)
		precondition(highlighted.first.map { String(dimmedSearch[$0]) } == query)
		precondition(!BrowserAddress.isSearchURL(URL(string: "http://www.google.com/search?q=word"), configuration: configuration))
		precondition(configuration.query(for: URL(string: "https://www.google.com/search?q=word+with+spaces")!) == "word with spaces")
		precondition(configuration.query(for: URL(string: "https://google.com.evil/search?q=word")!) == nil)
		precondition(configuration.query(for: URL(string: "https://www.google.co.uk/search?q=word")!) == "word")

		var custom = configuration
		custom.normalEngine = .custom
		custom.customTemplate = "https://search.example/find?client=astra&q={query}"
		guard let customURL = custom.searchURL(for: query) else { fatalError("missing custom search URL") }
		precondition(custom.query(for: customURL) == query)
		precondition(custom.searchLabel(for: "q: \(query)", isPrivate: false) == "Search Custom")
		precondition(custom.query(for: URL(string: "https://search.example/find?client=other&q=word")!) == nil)
		precondition(custom.queryParameterName(for: URL(string: "https://search.example/find?client=other&q=word")!) == nil)
		custom.customTemplate = "https://search.example/find?search%5Fterms={query}"
		let encodedParameterURL = URL(string: "https://search.example/find?search%5Fterms=hello")!
		precondition(custom.queryParameterName(for: encodedParameterURL) == "search_terms")
		precondition(custom.query(for: encodedParameterURL) == "hello")
		let encodedParameterDisplay = BrowserAddress.displayString(
			for: encodedParameterURL,
			style: .dimmed,
			isEditing: false,
			configuration: custom
		)
		let encodedParameterFullRange = BrowserAddress.primaryTextRanges(
			for: encodedParameterURL,
			displayedText: encodedParameterURL.absoluteString,
			configuration: custom
		).first
		precondition(encodedParameterFullRange.map { String(encodedParameterURL.absoluteString[$0]) } == "hello")
		let encodedParameterRange = BrowserAddress.primaryTextRanges(
			for: encodedParameterURL,
			displayedText: encodedParameterDisplay,
			configuration: custom
		).first
		precondition(encodedParameterRange.map { String(encodedParameterDisplay[$0]) } == "hello")
		custom.customTemplate = "http://search.example/?q={query}"
		precondition(custom.searchURL(for: "never fallback") == nil)
		precondition(BrowserSearchConfiguration.decode("invalid").searchURL(for: "never fallback") == nil)

		var split = configuration
		split.privateEngine = .bing
		precondition(split.query(for: split.searchURL(for: "normal")!) == "normal")
		precondition(split.searchURL(for: "private", isPrivate: true)?.host == "www.bing.com")
		precondition(split.suggestionsProvider(isPrivate: true) == nil)
		split.privateEngine = .google
		split.privateSuggestionsEnabled = true
		precondition(split.suggestionsProvider(isPrivate: true) == .google)

		let suggestionURL = BrowserSearchSuggestions.suggestionURL(for: "C++", provider: .google)
		precondition(URLComponents(url: suggestionURL!, resolvingAgainstBaseURL: false)?.percentEncodedQuery?.contains("C%2B%2B") == true)
		precondition(BrowserSearchSuggestions.parsedSuggestions(
			["café", ["café au lait", "café noir"]],
			query: "café",
			provider: .google
		) == ["café au lait", "café noir"])
		precondition(BrowserSearchSuggestions.parsedSuggestions(
			["old query", ["stale"]],
			query: "current query",
			provider: .google
		) == nil)
		precondition(BrowserSearchSuggestions.parsedSuggestions(
			[["phrase": "tea", "score": 1], ["phrase": "tea shop"]],
			query: "tea",
			provider: .duckDuckGo
		) == ["tea", "tea shop"])
		precondition(BrowserSearchSuggestions.parsedSuggestions(
			["unexpected tuple", "shape"],
			query: "tea",
			provider: .duckDuckGo
		) == [])

		var shortcuts = configuration
		shortcuts.keywordShortcuts = "w=https://en.wikipedia.org/w/index.php?search={query}"
		precondition(shortcuts.destination(for: "w café & tea")?.host == "en.wikipedia.org")
		precondition(shortcuts.destination(for: "w café & tea").flatMap { shortcuts.query(for: $0) } == "café & tea")
		precondition(shortcuts.searchLabel(for: "w café & tea", isPrivate: false) == "Search en.wikipedia.org")
		print("address/search checks passed")
	}

	private static func checkAddress(
		_ input: String,
		expected: String,
		configuration: BrowserSearchConfiguration
	) {
		precondition(BrowserAddress.destination(for: input, configuration: configuration)?.absoluteString == expected, input)
	}
}
