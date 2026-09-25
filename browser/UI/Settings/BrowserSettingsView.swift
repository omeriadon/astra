import AuthenticationServices
import Defaults
import SwiftUI

struct BrowserSettingsView: View {
	let browser: Browser
	@State private var sync = BrowserSync.shared
	@Binding var searchText: String
	@Binding var selectedPage: Page
	@Default(.browserTheme) private var theme
	@Environment(\.colorScheme) private var colorScheme
	@Default(.syncServerURL) private var syncServerURL
	@Default(.tabSwitchingOrder) private var tabSwitchingOrder
	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@Default(.peekLevel) private var peekLevel
	@Default(.zoomOutInPeeks) private var zoomOutInPeeks
	@Default(.renameDownloadsWithAppleIntelligence) private var renameDownloadsWithAppleIntelligence

	enum Page {
		case ui
		case account
		#if DEBUG
			case failedWebsiteStates
		#endif
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
				.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
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
			.background(theme.contentShade(for: colorScheme).gradient)

			Divider()

			VStack(alignment: .leading, spacing: 0) {
				Group {
					switch selectedPage {
						case .ui:
							Text("UI")
						case .account:
							Text("Account & Sync")
						#if DEBUG
							case .failedWebsiteStates:
								Text("Failed Website States")
						#endif
					}
				}
				.font(.largeTitle.bold())
				.padding(.horizontal, 24)
				.padding(.top, 12)
				.padding(.bottom, 12)

				List {
					switch selectedPage {
						case .ui:
							Section("Tab Switching") {
								Picker("Control-Tab order", selection: $tabSwitchingOrder) {
									ForEach(TabSwitchingOrder.allCases) { order in
										Text(order.title)
											.tag(order)
									}
								}
								.accessibilityIdentifier("tab-switching-order-picker")
							}

							Section("Address Bar") {
								Picker("Display", selection: $addressDisplayStyle) {
									ForEach(AddressDisplayStyle.allCases) { style in
										Text(style.title)
											.tag(style)
									}
								}
								.accessibilityIdentifier("address-display-style-picker")
							}

							Section("Peek") {
								Picker("Levels", selection: $peekLevel) {
									ForEach(PeekLevel.allCases) { level in
										Text(level.title)
											.tag(level)
									}
								}
								.accessibilityIdentifier("peek-level-picker")

								if peekLevel != .none {
									Toggle("Zoom out in Peeks", isOn: $zoomOutInPeeks)
										.accessibilityIdentifier("zoom-out-in-peeks-toggle")
								}
							}

							Section("Website Data") {
								Button(role: .destructive, action: FaviconStore.shared.clear) {
									Label("Clear All Favicons", systemImage: "trash")
								}
								.disabled(FaviconStore.shared.isEmpty)
								.accessibilityIdentifier("clear-all-favicons")
							}

							Section("Downloads") {
								Toggle("Rename downloads with Apple Intelligence", isOn: $renameDownloadsWithAppleIntelligence)
									.accessibilityLabel("Rename downloads with Apple Intelligence")
									.accessibilityIdentifier("rename-downloads-with-apple-intelligence")
							}

						case .account:
							Section("Account & Sync") {
								TextField("Sync Server URL", text: $syncServerURL)
									.textContentType(.URL)
									.autocorrectionDisabled()
									.disabled(sync.isSignedIn)
									.accessibilityIdentifier("sync-server-url")

								if sync.isSignedIn {
									Label("Signed in with Apple", systemImage: "person.crop.circle.badge.checkmark")
										.accessibilityIdentifier("apple-account-status")

									Button(role: .destructive) {
										sync.signOut()
									} label: {
										Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
									}
									.accessibilityIdentifier("sign-out")
								} else {
									SignInWithAppleButton(.signIn) { _ in
									} onCompletion: { result in
										Task { await sync.signIn(result: result) }
									}
									.frame(height: 44)
									.accessibilityLabel("Sign in with Apple")
									.accessibilityIdentifier("sign-in-with-apple")
								}

								#if DEBUG
									Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
										Task { await sync.syncNow() }
									}
									.disabled(!sync.isSignedIn || sync.isSyncing)
									.accessibilityIdentifier("debug-sync-now")
								#endif

								if sync.isSyncing {
									ProgressView("Syncing")
								} else if let lastSync = sync.lastSync {
									LabeledContent("Last Sync") {
										Text(lastSync, style: .relative)
									}
								}

								if let error = sync.errorDescription {
									Text(error)
										.foregroundStyle(.red)
										.accessibilityIdentifier("sync-error")
								}
							}

						#if DEBUG
							case .failedWebsiteStates:
								Section("Error Pages") {
									ForEach(BrowserNavigationFailure.Kind.allCases, id: \.self) { kind in
										Button {
											browser.openFailedWebsiteState(kind)
										} label: {
											Label {
												Text(kind.title)
											} icon: {
												Image(systemName: kind.systemImage)
											}
										}
										.accessibilityIdentifier("debug-error-\(String(describing: kind))")
									}
								}
						#endif
					}
				}
				.scrollContentBackground(.hidden)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.background(theme.contentShade(for: colorScheme).gradient)
		}
		.frame(minWidth: 650, minHeight: 400)
	}
}
