import Foundation

@main
struct AddressSearchChecks {
	static func main() {
		let configuration = BrowserSearchConfiguration.default
		precondition(BrowserSearchConfiguration.decode(configuration.encoded) == configuration)
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
