import Defaults
import SwiftUI

struct NewTabView: View {
	@Bindable var browser: Browser
	var isQuickSearch = false
	@Default(.searchSuggestionsEnabled) private var searchSuggestionsEnabled
	@Default(.browserSearchConfiguration) private var searchConfigurationValue
	@Default(.startPagePreferences) private var startPagePreferencesValue
	@FocusState private var isSearchFocused: Bool
	@Namespace private var transitions
	@State private var recentVisits: [BrowserVisit] = []
	@State private var frequentVisits: [BrowserVisitSummary] = []
	@State private var showingPreferences = false

	private var searchConfiguration: BrowserSearchConfiguration {
		BrowserSearchConfiguration.decode(searchConfigurationValue)
	}

	private var startPagePreferences: BrowserStartPagePreferences {
		BrowserStartPagePreferences.decode(startPagePreferencesValue) ?? .default
	}

	private var hasStartPageContent: Bool {
		let preferences = startPagePreferences
		return preferences.isVisible(.favourites) && !browser.favouriteTabs.isEmpty
			|| !browser.isPrivate && preferences.isVisible(.recent) && !recentVisits.isEmpty
			|| !browser.isPrivate && preferences.isVisible(.frequent) && !frequentVisits.isEmpty
			|| preferences.isVisible(.recentlyClosed) && !browser.closedHistoryTabs.isEmpty
	}

	private var emptyStartPageDescription: String {
		if BrowserStartPagePreferences.Module.allCases.allSatisfy({ !startPagePreferences.isVisible($0) }) {
			return "Enable a module in Customize Start Page to show it here."
		}
		if browser.isPrivate {
			return "Tabs closed in this private window will appear here."
		}
		return "Favorites and visited pages will appear here."
	}

	var body: some View {
		let selectedResultID = browser.selectedNewTabSearchResult?.id
		ScrollViewReader { proxy in
			List {
				if browser.newTabSearchText.isEmpty, !isQuickSearch {
					startPageModules
					if !hasStartPageContent {
						Section {
							ContentUnavailableView("Your Start Page Is Ready", systemImage: "sparkles", description: Text(emptyStartPageDescription))
						}
					}
				}
				Section(browser.newTabSearchText.isEmpty ? "Browser Actions" : "Suggestions") {
					ForEach(browser.newTabSearchResults) { result in
						let query = browser.newTabSearchText
						let generation = browser.newTabSearchGeneration
						Button {
							browser.performNewTabSearchResult(result)
						} label: {
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
								BrowserSearchResultIcon(result: result)
									.frame(width: 20, height: 20)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.listRowBackground(Color.primary.opacity(selectedResultID == result.id ? 0.12 : 0))
						.accessibilityLabel("\(result.title), \(result.detail)")
						.accessibilityAddTraits(selectedResultID == result.id ? [.isSelected] : [])
						.accessibilityIdentifier("new-tab-result-\(result.id)")
						.id(result.id)
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
										fromNewTab: true
									)
								}
								.accessibilityIdentifier("remove-history-\(result.id)")
							}
						}
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
		.task(id: browser.quickSearchFocusRequest) {
			guard isQuickSearch else { return }
			await Task.yield()
			isSearchFocused = true
		}
		.task(id: browser.selectedTabID) {
			isSearchFocused = true
		}
		.onChange(of: browser.addressFocusRequest) { _, _ in
			isSearchFocused = true
		}
		.onChange(of: browser.historyVisits, initial: true) { _, visits in
			recentVisits = BrowserStartPageProjection.recent(visits, isPrivate: browser.isPrivate)
			frequentVisits = BrowserStartPageProjection.frequent(visits, isPrivate: browser.isPrivate)
		}
		.task(id: suggestionRequest) {
			let request = suggestionRequest
			browser.newTabGoogleSuggestions = []
			guard request.suggestionsEnabled,
			      let provider = searchConfiguration.suggestionsProvider(isPrivate: request.isPrivate),
			      !request.query.isEmpty
			else {
				return
			}
			do {
				try await Task.sleep(for: .milliseconds(250))
				guard !Task.isCancelled,
				      searchSuggestionsEnabled,
				      suggestionRequest == request
				else {
					return
				}
				let suggestions = try await BrowserSearchSuggestions.fetch(
					for: request.query,
					provider: provider
				)
				try Task.checkCancellation()
				guard !Task.isCancelled,
				      searchSuggestionsEnabled,
				      suggestionRequest == request
				else {
					return
				}
				browser.newTabGoogleSuggestions = suggestions
			} catch {
				// Local suggestions and submitting the query remain available offline.
			}
		}
		.sheet(isPresented: $showingPreferences) {
			StartPagePreferencesView(value: $startPagePreferencesValue)
			#if os(iOS)
				.navigationTransition(.zoom(sourceID: "start-page-preferences", in: transitions))
				.presentationDetents([.fraction(0.6)])
			#endif
		}
	}

	@ViewBuilder
	private var startPageModules: some View {
		let preferences = startPagePreferences
		ForEach(preferences.moduleOrder) { module in
			if preferences.isVisible(module) {
				switch module {
					case .favourites:
						if !browser.favouriteTabs.isEmpty {
							Section("Favorites") {
								LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 100))], spacing: 12) {
									ForEach(browser.favouriteTabs) { tab in
										BrowserFavouriteTile(tab: tab, browser: browser, navigationNamespace: transitions)
									}
								}
								.padding(.vertical, 8)
							}
						}
					case .frequent:
						if !browser.isPrivate, !frequentVisits.isEmpty {
							Section("Frequently Visited") {
								ForEach(frequentVisits, id: \.url) { visit in
									StartPageVisitRow(
										title: visit.title,
										url: visit.url,
										count: visit.visitCount,
										session: browser.session,
										open: { browser.openHistoryURL(visit.url, inBackground: false) },
										openInBackground: { browser.openHistoryURL(visit.url, inBackground: true) }
									)
								}
							}
						}
					case .recent:
						if !browser.isPrivate, !recentVisits.isEmpty {
							Section("Recently Visited") {
								ForEach(recentVisits) { visit in
									StartPageVisitRow(
										title: visit.title,
										url: visit.url,
										count: nil,
										session: browser.session,
										open: { browser.openHistoryURL(visit.url, inBackground: false) },
										openInBackground: { browser.openHistoryURL(visit.url, inBackground: true) }
									)
								}
							}
						}
					case .recentlyClosed:
						if !browser.closedHistoryTabs.isEmpty {
							Section("Recently Closed") {
								ForEach(browser.closedHistoryTabs) { tab in
									Button {
										browser.reopenClosedTab(tab.id, inBackground: false)
									} label: {
										Label {
											VStack(alignment: .leading, spacing: 2) {
												Text(verbatim: tab.customTitle ?? tab.pageTitle)
													.lineLimit(1)
												Text(verbatim: tab.url?.host ?? "Recently closed tab")
													.font(.caption)
													.foregroundStyle(.secondary)
													.lineLimit(1)
											}
											.frame(maxWidth: .infinity, alignment: .leading)
										} icon: {
											Image(systemName: "arrow.uturn.backward")
												.frame(width: 20)
										}
									}
									.buttonStyle(.plain)
									.accessibilityLabel("Reopen \(tab.customTitle ?? tab.pageTitle)")
									.accessibilityIdentifier("start-page-closed-\(tab.id.uuidString)")
									.contextMenu {
										Button("Reopen in Background", systemImage: "plus.square.on.square") {
											browser.reopenClosedTab(tab.id, inBackground: true)
										}
										.accessibilityIdentifier("start-page-closed-background-\(tab.id.uuidString)")
									}
								}
							}
						}
				}
			}
		}
	}

	private var suggestionRequest: BrowserSearchSuggestionsRequest {
		BrowserSearchSuggestionsRequest(
			query: browser.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines),
			generation: browser.newTabSearchGeneration,
			scope: "new-tab:\(browser.windowID):\(browser.selectedTabID)",
			provider: searchConfiguration.suggestionsProvider(isPrivate: browser.isPrivate) ?? .custom,
			isPrivate: browser.isPrivate,
			configuration: searchConfiguration.encoded,
			suggestionsEnabled: searchSuggestionsEnabled
		)
	}

	private var searchHeader: some View {
		VStack(alignment: .leading, spacing: 14) {
			if !isQuickSearch {
				HStack {
					Text(browser.isPrivate ? "Private Browsing" : "astra")
						.font(.largeTitle.bold())
					Spacer()
					Button {
						showingPreferences = true
					} label: {
						Label("Customize Start Page", systemImage: "slider.horizontal.3")
					}
					.labelStyle(.iconOnly)
					.accessibilityLabel("Customize Start Page")
					.accessibilityIdentifier("start-page-preferences")
					.matchedTransitionSource(id: "start-page-preferences", in: transitions)
				}
				Text(browser.isPrivate ? "Tabs and website data are discarded when this window closes. Downloaded files are kept." : "Search the web, history, or browser actions")
					.foregroundStyle(.secondary)
			}
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
						if isQuickSearch {
							browser.dismissQuickSearch()
						} else {
							browser.newTabSearchSelection = "typed"
						}
						return .handled
					}
					.accessibilityLabel("Search the web, history, or browser actions")
					.accessibilityIdentifier("new-tab-search")
			}
			.padding(14)
			.glassEffect(.regular, in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
		}
		.padding(.horizontal, 24)
		.padding(.top, isQuickSearch ? 16 : 32)
		.padding(.bottom, 16)
	}
}

private struct StartPageVisitRow: View {
	let title: String
	let url: URL
	let count: Int?
	let session: BrowserWebSession
	let open: () -> Void
	let openInBackground: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Button(action: open) {
				Label {
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: title)
							.lineLimit(1)
						Text(count.map { "\(url.host ?? url.absoluteString) · \($0) visits" } ?? (url.host ?? url.absoluteString))
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				} icon: {
					Group {
						if let favicon = session.favicons.image(for: url) {
							favicon.resizable().scaledToFit()
						} else {
							Image(systemName: "clock.arrow.circlepath")
						}
					}
					.frame(width: 18, height: 18)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open \(title)")
			.accessibilityIdentifier("start-page-visit-\(url.absoluteString)")
			Button(action: openInBackground) {
				Label("Open in Background", systemImage: "plus.square.on.square")
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.accessibilityLabel("Open \(title) in Background")
			.accessibilityIdentifier("start-page-open-background-\(url.absoluteString)")
		}
	}
}

private struct StartPagePreferencesView: View {
	@Binding var value: String
	@Environment(\.dismiss) private var dismiss
	@State private var preferences: BrowserStartPagePreferences
	@State private var containsUnsupportedValue: Bool

	init(value: Binding<String>) {
		_value = value
		let decoded = BrowserStartPagePreferences.decode(value.wrappedValue)
		_preferences = State(initialValue: decoded ?? .default)
		_containsUnsupportedValue = State(initialValue: decoded == nil)
	}

	var body: some View {
		NavigationStack {
			List {
				if containsUnsupportedValue {
					Section {
						Label("These saved settings are unsupported or unreadable and cannot be edited here.", systemImage: "exclamationmark.triangle")
							.foregroundStyle(.secondary)
					}
				}
				Section("Visible Modules") {
					ForEach(Array(preferences.moduleOrder.enumerated()), id: \.element) { index, module in
						HStack {
							Toggle(module.title, isOn: visibilityBinding(for: module))
								.accessibilityIdentifier("start-page-module-\(module.id)")
							Spacer(minLength: 8)
							Button("Move \(module.title) Up", systemImage: "arrow.up") {
								preferences.move(module, by: -1)
								save()
							}
							.labelStyle(.iconOnly)
							.disabled(containsUnsupportedValue || index == 0)
							.accessibilityIdentifier("start-page-module-up-\(module.id)")
							Button("Move \(module.title) Down", systemImage: "arrow.down") {
								preferences.move(module, by: 1)
								save()
							}
							.labelStyle(.iconOnly)
							.disabled(containsUnsupportedValue || index == preferences.moduleOrder.count - 1)
							.accessibilityIdentifier("start-page-module-down-\(module.id)")
						}
						.disabled(containsUnsupportedValue)
					}
				}
			}
			.listStyle(.sidebar)
			.scrollContentBackground(.hidden)
			.navigationTitle("Start Page")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) { dismiss() }
						.accessibilityLabel("Close Start Page Settings")
						.accessibilityIdentifier("close-start-page-settings")
				}
			}
		}
		#if os(macOS)
		.frame(width: 520, height: 360)
		#endif
	}

	private func visibilityBinding(for module: BrowserStartPagePreferences.Module) -> Binding<Bool> {
		Binding(
			get: { preferences.isVisible(module) },
			set: { isVisible in
				if isVisible {
					preferences.hiddenModules.remove(module)
				} else {
					preferences.hiddenModules.insert(module)
				}
				save()
			}
		)
	}

	private func save() {
		guard !containsUnsupportedValue else { return }
		value = preferences.encoded
	}
}

#Preview {
	NewTabView(browser: Browser())
}
