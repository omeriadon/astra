import Defaults
import SwiftUI

struct BrowserAddressField: View {
	let browser: Browser
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
	@FocusState private var isFocused: Bool

	private var isDimmed: Bool {
		addressDisplayStyle == .dimmed && !isFocused && !addressText.isEmpty
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

	private var currentAddressSuggestions: [String] {
		addressSuggestionsRequest == addressSuggestionRequest ? addressRemoteSuggestions : []
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
			PasteButton(payloadType: String.self) { values in
				guard let value = values.first,
				      let destination = BrowserSearchMatching.pastedHTTPURL(value)
			else {
					return
				}
				addressText = destination.absoluteString
				isFocused = true
			}
			.labelStyle(.iconOnly)
			.accessibilityLabel("Paste address")
			.accessibilityIdentifier("paste-address")
			if !browser.isPrivate,
			   let url = browser.selectedTab?.activeController?.url,
			   url.scheme?.lowercased() == "https"
			{
				Button {
					browser.discoverSearchEngineFromAddressBar()
				} label: {
					Label("Discover Search Engine", systemImage: "magnifyingglass.circle")
				}
				.accessibilityIdentifier("discover-search-engine")
			}
		}
		.overlay(alignment: .topLeading) {
			if isFocused, !browser.isShowingNewTab, !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				addressSuggestions
					.offset(y: 38)
			}
		}
		.confirmationDialog(
			"Use this site's search engine?",
			isPresented: Binding(
				get: { browser.pendingSearchEngineDiscovery != nil },
				set: { if !$0 { browser.pendingSearchEngineDiscovery = nil } }
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
			updateForSelectedTab()
		}
		.onChange(of: browser.addressFocusRequest) { _, _ in
			isFocused = true
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
			let next = BrowserAddress.displayString(
				for: url,
				style: addressDisplayStyle,
				isEditing: false,
				configuration: searchConfiguration,
				isPrivate: browser.isPrivate
			)
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
			let simpleAddress = BrowserAddress.displayString(
				for: browser.selectedTab?.activeController?.url,
				style: addressDisplayStyle,
				isEditing: false,
				configuration: searchConfiguration,
				isPrivate: browser.isPrivate
			)
			if focused {
				if BrowserSearchMatching.shouldExpandAddressOnFocus(text: addressText, simpleAddress: simpleAddress) {
					addressText = BrowserAddress.displayString(
						for: browser.selectedTab?.activeController?.url,
						style: addressDisplayStyle,
						isEditing: true,
						configuration: searchConfiguration,
						isPrivate: browser.isPrivate
					)
				}
				return
			}
			addressText = simpleAddress
		}
		.onAppear {
			updateForSelectedTab()
		}
		.task(id: addressSuggestionRequest) {
			let request = addressSuggestionRequest
			addressRemoteSuggestions = []
			addressSuggestionsRequest = nil
			browser.addressSuggestionsRequest = request
			guard isFocused,
			      !browser.isShowingNewTab,
			      request.suggestionsEnabled,
			      let provider = searchConfiguration.suggestionsProvider(isPrivate: request.isPrivate),
			      !request.query.isEmpty,
			      let destination = BrowserAddress.destination(
				for: request.query,
				configuration: searchConfiguration,
				isPrivate: browser.isPrivate
			      ),
			      BrowserAddress.isSearchURL(destination, configuration: searchConfiguration, isPrivate: browser.isPrivate)
			else { return }
			do {
				try await Task.sleep(for: .milliseconds(250))
				guard !Task.isCancelled, request == addressSuggestionRequest else { return }
				let suggestions = try await BrowserSearchSuggestions.fetch(for: request.query, provider: provider)
				try Task.checkCancellation()
				guard !Task.isCancelled, request == addressSuggestionRequest else { return }
				addressRemoteSuggestions = suggestions
				addressSuggestionsRequest = request
			} catch {
				// Local address, bookmark, and history results remain available offline.
			}
		}
	}

	private var dimmedAddressText: AttributedString {
		var text = AttributedString(addressText)
		text.foregroundColor = Color.primary.opacity(0.2)
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
		List(browser.searchResults(
			for: addressText,
			includeActions: false,
			remoteSuggestions: currentAddressSuggestions,
			remoteSuggestionRequest: addressSuggestionRequest
		)) { result in
			let query = addressText
			let generation = browser.addressSearchGeneration
			Button {
				selectAddressSuggestion(result)
			} label: {
				Label {
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: result.title).lineLimit(1)
						Text(verbatim: result.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
					}
				} icon: {
					Image(systemName: result.symbol).frame(width: 20)
				}
			}
			.buttonStyle(.plain)
			.accessibilityLabel("\(result.title), \(result.detail)")
			.accessibilityIdentifier("address-suggestion-\(result.id)")
			.listRowBackground(Color.primary.opacity(addressSelectionID == result.id ? 0.12 : 0))
			.contextMenu {
				if result.kind == .history,
				   let value = result.destination,
				   let url = URL(string: value)
				{
					Button("Remove from History", systemImage: "trash", role: .destructive) {
						browser.removeHistorySuggestion(
							id: result.id,
							url: url,
							query: query,
							generation: generation,
							fromNewTab: false
						)
					}
					.accessibilityIdentifier("remove-history-\(result.id)")
				}
			}
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
		.frame(maxWidth: 520, minHeight: 0, maxHeight: 260)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
		.shadow(radius: 12)
	}

	private func updateForSelectedTab() {
		updateAddressFromURL()
		if browser.selectedTab?.activeController?.url == nil {
			isFocused = true
		}
	}

	private func updateAddressFromURL() {
		if browser.isShowingNewTab {
			addressText = browser.newTabSearchText
			return
		}
		let next = BrowserAddress.displayString(
			for: browser.selectedTab?.activeController?.url,
			style: addressDisplayStyle,
			isEditing: isFocused,
			configuration: searchConfiguration,
			isPrivate: browser.isPrivate
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
		addressText = BrowserAddress.displayString(
			for: destination,
			style: addressDisplayStyle,
			isEditing: false,
			configuration: searchConfiguration,
			isPrivate: browser.isPrivate
		)
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
