import Foundation

@main
enum AddressIntelligenceCheck {
	static func main() {
		let history = BrowserSearchResult(
			id: "history-one", kind: .history, title: "Example", detail: "History",
			symbol: "clock", score: 0.8, destination: "https://example.com/",
			perform: {}
		)
		let duplicateHistory = BrowserSearchResult(
			id: "history-two", kind: .history, title: "Example", detail: "History",
			symbol: "clock", score: 0.7, destination: "https://example.com/",
			perform: {}
		)
		let bookmark = BrowserSearchResult(
			id: "bookmark-one", kind: .bookmark, title: "Example", detail: "Bookmark",
			symbol: "bookmark", score: 0.9, destination: "https://example.com/",
			perform: {}
		)
		let ranked = BrowserSearchResult.ranked([history, duplicateHistory, bookmark])
		precondition(ranked.map(\.id) == ["bookmark-one", "history-one"])
		precondition(BrowserSearchResult.selected(in: ranked, id: "history-one", automaticallySelectFirst: true)?.id == "history-one")
		precondition(BrowserSearchResult.selected(in: ranked, id: nil, automaticallySelectFirst: false) == nil)

		let request = BrowserSearchSuggestionsRequest(
			query: "example", generation: 1, scope: "address:one", provider: .google, isPrivate: false,
			configuration: "google", suggestionsEnabled: true
		)
		let nextRequest = BrowserSearchSuggestionsRequest(
			query: "example", generation: 2, scope: "address:one", provider: .google, isPrivate: false,
			configuration: "google", suggestionsEnabled: true
		)
		precondition(request != nextRequest)
		precondition(request != BrowserSearchSuggestionsRequest(
			query: "example", generation: 1, scope: "address:two", provider: .google, isPrivate: false,
			configuration: "google", suggestionsEnabled: true
		))
		precondition(BrowserSearchSuggestionsRequest(
			query: "example", generation: 1, scope: "address:two", provider: .google, isPrivate: true,
			configuration: "google", suggestionsEnabled: false
		) != request)
		var configuration = BrowserSearchConfiguration.default
		precondition(configuration.suggestionsProvider(isPrivate: true) == nil)
		configuration.privateSuggestionsEnabled = true
		precondition(configuration.suggestionsProvider(isPrivate: true) == .google)

		let xml = Data("""
		<OpenSearchDescription>
		  <Url type="text/html" method="GET" template="https://search.example/find?q={searchTerms}" />
		</OpenSearchDescription>
		""".utf8)
		precondition(BrowserSearchMatching.openSearchTemplate(from: xml) == "https://search.example/find?q={query}")
		precondition(BrowserSearchMatching.openSearchTemplate(from: Data("<not-search/>".utf8)) == nil)
		let insecureXML = Data("<OpenSearchDescription><Url type=\"text/html\" method=\"GET\" template=\"http://search.example/?q={searchTerms}\" /></OpenSearchDescription>".utf8)
		precondition(BrowserSearchMatching.openSearchTemplate(from: insecureXML) == nil)
		precondition(BrowserSearchMatching.openSearchTemplate(from: Data(repeating: 0, count: 65_537)) == nil)
		let namespacedXML = Data("""
		<os:OpenSearchDescription xmlns:os="http://a9.com/-/spec/opensearch/1.1/">
		  <os:Url type="text/html" template="https://search.example/?q={searchTerms}" />
		</os:OpenSearchDescription>
		""".utf8)
		precondition(BrowserSearchMatching.openSearchTemplate(from: namespacedXML) == "https://search.example/?q={query}")
		let defaultGetXML = Data("<OpenSearchDescription><Url type='text/html' template='https://search.example/?q={searchTerms}'/></OpenSearchDescription>".utf8)
		precondition(BrowserSearchMatching.openSearchTemplate(from: defaultGetXML) == "https://search.example/?q={query}")
		let dtdXML = Data("<!DOCTYPE x [<!ENTITY x 'x'>]><OpenSearchDescription><Url type='text/html' template='https://s.example/?q={searchTerms}'/></OpenSearchDescription>".utf8)
		precondition(BrowserSearchMatching.openSearchTemplate(from: dtdXML) == nil)
		let postXML = Data("<OpenSearchDescription><Url type='text/html' method='POST' template='https://s.example/?q={searchTerms}'/></OpenSearchDescription>".utf8)
		precondition(BrowserSearchMatching.openSearchTemplate(from: postXML) == nil)
		let placeholderXML = Data("<OpenSearchDescription><Url type='text/html' template='https://s.example/?q={searchTerms}&amp;count={count}'/></OpenSearchDescription>".utf8)
		precondition(BrowserSearchMatching.openSearchTemplate(from: placeholderXML) == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("ordinary search terms") == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("example.com/path")?.absoluteString == "https://example.com/path")
		precondition(BrowserSearchMatching.pastedHTTPURL("<https://example.com>")?.absoluteString == "https://example.com")
		precondition(BrowserSearchMatching.pastedHTTPURL("https://user@example.com") == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("ordinary search terms") == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("https:///example.com") == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("https://example.com:") == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("https://example.com:abc") == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("javascript:example.com") == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("https://example.com/\u{0001}") == nil)
		precondition(BrowserSearchMatching.pastedHTTPURL("localhost:8080/path")?.absoluteString == "https://localhost:8080/path")
		precondition(BrowserSearchMatching.shouldExpandAddressOnFocus(text: "example.com", simpleAddress: "example.com"))
		precondition(!BrowserSearchMatching.shouldExpandAddressOnFocus(text: "https://other.example/path", simpleAddress: "example.com"))

		let firstWebView = NSObject()
		let secondWebView = NSObject()
		let discovery = BrowserSearchEngineDiscovery(
			template: "https://search.example/?q={query}",
			tabID: UUID(), controllerID: UUID(), webViewID: ObjectIdentifier(firstWebView), documentID: 7,
			pageURL: URL(string: "https://example.com/page")!,
			query: "exa", queryGeneration: 4, configuration: "config-a"
		)
		precondition(discovery.matches(
			tabID: discovery.tabID, controllerID: discovery.controllerID,
			webViewID: discovery.webViewID, documentID: 7, pageURL: discovery.pageURL, query: "exa",
			queryGeneration: 4, configuration: "config-a"
		))
		precondition(!discovery.matches(
			tabID: discovery.tabID, controllerID: discovery.controllerID,
			webViewID: discovery.webViewID, documentID: 8, pageURL: discovery.pageURL, query: "exa",
			queryGeneration: 4, configuration: "config-a"
		))
		precondition(!discovery.matches(
			tabID: discovery.tabID, controllerID: discovery.controllerID,
			webViewID: ObjectIdentifier(secondWebView), documentID: 7, pageURL: discovery.pageURL, query: "exa",
			queryGeneration: 4, configuration: "config-a"
		))
		precondition(!discovery.matches(
			tabID: discovery.tabID, controllerID: discovery.controllerID,
			webViewID: discovery.webViewID, documentID: 7, pageURL: discovery.pageURL, query: "changed",
			queryGeneration: 4, configuration: "config-a"
		))
		precondition(!discovery.matches(
			tabID: discovery.tabID, controllerID: discovery.controllerID,
			webViewID: discovery.webViewID, documentID: 7, pageURL: discovery.pageURL, query: "exa",
			queryGeneration: 4, configuration: "config-b"
		))
		print("Task 15 address intelligence checks passed")
	}
}
