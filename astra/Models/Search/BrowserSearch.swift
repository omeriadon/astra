import Defaults
import Foundation
import WebKit

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

	func searchResults(
		for rawQuery: String,
		includeActions: Bool,
		remoteSuggestions: [String]? = nil,
		remoteSuggestionRequest: BrowserSearchSuggestionsRequest? = nil
	) -> [BrowserSearchResult] {
		let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
		let generation = newTabSearchGeneration
		let guardsNewTabQuery = includeActions
		let addressGeneration = addressSearchGeneration
		let selectedTabID = selectedTabID
		let configuration = browserSearchConfiguration
		let actions = BrowserSearchAction.catalogue(for: self)
		if query.isEmpty {
			guard includeActions else { return [] }
			let shortcuts = ["page-history", "page-bookmarks", "page-settings", "page-themeEditor", "reopen-tab", "new-space"]
			var results = shortcuts.compactMap { id in
				actions.first(where: { $0.id == id }).map { actionResult($0, score: 0) }
			}
			if let clipboardURL = newTabClipboardURL {
				results.insert(
					BrowserSearchResult(
						id: "clipboard-url", kind: .typed, title: clipboardURL.absoluteString,
						detail: "Open Clipboard URL", symbol: "link", score: 2,
						destination: clipboardURL.absoluteString,
						perform: { self.openSearchDestination(clipboardURL) }
					),
					at: 0
				)
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

		let normalizedQuery = BrowserSearchMatching.normalized(query)
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
			let isGitHubRepository = configuration.githubRepositoryShorthandEnabled
				&& BrowserSearchConfiguration.githubRepositoryDestination(for: query) == destination
			results.append(BrowserSearchResult(
				id: "typed", kind: .typed, title: query,
				detail: isGitHubRepository ? "Open GitHub repository · \(destination.absoluteString)"
					: isSearch ? configuration.searchLabel(for: query, isPrivate: isPrivate) : "Open Website",
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
					self.openSearchDestination(destination, fromAddressBar: true)
				}
			))
		}

		if includeActions {
			for action in actions {
				let score = ([action.title] + action.terms).map {
					BrowserSearchMatching.score(normalizedQuery: normalizedQuery, in: $0)
				}.max() ?? 0
				if score > 0 {
					results.append(actionResult(action, score: score + 0.02))
				}
			}
		}
		results += historySearchResults(normalizedQuery: normalizedQuery)
		results += bookmarkSearchResults(normalizedQuery: normalizedQuery)
		results += openTabSearchResults(normalizedQuery: normalizedQuery)
		let suggestions = remoteSuggestions ?? (includeActions ? newTabGoogleSuggestions : [])
		for (index, suggestion) in suggestions.enumerated()
			where BrowserSearchMatching.normalized(suggestion) != normalizedQuery
		{
			guard let url = configuration.searchURL(for: suggestion, isPrivate: isPrivate) else { continue }
			results.append(BrowserSearchResult(
				id: "search-\(suggestion)", kind: .search, title: suggestion,
				detail: "Search \(configuration.engine(isPrivate: isPrivate).title)", symbol: "magnifyingglass",
				score: 0.79 - Double(index) * 0.015,
				destination: url.absoluteString,
				perform: { self.openSearchDestination(url) }
			))
		}
		let ranked = BrowserSearchResult.ranked(results)
		let ordered: [BrowserSearchResult]
		if includeActions, let searchURL = configuration.searchURL(for: query, isPrivate: isPrivate) {
			let exactSearch = BrowserSearchResult(
				id: "exact-search", kind: .typed, title: query,
				detail: "Search \(configuration.engine(isPrivate: isPrivate).title)", symbol: "magnifyingglass",
				score: 0, destination: searchURL.absoluteString,
				perform: { self.openSearchDestination(searchURL) }
			)
			ordered = BrowserSearchResult.enforceExactSearchSecond(
				ranked, candidate: exactSearch, destination: searchURL.absoluteString
			)
		} else {
			ordered = ranked
		}
		return ordered.map { result in
			BrowserSearchResult(
				id: result.id, kind: result.kind, title: result.title,
				detail: result.detail, symbol: result.symbol,
				score: result.score, destination: result.destination,
				perform: {
					guard self.selectedTabID == selectedTabID,
					      self.browserSearchConfiguration.encoded == configuration.encoded
					else { return }
					if result.kind == .search {
						guard Defaults[.searchSuggestionsEnabled],
						      self.browserSearchConfiguration.suggestionsProvider(isPrivate: self.isPrivate) != nil
						else { return }
						if includeActions {
							guard self.newTabGoogleSuggestions.contains(result.title) else { return }
						} else {
							guard let remoteSuggestionRequest,
							      self.addressSuggestionsRequest == remoteSuggestionRequest,
							      self.ownsAddressSuggestionRequest(remoteSuggestionRequest)
							else { return }
						}
					}
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

	private func ownsAddressSuggestionRequest(_ request: BrowserSearchSuggestionsRequest) -> Bool {
		let controller = selectedTab?.activeController
		let scope = "address:\(windowID):\(selectedTabID):\(controller?.id.uuidString ?? "none"):\(controller?.navigationIdentifier ?? -1)"
		guard let provider = browserSearchConfiguration.suggestionsProvider(isPrivate: isPrivate) else { return false }
		return request.query == addressSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
			&& request.generation == addressSearchGeneration
			&& request.scope == scope
			&& request.provider == provider
			&& request.isPrivate == isPrivate
			&& request.configuration == browserSearchConfiguration.encoded
			&& request.suggestionsEnabled == Defaults[.searchSuggestionsEnabled]
			&& request.suggestionsEnabled == addressFieldIsFocused
			&& !isShowingNewTab
	}

	func discoverSearchEngineFromAddressBar(template: String) {
		guard !isPrivate, !isShowingNewTab,
		      let tab = selectedTab, tab.internalPage == nil,
		      let controller = tab.activeController,
		      controller.hasCurrentPageDocument, !controller.isLoading,
		      let webView = controller.webViewIfLoaded,
		      let pageURL = controller.url,
		      pageURL.scheme?.lowercased() == "https"
		else { return }
		let discovery = BrowserSearchEngineDiscovery(
			template: template,
			tabID: tab.id,
			controllerID: controller.id,
			webViewID: ObjectIdentifier(webView),
			documentID: controller.navigationIdentifier,
			pageURL: pageURL,
			query: addressSearchText.trimmingCharacters(in: .whitespacesAndNewlines),
			queryGeneration: addressSearchGeneration,
			configuration: browserSearchConfiguration.encoded
		)
		guard isCurrentSearchEngineDiscovery(discovery) else { return }
		pendingSearchEngineDiscovery = discovery
	}

	var canAcceptSearchEngineDiscovery: Bool {
		guard let pending = pendingSearchEngineDiscovery else { return false }
		return isCurrentSearchEngineDiscovery(pending)
	}

	func consumeSearchEngineDiscovery() -> String? {
		defer { pendingSearchEngineDiscovery = nil }
		guard let pending = pendingSearchEngineDiscovery,
		      isCurrentSearchEngineDiscovery(pending)
		else { return nil }
		return pending.template
	}

	func discardStaleSearchEngineDiscovery() {
		guard let pending = pendingSearchEngineDiscovery,
		      !isCurrentSearchEngineDiscovery(pending)
		else { return }
		pendingSearchEngineDiscovery = nil
	}

	private func isCurrentSearchEngineDiscovery(_ pending: BrowserSearchEngineDiscovery) -> Bool {
		guard !isPrivate, !isShowingNewTab,
		      selectedTab?.internalPage == nil,
		      let controller = selectedTab?.activeController,
		      controller.hasCurrentPageDocument, !controller.isLoading,
		      controller.navigationFailure == nil,
		      let webView = controller.webViewIfLoaded,
		      let pageURL = controller.url,
		      webView.url == pageURL,
		      pending.matches(
		      	tabID: selectedTabID,
		      	controllerID: controller.id,
		      	webViewID: ObjectIdentifier(webView),
		      	documentID: controller.navigationIdentifier,
		      	pageURL: pageURL,
		      	query: addressSearchText.trimmingCharacters(in: .whitespacesAndNewlines),
		      	queryGeneration: addressSearchGeneration,
		      	configuration: browserSearchConfiguration.encoded
		      )
		else { return false }
		return true
	}

	private func actionResult(_ action: BrowserSearchAction, score: Double) -> BrowserSearchResult {
		BrowserSearchResult(
			id: action.id, kind: .action, title: action.title,
			detail: action.detail, symbol: action.symbol,
			score: score, destination: nil, perform: action.perform
		)
	}

	private func historySearchResults(normalizedQuery: String) -> [BrowserSearchResult] {
		// Retain the SwiftUI observation dependency even when using the ignored cache.
		_ = historyVisits.count
		if historySearchIndex == nil {
			// Build once per history mutation, not for every keystroke.
			var newestVisit = Date.distantPast
			var summaries: [URL: (visit: BrowserVisit, count: Int)] = [:]
			for visit in historyVisits {
				if visit.visitedAt > newestVisit {
					newestVisit = visit.visitedAt
				}
				if var existing = summaries[visit.url] {
					existing.count += 1
					if visit.visitedAt > existing.visit.visitedAt ||
						(visit.visitedAt == existing.visit.visitedAt &&
						 visit.id.uuidString < existing.visit.id.uuidString)
					{
						existing.visit = visit
					}
					summaries[visit.url] = existing
				} else {
					summaries[visit.url] = (visit, 1)
				}
			}
			let entries = summaries.map { (url: $0.key, visit: $0.value.visit, count: $0.value.count) }
			historySearchIndex = (newestVisit: newestVisit, entries: entries)
		}
		guard let index = historySearchIndex else { return [] }
		return index.entries.compactMap { entry in
			let url = entry.url
			let visit = entry.visit
			let count = entry.count
			let match = max(
				BrowserSearchMatching.score(normalizedQuery: normalizedQuery, in: visit.title),
				BrowserSearchMatching.score(normalizedQuery: normalizedQuery, in: url.host ?? ""),
				BrowserSearchMatching.score(normalizedQuery: normalizedQuery, in: url.absoluteString)
			)
			guard match > 0 else { return nil }
			let age = max(0, index.newestVisit.timeIntervalSince(visit.visitedAt) / 86400)
			let recency = 1 / (1 + age / 365)
			return BrowserSearchResult(
				id: "history-\(visit.id)", kind: .history, title: visit.title,
				detail: "History · \(url.absoluteString)", symbol: "clock.arrow.circlepath",
				score: match + min(Double(count), 20) * 0.002 + recency * 0.02,
				destination: url.absoluteString,
				perform: { self.openSearchDestination(url) }
			)
		}
	}

	private func bookmarkSearchResults(normalizedQuery: String) -> [BrowserSearchResult] {
		bookmarks.compactMap { bookmark in
			let match = max(
				BrowserSearchMatching.score(normalizedQuery: normalizedQuery, in: bookmark.name),
				BrowserSearchMatching.score(normalizedQuery: normalizedQuery, in: bookmark.url.absoluteString)
			)
			guard match > 0 else { return nil }
			return BrowserSearchResult(
				id: "bookmark-\(bookmark.id)", kind: .bookmark,
				title: bookmark.name, detail: "Bookmark · \(bookmark.url.absoluteString)",
				symbol: "bookmark", score: match + (bookmark.isFavorite ? 0.03 : 0),
				destination: bookmark.url.absoluteString,
				perform: { self.openSearchDestination(bookmark.url) }
			)
		}
	}

	private func openTabSearchResults(normalizedQuery: String) -> [BrowserSearchResult] {
		tabs.compactMap { tab in
			guard let url = tab.activeController?.url ?? tab.currentURL else { return nil }
			let title = tab.title.isEmpty ? url.host ?? url.absoluteString : tab.title
			let match = max(
				BrowserSearchMatching.score(normalizedQuery: normalizedQuery, in: title),
				BrowserSearchMatching.score(normalizedQuery: normalizedQuery, in: url.absoluteString)
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

	func performNewTabSearchResult(_ result: BrowserSearchResult) {
		result.perform()
		showsQuickSearch = false
	}

	private func openSearchDestination(_ url: URL, fromAddressBar: Bool = false) {
		let controller = showsQuickSearch ? addTab().controller : selectedTab?.activeController
		if fromAddressBar {
			controller?.loadFromAddressBar(url)
		} else {
			controller?.load(url)
		}
	}

	func submitNewTabSearch() {
		if let result = selectedNewTabSearchResult {
			performNewTabSearchResult(result)
		}
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
