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
			query: "example", generation: 1, provider: .google, isPrivate: false,
			configuration: "google", suggestionsEnabled: true
		)
		let nextRequest = BrowserSearchSuggestionsRequest(
			query: "example", generation: 2, provider: .google, isPrivate: false,
			configuration: "google", suggestionsEnabled: true
		)
		precondition(request != nextRequest)
		precondition(BrowserSearchSuggestionsRequest(
			query: "example", generation: 1, provider: .google, isPrivate: true,
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
		print("Task 15 address intelligence checks passed")
	}
}
