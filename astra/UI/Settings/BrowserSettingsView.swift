import Defaults
import SwiftUI

struct BrowserSettingsView: View {
	let browser: Browser
	@Binding var searchText: String
	@Binding var selectedPage: Page
	@Default(.browserTheme) private var theme

	enum Page: CaseIterable {
		case ui
		case account
		case privacyAndSecurity
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
							"Address Bar", "Peek", "Levels",
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
			let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
				.split(whereSeparator: \.isWhitespace)
			guard !words.isEmpty else { return true }
			let metadata = definition
			let text = ([metadata.title, metadata.section?.rawValue ?? ""] + metadata.terms)
				.joined(separator: " ")
				.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
			return words.allSatisfy { text.contains($0) }
		}
	}

	private var matchingPages: [Page] {
		Page.allCases.filter { $0.matches(searchText) }
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
				.padding(.top, !browser.sidebarShown ? 37 : 12)
				.padding(.bottom, 12)
			}
			.safeAreaBar(edge: .bottom) {
				VStack(spacing: 8) {
					ForEach(matchingPages.filter { $0.definition.section == nil }, id: \.self) { page in
						row(for: page)
					}
				}
				.padding(.bottom, 16)
			}
			.frame(width: 230)
			.foregroundStyle(theme.foregroundColor)

			Divider()

			Group {
				switch selectedPage {
					case .ui:
						BrowserGeneralSettingsView()
					case .account:
						BrowserAccountSettingsView()
					case .privacyAndSecurity:
						BrowserPrivacyAndSecuritySettingsView()
					case .about:
						AboutView()
					#if DEBUG
						case .failedWebsiteStates:
							BrowserFailedWebsiteStatesSettingsView(browser: browser)
					#endif
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
		.frame(minWidth: 650, minHeight: 400)
		.monospaced()
	}

	private func row(for page: Page) -> some View {
		let metadata = page.definition
		return BrowserSettingsSidebarRow(
			title: metadata.title,
			symbol: metadata.symbol,
			isSelected: selectedPage == page,
			identifier: metadata.identifier
		) {
			selectedPage = page
		}
		.listRowInsets(EdgeInsets())
		.listRowBackground(Color.clear)
	}
}
