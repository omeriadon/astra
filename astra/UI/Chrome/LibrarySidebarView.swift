import SwiftUI

#if !ASTRA_WEBSITE_APP_RUNTIME

	struct LibrarySidebarView: View {
		let browser: Browser
		let manager: BrowserDownloadManager
		let theme: BrowserTheme
		@State private var selection = 0

		var body: some View {
			VStack(spacing: 0) {
				Picker("Library", selection: $selection) {
					Text("Downloads").tag(0)
					Text("Easels").tag(1)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				#if os(macOS)
					.padding(.top, BrowserChromeMetrics.topBarRegionHeight)
				#endif
					.accessibilityIdentifier("library-category")
					.padding(8)
				if selection == 0 {
					DownloadsSidebarView(manager: manager, theme: theme)
				} else {
					List {
						Section("Favourites") {
							ForEach(browser.favouriteTabs.filter { $0.internalPage == .easel }) { tab in
								EaselLibraryRow(browser: browser, tab: tab)
							}
						}
						ForEach(browser.workspace.spaces) { space in
							let tabs = space.pinnedTabIDs.compactMap { browser.tab(withID: $0) }.filter { $0.internalPage == .easel }
							if !tabs.isEmpty {
								Section(space.name) {
									ForEach(tabs) { tab in
										EaselLibraryRow(browser: browser, tab: tab)
									}
								}
							}
						}
					}
					.scrollContentBackground(.hidden)
					.overlay {
						if browser.tabs.allSatisfy({ $0.internalPage != .easel }) {
							ContentUnavailableView("No Easels", systemImage: "paintbrush.pointed")
						}
					}
				}
			}
			.accessibilityIdentifier("library-sidebar")
		}
	}

	private struct EaselLibraryRow: View {
		let browser: Browser
		let tab: BrowserTab
		@State private var confirmsDeletion = false

		var body: some View {
			Button(tab.title, systemImage: "paintbrush.pointed") {
				browser.selectTab(tab.id)
			}
			.buttonStyle(.plain)
			.contextMenu {
				Button("Open Beside Current Page", systemImage: "rectangle.split.2x1") {
					browser.openEaselInSplit(tab.id)
				}
				.disabled((browser.selectedTab?.canAppearInEaselSplit != true && !browser.isShowingEaselSplit) || !browser.visibleTabs.contains(where: { $0.id == tab.id }) || browser.selectedTabID == tab.id)
				Button("Delete Easel", systemImage: "trash", role: .destructive) {
					confirmsDeletion = true
				}
			}
			.confirmationDialog("Delete this easel? Its contents will be permanently deleted from your devices and open peeks will close.", isPresented: $confirmsDeletion, titleVisibility: .visible) {
				Button("Delete Easel", systemImage: "trash", role: .destructive) {
					browser.deleteEasel(tab.id, confirmed: true)
				}
			}
			.accessibilityIdentifier("library-easel-\(tab.id.uuidString)")
		}
	}
#endif
