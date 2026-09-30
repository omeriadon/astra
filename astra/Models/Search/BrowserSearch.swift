import Foundation

extension Browser {
	var isShowingNewTab: Bool {
		guard let tab = selectedTab else { return false }
		return tab.internalPage == nil && tab.currentURL == nil && !tab.isHibernated && tab.peeks.isEmpty
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
		if let destination = BrowserAddress.destination(for: query) {
			let isSearch = BrowserAddress.isGoogleSearchURL(destination)
			results.append(BrowserSearchResult(
				id: "typed", kind: .typed, title: query,
				detail: isSearch ? "Search Google" : "Open Website",
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
			guard let url = BrowserAddress.destination(for: suggestion) else { continue }
			results.append(BrowserSearchResult(
				id: "search-\(suggestion)", kind: .search, title: suggestion,
				detail: "Google Suggestion", symbol: "magnifyingglass",
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
		let history = (tabs.filter { $0.internalPage == nil }.map(\.openTab) + closedHistoryTabs)
			.sorted { $0.modifiedAt > $1.modifiedAt }
		var seen = Set<URL>()
		var results: [BrowserSearchResult] = []
		for tab in history {
			for url in tab.history + (tab.url.map { [$0] } ?? []) {
				guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
				      seen.insert(url).inserted
				else { continue }
				let title = url == tab.url ? (tab.customTitle ?? tab.pageTitle) : (url.host ?? url.absoluteString)
				let score = max(
					BrowserSearchMatching.score(query, in: title),
					BrowserSearchMatching.score(query, in: url.host ?? ""),
					BrowserSearchMatching.score(query, in: url.absoluteString)
				)
				guard score > 0 else { continue }
				let age = max(0, Date.now.timeIntervalSince(tab.modifiedAt)) / 86400
				results.append(BrowserSearchResult(
					id: "history-\(url.absoluteString)", kind: .history, title: title,
					detail: "History · \(url.absoluteString)", symbol: "clock.arrow.circlepath",
					score: score + 0.04 / (1 + age),
					perform: { self.selectedTab?.activeController?.load(url) }
				))
			}
		}
		return results
	}

	func moveNewTabSearchSelection(by offset: Int) {
		let results = newTabSearchResults
		guard !results.isEmpty else { return }
		let index = results.firstIndex { $0.id == newTabSearchSelection }
		let next = index.map { ($0 + offset + results.count) % results.count }
			?? (offset > 0 ? 0 : results.count - 1)
		newTabSearchSelection = results[next].id
	}

	func submitNewTabSearch() {
		let results = newTabSearchResults
		let result = results.first { $0.id == newTabSearchSelection }
			?? results.first { $0.kind == .typed }
		result?.perform()
		newTabSearchSelection = nil
	}
}
