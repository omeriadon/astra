// Run from the worktree root:
// swiftc astra/Models/Search/BrowserSearchMatching.swift astra/Models/Search/BrowserSearchResult.swift Tests/BrowserSearchChecks.swift -o /tmp/astra-search-checks && /tmp/astra-search-checks
import Foundation

@main
struct BrowserSearchChecks {
	@MainActor
	static func main() {
		assert(BrowserSearchMatching.score("history", in: "History") == 1)
		assert(BrowserSearchMatching.score("hist", in: "History") > BrowserSearchMatching.score("hstry", in: "History"))
		assert(BrowserSearchMatching.score("bookmrks", in: "Bookmarks") > 0)
		assert(BrowserSearchMatching.score("histroy", in: "History") > 0)
		assert(BrowserSearchMatching.score("sync server", in: "Sync Server URL") > 0)
		assert(BrowserSearchMatching.score("CAFE", in: "Café") == 1)
		assert(BrowserSearchMatching.score("cat", in: "Account") == 0)
		assert(BrowserSearchMatching.score("", in: "History") == 0)
		assert(BrowserSearchMatching.score("potato", in: "Privacy and Security") == 0)

		let results = (0 ..< 20).flatMap { index in
			[BrowserSearchResult.Kind.action, .history, .search].map { kind in
				BrowserSearchResult(
					id: "\(kind.rawValue)-\(index)", kind: kind, title: "Result",
					detail: "", symbol: "magnifyingglass",
					score: kind == .action ? 1 : 0.8, perform: {}
				)
			}
		}
		let typed = BrowserSearchResult(
			id: "typed", kind: .typed, title: "query", detail: "Search Google",
			symbol: "magnifyingglass", score: 0.8, perform: {}
		)
		let ranked = BrowserSearchResult.ranked(results + [results[0], typed])
		assert(ranked.filter { $0.kind == .action }.count == 3)
		assert(ranked.filter { $0.kind == .history }.count == 4)
		assert(ranked.filter { $0.kind == .search }.count == 4)
		assert(Set(ranked.map(\.id)).count == ranked.count)
		assert(ranked.first?.kind == .action)
		assert(ranked.filter { $0.kind == .typed }.count == 1)
		assert(BrowserSearchResult.ranked(results.reversed()).map(\.id) == BrowserSearchResult.ranked(results).map(\.id))
		assert(BrowserSearchResult.selected(in: ranked, id: nil, automaticallySelectFirst: true)?.id == ranked.first?.id)
		assert(BrowserSearchResult.selected(in: ranked, id: typed.id, automaticallySelectFirst: true)?.id == typed.id)
		assert(BrowserSearchResult.selected(in: ranked, id: "removed", automaticallySelectFirst: true)?.id == ranked.first?.id)
		assert(BrowserSearchResult.selected(in: ranked, id: nil, automaticallySelectFirst: false) == nil)
		assert(BrowserSearchResult.selected(in: ranked, id: ranked.last?.id, automaticallySelectFirst: true)?.id == ranked.last?.id)
		assert(BrowserSearchResult.selected(in: [], id: nil, automaticallySelectFirst: true) == nil)
		print("Search matching, balanced ranking, and automatic selection checks passed")
	}
}
