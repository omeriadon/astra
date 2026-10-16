import Defaults
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NewTabView: View {
	@Bindable var browser: Browser
	@Default(.searchSuggestionsEnabled) private var searchSuggestionsEnabled
	@Default(.browserSearchConfiguration) private var searchConfigurationValue
	@Default(.startPagePreferences) private var startPagePreferencesValue
	@FocusState private var isSearchFocused: Bool
	@Namespace private var transitions
	@AppStorage("astra.newTabBackgroundImage") private var backgroundImagePath = ""
	@State private var choosingBackgroundImage = false
	@State private var recentVisits: [BrowserVisit] = []
	@State private var frequentVisits: [BrowserVisitSummary] = []

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

	private var historySearchRequest: BrowserHistorySearchModel.Request {
		.init(query: browser.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines), revision: browser.historyChangeRevision)
	}

	var body: some View {
		let selectedResultID = browser.selectedNewTabSearchResult?.id
		ZStack(alignment: .bottomTrailing) {
			newTabBackground
		ScrollViewReader { proxy in
			List {
				BrowserSearchSuggestionsSection(
					browser: browser,
					results: browser.newTabSearchText.isEmpty ? [] : browser.newTabSearchResults,
					query: browser.newTabSearchText,
					generation: browser.newTabSearchGeneration,
					selectedResultID: selectedResultID,
					fromNewTab: true,
					onSelect: browser.performNewTabSearchResult
				)
			}
			.listStyle(.sidebar)
			.scrollContentBackground(.hidden)
			.safeAreaBar(edge: .top, spacing: 0) {
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
		}
		.overlay(alignment: .bottomTrailing) {
			backgroundPicker.padding(20)
		}
		#if os(macOS)
		.fileImporter(isPresented: $choosingBackgroundImage, allowedContentTypes: [.image]) { result in
			guard case let .success(url) = result else { return }
			let access = url.startAccessingSecurityScopedResource()
			defer { if access { url.stopAccessingSecurityScopedResource() } }
			let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Astra", isDirectory: true)
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			let target = directory.appendingPathComponent("new-tab-background.\(url.pathExtension)")
			try? FileManager.default.removeItem(at: target)
			if (try? FileManager.default.copyItem(at: url, to: target)) != nil { backgroundImagePath = target.path }
		}
		#endif
		.task(id: browser.quickSearchFocusRequest) {
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
		.task(id: historySearchRequest) {
			await browser.historySearch.update(historySearchRequest, scope: .newTab, visits: browser.historyVisits)
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
	}

	@ViewBuilder
	private var newTabBackground: some View {
		#if os(macOS)
		if !backgroundImagePath.isEmpty, let image = NSImage(contentsOfFile: backgroundImagePath) {
			GeometryReader { geometry in
				Image(nsImage: image).resizable().scaledToFill()
					.frame(width: geometry.size.width, height: geometry.size.height).clipped()
			}
		} else {
			Color(nsColor: .windowBackgroundColor)
		}
		#else
		Color(.systemBackground)
		#endif
	}

	private var backgroundPicker: some View {
		Menu {
			Button("Choose Background Image…", systemImage: "photo") { choosingBackgroundImage = true }
			if !backgroundImagePath.isEmpty {
				Button("Remove Background Image", systemImage: "trash") { backgroundImagePath = "" }
			}
		} label: {
			Image(systemName: "paintpalette").font(.system(size: 15))
				.padding(10)
				.background(.regularMaterial, in: Circle())
		}
		.menuStyle(.borderlessButton)
		.accessibilityLabel("Customize new tab background")
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
										BrowserFavouriteTile(tab: tab, browser: browser, isSelected: browser.selectedTabID == tab.id, navigationNamespace: transitions)
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
						browser.dismissQuickSearch()
						return .handled
					}
					.accessibilityLabel("Search the web, history, or browser actions")
					.accessibilityIdentifier("new-tab-search")
			}
			.padding(14)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
		}
		.padding(.horizontal, 10)
		.padding(.top, 10)
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

#Preview {
	NewTabView(browser: Browser())
}
