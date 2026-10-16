import Defaults
import SwiftUI

struct BrowserAddressField: View {
	let browser: Browser
	var usesGlassBackground = false
	var acceptsFocusRequests = true

	init(browser: Browser) {
		self.browser = browser
	}

	init(browser: Browser, usesGlassBackground: Bool) {
		self.browser = browser
		self.usesGlassBackground = usesGlassBackground
	}

	init(browser: Browser, usesGlassBackground: Bool = false, acceptsFocusRequests: Bool) {
		self.browser = browser
		self.usesGlassBackground = usesGlassBackground
		self.acceptsFocusRequests = acceptsFocusRequests
	}

	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@Default(.browserSearchConfiguration) private var searchConfigurationValue
	@Default(.searchSuggestionsEnabled) private var searchSuggestionsEnabled

	private var searchConfiguration: BrowserSearchConfiguration {
		BrowserSearchConfiguration.decode(searchConfigurationValue)
	}

	@State private var addressText = ""
	@State private var addressSelectionID: String?
	@State private var addressRemoteSuggestions: [String] = []
	@State private var addressSuggestionsRequest: BrowserSearchSuggestionsRequest?
	@State private var discoveredSearchEngineTemplate: String?
	@State private var discoveredSearchEngineScope: String?
	@FocusState private var isFocused: Bool

	private var isDimmed: Bool {
		!usesGlassBackground && addressDisplayStyle == .dimmed && !isFocused && !addressText.isEmpty
	}

	private var isSearch: Bool {
		BrowserAddress.isSearchURL(
			browser.selectedTab?.activeController?.url,
			configuration: searchConfiguration,
			isPrivate: browser.isPrivate
		)
	}

	private var addressSuggestionRequest: BrowserSearchSuggestionsRequest {
		let controller = browser.selectedTab?.activeController
		let scope = "address:\(browser.windowID):\(browser.selectedTabID):\(controller?.id.uuidString ?? "none"):\(controller?.navigationIdentifier ?? -1)"
		return BrowserSearchSuggestionsRequest(
			query: addressText.trimmingCharacters(in: .whitespacesAndNewlines),
			generation: browser.addressSearchGeneration,
			scope: scope,
			provider: searchConfiguration.suggestionsProvider(isPrivate: browser.isPrivate) ?? .custom,
			isPrivate: browser.isPrivate,
			configuration: searchConfiguration.encoded,
			suggestionsEnabled: searchSuggestionsEnabled && isFocused && !browser.isShowingNewTab
		)
	}

	private func displayString(for url: URL?, isEditing: Bool = false) -> String {
		if usesGlassBackground, !isEditing {
			return BrowserAddress.domainDisplayString(
				for: url,
				configuration: searchConfiguration,
				isPrivate: browser.isPrivate
			)
		}
		return BrowserAddress.displayString(
			for: url,
			style: addressDisplayStyle,
			isEditing: isEditing,
			configuration: searchConfiguration,
			isPrivate: browser.isPrivate
		)
	}

	private var currentAddressSuggestions: [String] {
		addressSuggestionsRequest == addressSuggestionRequest ? addressRemoteSuggestions : []
	}

	private var addressSuggestionResults: [BrowserSearchResult] {
		browser.searchResults(
			for: addressText,
			includeActions: false,
			remoteSuggestions: currentAddressSuggestions,
			remoteSuggestionRequest: addressSuggestionRequest
		)
	}

	private var showsAddressSuggestions: Bool {
		isFocused
			&& browser.addressFieldIsFocused
			&& !browser.isShowingNewTab
			&& !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& !addressSuggestionResults.isEmpty
	}

	private var searchEngineDiscoveryScope: String? {
		guard !browser.isPrivate, !browser.isShowingNewTab,
		      let tab = browser.selectedTab, tab.internalPage == nil,
		      let controller = tab.activeController,
		      controller.hasCurrentPageDocument, !controller.isLoading,
		      let url = controller.url, url.scheme?.lowercased() == "https"
		else { return nil }
		return "\(tab.id):\(controller.id):\(controller.navigationIdentifier):\(url.absoluteString)"
	}

	private var availableSearchEngineTemplate: String? {
		guard let scope = searchEngineDiscoveryScope, discoveredSearchEngineScope == scope else { return nil }
		return discoveredSearchEngineTemplate
	}

	private func validateSearchEngineMetadata() async {
		discoveredSearchEngineTemplate = nil
		discoveredSearchEngineScope = nil
		guard let scope = searchEngineDiscoveryScope,
		      let webView = browser.selectedTab?.activeController?.webViewIfLoaded else { return }
		do {
			let outcome = try await BrowserSearchSuggestions.discoverOpenSearchTemplate(in: webView)
			guard !Task.isCancelled, searchEngineDiscoveryScope == scope,
			      case let .found(template) = outcome else { return }
			discoveredSearchEngineTemplate = template
			discoveredSearchEngineScope = scope
		} catch {
			// Unsupported or unreachable metadata leaves discovery unavailable.
		}
	}

	private var historySearchRequest: BrowserHistorySearchModel.Request {
		.init(query: isFocused && !browser.isShowingNewTab ? addressText.trimmingCharacters(in: .whitespacesAndNewlines) : "", revision: browser.historyChangeRevision)
	}

	var body: some View {
		HStack(spacing: 6) {
			AddressTextField(
				addressText: $addressText,
				isFocused: $isFocused,
				isDimmed: isDimmed,
				isSearch: isSearch,
				dimmedAddressText: dimmedAddressText,
				onSubmitAddress: submitAddress,
				onCompleteAddress: completeAddress,
				onEscape: {
					if browser.isShowingNewTab {
						browser.newTabSearchSelection = "typed"
					} else {
						addressSelectionID = nil
					}
					isFocused = false
				},
				onMoveSelection: { offset in
					if browser.isShowingNewTab {
						guard !browser.newTabSearchResults.isEmpty else { return false }
						browser.moveNewTabSearchSelection(by: offset)
						return true
					} else {
						return moveAddressSelection(by: offset)
					}
				}
			)
			if let template = availableSearchEngineTemplate {
				Button {
					browser.discoverSearchEngineFromAddressBar(template: template)
				} label: {
					Label("Discover Search Engine", systemImage: "magnifyingglass.circle")
				}
				.accessibilityIdentifier("discover-search-engine")
			}
		}
		.padding(.horizontal, usesGlassBackground ? 10 : 0)
		.frame(height: usesGlassBackground ? BrowserChromeMetrics.topBarRegionHeight : nil)
		.glassEffect(
			usesGlassBackground ? .regular.interactive() : .identity,
			in: Capsule()
		)

		.confirmationDialog(
			"Use this site's search engine?",
			isPresented: Binding(
				get: { browser.pendingSearchEngineDiscovery != nil },
				set: {
					if !$0 {
						browser.pendingSearchEngineDiscovery = nil
					}
				}
			),
			titleVisibility: .visible
		) {
			Button("Use as Search Engine", systemImage: "checkmark", role: .confirm) {
				guard let template = browser.consumeSearchEngineDiscovery() else { return }
				var configuration = searchConfiguration
				configuration.customTemplate = template
				configuration.normalEngine = .custom
				searchConfigurationValue = configuration.encoded
			}
			.buttonStyle(.glassProminent)
			.disabled(!browser.canAcceptSearchEngineDiscovery)
			.accessibilityIdentifier("confirm-search-engine-discovery")
			Button(role: .cancel) {
				browser.pendingSearchEngineDiscovery = nil
			}
		} message: {
			if let template = browser.pendingSearchEngineDiscovery?.template {
				Text(template)
			}
		}
		.onChange(of: addressText) { _, text in
			addressSelectionID = nil
			if browser.isShowingNewTab {
				browser.newTabSearchText = text
			} else {
				browser.addressSearchText = text
			}
		}
		.onChange(of: browser.newTabSearchText) { _, text in
			if browser.isShowingNewTab, addressText != text {
				addressText = text
			}
		}
		.onChange(of: browser.selectedTabID) { _, _ in
			browser.discardStaleSearchEngineDiscovery()
			isFocused = false
			addressSelectionID = nil
			updateForSelectedTab()
		}
		.onChange(of: browser.workspace.selectedSpaceID) { _, _ in
			isFocused = false
			addressSelectionID = nil
			updateForSelectedTab()
		}
		.onChange(of: browser.selectedTab?.activeController?.showsFind) { _, showsFind in
			if showsFind == true {
				isFocused = false
			}
		}
		.onChange(of: browser.addressFocusRequest) { _, _ in
			if acceptsFocusRequests {
				isFocused = true
			} else {
				isFocused = false
			}
		}
		.onChange(of: browser.selectedTab?.peeks.last?.id) { _, _ in
			isFocused = false
			updateAddressFromURL()
		}
		.onChange(of: browser.selectedTab?.activeController?.id) { _, _ in
			browser.discardStaleSearchEngineDiscovery()
			guard !isFocused else { return }
			updateAddressFromURL()
		}
		.onChange(of: browser.selectedTab?.activeController?.url) { _, url in
			browser.discardStaleSearchEngineDiscovery()
			guard !isFocused else { return }
			let next = displayString(for: url)
			guard next != addressText else { return }
			addressText = next
		}
		.onChange(of: addressDisplayStyle) { _, _ in
			guard !isFocused else { return }
			updateAddressFromURL()
		}
		.onChange(of: searchConfigurationValue) { _, _ in
			browser.discardStaleSearchEngineDiscovery()
			guard !isFocused else { return }
			updateAddressFromURL()
		}
		.onChange(of: isFocused) { _, focused in
			browser.addressFieldIsFocused = focused
			if browser.isShowingNewTab {
				addressText = browser.newTabSearchText
				return
			}
			let simpleAddress = displayString(for: browser.selectedTab?.activeController?.url)
			if focused {
				if BrowserSearchMatching.shouldExpandAddressOnFocus(text: addressText, simpleAddress: simpleAddress) {
					addressText = displayString(
						for: browser.selectedTab?.activeController?.url,
						isEditing: true
					)
				}
				return
			}
			addressText = simpleAddress
		}
		.onAppear {
			updateForSelectedTab()
		}
		.onDisappear {
			browser.addressFieldIsFocused = false
		}
		.task(id: historySearchRequest) {
			await browser.historySearch.update(historySearchRequest, scope: .address, visits: browser.historyVisits)
		}
		.task(id: searchEngineDiscoveryScope) {
			await validateSearchEngineMetadata()
		}
	}

	private var dimmedAddressText: AttributedString {
		var text = AttributedString(addressText)
		text.foregroundColor = Color.primary.opacity(0.65)
		guard let url = browser.selectedTab?.activeController?.url else {
			text.foregroundColor = .primary
			return text
		}
		for range in BrowserAddress.primaryTextRanges(
			for: url,
			displayedText: addressText,
			configuration: searchConfiguration,
			isPrivate: browser.isPrivate
		) {
			guard let attributedRange = Range(range, in: text) else { continue }
			text[attributedRange].foregroundColor = .primary
		}
		return text
	}

	private var addressSuggestions: some View {
		let results = addressSuggestionResults
		return ScrollViewReader { proxy in
			List {
				BrowserSearchSuggestionsSection(
					browser: browser,
					results: results,
					query: addressText,
					generation: browser.addressSearchGeneration,
					selectedResultID: addressSelectionID,
					fromNewTab: false,
					onSelect: selectAddressSuggestion
				)
			}
			.listStyle(.sidebar)
			.scrollContentBackground(.hidden)
			.frame(maxWidth: 520)
			.frame(height: min(max(CGFloat(results.count) * 56, 56), 260))
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
			.shadow(radius: 12)
			.onChange(of: addressSelectionID) { _, selection in
				if let selection {
					proxy.scrollTo(selection)
				}
			}
		}
	}

	private func updateForSelectedTab() {
		updateAddressFromURL()
	}

	private func updateAddressFromURL() {
		if browser.isShowingNewTab {
			addressText = browser.newTabSearchText
			return
		}
		let next = displayString(
			for: browser.selectedTab?.activeController?.url,
			isEditing: isFocused
		)
		browser.addressSearchText = next
		guard next != addressText else { return }
		addressText = next
	}

	private func submitAddress() {
		if browser.isShowingNewTab {
			browser.newTabSearchText = addressText
			browser.submitNewTabSearch()
			isFocused = false
			updateAddressFromURL()
			return
		}
		if let selected = browser.searchResults(for: addressText, includeActions: false)
			.first(where: { $0.id == addressSelectionID })
		{
			selectAddressSuggestion(selected)
			return
		}
		guard let destination = BrowserAddress.destination(
			for: addressText,
			configuration: searchConfiguration,
			isPrivate: browser.isPrivate
		) else { return }
		browser.selectedTab?.activeController?.loadFromAddressBar(destination)
		addressText = displayString(for: destination)
		isFocused = false
	}

	private func moveAddressSelection(by offset: Int) -> Bool {
		let results = browser.searchResults(for: addressText, includeActions: false)
		guard !results.isEmpty else { return false }
		let index = results.firstIndex { $0.id == addressSelectionID }
		let next = index.map { ($0 + offset + results.count) % results.count }
			?? (offset > 0 ? 0 : results.count - 1)
		addressSelectionID = results[next].id
		return true
	}

	private func completeAddress() -> Bool {
		let results = browser.searchResults(for: addressText, includeActions: false)
		let query = BrowserSearchMatching.normalized(addressText)
		guard let result = results.first(where: { result in
			guard [.history, .bookmark, .openTab].contains(result.kind),
			      let value = result.destination,
			      let url = URL(string: value),
			      let host = url.host
			else { return false }
			return BrowserSearchMatching.normalized(host).hasPrefix(query)
		}) else { return false }
		addressText = result.destination ?? addressText
		isFocused = true
		return true
	}

	private func selectAddressSuggestion(_ result: BrowserSearchResult) {
		result.perform()
		addressSelectionID = result.id
		isFocused = false
		updateAddressFromURL()
	}
}

private struct AddressTextField: View {
	@Binding var addressText: String
	var isFocused: FocusState<Bool>.Binding
	var isDimmed: Bool
	var isSearch: Bool
	var dimmedAddressText: AttributedString
	var onSubmitAddress: () -> Void
	var onCompleteAddress: () -> Bool
	var onEscape: () -> Void
	var onMoveSelection: (Int) -> Bool

	var body: some View {
		TextField("Search or type a URL", text: $addressText)
			.textFieldStyle(.plain)
			.fontDesign(.monospaced)
			.lineLimit(1)
			.foregroundStyle(isDimmed ? .clear : .primary)
			.padding(.leading, isSearch ? 20 : 0)
			.focused(isFocused)
			.submitLabel(.go)
			.onSubmit(onSubmitAddress)
			.onChange(of: addressText) { _, _ in
				#if os(macOS)
					BrowserPerformanceBenchmark.recordAddressTextChange()
				#endif
			}
			.onKeyPress(.tab) {
				onCompleteAddress() ? .handled : .ignored
			}
			.onKeyPress(.downArrow) {
				onMoveSelection(1) ? .handled : .ignored
			}
			.onKeyPress(.upArrow) {
				onMoveSelection(-1) ? .handled : .ignored
			}
			.onKeyPress(.escape) {
				onEscape()
				return .handled
			}
			.overlay(alignment: .leading) {
				DimmedAddressOverlay(
					isSearch: isSearch,
					isDimmed: isDimmed,
					dimmedAddressText: dimmedAddressText
				)
			}
			.accessibilityLabel("Address")
			.accessibilityIdentifier("browser-address")
	}
}

private struct DimmedAddressOverlay: View {
	var isSearch: Bool
	var isDimmed: Bool
	var dimmedAddressText: AttributedString

	var body: some View {
		HStack(spacing: 6) {
			if isSearch {
				Image(systemName: "magnifyingglass")
					.accessibilityHidden(true)
			}
			if isDimmed {
				Text(dimmedAddressText)
					.fontDesign(.monospaced)
					.lineLimit(1)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}
}
