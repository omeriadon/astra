#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif
import Defaults
import Foundation
import Observation
import SwiftUI
#if os(macOS)
	import UniformTypeIdentifiers
#endif

struct BrowserTabRow: View {
	let tab: BrowserTab
	let browser: Browser
	let isSelected: Bool
	/// Precomputed by the parent sidebar (avoids O(n²) normalTabs scans per row).
	var tabIndex: Int?
	var normalCount: Int?
	var pinned: Bool?
	var rowSpaceID: UUID?
	var rowTheme: BrowserTheme?
	var splitSide: Browser.SplitSide?
	var compactSplitStyle = false
	var isOpenElsewhere: Bool?
	var onSelectTab: ((UUID) -> Void)?
	var navigationNamespace: Namespace.ID?
	var sidebarSelection: BrowserSidebarTabSelection?
	var selectionOrder: [UUID] = []
	@Namespace private var rowTransitions
	private var theme: BrowserTheme {
		rowTheme ?? browser.theme
	}

	@State private var isRenaming = false
	@State private var isHovered = false
	@State private var showsMonitorDetails = false
	#if os(macOS)
		@State private var hoverFrame = CGRect.zero
		@State private var hoverPreviewStarted = false
		@State private var splitDropSide: Browser.SplitSide?
		@State private var splitDropWidth: CGFloat = 1
	#endif
	@State private var renameText = ""
	@Default(.developerModeEnabled) private var developerModeEnabled
	@FocusState private var isTitleFocused: Bool
	private var isMultiSelected: Bool {
		sidebarSelection?.contains(tab.id, area: isPinned ? .pinned : .normal, spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID) == true
	}

	private func activateTab() {
		#if os(macOS)
			if let sidebarSelection, onSelectTab == nil {
				let activate = sidebarSelection.click(tab.id, area: isPinned ? .pinned : .normal,
				                                      spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID,
				                                      orderedIDs: selectionOrder, currentID: browser.selectedTabID,
				                                      modifiers: NSEvent.modifierFlags)
				guard activate else { return }
			}
		#endif
		browser.selectTab(tab.id)
		onSelectTab?(tab.id)
	}

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
		let isOpenElsewhere = isOpenElsewhere ?? BrowserWindowRegistry.shared.isOpenInAnotherWindow(tab.id, than: browser)
		return HStack(spacing: 6) {
			TabIconView(tab: tab, browser: browser, onSelectTab: onSelectTab, onActivate: activateTab)
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

			if let side = splitSide, !compactSplitStyle {
				Image(systemName: side == .left ? "rectangle.lefthalf.filled" : "rectangle.righthalf.filled")
					.font(.system(size: 11))
					.foregroundStyle(theme.foregroundColor.opacity(0.75))
					.help(side == .left ? "Left split pane" : "Right split pane")
					.accessibilityIdentifier("split-tab-\(tab.id.uuidString)")
			}
			TabTitleView(
				tab: tab,
				browser: browser,
				isRenaming: isRenaming,
				isHovered: isHovered,
				showsCloseButton: isSelected || onSelectTab != nil || isHovered,
				closeFadeWidth: onSelectTab != nil ? 64 : (isSelected || isHovered ? 36 : 12),
				renameText: $renameText,
				isTitleFocused: $isTitleFocused,
				onBeginRenaming: beginRenaming,
				onCommitRenaming: commitRenaming,
				onCancelRenaming: cancelRenaming,
				onSelectTab: onSelectTab,
				onActivate: activateTab
			)
			.foregroundStyle(Color.primary.mix(with: theme.tabColor, by: 0.25))
			.overlay(alignment: .trailing) {
				if isSelected || onSelectTab != nil {
					#if os(macOS)
						TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil)
							.keyboardShortcut(BrowserShortcutRegistry.shared.menuKeyboardShortcut("Close Tab", section: "File"))
					#else
						TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil)
							.keyboardShortcut("W", modifiers: .command)
					#endif
				} else if isHovered {
					TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil)
				}
			}
		}
		.opacity(isOpenElsewhere ? 0.35 : 1)
		.allowsHitTesting(!isOpenElsewhere)
		.padding(.horizontal, 10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.frame(height: onSelectTab == nil ? 36 : 48)
		.matchedTransitionSource(id: tab.id.uuidString, in: navigationNamespace ?? rowTransitions)
		.foregroundStyle(theme.foregroundColor)
		.background {
			if !compactSplitStyle, isSelected || splitSide != nil {
				Color.clear
					.glassEffect(
						.clear,
						in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabCornerRadius)
					)
			} else if !compactSplitStyle, isMultiSelected {
				ZStack {
					Color.clear
						.glassEffect(
							.clear,
							in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabCornerRadius)
						)
					if isSelected {
						Color.white.opacity(0.2)
					}
				}
			} else if !compactSplitStyle, isHovered {
				RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabCornerRadius)
					.fill(.ultraThinMaterial)
			}
		}
		.overlay {
			if isSelected, tab.internalPage == nil, developerModeEnabled || tab.isDeveloperMode {
				RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
					.strokeBorder(Color(red: 0.55, green: 0.4, blue: 0), lineWidth: 2)
					.overlay {
						RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
							.strokeBorder(.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
					}
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			}
		}
		.onHover { hovering in
			isHovered = hovering
			#if os(macOS)
				guard onSelectTab == nil else { return }
				if hovering, NSEvent.pressedMouseButtons == 0 {
					// Hover-only geometry observation below supplies the initial frame;
					// subsequent movements keep the preview anchored during scrolling.
					if hoverPreviewStarted {
						BrowserTabHoverPreviewCoordinator.shared.updateFrame(
							for: tab.id,
							windowID: browser.windowID,
							frame: hoverFrame
						)
					} else if hoverFrame != .zero {
						hoverPreviewStarted = true
						BrowserTabHoverPreviewCoordinator.shared.hoverBegan(
							tabID: tab.id,
							windowID: browser.windowID,
							sourceFrame: hoverFrame
						)
					}
				} else {
					if hoverPreviewStarted {
						BrowserTabHoverPreviewCoordinator.shared.hoverEnded(
							tabID: tab.id,
							windowID: browser.windowID
						)
					}
					hoverPreviewStarted = false
					hoverFrame = .zero
				}
			#endif
		}
		#if os(macOS)
		.background {
			// Do not install a geometry observer for every non-hovered tab.
			if isHovered, onSelectTab == nil {
				GeometryReader { proxy in
					Color.clear
						.onAppear { updateHoveredFrame(proxy.frame(in: .global)) }
						.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
							updateHoveredFrame(frame)
						}
				}
				.allowsHitTesting(false)
			}
		}
		.onChange(of: tab.id) { oldID, _ in
			if hoverPreviewStarted {
				BrowserTabHoverPreviewCoordinator.shared.hoverEnded(
					tabID: oldID,
					windowID: browser.windowID
				)
			}
			hoverPreviewStarted = false
		}
		.onDisappear {
			if hoverPreviewStarted {
				BrowserTabHoverPreviewCoordinator.shared.hoverEnded(
					tabID: tab.id,
					windowID: browser.windowID
				)
			}
			hoverPreviewStarted = false
		}
		#endif
		#if os(macOS)
		// Drag the whole tab, not merely its title or icon. Tab and page drop
		// zones consume the same in-process tab identity.
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { splitDropWidth = $0 }
		.onDrag {
			BrowserTabHoverPreviewCoordinator.shared.dismiss(for: browser.windowID)
			let data = tab.id.uuidString.data(using: .utf8) ?? Data()
			let provider = NSItemProvider()
			provider.registerDataRepresentation(forTypeIdentifier: "com.omeriadon.astra.tab", visibility: .ownProcess) { completion in
				completion(data, nil)
				return nil
			}
			return provider
		} preview: {
			HStack(spacing: 8) {
				Image(systemName: tab.internalPage?.symbol ?? "globe")
				Text(verbatim: tab.title).lineLimit(1)
				Spacer(minLength: 0)
			}
			.padding(.horizontal, 10)
			.frame(width: max(splitDropWidth, 140), height: 28)
			.glassEffect(.regular, in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
		}
		.onDrop(of: [UTType(exportedAs: "com.omeriadon.astra.tab", conformingTo: .data)],
		        delegate: BrowserTabRowSplitDropDelegate(
		        	browser: browser, anchorID: tab.id, width: splitDropWidth, side: $splitDropSide
		        ))
		.overlay {
			if let splitDropSide {
				HStack(spacing: 0) {
					splitDropSide == .left ? Color.accentColor.opacity(0.19) : Color.clear
					(splitDropSide == .right ? Color.accentColor.opacity(0.19) : Color.clear)
				}
				.clipShape(RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
				.allowsHitTesting(false)
			}
		}
		#endif
		.contextMenu {
			if let sidebarSelection, isMultiSelected, sidebarSelection.tabIDs.count > 1 {
				SidebarSelectedTabsContextMenu(
					browser: browser, selection: sidebarSelection,
					ids: sidebarSelection.orderedIDs(in: selectionOrder, area: isPinned ? .pinned : .normal,
					                                 spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID),
					spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID,
					isPinned: isPinned
				)
			} else {
				TabRowContextMenu(
					tab: tab,
					browser: browser,
					isPinned: isPinned,
					canCloseAbove: canCloseAbove,
					canCloseBelow: canCloseBelow,
					normalCount: resolvedNormalCount,
					spaceID: rowSpaceID,
					onCopyURL: copyURL,
					onBeginRenaming: beginRenaming,
					onSelectTab: onSelectTab
				)
			}
		}
		.onChange(of: isSelected) { _, selected in
			if !selected, isRenaming {
				commitRenaming()
			}
		}
	}

	#if os(macOS)
		private func updateHoveredFrame(_ frame: CGRect) {
			guard isHovered && onSelectTab == nil && NSEvent.pressedMouseButtons == 0 else { return }
			guard frame != hoverFrame || !hoverPreviewStarted else { return }
			hoverFrame = frame
			if hoverPreviewStarted {
				BrowserTabHoverPreviewCoordinator.shared.updateFrame(
					for: tab.id, windowID: browser.windowID, frame: frame
				)
			} else {
				hoverPreviewStarted = true
				BrowserTabHoverPreviewCoordinator.shared.hoverBegan(
					tabID: tab.id, windowID: browser.windowID, sourceFrame: frame
				)
			}
		}
	#endif

	private func beginRenaming() {
		guard tab.internalPage == nil || tab.internalPage == .easel else { return }
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
			&& lhs.rowSpaceID == rhs.rowSpaceID
			&& lhs.rowTheme == rhs.rowTheme
			&& lhs.isOpenElsewhere == rhs.isOpenElsewhere
			&& lhs.splitSide == rhs.splitSide
			&& lhs.compactSplitStyle == rhs.compactSplitStyle
			&& (lhs.onSelectTab == nil) == (rhs.onSelectTab == nil)
			&& lhs.navigationNamespace == rhs.navigationNamespace
			&& lhs.sidebarSelection === rhs.sidebarSelection
			&& lhs.selectionOrder == rhs.selectionOrder
	}
}

private struct TabIconView: View {
	let tab: BrowserTab
	let browser: Browser
	var onSelectTab: ((UUID) -> Void)?
	var onActivate: (() -> Void)?

	var body: some View {
		Button {
			if let onActivate {
				onActivate()
			} else {
				browser.selectTab(tab.id)
				onSelectTab?(tab.id)
			}
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
	let isHovered: Bool
	let showsCloseButton: Bool
	let closeFadeWidth: CGFloat
	@Binding var renameText: String
	var isTitleFocused: FocusState<Bool>.Binding
	let onBeginRenaming: () -> Void
	let onCommitRenaming: () -> Void
	let onCancelRenaming: () -> Void
	var onSelectTab: ((UUID) -> Void)?
	var onActivate: (() -> Void)?

	var body: some View {
		if isRenaming {
			TextField("Tab Name", text: $renameText)
				.textFieldStyle(.plain)
				.padding(.trailing, showsCloseButton ? closeFadeWidth : 0)
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
				if let onActivate {
					onActivate()
				} else {
					browser.selectTab(tab.id)
					onSelectTab?(tab.id)
				}
			} label: {
				Color.clear
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.overlay(alignment: .leading) {
						Text(verbatim: tab.title)
							.contentTransition(.opacity)
							.animation(
								reduceMotion ? nil : .smooth(duration: 0.2),
								value: tab.title
							)
							.lineLimit(1)
							.fixedSize(horizontal: true, vertical: false)
					}
					.mask {
						HStack(spacing: 0) {
							Color.white

							LinearGradient(
								colors: [.white, .clear],
								startPoint: .leading,
								endPoint: .trailing
							)
							.frame(
								width: isHovered
									? max(0, closeFadeWidth + 28 - hoverClearWidth)
									: closeFadeWidth
							)

							if isHovered {
								Color.clear.frame(width: hoverClearWidth)
							}
						}
					}
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.simultaneousGesture(
				TapGesture(count: 2)
					.onEnded { _ in onBeginRenaming() }
			)
			.accessibilityLabel(Text(verbatim: tab.title))
			.accessibilityActions {
				if tab.internalPage == nil || tab.internalPage == .easel {
					Button("Rename", systemImage: "pencil") { onBeginRenaming() }
				}
			}
			.accessibilityIdentifier("tab-title-\(tab.id.uuidString)")
		}
	}

	private var hoverClearWidth: CGFloat {
		onSelectTab == nil ? 20 : 44
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
		.accessibilityLabel(tab.internalPage == .easel ? "Close Easel" : isPinned ? "Hibernate Tab" : "Close Tab")
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
	var spaceID: UUID?
	let onCopyURL: () -> Void
	let onBeginRenaming: () -> Void
	var onSelectTab: ((UUID) -> Void)?

	var body: some View {
		if tab.canAppearInEaselSplit, !browser.isPrivate, !browser.isMini {
			if let selected = browser.selectedTab, selected.id != tab.id, selected.canAppearInEaselSplit {
				Button("Add to Current Tab on Left", systemImage: "rectangle.lefthalf.filled") {
					browser.openSplit(tab.id, beside: selected.id, onLeft: true)
				}
				Button("Add to Current Tab on Right", systemImage: "rectangle.righthalf.filled") {
					browser.openSplit(tab.id, beside: selected.id, onLeft: false)
				}
			}
			if browser.splitSide(for: tab.id) != nil {
				Button("Close Split View", systemImage: "rectangle.split.2x1.slash") {
					browser.closeEaselSplit()
				}
			}
			Divider()
		}
		if tab.internalPage == .easel {
			Button("Rename Easel", systemImage: "pencil", action: onBeginRenaming)
			Button("Revert Easel Name", systemImage: "arrow.uturn.backward", action: tab.revertTitle)
				.disabled(!tab.hasCustomTitle)
			Menu("Move to Space", systemImage: "rectangle.3.group") {
				ForEach(browser.workspace.spaces) { space in
					Button(space.name, systemImage: space.symbol) {
						browser.moveTab(tab.id, to: .pinned, in: space.id)
					}
				}
			}
			Button("Add to Favourites", systemImage: "star") {
				browser.moveTab(tab.id, to: .favourite)
			}
		}
		Button("New Folder with Tab", systemImage: "folder.badge.plus") {
			browser.createPinnedFolder(with: [tab.id], in: spaceID)
		}
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
			Button("Bookmark Tab", systemImage: "bookmark") {
				browser.bookmarkTabs([tab.id])
			}
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
			Label(tab.internalPage == .easel ? "Close Easel" : isPinned ? "Hibernate Tab" : "Close Tab", systemImage: isPinned && tab.internalPage != .easel ? "moon.zzz" : "xmark")
		}
	}
}

private struct SidebarSelectedTabsContextMenu: View {
	let browser: Browser
	let selection: BrowserSidebarTabSelection
	let ids: [UUID]
	let spaceID: UUID
	let isPinned: Bool

	var body: some View {
		Button("New Folder from \(ids.count) Tabs", systemImage: "folder.badge.plus") {
			browser.createPinnedFolder(with: ids, in: spaceID)
			selection.clear()
		}
		Button(isPinned ? "Unpin Selected Tabs" : "Pin Selected Tabs", systemImage: isPinned ? "pin.slash" : "pin") {
			browser.moveTabs(ids, to: isPinned ? .normal : .pinned, in: spaceID)
			selection.clear()
		}
		Button("Add to Favourites", systemImage: "star") {
			browser.moveTabs(ids, to: .favourite)
			selection.clear()
		}
		Divider()
		Button("Bookmark \(ids.count) Tabs", systemImage: "bookmark") {
			browser.bookmarkTabs(ids)
			selection.clear()
		}
		Button("Add to Reading List", systemImage: "text.badge.plus") {
			for id in ids {
				browser.addToReadingList(tabID: id)
			}
			selection.clear()
		}
		Divider()
		Button(isPinned ? "Hibernate Selected Tabs" : "Close Selected Tabs", systemImage: isPinned ? "moon.zzz" : "xmark", role: .destructive) {
			for id in ids {
				browser.closeTab(id)
			}
			selection.clear()
		}
	}
}

#if os(macOS)
	struct BrowserTabHoverPreviewOverlay: View {
		let browser: Browser
		@State private var coordinator = BrowserTabHoverPreviewCoordinator.shared
		@Environment(\.accessibilityReduceMotion) private var reduceMotion

		private let cardWidth: CGFloat = 320
		private let cardHeight: CGFloat = 306
		private let margin: CGFloat = 12

		var body: some View {
			GeometryReader { geometry in
				let globalFrame = geometry.frame(in: .global)
				if coordinator.isVisible,
				   coordinator.windowID == browser.windowID,
				   let tabID = coordinator.presentedTabID,
				   let tab = browser.tabsByID[tabID]
				{
					let desiredX = coordinator.sourceFrame.maxX - globalFrame.minX + margin + cardWidth / 2
					let desiredY = coordinator.sourceFrame.midY - globalFrame.minY
					let x = min(
						max(cardWidth / 2 + margin, desiredX),
						max(cardWidth / 2 + margin, geometry.size.width - cardWidth / 2 - margin)
					)
					let y = min(
						max(cardHeight / 2 + margin, desiredY),
						max(cardHeight / 2 + margin, geometry.size.height - cardHeight / 2 - margin)
					)

					ZStack {
						BrowserTabHoverPreviewCard(tab: tab, browser: browser)
							.id(tab.id)
							.transition(.opacity)
						}
						.animation(.easeInOut(duration: 0.075), value: tab.id)
						.frame(width: cardWidth, height: cardHeight)
						.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
						.position(x: x, y: y)
						.animation(reduceMotion ? nil : .easeInOut(duration: 0.075), value: y)
				}
			}
			.animation(.linear(duration: 0.1), value: coordinator.isVisible)
			.allowsHitTesting(false)
			.accessibilityHidden(true)
		}
	}

	private struct BrowserTabHoverPreviewCard: View {
		let tab: BrowserTab
		let browser: Browser
		@State private var memorySnapshot: BrowserTabProcessMemorySnapshot?
		@State private var hasSampledMemory = false

		private var host: String {
			if tab.internalPage != nil {
				return "Internal Page"
			}
			return tab.currentURL?.host ?? "New Tab"
		}

		private var unavailableMemoryLabel: String {
			if tab.isHibernated {
				return "Hibernated"
			}
			return hasSampledMemory ? "Not measurable" : "Measuring…"
		}

		var body: some View {
			VStack(alignment: .leading, spacing: 10) {
				HStack(spacing: 9) {
					if let favicon = tab.session.favicons.image(for: tab.currentURL, in: tab.controller?.webViewIfLoaded) {
						favicon
							.resizable()
							.scaledToFit()
							.frame(width: 18, height: 18)
					} else {
						Image(systemName: tab.internalPage?.symbol ?? "globe")
							.frame(width: 18, height: 18)
					}

					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: tab.title)
							.font(.headline)
							.lineLimit(1)
						Text(verbatim: host)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}

				Group {
					if let page = tab.internalPage {
						Image(systemName: page.symbol)
							.font(.system(size: 42))
							.frame(maxWidth: .infinity, maxHeight: .infinity)
					} else if let controller = tab.controller,
					          controller.hasCurrentPreviewSnapshot,
					          let snapshot = controller.previewSnapshot
					{
						Image(nsImage: snapshot)
							.resizable()
							.aspectRatio(contentMode: .fill)
					} else {
						ZStack {
							ThemeSurface(theme: browser.theme)
								.background(.quaternary)
							Image(systemName: tab.isHibernated ? "moon.zzz" : "rectangle.dashed")
								.font(.system(size: 28))
								.foregroundStyle(.secondary)
						}
					}
				}
				.frame(width: 296, height: 166)
				.clipped()
				.clipShape(RoundedRectangle(cornerRadius: 10))

				HStack {
					Text("Process memory")
						.font(.subheadline.weight(.semibold))
					Spacer()
					Text(memorySnapshot?.knownProcessBytes.map(Self.formatBytes) ?? unavailableMemoryLabel)
						.font(.subheadline.monospacedDigit())
						.foregroundStyle(.secondary)
				}
				if let snapshot = memorySnapshot {
					HStack(spacing: 12) {
						if let bytes = snapshot.webContentBytes {
							Text("Web: \(Self.formatBytes(bytes))")
						}
						if let bytes = snapshot.graphicsBytes {
							Text("GPU*: \(Self.formatBytes(bytes))")
						}
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.tertiary)
					.help("WebKit may share processes between tabs; GPU memory is not exclusive to this tab.")
				}
			}
			.padding(12)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.task(id: tab.id) {
				memorySnapshot = nil
				hasSampledMemory = false
				guard let controller = tab.controller else {
					hasSampledMemory = true
					return
				}

				if !controller.hasCurrentPreviewSnapshot {
					await controller.refreshPreviewSnapshot()
				}
				memorySnapshot = await sampleTabMemory(for: controller)
				hasSampledMemory = true
				while !Task.isCancelled {
					do {
						try await Task.sleep(for: .seconds(2))
					} catch {
						return
					}
					memorySnapshot = await sampleTabMemory(for: controller)
					hasSampledMemory = true
					if !controller.hasCurrentPreviewSnapshot {
						await controller.refreshPreviewSnapshot()
					}
				}
			}
		}

		private func sampleTabMemory(for controller: BrowserController) async -> BrowserTabProcessMemorySnapshot? {
			let snapshots = await BrowserController.tabProcessMemorySnapshots(for: [controller])
			return snapshots[controller.id]
		}

		private nonisolated static func formatBytes(_ bytes: UInt64) -> String {
			ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
		}
	}
#endif

#if os(macOS)
	private struct BrowserTabRowSplitDropDelegate: DropDelegate {
		let browser: Browser
		let anchorID: UUID
		let width: CGFloat
		@Binding var side: Browser.SplitSide?

		private func locationSide(_ info: DropInfo) -> Browser.SplitSide {
			info.location.x < width / 2 ? .left : .right
		}

		func validateDrop(info: DropInfo) -> Bool {
			!browser.isPrivate && !browser.isMini
				&& browser.tab(withID: anchorID)?.canAppearInEaselSplit == true
				&& info.hasItemsConforming(to: ["com.omeriadon.astra.tab"])
		}

		func dropEntered(info: DropInfo) {
			guard validateDrop(info: info) else { return }
			side = locationSide(info)
			BrowserTabHoverPreviewCoordinator.shared.dismiss(for: browser.windowID)
		}

		func dropUpdated(info: DropInfo) -> DropProposal? {
			guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
			side = locationSide(info)
			return DropProposal(operation: .move)
		}

		func dropExited(info _: DropInfo) {
			side = nil
		}

		func performDrop(info: DropInfo) -> Bool {
			defer { side = nil }
			guard validateDrop(info: info),
			      let provider = info.itemProviders(for: ["com.omeriadon.astra.tab"]).first
			else { return false }
			let onLeft = locationSide(info) == .left
			_ = provider.loadDataRepresentation(forTypeIdentifier: "com.omeriadon.astra.tab") { data, _ in
				guard let data, let raw = String(data: data, encoding: .utf8),
				      let id = UUID(uuidString: raw), id != anchorID else { return }
				Task { @MainActor in
					browser.openSplit(id, beside: anchorID, onLeft: onLeft)
				}
			}
			return true
		}
	}
#endif
