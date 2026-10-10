#if os(iOS)
	import SwiftUI

	struct CompactBrowserShell: View {
		let browser: Browser
		@State private var downloads = BrowserDownloadManager.shared
		@State private var navigation = CompactBrowserNavigation()
		@State private var showsDownloads = false
		@Namespace private var presentations

		var body: some View {
			GeometryReader { systemGeometry in
				NavigationStack {
					ZStack {
						background
						if showsDownloads {
							DownloadsSidebarView(manager: downloads, theme: browser.theme)
						} else {
							ShellSidebarListView(
								browser: browser,
								space: browser.selectedSpace,
								theme: browser.theme,
								favouriteTabIDs: browser.workspace.favouriteTabIDs,
								onSelectTab: { id in showPage(from: id.uuidString) },
								onNewTab: { showPage(from: "sidebar-new-tab") },
								navigationNamespace: presentations
							)
						}
					}
					.foregroundStyle(browser.theme.foregroundColor)
					.matchedTransitionSource(id: "sidebar", in: presentations)
					.navigationTitle(showsDownloads ? "Downloads" : browser.selectedSpace.name)
					.navigationDestination(isPresented: $navigation.showsPage) {
						page(systemInsets: systemGeometry.safeAreaInsets)
							.navigationBarBackButtonHidden()
							.navigationTitle(browser.selectedTab?.title ?? "New Tab")
							.navigationBarTitleDisplayMode(.inline)
							.toolbar(browser.selectedTab?.internalPage == nil ? .hidden : .visible, for: .navigationBar)
							.navigationTransition(.zoom(sourceID: navigation.sourceID, in: presentations))
					}
					.toolbar {
						if !navigation.showsPage {
							ToolbarItem(placement: .topBarTrailing) {
								browserActions
							}
							ToolbarItem(placement: .bottomBar) {
								Button(showsDownloads ? "Show Tabs" : "Downloads", systemImage: downloads.buttonSymbol) {
									showsDownloads.toggle()
								}
								.accessibilityValue(downloads.activeProgress.map { "\(Int($0 * 100)) percent" } ?? "No active downloads")
								.accessibilityIdentifier("compact-downloads")
							}
							ToolbarSpacer(.flexible, placement: .bottomBar)
							ToolbarItem(placement: .bottomBar) {
								BrowserSpacesBar(
									browser: browser,
									onOpenPage: { showPage(from: "sidebar") }
								)
							}
							ToolbarSpacer(.flexible, placement: .bottomBar)
							ToolbarItem(placement: .bottomBar) {
								newTabButton
									.matchedTransitionSource(id: "toolbar-new-tab", in: presentations)
							}
						}
					}
					.toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
				}
				.tint(browser.theme.foregroundColor)
				.preferredColorScheme(browser.theme.foregroundColor == .white ? .dark : .light)
				.onOpenURL { url in
					guard url.scheme == "http" || url.scheme == "https" else { return }
					showPage(from: "sidebar")
				}
			}
		}

		private var background: some View {
			BrowserThemeBackground(theme: browser.theme)
				.ignoresSafeArea()
		}

		private func page(systemInsets: EdgeInsets) -> some View {
			GeometryReader { geometry in
				let isWebsite = browser.selectedTab?.internalPage == nil && browser.selectedTab?.activeController?.url != nil
				let webInsets = isWebsite ? EdgeInsets(
					top: max(systemInsets.top, geometry.safeAreaInsets.top),
					leading: max(systemInsets.leading, geometry.safeAreaInsets.leading),
					bottom: max(systemInsets.bottom, geometry.safeAreaInsets.bottom),
					trailing: max(systemInsets.trailing, geometry.safeAreaInsets.trailing)
				) : EdgeInsets()
				ZStack {
					background
					BrowserPageView(
						browser: browser,
						cornerRadius: 0,
						insets: BrowserViewportInsets(obscured: webInsets, minimum: webInsets, maximum: webInsets)
					)
					.ignoresSafeArea(.container, edges: isWebsite ? .vertical : [])
				}
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) {
						if let controller = browser.selectedTab?.activeController, browser.selectedTab?.internalPage == nil {
							BrowserAdBlockingButton(controller: controller)
						}
					}
					ToolbarItem(placement: .bottomBar) {
						HStack(spacing: 8) {
							Button("Sidebar", systemImage: "sidebar.leading") {
								navigation.showsPage = false
							}
							.labelStyle(.iconOnly)
							.frame(width: 44, height: 44)
							.buttonStyle(.glass)
							.buttonBorderShape(.circle)
							.accessibilityIdentifier("compact-sidebar")
							.contextMenu { browserActionsContent }

							addressCapsule
								.frame(maxWidth: .infinity)
								.glassEffect(.regular, in: Capsule())
							if let controller = browser.selectedTab?.activeController, browser.selectedTab?.internalPage == nil {
								BrowserTranslationButton(browser: browser, controller: controller)
									.frame(width: 44, height: 44)
									.buttonBorderShape(.circle)
							}

							newTabButton
								.labelStyle(.iconOnly)
								.frame(width: 44, height: 44)
								.buttonStyle(.glass)
								.buttonBorderShape(.circle)
						}
						.frame(width: max(0, geometry.size.width - 48))
					}
					.sharedBackgroundVisibility(.hidden)
				}
				.toolbarBackground(.hidden, for: .bottomBar)
			}
		}

		private var addressCapsule: some View {
			HStack(spacing: 0) {
				if let controller = browser.selectedTab?.activeController, browser.selectedTab?.internalPage == nil {
					if controller.canGoBack {
						Button("Back", systemImage: "chevron.backward", action: controller.goBack)
							.frame(width: 44, height: 44)
							.accessibilityIdentifier("browser-back")
							.contextMenu {
								ForEach((0 ..< controller.historyIndex).reversed(), id: \.self) { index in
									Button(controller.history[index].absoluteString, systemImage: "clock.arrow.circlepath") {
										controller.go(toHistoryIndex: index)
									}
								}
							}
					}
					if controller.canGoForward {
						Button("Forward", systemImage: "chevron.forward", action: controller.goForward)
							.frame(width: 44, height: 44)
							.accessibilityIdentifier("browser-forward")
							.contextMenu {
								ForEach(min(controller.historyIndex + 1, controller.history.count) ..< controller.history.count, id: \.self) { index in
									Button(controller.history[index].absoluteString, systemImage: "clock.arrow.circlepath") {
										controller.go(toHistoryIndex: index)
									}
								}
							}
					}
				}
				if browser.selectedTab?.internalPage == nil, !browser.isShowingNewTab {
					BrowserAddressField(browser: browser)
						.frame(maxWidth: .infinity)
						.padding(.horizontal, 12)
				} else {
					Text(verbatim: browser.selectedTab?.title ?? "New Tab")
						.lineLimit(1)
						.frame(maxWidth: .infinity)
				}
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.frame(height: 44)
			.overlay(alignment: .bottom) {
				if let controller = browser.selectedTab?.activeController {
					BrowserLoadingBar(isLoading: controller.isLoading, estimatedProgress: controller.estimatedProgress, theme: browser.theme)
						.frame(height: 2)
				}
			}
			.contextMenu {
				if let controller = browser.selectedTab?.activeController, browser.selectedTab?.internalPage == nil {
					Button(controller.isLoading ? "Stop Loading" : "Reload", systemImage: controller.isLoading ? "xmark" : "arrow.clockwise") {
						if controller.isLoading {
							controller.stopLoading()
						} else {
							controller.reload()
						}
					}
					Button("Force Reload", systemImage: "arrow.trianglehead.2.clockwise.rotate.90", action: controller.reloadFromOrigin)
					Button(controller.isZapping ? "Cancel Zap" : "Zap Element", systemImage: "bolt.slash", action: controller.toggleZap)
					ShellExtensionControls(browser: browser, theme: browser.theme)
				}
				browserActionsContent
			}
		}

		private var browserActions: some View {
			Menu("Browser Actions", systemImage: "ellipsis") {
				browserActionsContent
			}
			.accessibilityIdentifier("compact-browser-actions")
		}

		@ViewBuilder
		private var browserActionsContent: some View {
			Button("Settings", systemImage: "gearshape") { openPage(.settings) }
			Button("History", systemImage: "clock.arrow.circlepath") { openPage(.history) }
			Button("Bookmarks", systemImage: "bookmark") { openPage(.bookmarks) }
			Button("Edit Space", systemImage: "paintpalette") { openPage(.themeEditor) }
			Button("New Space", systemImage: "plus.rectangle.on.rectangle") { browser.createSpace() }
			Button("Bookmark Page", systemImage: "bookmark.badge.plus") { browser.bookmarkSelectedPage() }
				.disabled(browser.selectedTab?.activeController?.url == nil)
			Button("Downloads", systemImage: downloads.buttonSymbol) {
				showsDownloads = true
				navigation.showsPage = false
			}
			Divider()
			Button("Duplicate Tab", systemImage: "plus.square.on.square") {
				if browser.duplicateTab(browser.selectedTabID) != nil {
					showPage(from: "sidebar")
				}
			}
			.disabled(browser.selectedTab?.internalPage != nil)
			Button("Reopen Closed Tab", systemImage: "arrow.uturn.backward") {
				browser.reopenLastClosedTab()
				showPage(from: "sidebar")
			}
			.disabled(browser.closedHistoryTabs.isEmpty)
			Button("Close Tab", systemImage: "xmark", role: .destructive) {
				browser.closeTab(browser.selectedTabID)
			}
		}

		private var newTabButton: some View {
			Button("New Tab", systemImage: "plus") {
				browser.addTab()
				showPage(from: "toolbar-new-tab")
			}
			.accessibilityIdentifier("compact-new-tab")
		}

		private func openPage(_ page: BrowserInternalPage) {
			browser.openInternalPage(page)
			showPage(from: "sidebar")
		}

		private func showPage(from sourceID: String) {
			navigation.open(from: sourceID)
		}
	}

	#Preview {
		CompactBrowserShell(browser: Browser())
	}
#endif
