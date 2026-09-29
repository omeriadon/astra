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
	private var theme: BrowserTheme {
		browser.theme
	}

	@State private var isRenaming = false
	@State private var isHovered = false
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
			TabIconView(tab: tab, browser: browser)

			TabTitleView(
				tab: tab,
				browser: browser,
				isRenaming: isRenaming,
				renameText: $renameText,
				isTitleFocused: $isTitleFocused,
				onBeginRenaming: beginRenaming,
				onCommitRenaming: commitRenaming,
				onCancelRenaming: cancelRenaming
			)

			if isSelected {
				TabCloseButton(tab: tab, browser: browser, isPinned: isPinned)
					.keyboardShortcut("W", modifiers: .command)
			} else {
				TabCloseButton(tab: tab, browser: browser, isPinned: isPinned)
					.opacity(isHovered ? 1 : 0)
					.allowsHitTesting(isHovered)
					.accessibilityHidden(!isHovered)
			}
		}
		.padding(.horizontal, 8)
		.frame(height: 28)
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
				onCopyURL: copyURL
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
		guard let url = tab.currentURL else { return }
		#if os(macOS)
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(url.absoluteString, forType: .string)
		#elseif os(iOS)
			UIPasteboard.general.url = url
		#endif
	}
}

private struct TabIconView: View {
	let tab: BrowserTab
	let browser: Browser

	var body: some View {
		Button {
			browser.selectTab(tab.id)
		} label: {
			Label {
				Text("Select Tab")
			} icon: {
				if let page = tab.internalPage {
					Image(systemName: page.symbol)
				} else if let favicon = FaviconStore.shared.image(
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
			.frame(width: 16, height: 16)
		}
		.buttonStyle(.plain)
		.accessibilityIdentifier("select-tab-\(tab.id.uuidString)")
	}
}

private struct TabTitleView: View {
	let tab: BrowserTab
	let browser: Browser
	let isRenaming: Bool
	@Binding var renameText: String
	var isTitleFocused: FocusState<Bool>.Binding
	let onBeginRenaming: () -> Void
	let onCommitRenaming: () -> Void
	let onCancelRenaming: () -> Void

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
			Text(verbatim: tab.title)
				.lineLimit(1)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
				.contentShape(Rectangle())
				.onTapGesture {
					browser.selectTab(tab.id)
				}
				.simultaneousGesture(
					TapGesture(count: 2)
						.onEnded { _ in onBeginRenaming() }
				)
				.accessibilityLabel(Text(verbatim: tab.title))
				.accessibilityAddTraits(.isButton)
				.accessibilityAction(.default) {
					browser.selectTab(tab.id)
				}
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
				.frame(width: 13, height: 16)
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

	var body: some View {
		if tab.internalPage == nil {
			Button("Revert Tab Name", systemImage: "arrow.uturn.backward", action: tab.revertTitle)
				.disabled(!tab.hasCustomTitle)

			Button("Duplicate Tab", systemImage: "plus.square.on.square") {
				browser.duplicateTab(tab.id)
			}

			Button("Hibernate Tab", systemImage: "moon.zzz") {
				browser.hibernateTab(tab.id)
			}
			.disabled(tab.isHibernated)
			.accessibilityIdentifier("hibernate-tab-\(tab.id.uuidString)")

			if isPinned {
				Button("Unpin Tab", systemImage: "pin.slash") {
					browser.moveTab(tab.id, to: .normal)
				}
			} else {
				Button("Pin Tab", systemImage: "pin") {
					browser.moveTab(tab.id, to: .pinned)
				}
			}
			Button("Add to Favourites", systemImage: "star") {
				browser.moveTab(tab.id, to: .favourite)
			}

			Divider()

			Button("Copy URL", systemImage: "doc.on.doc", action: onCopyURL)
				.disabled(tab.currentURL == nil)

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
