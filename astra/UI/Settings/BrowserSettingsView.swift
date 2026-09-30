import Defaults
import SwiftUI

struct BrowserSettingsView: View {
	let browser: Browser
	@Binding var searchText: String
	@Binding var selectedPage: Page
	@State private var sidebarSelection: Page?
	@State private var settingsColumn: NavigationSplitViewColumn = .sidebar
	#if os(iOS)
		@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	#endif
	private var theme: BrowserTheme {
		browser.theme
	}

	enum Page: CaseIterable, Hashable {
		case ui
		case account
		case privacyAndSecurity
		case extensions
		case advanced
		case about
		#if DEBUG
			case failedWebsiteStates
		#endif

		enum Section: String, CaseIterable {
			case ui = "UI"
			case account = "Account"
			case advanced = "Advanced"
		}

		struct Definition {
			let title: String
			let symbol: String
			let section: Section?
			let identifier: String
			let terms: [String]
		}

		var definition: Definition {
			switch self {
				case .ui:
					Definition(
						title: "General",
						symbol: "slider.horizontal.3",
						section: .ui,
						identifier: "settings-ui",
						terms: [
							"Default Browser", "Make Default Browser",
							"Address Bar", "Peek", "Levels",
							"Mini Astra", "links", "cursor", "animation", "shortcut",
							"Zoom out in Peeks", "Downloads", "Rename downloads with Apple Intelligence",
							"Updates", "Automatically check for updates", "Automatically install updates",
						] + AddressDisplayStyle.allCases.map(\.title) + PeekLevel.allCases.map(\.title)
					)
				case .account:
					Definition(
						title: "Account & Sync",
						symbol: "person.crop.circle",
						section: .account,
						identifier: "settings-account",
						terms: [
							"Sync Server URL", "Signed in with Apple", "Sign in with Apple",
							"Sign Out", "Sync Now", "Syncing", "Last Sync",
						]
					)
				case .privacyAndSecurity:
					Definition(
						title: "Privacy and Security",
						symbol: "hand.raised.fill",
						section: .advanced,
						identifier: "settings-privacy-and-security",
						terms: ["Website Data", "Clear All Favicons"]
					)
				case .extensions:
					Definition(
						title: "Extensions",
						symbol: "puzzlepiece.extension",
						section: .advanced,
						identifier: "settings-extensions",
						terms: ["Chrome", "Safari", "Web Store", "Dark Reader", "uBlock Origin Lite", "Import ZIP"]
					)
				case .advanced:
					Definition(
						title: "Advanced",
						symbol: "gearshape.2",
						section: .advanced,
						identifier: "settings-advanced",
						terms: ["Links", "Copy email addresses from mailto links", "Quit", "Press Command-Q twice to quit"]
					)
				case .about:
					Definition(
						title: "About astra",
						symbol: "sparkle",
						section: nil,
						identifier: "settings-about-astra",
						terms: ["Version", "Build", "Check for Updates"]
					)
				#if DEBUG
					case .failedWebsiteStates:
						Definition(
							title: "Failed Website States",
							symbol: "ladybug",
							section: nil,
							identifier: "settings-failed-website-states",
							terms: ["Error Pages"] + BrowserNavigationFailure.Kind.allCases.map { String(localized: $0.title) }
						)
				#endif
			}
		}

		func matches(_ query: String) -> Bool {
			guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
			let metadata = definition
			let text = ([metadata.title, metadata.section?.rawValue ?? ""] + metadata.terms)
				.joined(separator: " ")
			return BrowserSearchMatching.score(query, in: text) > 0
		}
	}

	private var matchingPages: [Page] {
		Page.allCases.filter { $0.matches(searchText) }
	}

	init(browser: Browser, searchText: Binding<String>, selectedPage: Binding<Page>) {
		self.browser = browser
		_searchText = searchText
		_selectedPage = selectedPage
		#if os(iOS)
			let initialPage = selectedPage.wrappedValue == .ui ? nil : selectedPage.wrappedValue
			_sidebarSelection = State(initialValue: initialPage)
			_settingsColumn = State(initialValue: initialPage == nil ? .sidebar : .detail)
		#else
			_sidebarSelection = State(initialValue: selectedPage.wrappedValue)
		#endif
	}

	var body: some View {
		#if os(iOS)
			if horizontalSizeClass == .compact {
				compactSettings
			} else {
				splitSettings
			}
		#else
			splitSettings
		#endif
	}

	#if os(iOS)
		private var compactSettings: some View {
			VStack(spacing: 0) {
				settingsSidebar
			}
		}

	#endif

	private var splitSettings: some View {
		NavigationSplitView(preferredCompactColumn: $settingsColumn) {
			settingsSidebar
				.navigationSplitViewColumnWidth(230)
				.navigationDestination(for: Page.self) { page in
					settingsDestination(for: page)
				}
		} detail: {
			NavigationStack {
				settingsDestination(for: sidebarSelection ?? selectedPage)
			}
		}
		#if os(iOS)
		.containerBackground(.clear, for: .navigationSplitView)
		#endif
		.background {
			BrowserThemeBackground(theme: theme).ignoresSafeArea()
		}
		.onChange(of: sidebarSelection) { _, page in
			if let page, selectedPage != page {
				selectedPage = page
			}
		}
		.onChange(of: selectedPage) { _, page in
			if sidebarSelection != page {
				sidebarSelection = page
				settingsColumn = .detail
			}
		}
		.onChange(of: browser.settingsScrollTarget, initial: true) { _, target in
			if target != nil {
				sidebarSelection = selectedPage
				settingsColumn = .detail
			}
		}
	}

	private var listSelection: Binding<Page?>? {
		#if os(iOS)
			if horizontalSizeClass == .compact {
				return nil
			}
		#endif
		return $sidebarSelection
	}

	private var settingsSidebar: some View {
		List(selection: listSelection) {
			ForEach(Page.Section.allCases, id: \.self) { section in
				let pages = matchingPages.filter { $0.definition.section == section }
				if !pages.isEmpty {
					Section(section.rawValue) {
						ForEach(pages, id: \.self) { page in
							settingsLink(for: page)
						}
					}
				}
			}
			Section {
				ForEach(matchingPages.filter { $0.definition.section == nil }, id: \.self) { page in
					settingsLink(for: page)
				}
			}
		}
		#if os(iOS)
		.listStyle(.insetGrouped)
		#else
		.listStyle(.sidebar)
		#endif
		.scrollContentBackground(.hidden)
		.navigationTitle("Settings")
		#if os(iOS)
			.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Settings")
		#else
			.searchable(text: $searchText, prompt: "Search Settings")
		#endif
		#if os(iOS)
		.toolbar(.visible, for: .navigationBar)
		.containerBackground(.clear, for: .navigation)
		#endif
		.background {
			BrowserThemeBackground(theme: theme).ignoresSafeArea()
		}
		.overlay {
			if matchingPages.isEmpty {
				ContentUnavailableView.search(text: searchText)
			}
		}
	}

	private func settingsDestination(for page: Page) -> some View {
		ScrollViewReader { proxy in
			settingsDetail(for: page)
				.task(id: browser.settingsScrollTarget) {
					guard let target = browser.settingsScrollTarget else { return }
					await Task.yield()
					proxy.scrollTo(target, anchor: .top)
				}
		}
		.navigationTitle(page.definition.title)
		#if os(iOS)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar(.visible, for: .navigationBar)
			.containerBackground(.clear, for: .navigation)
		#endif
			.background {
				BrowserThemeBackground(theme: theme).ignoresSafeArea()
			}
	}

	@ViewBuilder
	private func settingsLink(for page: Page) -> some View {
		#if os(iOS)
			if horizontalSizeClass == .compact {
				NavigationLink {
					settingsDestination(for: page)
						.navigationBarBackButtonHidden(false)
						.onAppear { selectedPage = page }
				} label: {
					Label(page.definition.title, systemImage: page.definition.symbol)
				}
				.accessibilityIdentifier(page.definition.identifier)
			} else {
				selectionLink(for: page)
			}
		#else
			selectionLink(for: page)
		#endif
	}

	private func selectionLink(for page: Page) -> some View {
		NavigationLink(value: page) {
			Label(page.definition.title, systemImage: page.definition.symbol)
		}
		.tag(page)
		.accessibilityIdentifier(page.definition.identifier)
	}

	@ViewBuilder
	private func settingsDetail(for page: Page) -> some View {
		switch page {
			case .ui:
				BrowserGeneralSettingsView()
			case .account:
				BrowserAccountSettingsView()
			case .privacyAndSecurity:
				BrowserPrivacyAndSecuritySettingsView()
			case .advanced:
				BrowserAdvancedSettingsView()
			case .extensions:
				BrowserExtensionsSettingsView(browser: browser)
			case .about:
				AboutView()
			#if DEBUG
				case .failedWebsiteStates:
					BrowserFailedWebsiteStatesSettingsView(browser: browser)
			#endif
		}
	}
}
