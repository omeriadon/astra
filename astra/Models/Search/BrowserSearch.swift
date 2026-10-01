import Defaults
import Foundation

extension Browser {
	var isShowingNewTab: Bool {
		guard let tab = selectedTab else { return false }
		return tab.internalPage == nil && tab.currentURL == nil && !tab.isHibernated && tab.peeks.isEmpty
	}

	var browserSearchConfiguration: BrowserSearchConfiguration {
		BrowserSearchConfiguration.decode(Defaults[.browserSearchConfiguration])
	}

	var newTabSearchResults: [BrowserSearchResult] {
		let query = newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
		let actions = BrowserSearchAction.catalogue(for: self)
		if query.isEmpty {
			let shortcuts = ["page-history", "page-bookmarks", "page-settings", "page-themeEditor", "reopen-tab", "new-space"]
			return shortcuts.compactMap { id in
				actions.first(where: { $0.id == id }).map { actionResult($0, score: 0) }
			}
		}
		var results: [BrowserSearchResult] = []
		if let destination = BrowserAddress.destination(
			for: query,
			configuration: browserSearchConfiguration,
			isPrivate: isPrivate
		) {
			let isSearch = BrowserAddress.isSearchURL(
				destination,
				configuration: browserSearchConfiguration,
				isPrivate: isPrivate
			)
			results.append(BrowserSearchResult(
				id: "typed", kind: .typed, title: query,
				detail: isSearch ? browserSearchConfiguration.searchLabel(for: query, isPrivate: isPrivate) : "Open Website",
				symbol: isSearch ? "magnifyingglass" : "globe",
				score: isSearch ? 0.8 : 1.1,
				perform: { self.selectedTab?.activeController?.load(destination) }
			))
		}
		for action in actions {
			let score = ([action.title] + action.terms).map {
				BrowserSearchMatching.score(query, in: $0)
			}.max() ?? 0
			if score > 0 {
				results.append(actionResult(action, score: score + 0.02))
			}
		}
		results += historySearchResults(for: query)
		for (index, suggestion) in newTabGoogleSuggestions.enumerated()
			where BrowserSearchMatching.normalized(suggestion) != BrowserSearchMatching.normalized(query)
		{
			guard let url = browserSearchConfiguration.searchURL(for: suggestion, isPrivate: isPrivate) else { continue }
			results.append(BrowserSearchResult(
				id: "search-\(suggestion)", kind: .search, title: suggestion,
				detail: "Search \(browserSearchConfiguration.engine(isPrivate: isPrivate).title)", symbol: "magnifyingglass",
				score: 0.79 - Double(index) * 0.015,
				perform: { self.selectedTab?.activeController?.load(url) }
			))
		}
		return BrowserSearchResult.ranked(results)
	}

	private func actionResult(_ action: BrowserSearchAction, score: Double) -> BrowserSearchResult {
		BrowserSearchResult(
			id: action.id, kind: .action, title: action.title,
			detail: action.detail, symbol: action.symbol,
			score: score, perform: action.perform
		)
	}

	private func historySearchResults(for query: String) -> [BrowserSearchResult] {
		var seen = Set<URL>()
		return historyVisits.compactMap { visit in
			guard seen.insert(visit.url).inserted else { return nil }
			let score = max(
				BrowserSearchMatching.score(query, in: visit.title),
				BrowserSearchMatching.score(query, in: visit.url.host ?? ""),
				BrowserSearchMatching.score(query, in: visit.url.absoluteString)
			)
			guard score > 0 else { return nil }
			return BrowserSearchResult(
				id: "history-\(visit.id)", kind: .history, title: visit.title,
				detail: "History · \(visit.url.absoluteString)", symbol: "clock.arrow.circlepath",
				score: score,
				perform: { self.selectedTab?.activeController?.load(visit.url) }
			)
		}
	}

	var selectedNewTabSearchResult: BrowserSearchResult? {
		BrowserSearchResult.selected(
			in: newTabSearchResults,
			id: newTabSearchSelection,
			automaticallySelectFirst: !newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		)
	}

	func moveNewTabSearchSelection(by offset: Int) {
		let results = newTabSearchResults
		guard !results.isEmpty else { return }
		let selectedID = selectedNewTabSearchResult?.id
		let index = results.firstIndex { $0.id == selectedID }
		let next = index.map { ($0 + offset + results.count) % results.count }
			?? (offset > 0 ? 0 : results.count - 1)
		newTabSearchSelection = results[next].id
	}

	func submitNewTabSearch() {
		selectedNewTabSearchResult?.perform()
		newTabSearchSelection = nil
	}
}
