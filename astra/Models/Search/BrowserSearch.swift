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
		searchResults(for: newTabSearchText, includeActions: true)
	}

	func searchResults(for rawQuery: String, includeActions: Bool) -> [BrowserSearchResult] {
		let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
		let generation = newTabSearchGeneration
		let guardsNewTabQuery = includeActions
		let addressGeneration = addressSearchGeneration
		let selectedTabID = self.selectedTabID
		let configuration = browserSearchConfiguration
		let actions = BrowserSearchAction.catalogue(for: self)
		if query.isEmpty {
			guard includeActions else { return [] }
			let shortcuts = ["page-history", "page-bookmarks", "page-settings", "page-themeEditor", "reopen-tab", "new-space"]
			let results = shortcuts.compactMap { id in
				actions.first(where: { $0.id == id }).map { actionResult($0, score: 0) }
			}
			return results.map { result in
				BrowserSearchResult(
					id: result.id, kind: result.kind, title: result.title,
					detail: result.detail, symbol: result.symbol,
					score: result.score, destination: result.destination,
					perform: {
						guard self.newTabSearchGeneration == generation,
						      self.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
						      self.selectedTabID == selectedTabID,
						      self.browserSearchConfiguration.encoded == configuration.encoded
						else { return }
						result.perform()
					}
				)
			}
		}

		var results: [BrowserSearchResult] = []
		if let destination = BrowserAddress.destination(
			for: query,
			configuration: configuration,
			isPrivate: isPrivate
		) {
			let isSearch = BrowserAddress.isSearchURL(
				destination,
				configuration: configuration,
				isPrivate: isPrivate
			)
			results.append(BrowserSearchResult(
				id: "typed", kind: .typed, title: query,
				detail: isSearch ? configuration.searchLabel(for: query, isPrivate: isPrivate) : "Open Website",
				symbol: isSearch ? "magnifyingglass" : "globe",
				score: isSearch ? 0.8 : 1.1,
				destination: destination.absoluteString,
				perform: {
					if guardsNewTabQuery {
						guard self.newTabSearchGeneration == generation,
						      self.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
						else { return }
					} else {
						guard self.addressSearchGeneration == addressGeneration,
						      self.addressSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
						else { return }
					}
					self.selectedTab?.activeController?.loadFromAddressBar(destination)
				}
			))
		}

		if includeActions {
			for action in actions {
				let score = ([action.title] + action.terms).map {
					BrowserSearchMatching.score(query, in: $0)
				}.max() ?? 0
				if score > 0 {
					results.append(actionResult(action, score: score + 0.02))
				}
			}
		}
		if !isPrivate,
		   let tab = selectedTab,
		   let websiteURL = tab.activeController?.url,
		   websiteURL.scheme?.lowercased() == "https"
		{
			let title = "Discover search engine from this site"
			let score = BrowserSearchMatching.score(query, in: title)
			if score > 0 {
				results.append(BrowserSearchResult(
					id: "discover-search-engine", kind: .action,
					title: title, detail: "Checks this site's public OpenSearch metadata",
					symbol: "magnifyingglass.circle", score: score + 0.02,
					destination: nil,
					perform: {
						Task {
							guard let template = try? await BrowserSearchSuggestions.discoverOpenSearchTemplate(for: websiteURL) else { return }
							if includeActions {
								guard self.newTabSearchGeneration == generation,
								      self.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
								else { return }
							} else {
								guard self.addressSearchGeneration == addressGeneration,
								      self.addressSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
								else { return }
							}
							guard self.browserSearchConfiguration.encoded == configuration.encoded,
							      self.selectedTabID == tab.id,
							      self.selectedTab?.activeController?.url == websiteURL
							else { return }
							self.pendingSearchEngineTemplate = template
						}
					}
				))
			}
		}

		results += historySearchResults(for: query)
		results += bookmarkSearchResults(for: query)
		results += openTabSearchResults(for: query)
		if includeActions {
			for (index, suggestion) in newTabGoogleSuggestions.enumerated()
				where BrowserSearchMatching.normalized(suggestion) != BrowserSearchMatching.normalized(query)
			{
				guard let url = configuration.searchURL(for: suggestion, isPrivate: isPrivate) else { continue }
				results.append(BrowserSearchResult(
					id: "search-\(suggestion)", kind: .search, title: suggestion,
					detail: "Search \(browserSearchConfiguration.engine(isPrivate: isPrivate).title)", symbol: "magnifyingglass",
					score: 0.79 - Double(index) * 0.015,
					destination: url.absoluteString,
					perform: { self.selectedTab?.activeController?.load(url) }
				))
			}
		}
		let ranked = BrowserSearchResult.ranked(results)
		return ranked.map { result in
			BrowserSearchResult(
				id: result.id, kind: result.kind, title: result.title,
				detail: result.detail, symbol: result.symbol,
				score: result.score, destination: result.destination,
				perform: {
					guard self.selectedTabID == selectedTabID,
					      self.browserSearchConfiguration.encoded == configuration.encoded
				else { return }
					if includeActions {
						guard self.newTabSearchGeneration == generation,
						      self.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
						else { return }
					} else {
						guard self.addressSearchGeneration == addressGeneration,
						      self.addressSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
						else { return }
					}
					result.perform()
				}
			)
		}
	}

	private func actionResult(_ action: BrowserSearchAction, score: Double) -> BrowserSearchResult {
		BrowserSearchResult(
			id: action.id, kind: .action, title: action.title,
			detail: action.detail, symbol: action.symbol,
			score: score, destination: nil, perform: action.perform
		)
	}

	private func historySearchResults(for query: String) -> [BrowserSearchResult] {
		let newestVisit = historyVisits.map(\.visitedAt).max() ?? .distantPast
		let summaries = Dictionary(grouping: historyVisits, by: \.url).compactMap { url, visits -> (URL, BrowserVisit, Int)? in
			guard let latest = visits.max(by: {
				$0.visitedAt == $1.visitedAt
					? $0.id.uuidString > $1.id.uuidString
					: $0.visitedAt < $1.visitedAt
			}) else { return nil }
			return (url, latest, visits.count)
		}
		return summaries.compactMap { url, visit, count in
			let match = max(
				BrowserSearchMatching.score(query, in: visit.title),
				BrowserSearchMatching.score(query, in: url.host ?? ""),
				BrowserSearchMatching.score(query, in: url.absoluteString)
			)
			guard match > 0 else { return nil }
			let age = max(0, newestVisit.timeIntervalSince(visit.visitedAt) / 86_400)
			let recency = 1 / (1 + age / 365)
			return BrowserSearchResult(
				id: "history-\(visit.id)", kind: .history, title: visit.title,
				detail: "History · \(url.absoluteString)", symbol: "clock.arrow.circlepath",
				score: match + min(Double(count), 20) * 0.002 + recency * 0.02,
				destination: url.absoluteString,
				perform: { self.selectedTab?.activeController?.load(url) }
			)
		}
	}

	private func bookmarkSearchResults(for query: String) -> [BrowserSearchResult] {
		bookmarks.compactMap { bookmark in
			let match = max(
				BrowserSearchMatching.score(query, in: bookmark.name),
				BrowserSearchMatching.score(query, in: bookmark.url.absoluteString)
			)
			guard match > 0 else { return nil }
			return BrowserSearchResult(
				id: "bookmark-\(bookmark.id)", kind: .bookmark,
				title: bookmark.name, detail: "Bookmark · \(bookmark.url.absoluteString)",
				symbol: "bookmark", score: match + (bookmark.isFavorite ? 0.03 : 0),
				destination: bookmark.url.absoluteString,
				perform: { self.selectedTab?.activeController?.load(bookmark.url) }
			)
		}
	}

	private func openTabSearchResults(for query: String) -> [BrowserSearchResult] {
		tabs.compactMap { tab in
			guard let url = tab.activeController?.url ?? tab.currentURL else { return nil }
			let title = tab.title.isEmpty ? url.host ?? url.absoluteString : tab.title
			let match = max(
				BrowserSearchMatching.score(query, in: title),
				BrowserSearchMatching.score(query, in: url.absoluteString)
			)
			guard match > 0 else { return nil }
			return BrowserSearchResult(
				id: "tab-\(tab.id)", kind: .openTab,
				title: title, detail: "Open Tab · \(url.absoluteString)",
				symbol: "rectangle.on.rectangle", score: match + 0.04,
				destination: url.absoluteString,
				perform: {
					guard self.tabs.contains(where: { $0.id == tab.id && ($0.activeController?.url ?? $0.currentURL) == url }) else { return }
					self.selectTab(tab.id)
				}
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

	func removeHistorySuggestion(
		id: String,
		url: URL,
		query: String,
		generation: Int,
		fromNewTab: Bool
	) {
		let currentGeneration = fromNewTab ? newTabSearchGeneration : addressSearchGeneration
		let currentQuery = fromNewTab ? newTabSearchText : addressSearchText
		guard currentGeneration == generation,
		      currentQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query,
		      searchResults(for: query, includeActions: fromNewTab).contains(where: {
			$0.id == id && $0.kind == .history && $0.destination == url.absoluteString
		      })
		else { return }
		removeHistory(for: url)
	}
}
