import Defaults
import SwiftUI

struct BrowserSettingsView: View {
	let browser: Browser
	@Binding var searchText: String
	@Binding var selectedPage: Page
	private var theme: BrowserTheme {
		browser.theme
	}

	enum Page: CaseIterable {
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
							"Ask where to save each download", "Download folder", "Choose Folder",
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
			.frame(width: 230)
			.foregroundStyle(theme.foregroundColor)

			Divider()

			ScrollViewReader { proxy in
				Group {
					switch selectedPage {
						case .ui:
							BrowserGeneralSettingsView()
						case .account:
							BrowserAccountSettingsView()
						case .privacyAndSecurity:
							BrowserPrivacyAndSecuritySettingsView(session: browser.session)
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
				.id(selectedPage)
				.task(id: browser.settingsScrollTarget) {
					guard let target = browser.settingsScrollTarget else { return }
					await Task.yield()
					proxy.scrollTo(target, anchor: .top)
				}
			}
			.padding(.horizontal, selectedPage != .about ? 16 : 0)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.safeAreaBar(edge: .top) {
				if selectedPage != .about {
					BrowserSettingsTitleView(page: selectedPage)
				}
			}
		}
		.monospaced()
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
