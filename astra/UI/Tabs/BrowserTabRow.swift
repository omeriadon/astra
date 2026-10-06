#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif
import Defaults
import SwiftUI

struct BrowserTabRow: View {
	let tab: BrowserTab
	let browser: Browser
	let isSelected: Bool
	/// Precomputed by the parent sidebar (avoids O(n²) normalTabs scans per row).
	var tabIndex: Int?
	var normalCount: Int?
	var pinned: Bool?
	var onSelectTab: ((UUID) -> Void)?
	var navigationNamespace: Namespace.ID?
	@Namespace private var rowTransitions
	private var theme: BrowserTheme {
		browser.theme
	}

	@State private var isRenaming = false
	@State private var isHovered = false
	@State private var showsMonitorDetails = false
	@State private var renameText = ""
	@FocusState private var isTitleFocused: Bool
	#if os(macOS)
		@State private var tabDrag = BrowserTabDragCoordinator.shared
	#endif

	private var resolvedTabIndex: Int? {
		tabIndex ?? browser.normalTabs.firstIndex(where: { $0.id == tab.id })
	}

	private var resolvedNormalCount: Int {
		normalCount ?? browser.normalTabs.count
	}

	private var isPinned: Bool {
		pinned ?? browser.selectedSpace.pinnedTabIDs.contains(tab.id)
	}

	private var canCloseAbove: Bool {
		(resolvedTabIndex ?? 0) > 0
	}

	private var canCloseBelow: Bool {
		guard let resolvedTabIndex else { return false }
		return resolvedTabIndex < resolvedNormalCount - 1
	}

	var body: some View {
		HStack(spacing: 6) {
			TabIconView(tab: tab, browser: browser, onSelectTab: onSelectTab)
			if let match = tab.monitorMatch {
				Button("Monitored condition met", systemImage: "bell.badge.fill") { browser.selectTab(tab.id) }
					.labelStyle(.iconOnly)
					.buttonStyle(.glassProminent)
					.tint(.yellow)
					.onHover { showsMonitorDetails = $0 }
					.accessibilityIdentifier("monitor-match-\(match.id.uuidString)")
					.popover(isPresented: $showsMonitorDetails) {
						VStack(alignment: .leading, spacing: 8) {
							Label("Condition fulfilled", systemImage: "bell.badge.fill").font(.headline)
							Text(match.criterion).font(.caption).foregroundStyle(.secondary)
							Text(match.message).textSelection(.enabled)
						}
						.padding(16)
						.frame(width: 300)
					}
			}

			TabTitleView(
				tab: tab,
				browser: browser,
				isRenaming: isRenaming,
				renameText: $renameText,
				isTitleFocused: $isTitleFocused,
				onBeginRenaming: beginRenaming,
				onCommitRenaming: commitRenaming,
				onCancelRenaming: cancelRenaming,
				onSelectTab: onSelectTab
			)

			if isSelected || onSelectTab != nil {
				TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil)
					.keyboardShortcut("W", modifiers: .command)
			} else {
				TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil)
					.opacity(isHovered ? 1 : 0)
					.allowsHitTesting(isHovered)
					.accessibilityHidden(!isHovered)
			}
		}
		.opacity(BrowserWindowRegistry.shared.isOpenInAnotherWindow(tab.id, than: browser) ? 0.35 : 1)
		.allowsHitTesting(!BrowserWindowRegistry.shared.isOpenInAnotherWindow(tab.id, than: browser))
		.padding(.horizontal, 8)
		.frame(height: onSelectTab == nil ? 28 : 44)
		.matchedTransitionSource(id: tab.id.uuidString, in: navigationNamespace ?? rowTransitions)
		.foregroundStyle(theme.foregroundColor)
		.background {
			if isSelected {
				Color.clear
					.glassEffect(
						.clear,
						in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
					)
			} else if isHovered {
				Color.clear
					.glassEffect(
						.regular,
						in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
					)
			}
		}
		#if os(macOS)
		.background {
			BrowserDropZone(
				browser: browser,
				area: browser.selectedSpace.pinnedTabIDs.contains(tab.id) ? .pinned : .normal,
				spaceID: browser.workspace.selectedSpaceID,
				beforeTabID: tab.id
			)
		}
		.highPriorityGesture(
			DragGesture(minimumDistance: 8)
				.onChanged { _ in
					if tabDrag.activeTabID != tab.id {
						browser.flushPersistence()
						tabDrag.begin(tab.id, from: browser)
					}
					tabDrag.update()
				}
				.onEnded { _ in
					tabDrag.drop()
				}
		)
		#endif
		.onHover { isHovered = $0 }
		.contextMenu {
			TabRowContextMenu(
				tab: tab,
				browser: browser,
				isPinned: isPinned,
				canCloseAbove: canCloseAbove,
				canCloseBelow: canCloseBelow,
				normalCount: resolvedNormalCount,
				onCopyURL: copyURL,
				onBeginRenaming: beginRenaming,
				onSelectTab: onSelectTab
			)
		}
		.onChange(of: isSelected) { _, selected in
			if !selected, isRenaming {
				commitRenaming()
			}
		}
	}

	private func beginRenaming() {
		guard tab.internalPage == nil else { return }
		browser.selectTab(tab.id)
		renameText = tab.title
		isRenaming = true
		isTitleFocused = true
	}

	private func commitRenaming() {
		tab.rename(to: renameText)
		isRenaming = false
		isTitleFocused = false
	}

	private func cancelRenaming() {
		isRenaming = false
		isTitleFocused = false
	}

	private func copyURL() {
		browser.copyURL(for: tab)
	}
}

/// Favicons arrive via browser.session.favicons.image inside TabIconView, which stays
/// independently subscribed: skipping unchanged rows here never blocks new icons.
extension BrowserTabRow: Equatable {
	static func == (lhs: BrowserTabRow, rhs: BrowserTabRow) -> Bool {
		lhs.tab === rhs.tab
			&& lhs.browser === rhs.browser
			&& lhs.theme == rhs.theme
			&& lhs.isSelected == rhs.isSelected
			&& lhs.tabIndex == rhs.tabIndex
			&& lhs.normalCount == rhs.normalCount
			&& lhs.pinned == rhs.pinned
			&& (lhs.onSelectTab == nil) == (rhs.onSelectTab == nil)
			&& lhs.navigationNamespace == rhs.navigationNamespace
	}
}

private struct TabIconView: View {
	let tab: BrowserTab
	let browser: Browser
	var onSelectTab: ((UUID) -> Void)?

	var body: some View {
		Button {
			browser.selectTab(tab.id)
			onSelectTab?(tab.id)
		} label: {
			Label {
				Text("Select Tab")
			} icon: {
				if let page = tab.internalPage {
					Image(systemName: page.symbol)
				} else if let favicon = browser.session.favicons.image(
					for: tab.currentURL,
					in: tab.controller?.webViewIfLoaded
				) {
					favicon
						.resizable()
						.scaledToFit()
				} else {
					Image(systemName: "globe")
				}
			}
			.labelStyle(.iconOnly)
			.frame(width: onSelectTab == nil ? 16 : 22, height: onSelectTab == nil ? 16 : 22)
		}
		.buttonStyle(.plain)
		.accessibilityIdentifier("select-tab-\(tab.id.uuidString)")
	}
}

private struct TabTitleView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let tab: BrowserTab
	let browser: Browser
	let isRenaming: Bool
	@Binding var renameText: String
	var isTitleFocused: FocusState<Bool>.Binding
	let onBeginRenaming: () -> Void
	let onCommitRenaming: () -> Void
	let onCancelRenaming: () -> Void
	var onSelectTab: ((UUID) -> Void)?

	var body: some View {
		if isRenaming {
			TextField("Tab Name", text: $renameText)
				.textFieldStyle(.plain)
				.focused(isTitleFocused)
				.onSubmit(onCommitRenaming)
				.onKeyPress(.escape) {
					onCancelRenaming()
					return .handled
				}
				.onChange(of: isTitleFocused.wrappedValue) { _, isFocused in
					if !isFocused, isRenaming {
						onCommitRenaming()
					}
				}
				.accessibilityIdentifier("tab-name-\(tab.id.uuidString)")
		} else {
			Button {
				browser.selectTab(tab.id)
				onSelectTab?(tab.id)
			} label: {
				Label {
					Text(verbatim: tab.title)
						.contentTransition(.opacity)
						.animation(reduceMotion ? nil : .smooth(duration: 0.2), value: tab.title)
						.lineLimit(1)
				} icon: {
					Image(systemName: tab.internalPage?.symbol ?? "globe")
				}
				.labelStyle(.titleOnly)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.simultaneousGesture(
				TapGesture(count: 2)
					.onEnded { _ in onBeginRenaming() }
			)
			.accessibilityLabel(Text(verbatim: tab.title))
			.accessibilityActions {
				if tab.internalPage == nil {
					Button("Rename", systemImage: "pencil") { onBeginRenaming() }
				}
			}
			.accessibilityIdentifier("tab-title-\(tab.id.uuidString)")
		}
	}
}

private struct TabCloseButton: View {
	let tab: BrowserTab
	let browser: Browser
	let isPinned: Bool
	var isCompact = false
	@State private var hovered = false

	var body: some View {
		Button {
			browser.closeTab(tab.id)
		} label: {
			Image(systemName: "xmark")
				.frame(width: 22, height: 22)
				.background {
					if hovered {
						Color.primary
							.colorInvert()
							.opacity(0.3)
							.clipShape(RoundedRectangle(cornerRadius: 9))
					}
				}
				.contentShape(RoundedRectangle(cornerRadius: 9))
				.onHover {
					hovered = $0
				}
				.frame(width: isCompact ? 44 : 13, height: isCompact ? 44 : 16)
		}
		.buttonStyle(.plain)
		.accessibilityLabel(isPinned ? "Hibernate Tab" : "Close Tab")
		.accessibilityIdentifier("close-tab-\(tab.id.uuidString)")
	}
}

private struct TabRowContextMenu: View {
	let tab: BrowserTab
	let browser: Browser
	let isPinned: Bool
	let canCloseAbove: Bool
	let canCloseBelow: Bool
	let normalCount: Int
	let onCopyURL: () -> Void
	let onBeginRenaming: () -> Void
	var onSelectTab: ((UUID) -> Void)?

	var body: some View {
		if tab.internalPage == nil {
			Button("Rename Tab", systemImage: "pencil", action: onBeginRenaming)
			Button("Revert Tab Name", systemImage: "arrow.uturn.backward", action: tab.revertTitle)
				.disabled(!tab.hasCustomTitle)

			Button("Duplicate Tab", systemImage: "plus.square.on.square") {
				if browser.duplicateTab(tab.id) != nil {
					onSelectTab?(tab.id)
				}
			}

			Button("Hibernate Tab", systemImage: "moon.zzz") {
				browser.hibernateTab(tab.id)
			}
			.disabled(tab.isHibernated || !tab.canHibernate)
			.accessibilityIdentifier("hibernate-tab-\(tab.id.uuidString)")

			if isPinned {
				Button("Unpin Tab", systemImage: "pin.slash") {
					browser.moveTab(tab.id, to: .normal)
				}
				if !browser.selectedSpace.pinnedFolders.isEmpty {
					Menu("Move to Folder", systemImage: "folder") {
						Button("No Folder", systemImage: "tray") {
							browser.movePinnedTab(tab.id, toFolder: nil)
						}
						ForEach(browser.selectedSpace.pinnedFolders) { folder in
							Button(folder.name, systemImage: "folder") {
								browser.movePinnedTab(tab.id, toFolder: folder.id)
							}
						}
					}
				}
			} else {
				Button("Pin Tab", systemImage: "pin") {
					browser.moveTab(tab.id, to: .pinned)
				}
			}
			Menu("Move to Space", systemImage: "rectangle.3.group") {
				ForEach(browser.workspace.spaces) { space in
					Button(space.name, systemImage: space.symbol) {
						browser.moveTab(tab.id, to: isPinned ? .pinned : .normal, in: space.id)
					}
				}
			}
			.accessibilityIdentifier("move-tab-space-\(tab.id.uuidString)")
			Button("Add to Favourites", systemImage: "star") {
				browser.moveTab(tab.id, to: .favourite)
			}

			Divider()

			Button("Copy URL", systemImage: "doc.on.doc", action: onCopyURL)
				.disabled(tab.copyableURL == nil)
				.accessibilityIdentifier("copy-tab-url-\(tab.id.uuidString)")
			Button("Add to Reading List", systemImage: "text.badge.plus") {
				browser.addToReadingList(tabID: tab.id)
			}
			.disabled(!browser.canAddToReadingList(tabID: tab.id))
			.accessibilityIdentifier("tab-add-reading-list-\(tab.id.uuidString)")
			Button("Save Page Offline", systemImage: "arrow.down.circle") {
				browser.saveReadingListSnapshot(tabID: tab.id)
			}
			.disabled(!browser.canSaveReadingListSnapshot(tabID: tab.id))
			.accessibilityIdentifier("tab-save-offline-\(tab.id.uuidString)")

			Divider()
		}

		Button("Close Tabs Above", systemImage: "arrow.up.to.line") {
			browser.closeTabsAbove(tab.id)
		}
		.disabled(!canCloseAbove)

		Button("Close Tabs Below", systemImage: "arrow.down.to.line") {
			browser.closeTabsBelow(tab.id)
		}
		.disabled(!canCloseBelow)

		Button("Close Other Tabs", systemImage: "xmark.circle") {
			browser.closeOtherTabs(tab.id)
		}
		.disabled(normalCount < 2)

		Button(role: isPinned ? nil : .destructive) {
			browser.closeTab(tab.id)
		} label: {
			Label(isPinned ? "Hibernate Tab" : "Close Tab", systemImage: isPinned ? "moon.zzz" : "xmark")
		}
	}
}
