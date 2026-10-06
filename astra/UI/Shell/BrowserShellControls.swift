import Defaults
import SwiftUI
import WebKit

struct ShellSidebarListView: View {
	let browser: Browser
	let space: BrowserSpace
	let theme: BrowserTheme
	var onSelectTab: ((UUID) -> Void)?
	var onNewTab: (() -> Void)?
	var navigationNamespace: Namespace.ID?
	@Namespace private var sidebarTransitions
	#if os(macOS)
		@State private var tabDrag = BrowserTabDragCoordinator.shared
	#endif
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		// Single O(n) lookup + filtered lists per sidebar render instead of
		// O(n²) tabs.first scans inside every row.
		let tabsByID = browser.tabsByID
		let pinnedTabs = space.pinnedTabIDs.compactMap { tabsByID[$0] }
		let folderTabIDs = Set(space.pinnedFolders.flatMap(\.tabIDs))
		let ungroupedPinnedTabs = pinnedTabs.filter { !folderTabIDs.contains($0.id) }
		let pinnedSet = Set(space.pinnedTabIDs)
		let normalTabs = space.tabIDs.filter { !pinnedSet.contains($0) }.compactMap { tabsByID[$0] }
		let normalIDSet = Set(normalTabs.map(\.id))
		let normalIndexes = Dictionary(uniqueKeysWithValues: normalTabs.enumerated().map { ($0.element.id, $0.offset) })
		let groupedIDs = Set(space.todayTabGroups.flatMap(\.tabIDs))
		let ungroupedNormalTabs = normalTabs.enumerated().filter { !groupedIDs.contains($0.element.id) }
		let isActiveSpace = space.id == browser.workspace.selectedSpaceID
		let selectedID = browser.selectedTabID
		return GeometryReader { geometry in
			ScrollViewReader { reader in
				ScrollView {
					LazyVStack(spacing: onSelectTab == nil ? 2 : 8) {
						if !browser.favouriteTabs.isEmpty {
							LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
								ForEach(browser.favouriteTabs) { tab in
									BrowserFavouriteTile(tab: tab, browser: browser, onSelectTab: onSelectTab, navigationNamespace: navigationNamespace ?? sidebarTransitions)
										.equatable()
								}
							}
							.padding(.bottom, 12)
							#if os(macOS)
								.background {
									BrowserDropZone(browser: browser, area: .favourite, spaceID: nil, beforeTabID: nil)
								}
							#endif
						}
						#if os(macOS)
							if browser.favouriteTabs.isEmpty, tabDrag.activeTabID != nil {
								Color.clear
									.frame(height: 34)
									.background {
										BrowserDropZone(browser: browser, area: .favourite, spaceID: nil, beforeTabID: nil)
									}
							}
						#endif

						if !pinnedTabs.isEmpty || !space.pinnedFolders.isEmpty {
							VStack(spacing: 2) {
								HStack {
									Text("Pinned Tabs")
										.font(.caption)
									Spacer()
									Button("New Folder", systemImage: "folder.badge.plus") {
										browser.createPinnedFolder()
									}
									.labelStyle(.iconOnly)
									.accessibilityIdentifier("new-pinned-folder")
								}
								ForEach(space.pinnedFolders) { folder in
									PinnedFolderRow(folder: folder, browser: browser, tabsByID: tabsByID, selectedID: selectedID, isActiveSpace: isActiveSpace, normalCount: normalTabs.count, onSelectTab: onSelectTab, navigationNamespace: navigationNamespace ?? sidebarTransitions)
								}
								ForEach(ungroupedPinnedTabs) { tab in
									BrowserTabRow(tab: tab, browser: browser, isSelected: isActiveSpace && selectedID == tab.id, tabIndex: nil, normalCount: normalTabs.count, pinned: true, onSelectTab: onSelectTab, navigationNamespace: navigationNamespace ?? sidebarTransitions)
										.equatable()
										.id(tab.id)
								}
							}
							#if os(macOS)
							.background {
								BrowserDropZone(browser: browser, area: .pinned, spaceID: browser.workspace.selectedSpaceID, beforeTabID: nil)
							}
							#endif
						}
						if pinnedTabs.isEmpty, space.pinnedFolders.isEmpty {
							Button("New Pinned Folder", systemImage: "folder.badge.plus") {
								browser.createPinnedFolder()
							}
							.buttonStyle(.plain)
							.accessibilityIdentifier("new-pinned-folder")
						}
						#if os(macOS)
							if space.pinnedTabIDs.isEmpty, tabDrag.activeTabID != nil {
								Color.clear
									.frame(height: 28)
									.background {
										BrowserDropZone(browser: browser, area: .pinned, spaceID: browser.workspace.selectedSpaceID, beforeTabID: nil)
									}
							}
						#endif
						BrowserAITabDivider(browser: browser, space: space, tabs: normalTabs)
						VStack(spacing: 2) {
							ForEach(space.todayTabGroups) { group in
								let groupTabs = group.tabIDs.compactMap { tabsByID[$0] }.filter { normalIDSet.contains($0.id) }
								if !groupTabs.isEmpty {
									Text(group.name)
										.font(.caption.weight(.semibold))
										.frame(maxWidth: .infinity, alignment: .leading)
										.padding(.horizontal, 10)
										.padding(.top, 8)
									ForEach(groupTabs) { tab in
										BrowserTabRow(tab: tab, browser: browser, isSelected: isActiveSpace && selectedID == tab.id, tabIndex: normalIndexes[tab.id], normalCount: normalTabs.count, pinned: false, onSelectTab: onSelectTab, navigationNamespace: navigationNamespace ?? sidebarTransitions)
											.equatable()
											.id(tab.id)
									}
								}
							}
							ForEach(ungroupedNormalTabs, id: \.element.id) { index, tab in
								BrowserTabRow(tab: tab, browser: browser, isSelected: isActiveSpace && selectedID == tab.id, tabIndex: index, normalCount: normalTabs.count, pinned: false, onSelectTab: onSelectTab, navigationNamespace: navigationNamespace ?? sidebarTransitions)
									.equatable()
									.id(tab.id)
							}
							ShellNewTabButton(browser: browser, theme: theme, onNewTab: onNewTab)
								.matchedTransitionSource(id: "sidebar-new-tab", in: navigationNamespace ?? sidebarTransitions)
						}
						#if os(macOS)
						.background {
							BrowserDropZone(browser: browser, area: .normal, spaceID: browser.workspace.selectedSpaceID, beforeTabID: nil)
						}
						#endif
					}
					.padding(.horizontal, onSelectTab == nil ? BrowserChromeMetrics.shellEdgePadding : 16)
					.padding(.top, 4)
					.padding(.bottom, 48)
					.frame(minHeight: geometry.size.height, alignment: .top)
				}
				.onChange(of: selectedID, initial: true) { oldID, id in
					// Only scroll the active space's list; the swipe-preview
					// copy has allowsHitTesting(false) and no reader anchor.
					guard isActiveSpace else { return }
					// Initial layout and disk restoration should settle without a scroll animation.
					let animate = !reduceMotion && oldID != id && tabsByID[oldID] != nil
					withAnimation(animate ? .smooth(duration: 0.25) : nil) {
						reader.scrollTo(id, anchor: .center)
					}
				}
			}
		}
	}
}

private struct PinnedFolderRow: View {
	let folder: PinnedTabFolder
	let browser: Browser
	let tabsByID: [UUID: BrowserTab]
	let selectedID: UUID
	let isActiveSpace: Bool
	let normalCount: Int
	var onSelectTab: ((UUID) -> Void)?
	let navigationNamespace: Namespace.ID
	@State private var isExpanded = true
	@State private var isRenaming = false
	@State private var name = ""

	var body: some View {
		VStack(spacing: 2) {
			Button {
				isExpanded.toggle()
			} label: {
				Label(folder.name, systemImage: isExpanded ? "folder.fill" : "folder")
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.buttonStyle(.plain)
			.accessibilityIdentifier("pinned-folder-\(folder.id.uuidString)")
			.contextMenu {
				Button("Rename Folder", systemImage: "pencil") {
					name = folder.name
					isRenaming = true
				}
				Button("Delete Folder", systemImage: "trash", role: .destructive) {
					browser.deletePinnedFolder(folder.id)
				}
			}
			.alert("Rename Folder", isPresented: $isRenaming) {
				TextField("Folder Name", text: $name)
				Button("Save", systemImage: "checkmark", role: .confirm) {
					browser.renamePinnedFolder(folder.id, to: name)
				}
				Button(role: .cancel) {}
			}
			if isExpanded {
				ForEach(folder.tabIDs.compactMap { tabsByID[$0] }) { tab in
					BrowserTabRow(tab: tab, browser: browser, isSelected: isActiveSpace && selectedID == tab.id, tabIndex: nil, normalCount: normalCount, pinned: true, onSelectTab: onSelectTab, navigationNamespace: navigationNamespace)
						.equatable()
						.padding(.leading, 12)
						.id(tab.id)
				}
			}
		}
	}
}

struct ShellTopBarView: View {
	let browser: Browser
	let theme: BrowserTheme
	let sidebarShown: Bool
	let topBarColorScheme: ColorScheme
	let transitionFromTheme: BrowserTheme?
	let transitionToTheme: BrowserTheme?
	let themeBlend: Double
	var isCompact = false

	var body: some View {
		if browser.selectedTab?.internalPage == nil, !browser.isShowingNewTab {
			websiteControls
				.transition(.identity)
				.frame(height: isCompact ? BrowserChromeMetrics.topBarRegionHeight * 2 : BrowserChromeMetrics.topBarRegionHeight)
				.background {
					if let transitionFromTheme {
						transitionFromTheme.tabColor
							.opacity(1 - themeBlend)
							.overlay((transitionToTheme ?? theme).tabColor.opacity(themeBlend))
					} else {
						theme.tabColor
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: sidebarShown ? BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar : BrowserChromeMetrics.tabWindowCornerRadiusWithoutSidebar))
				.padding([.top, .horizontal], sidebarShown ? BrowserChromeMetrics.shellEdgePadding : 0)
		}
	}

	private var websiteControls: some View {
		Group {
			if isCompact {
				VStack(spacing: 0) {
					BrowserAddressField(browser: browser)
						.frame(height: BrowserChromeMetrics.topBarRegionHeight)
					ScrollView(.horizontal) {
						HStack(spacing: 10) {
							ShellWebsiteNavigationControls(browser: browser, theme: theme)
							ShellExtensionControls(browser: browser, theme: theme)
						}
						.frame(height: BrowserChromeMetrics.topBarRegionHeight)
					}
					.scrollIndicators(.hidden)
				}
			} else {
				HStack(spacing: 10) {
					ShellWebsiteNavigationControls(browser: browser, theme: theme)
					BrowserAddressField(browser: browser)
					Spacer(minLength: 0)
					ShellExtensionControls(browser: browser, theme: theme)
				}
			}
		}
		.padding(
			.leading,
			sidebarShown ? 10 : BrowserChromeMetrics.persistentControlsAreaWidth
		)
		.frame(height: isCompact ? BrowserChromeMetrics.topBarRegionHeight * 2 : BrowserChromeMetrics.topBarRegionHeight)
		.frame(maxWidth: .infinity, alignment: .leading)
		#if os(macOS)
			.background {
				NonDraggableTitlebarRegion()
			}
		#endif
			.environment(\.colorScheme, topBarColorScheme)
			.overlay(alignment: .bottom) {
				if let controller = browser.selectedTab?.activeController {
					ShellTopBarLoadingBar(
						controller: controller,
						theme: theme,
						tabID: browser.selectedTabID
					)
				}
			}
	}
}

private struct ShellWebsiteNavigationControls: View {
	let browser: Browser
	let theme: BrowserTheme

	var body: some View {
		if let controller = browser.selectedTab?.activeController {
			BrowserNavigationControls(controller: controller)
				.controlSize(.regular)
				.labelStyle(.iconOnly)
				.buttonSizing(.fitted)
				.buttonStyle(.bordered)
				.foregroundStyle(theme.foregroundColor)
				.id(ObjectIdentifier(controller))
			BrowserTranslationButton(browser: browser, controller: controller)
			if !browser.isPrivate, Defaults[.aiSidebar] {
				Button("AI Sidebar", systemImage: "bubble.left.and.text.bubble.right") {
					browser.showsAISidebar.toggle()
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.bordered)
				.accessibilityIdentifier("ai-sidebar-toggle")
			}
		}
	}
}

struct ShellExtensionControls: View {
	let browser: Browser
	let theme: BrowserTheme
	@State private var extensions = BrowserExtensionManager.shared

	var body: some View {
		if !browser.isPrivate {
			if let listing = browser.selectedTab?.activeController?.url,
			   ChromeExtensionPackage.extensionID(from: listing) != nil
			{
				Button("Install Extension", systemImage: "square.and.arrow.down") {
					Task { await extensions.installFromChromeStore(listing) }
				}
				.disabled(extensions.isInstallingFromStore)
				.accessibilityIdentifier("install-chrome-store-extension")
			}
			let _ = extensions.actionsRevision
			ForEach(extensions.loadedNames().filter { extensions.isPinned($0) }, id: \.self) { name in
				let action = extensions.action(for: name, in: browser)
				Button {
					extensions.performAction(name, in: browser)
				} label: {
					#if os(macOS)
						if let icon = action?.icon(for: CGSize(width: 18, height: 18)) {
							Image(nsImage: icon)
								.resizable()
								.frame(width: 18, height: 18)
						} else {
							Label(action?.label ?? extensions.title(for: name), systemImage: "puzzlepiece.extension.fill")
								.labelStyle(.iconOnly)
						}
					#else
						if let icon = action?.icon(for: CGSize(width: 18, height: 18)) {
							Image(uiImage: icon)
								.resizable()
								.frame(width: 18, height: 18)
						} else {
							Label(action?.label ?? extensions.title(for: name), systemImage: "puzzlepiece.extension.fill")
								.labelStyle(.iconOnly)
						}
					#endif
				}
				.disabled(action?.isEnabled == false)
				.controlSize(.regular)
				.buttonSizing(.fitted)
				.buttonStyle(.bordered)
				.foregroundStyle(theme.foregroundColor)
				.accessibilityLabel(action?.label ?? extensions.title(for: name))
				.accessibilityIdentifier("extension-action-\(name)")
			}

			Menu {
				ForEach(extensions.availableNames, id: \.self) { name in
					extensionMenuItem(extensions.title(for: name), name: name)
				}
				Divider()
				Button("Manage Extensions", systemImage: "gearshape") {
					browser.settingsPage = .extensions
					browser.openInternalPage(.settings)
				}
			} label: {
				Label("Extensions", systemImage: "puzzlepiece.extension")
					.labelStyle(.iconOnly)
			}
			.controlSize(.regular)
			.buttonSizing(.fitted)
			.buttonStyle(.bordered)
			.foregroundStyle(theme.foregroundColor)
			.accessibilityLabel("Extensions")
			.accessibilityIdentifier("browser-extensions")
		}
	}

	@ViewBuilder
	private func extensionMenuItem(_ title: String, name: String) -> some View {
		if extensions.isLoaded(name) {
			Button("Open \(title)", systemImage: "puzzlepiece.extension") {
				extensions.performAction(name, in: browser)
			}
		}
		Button(title, systemImage: extensions.isLoaded(name) ? "checkmark.circle.fill" : "circle") {
			extensions.setEnabled(!extensions.isEnabled(name), for: name)
		}
		if let error = extensions.loadErrors[name] {
			Button("\(title): \(error)", systemImage: "exclamationmark.triangle") {}
				.disabled(true)
		}
	}
}

private struct ShellTopBarLoadingBar: View {
	let controller: BrowserController
	let theme: BrowserTheme
	let tabID: UUID

	var body: some View {
		BrowserLoadingBar(
			isLoading: controller.isLoading,
			estimatedProgress: controller.estimatedProgress,
			theme: theme
		)
		.frame(height: 1.5)
		.id(tabID)
	}
}

private struct ShellNewTabButton: View {
	let browser: Browser
	let theme: BrowserTheme
	var onNewTab: (() -> Void)?
	@State private var newTabHovered = false

	var body: some View {
		Button {
			browser.requestNewTab()
			onNewTab?()
		} label: {
			Label("New Tab", systemImage: "plus")
				.frame(maxWidth: .infinity, alignment: .leading)
				.contentShape(Rectangle())
		}
		.keyboardShortcut("t", modifiers: .command)
		.buttonStyle(.plain)
		.padding(.horizontal, 8)
		.foregroundStyle(theme.foregroundColor.opacity(0.65))
		.onHover { newTabHovered = $0 }
		.frame(height: onNewTab == nil ? 28 : 44)
		.background {
			if newTabHovered {
				Color.clear.glassEffect(
					.regular,
					in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
				)
			}
		}
		.accessibilityIdentifier("new-tab")
	}
}

struct ShellDownloadsBarView: View {
	let browser: Browser
	let theme: BrowserTheme
	let downloads: BrowserDownloadManager
	@Binding var showsDownloads: Bool
	let onSwipeProgress: (UUID?, Double) -> Void
	@State private var downloadsHover = false
	@State private var addSpaceHover = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		HStack {
			Button {
				withAnimation(reduceMotion ? .none : .smooth(duration: 0.32)) {
					showsDownloads.toggle()
				}
			} label: {
				HStack(spacing: 9) {
					ZStack {
						Image(systemName: downloads.buttonSymbol)
						if let progress = downloads.activeProgress {
							Circle()
								.trim(from: 0, to: progress)
								.stroke(theme.progressColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
								.rotationEffect(.degrees(-90))
						}
					}
				}
				.frame(width: 25, height: 25)
				.background {
					if downloadsHover {
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.primary.gradient)
							.opacity(0.3)
					}
					if showsDownloads {
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.primary.gradient)
							.opacity(0.4)
					}
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.keyboardShortcut("J", modifiers: .command)
			.accessibilityLabel(showsDownloads ? "Show Tabs" : "Show Downloads")
			.accessibilityValue(downloads.activeProgress.map { "\(Int($0 * 100)) percent" } ?? "No active downloads")
			.accessibilityIdentifier("downloads-button")
			.onHover { i in
				withAnimation(.smooth(duration: 0.1)) {
					downloadsHover = i
				}
			}

			if browser.isPrivate {
				Label("Private", systemImage: "eye.slash")
					.font(.caption)
					.frame(maxWidth: .infinity)
			} else {
				BrowserSpacesBar(browser: browser, onSwipeProgress: onSwipeProgress)
					.frame(maxWidth: .infinity)
			}

			if !browser.isPrivate, Defaults[.aiSidebar] {
				Button("AI Sidebar", systemImage: "bubble.left.and.text.bubble.right") {
					browser.showsAISidebar.toggle()
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.plain)
				.accessibilityIdentifier("sidebar-ai-toggle")
			}

			if !browser.isPrivate {
				Button {
					browser.createSpace()
				} label: {
					Image(systemName: "plus")
						.frame(width: 25, height: 25)
						.background {
							if addSpaceHover {
								RoundedRectangle(cornerRadius: 8)
									.fill(Color.primary.gradient)
									.opacity(0.3)
							}
						}
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Add Space")
				.accessibilityIdentifier("add-space")
				.onHover { addSpaceHover = $0 }
			}
		}
		.padding([.horizontal, .bottom], 8)
	}
}
