import Defaults
import SwiftUI

struct BrowserSettingsView: View {
	let browser: Browser
	@Binding var searchText: String
	@Binding var selectedPage: Page
	@Default(.browserTheme) private var theme
	@Environment(\.colorScheme) private var colorScheme

	enum Page {
		case ui
		case account
		#if DEBUG
			case failedWebsiteStates
		#endif
	}

	private var selectedPageTitle: LocalizedStringKey {
		switch selectedPage {
			case .ui: "UI"
			case .account: "Account & Sync"
			#if DEBUG
				case .failedWebsiteStates: "Failed Website States"
			#endif
		}
	}

	private func matches(_ title: String, section: String) -> Bool {
		searchText.isEmpty
			|| title.localizedCaseInsensitiveContains(searchText)
			|| section.localizedCaseInsensitiveContains(searchText)
	}

	var body: some View {
		HStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 0) {
				HStack(spacing: 8) {
					Image(systemName: "magnifyingglass")
						.accessibilityHidden(true)
					TextField("Search Settings", text: $searchText)
						.textFieldStyle(.plain)
						.accessibilityIdentifier("settings-search")
				}
				.padding(8)
				.glassEffect(.regular, in: Capsule())
				.padding(.horizontal, 12)
				.padding(.top, 12)
				.padding(.bottom, 20)

				if matches("General", section: "UI") {
					Text("UI")
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.leading, 20)
						.padding(.bottom, 6)

					BrowserSettingsSidebarRow(
						title: "General",
						symbol: "slider.horizontal.3",
						isSelected: selectedPage == .ui,
						identifier: "settings-ui"
					) {
						selectedPage = .ui
					}
				}

				if matches("Account & Sync", section: "Account") {
					Text("Account")
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.leading, 20)
						.padding(.top, 18)
						.padding(.bottom, 6)

					BrowserSettingsSidebarRow(
						title: "Account & Sync",
						symbol: "person.crop.circle",
						isSelected: selectedPage == .account,
						identifier: "settings-account"
					) {
						selectedPage = .account
					}
				}

				Spacer(minLength: 20)

				#if DEBUG
					if matches("Failed Website States", section: "Debug") {
						Text("Debug")
							.font(.caption)
							.foregroundStyle(.secondary)
							.padding(.leading, 20)
							.padding(.bottom, 6)

						BrowserSettingsSidebarRow(
							title: "Failed Website States",
							symbol: "ladybug",
							isSelected: selectedPage == .failedWebsiteStates,
							identifier: "settings-failed-website-states"
						) {
							selectedPage = .failedWebsiteStates
						}
						.padding(.bottom, 16)
					}
				#endif
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
					#if DEBUG
						case .failedWebsiteStates:
							BrowserFailedWebsiteStatesSettingsView(browser: browser)
					#endif
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.safeAreaBar(edge: .top) {
				Text(selectedPageTitle)
					.monospaced()
					.font(.largeTitle.bold())
					.contentTransition(.interpolate)
					.animation(.smooth, value: selectedPage)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 24)
					.padding(.top, 12)
					.padding(.bottom, 12)
			}
		}
		.frame(minWidth: 650, minHeight: 400)
	}
}
