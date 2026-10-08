import Defaults
import SwiftUI

struct BrowserSettingsView: View {
	let browser: Browser
	@Binding var searchText: String
	@Binding var selectedPage: Page
	private var theme: BrowserTheme {
		browser.theme
	}

	nonisolated enum Page: CaseIterable {
		case ui
		case ai
		case account
		case importData
		case privacyAndSecurity
		case extensions
		#if os(macOS)
			case websiteApps
		#endif
		case developer
		case advanced
		case about
		#if DEBUG
			case failedWebsiteStates
		#endif

		nonisolated enum Section: String, CaseIterable {
			case ui = "UI"
			case account = "Account"
			case advanced = "Advanced"
		}

		nonisolated struct Definition {
			let title: String
			let symbol: String
			let section: Section?
			let identifier: String
			let terms: [String]
		}

		@MainActor
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
							"New Tab", "Sidebar Tab", "Spotlight Overlay", "Address Bar", "Page Zoom", "Default Page Zoom", "Reset Default Zoom", "Peek", "Levels",
							"Mini Astra", "links", "cursor", "animation", "shortcut",
							"Zoom out in Peeks", "Downloads",
							"Ask where to save each download", "Download folder", "Choose Folder",
							"Updates", "Automatically check for updates", "Automatically install updates",
						] + AddressDisplayStyle.allCases.map(\.title) + PeekLevel.allCases.map(\.title)
					)
				case .ai:
					Definition(
						title: "AI",
						symbol: "sparkles",
						section: .ui,
						identifier: "settings-ai",
						terms: ["All AI Features", "Rename Downloads", "Rename downloads with Apple Intelligence", "Link Previews", "Today Tabs", "Clean Tab Titles", "Ask in Find", "AI Sidebar", "Usage Log", "Show Usage Log", "Codex", "Claude", "Tokens"]
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
				case .importData:
					Definition(
						title: "Import Browsing Data",
						symbol: "square.and.arrow.down",
						section: .account,
						identifier: "settings-import-data",
						terms: ["Bookmarks", "History", "Profile", "HTML", "JSON"] + BrowserImportSource.allCases.map(\.rawValue)
					)
				case .privacyAndSecurity:
					Definition(
						title: "Privacy and Security",
						symbol: "hand.raised.fill",
						section: .advanced,
						identifier: "settings-privacy-and-security",
						terms: ["Website Data", "Clear All Website Data", "Clear Cache", "Clear All Favicons", "Website Permissions", "Reset All Website Permissions", "Try HTTPS First", "Global Privacy Control", "Browsing History", "Keep History"]
					)
				case .extensions:
					Definition(
						title: "Extensions",
						symbol: "puzzlepiece.extension",
						section: .advanced,
						identifier: "settings-extensions",
						terms: ["Chrome", "Safari", "Web Store", "Dark Reader", "uBlock Origin Lite", "Import ZIP"]
					)
				#if os(macOS)
					case .websiteApps:
						Definition(
							title: "Website Apps",
							symbol: "macwindow.badge.plus",
							section: .advanced,
							identifier: "settings-website-apps",
							terms: ["Dock", "Add Website to Dock", "Standalone", "Launch", "Reveal", "Keep in Dock", "Uninstall"]
						)
				#endif
				case .developer:
					Definition(
						title: "Developer",
						symbol: "chevron.left.forwardslash.chevron.right",
						section: .advanced,
						identifier: "settings-developer",
						terms: ["GitHub", "Repository", "Shorthand", "owner/repository", "Web Inspector", "Safari", "Develop menu", "Developer Mode", "Usage Limits", "Codex", "Claude"]
					)
				case .advanced:
					Definition(
						title: "Advanced",
						symbol: "gearshape.2",
						section: .advanced,
						identifier: "settings-advanced",
						terms: ["Links", "Copy email addresses from mailto links", "Quit", "Press Command-Q twice to quit", "Search", "Show Search Suggestions"]
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

		@MainActor
		func matches(_ query: String) -> Bool {
			guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
			let metadata = definition
			let text = ([metadata.title, metadata.section?.rawValue ?? ""] + metadata.terms)
				.joined(separator: " ")
			return BrowserSearchMatching.score(query, in: text) > 0
		}
	}

	private var matchingPages: [Page] {
		Page.allCases.filter { $0.matches(searchText) && (!browser.isPrivate || $0 == .privacyAndSecurity) }
	}

	var body: some View {
		GeometryReader { geometry in
			ScrollView(.horizontal) {
				HStack(spacing: 0) {
					List {
						if matchingPages.isEmpty {
							Text("No settings found")
								.foregroundStyle(.secondary)
						}

						ForEach(Page.Section.allCases, id: \.self) { section in
							let pages = matchingPages.filter { $0.definition.section == section }
							if !pages.isEmpty {
								Section(section.rawValue) {
									ForEach(pages, id: \.self) { page in
										row(for: page)
									}
								}
							}
						}
					}
					.listStyle(.sidebar)
					.scrollContentBackground(.hidden)
					.safeAreaBar(edge: .top) {
						HStack(spacing: 8) {
							Image(systemName: "magnifyingglass")
								.accessibilityHidden(true)
							TextField("Search Settings", text: $searchText)
								.textFieldStyle(.plain)
								.accessibilityIdentifier("settings-search")
						}
						.padding(.horizontal, 8)
						.padding(.vertical, 6)
						.glassEffect(.regular, in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
						.padding(.horizontal, 12)
						.padding(.top, 12)
						.padding(.bottom, 12)
					}
					.safeAreaBar(edge: .bottom) {
						VStack(spacing: 8) {
							ForEach(matchingPages.filter { $0.definition.section == nil }, id: \.self) { page in
								row(for: page)
							}
						}
						.padding(.bottom, 6)
					}
					.frame(width: BrowserChromeMetrics.settingsSidebarWidth)
					.foregroundStyle(theme.foregroundColor)

					Divider()

					ScrollViewReader { proxy in
						Group {
							switch selectedPage {
								case .ai:
									BrowserAISettingsView()
								case .ui:
									BrowserGeneralSettingsView()
								case .importData:
									BrowserImportView(browser: browser)
								case .account:
									BrowserAccountSettingsView()
								case .privacyAndSecurity:
									BrowserPrivacyAndSecuritySettingsView(session: browser.session)
								case .developer:
									BrowserDeveloperSettingsView()
								case .advanced:
									BrowserAdvancedSettingsView()
								case .extensions:
									BrowserExtensionsSettingsView(browser: browser)
								#if os(macOS)
									case .websiteApps:
										BrowserWebsiteAppsSettingsView()
								#endif
								case .about:
									AboutView()
								#if DEBUG
									case .failedWebsiteStates:
										BrowserFailedWebsiteStatesSettingsView(browser: browser)
								#endif
							}
						}
						.id(selectedPage)
						.task(id: browser.settingsScrollTarget) {
							guard let target = browser.settingsScrollTarget else { return }
							await Task.yield()
							proxy.scrollTo(target, anchor: .top)
						}
					}
					.padding(.horizontal, selectedPage != .about ? BrowserChromeMetrics.settingsDetailPadding : 0)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
					.safeAreaBar(edge: .top) {
						if selectedPage != .about {
							BrowserSettingsTitleView(page: selectedPage)
						}
					}
				}
				.monospaced()
				.frame(
					width: max(geometry.size.width, BrowserChromeMetrics.minimumPageWidth(isSettings: true) - BrowserChromeMetrics.shellEdgePadding * 2),
					height: geometry.size.height,
					alignment: .topLeading
				)
			}
			.accessibilityIdentifier("settings-horizontal-overflow")
		}
	}

	private func row(for page: Page) -> some View {
		let metadata = page.definition
		return BrowserSettingsSidebarRow(
			title: metadata.title,
			symbol: metadata.symbol,
			theme: theme,
			isSelected: selectedPage == page,
			identifier: metadata.identifier
		) {
			browser.settingsScrollTarget = nil
			selectedPage = page
		}
		.listRowInsets(EdgeInsets())
		.listRowBackground(Color.clear)
	}
}
