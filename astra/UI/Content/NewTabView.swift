import Defaults
import SwiftUI

struct NewTabView: View {
	@Bindable var browser: Browser
	@FocusState private var isSearchFocused: Bool

	var body: some View {
		let selectedResultID = browser.selectedNewTabSearchResult?.id
		ScrollViewReader { proxy in
			List {
				Section(browser.newTabSearchText.isEmpty ? "Browser Actions" : "Suggestions") {
					ForEach(browser.newTabSearchResults) { result in
						Button(action: result.perform) {
							Label {
								VStack(alignment: .leading, spacing: 2) {
									Text(verbatim: result.title)
										.lineLimit(1)
									Text(verbatim: result.detail)
										.font(.caption)
										.foregroundStyle(.secondary)
										.lineLimit(1)
								}
								.frame(maxWidth: .infinity, alignment: .leading)
							} icon: {
								Image(systemName: result.symbol)
									.frame(width: 20)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.listRowBackground(Color.primary.opacity(selectedResultID == result.id ? 0.12 : 0))
						.accessibilityLabel("\(result.title), \(result.detail)")
						.accessibilityAddTraits(selectedResultID == result.id ? [.isSelected] : [])
						.accessibilityIdentifier("new-tab-result-\(result.id)")
						.id(result.id)
					}
				}
			}
			.listStyle(.sidebar)
			.scrollContentBackground(.hidden)
			.safeAreaBar(edge: .top) {
				searchHeader
			}
			.onChange(of: selectedResultID) { _, selection in
				if let selection {
					proxy.scrollTo(selection)
				}
			}
		}
		.frame(maxWidth: 680)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.task(id: browser.selectedTabID) {
			isSearchFocused = true
		}
		.onChange(of: browser.addressFocusRequest) { _, _ in
			isSearchFocused = true
		}
		.task(id: browser.newTabSearchText) {
			let query = browser.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !browser.isPrivate, Defaults[.searchSuggestionsEnabled], !query.isEmpty else { return }
			do {
				try await Task.sleep(for: .milliseconds(250))
				let suggestions = try await BrowserSearchSuggestions.fetch(for: query)
				try Task.checkCancellation()
				guard browser.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
				browser.newTabGoogleSuggestions = suggestions
			} catch {
				// Local suggestions and submitting the query remain available offline.
			}
		}
	}

	private var searchHeader: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text(browser.isPrivate ? "Private Browsing" : "astra")
				.font(.largeTitle.bold())
			Text(browser.isPrivate ? "Tabs and website data are discarded when this window closes. Downloaded files are kept." : "Search the web, history, or browser actions")
				.foregroundStyle(.secondary)
			HStack(spacing: 10) {
				Image(systemName: "magnifyingglass")
					.accessibilityHidden(true)
				TextField("Search or type a URL", text: $browser.newTabSearchText)
					.focused($isSearchFocused)
					.textFieldStyle(.plain)
				#if os(macOS)
					.fontDesign(.monospaced)
				#elseif os(iOS)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.keyboardType(.webSearch)
				#endif
					.submitLabel(.go)
					.onSubmit { browser.submitNewTabSearch() }
					.onKeyPress(.downArrow) {
						browser.moveNewTabSearchSelection(by: 1)
						return .handled
					}
					.onKeyPress(.upArrow) {
						browser.moveNewTabSearchSelection(by: -1)
						return .handled
					}
					.onKeyPress(.escape) {
						browser.newTabSearchSelection = "typed"
						return .handled
					}
					.accessibilityLabel("Search the web, history, or browser actions")
					.accessibilityIdentifier("new-tab-search")
			}
			.padding(14)
			.glassEffect(.regular, in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
		}
		.padding(.horizontal, 24)
		.padding(.top, 32)
		.padding(.bottom, 16)
	}
}

#Preview {
	NewTabView(browser: Browser())
}
